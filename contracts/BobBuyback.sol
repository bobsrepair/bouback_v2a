pragma solidity ^0.4.24;

import "./zeppelin/token/ERC20/ERC20.sol";
import './zeppelin/math/Math.sol';
import './zeppelin/math/SafeMath.sol';
import './zeppelin/ownership/Claimable.sol';        //Allows to safely transfer ownership
import './zeppelin/ownership/HasNoContracts.sol';   //Allows contracts accidentially sent to this contract
import './zeppelin/ownership/CanReclaimToken.sol';  //Allows to reclaim tokens accidentially sent to this contract
import './zeppelin/lifecycle/Destructible.sol';     //Allows to destroy this contract then not needed any more
import './QuickSort.sol';

/**
 * Automated buy back BOB tokens
 */
contract BobBuyback is Claimable, HasNoContracts, CanReclaimToken, Destructible {
    using SafeMath for uint256;    
    uint256 constant DEFAULT_PRICE_LIMIT = 2**255;  // See Holder.priceLimit
    uint8 constant ROUND_MAX_WINNERS = 64;
    //Random Generator constants. See https://en.wikipedia.org/wiki/Linear_congruential_generator
    uint256  constant RAND_MODULUS = 2**64;
    uint256  constant RAND_MULTIPLIER = 6364136223846793005;        
    uint256  constant RAND_INCREMENT = 1442695040888963407;


    struct Deposit {
        uint256 amount;                 // Amount deposited (and not whitdrawn yet)
        uint64  timestamp;              // Timestamp of deposit tx
    }
    struct Holder {
        Deposit[] deposits;             // List of deposits
        uint256 priceLimit;             // 1 ETH = priceLimit BOB. If current buyback price is lower 
                                        // (means beneficiary will receive less ETH for equal amount of BOB, priceLimit < roundPrice), 
                                        // this Holder does not participate in this round.
                                        // Note: to make calculations easier we assume price of BOB is significantly less then price of ETH. 
                                        // If this will change, we will update the contract.
                                        // priceLimit = 0 means holder is not registered
    }
    struct BuybackRound {
        uint256 price;                  // Price of current buyback round. 0 if no round currently started
        uint16 totalWinners;            // How many winners we will have in current round
        uint256 ethAmount;
        uint64 randSeed;
        address[] winners;
        uint64 timestamp;
        uint256 lastProcessedWeight;
        uint256 lastProcessedAddressIndex;
        uint8 lastProcessedWinnerIndex;
    }

    ERC20 public token;                         // Address of BOB token contract
    mapping(address => Holder) public holders;  // Map of holders
    address[] public holdersList;               // List of holders used to iterate map        
    uint256 public boughtTokens;                // How many BOB tokens is bought by buyback program since last claim by contract's owner
    BuybackRound public currentRound;

    modifier notProcessingRound() {
        require(currentRound.price == 0, "Action can not be executed during Buyback round processing");
        _;
    }
    modifier isProcessingRound() {
        require(currentRound.price != 0, "Buyback round not started");
        _;
    }

    //event Buyback(address indexed from, uint256 amountBob, uint256 amountEther);

    constructor(ERC20 _token) public {
        token = _token;
    }

    /**
     * @notice Calculates all tokens deposited (and not yet whitdrawn) by beneficiary
     * @param beneficiary Whos tokens we are calculating
     */
    function currentDeposit(address beneficiary) view public returns(uint256){
        if(!isHolder(beneficiary)) return 0;
        uint256 deposit = 0;
        for(uint256 i=0; i < holders[msg.sender].deposits.length; i++){
            deposit += holders[msg.sender].deposits[i].amount;  //Do not use SafeMath here because we are counting token amounts and results should always be less then token.totalSupply()
        }
        return deposit;
    }

    /**
     * @notice Deposit tokens
     * @param _amount How much tokens wil be deposited
     */
    function deposit(uint256 _amount) notProcessingRound external {
        require(token.transferFrom(msg.sender, address(this), _amount), "Failed to transfer tokens");
        if(!isHolder(msg.sender)){
            holders[msg.sender].priceLimit = DEFAULT_PRICE_LIMIT;
        }
        holders[msg.sender].deposits.push(Deposit({amount: _amount, timestamp: uint64(now)}));
    }
    /**
     * @notice Set price limit for buybacks
     * @param _priceLimit New price limit. See Holder.priceLimit
     */
    function setPriceLimit(uint256 _priceLimit) external {
        require(_priceLimit > 0, "Invalid price limit");   
        require(isHolder(msg.sender), "Can not set price limit for unregistered holder");
        holders[msg.sender].priceLimit = _priceLimit;
    }

    /**
     * @notice Whitdraw tokens
     * @param _amount How much tokens wil be whidrawn
     */
    function withdraw(uint256 _amount) notProcessingRound external {
        require(isHolder(msg.sender), "Unregistered holder can not whitdraw");
        uint256 cd = currentDeposit(msg.sender);
        require(_amount <= cd, "Not enough tokens deposited");
        decreaseDeposit(msg.sender, _amount);
        uint256 newDeposit = currentDeposit(msg.sender);
        assert(cd.sub(_amount) == newDeposit);
        require(token.transfer(msg.sender, _amount), "Failed to transfer tokens");
    }
    /**
     * @notice Decreases deposit (for whidrawals and buybacks)
     * @param beneficiary Whos deposit we are decreasing
     * @param _amount How much tokens will be decreased
     */
    function decreaseDeposit(address beneficiary, uint256 _amount) internal {
        Holder storage h = holders[beneficiary];
        uint256 decreased = 0;
        for(uint256 i = h.deposits.length -1; i >=0; i--){
            if(_amount < decreased + h.deposits[i].amount){
                //This is the last deposit we are decreasing and something will be left on it
                h.deposits[i].amount -= _amount - decreased;
                return;
            }else{
                //Remove this deposit from the list
                decreased += h.deposits[i].amount;
                h.deposits.length -= 1;
                if(decreased == _amount) return;
            }
        }
        assert(false); //we should never reach this point
    }

    /**
     * @notice used to setup Buyback round
     */
    function setupBuybackRound(uint256 roundPrice, uint16 winners) notProcessingRound onlyOwner public {
        require(winners <= ROUND_MAX_WINNERS, "Too much winners");
        require(holdersList.length > 0, "No holders available");
        currentRound.price = roundPrice;
        currentRound.totalWinners = winners;
        currentRound.winners.length = 0;
        currentRound.ethAmount = address(this).balance;
        currentRound.randSeed = uint64(uint256(blockhash(block.number-1)) % RAND_MODULUS);  //using hash of last known block //TODO think on this... 
        currentRound.timestamp = uint64(now);
        currentRound.lastProcessedWeight = 0;
        currentRound.lastProcessedAddressIndex = 0;
        currentRound.lastProcessedWinnerIndex = 0;
    }
    function getCurrentRoundTotalWeight() isProcessingRound view public returns(uint256){
        uint256 totalWeight = 0; //totalWeight will always be less then token.totalSupply * now, so no need to use SafeMath here because we know BOB.totalSupply
        for(uint256 i=0; i < holdersList.length; i++){
            totalWeight += getHolderWeight(holdersList[i]);
        }
        return totalWeight;
    }
    function getCurrentRoundWinnerWeights() isProcessingRound view public returns(uint256[]){
        uint256 totalWeight = getCurrentRoundTotalWeight();
        require(totalWeight != 0);
        uint256[] memory winnerWeights = new uint256[](currentRound.totalWinners);
        uint64 rnd = currentRound.randSeed;
        for(uint16 i=0; i < currentRound.totalWinners; i++){
            rnd = getRand(rnd);
            winnerWeights[i] = totalWeight * rnd / RAND_MODULUS;
        }
        return QuickSort.sort(winnerWeights);
    }
    /**
     * @notice Partially process winners of current round
     * @param winnerWeights Sorted array of winners
     * @param lastAddressIndex Index of last address to process in holdersList 
     */
    function processCurrentRoundWinners(uint256[] winnerWeights, uint256 lastAddressIndex) isProcessingRound onlyOwner external {
        //require(holdersList.length > 0, "No holders available") // This condition is required by setupBuybackRound()
        require(arrayIsAscSorted(winnerWeights), "Winner weights should be a sorted array");
        require(currentRound.lastProcessedWinnerIndex < currentRound.totalWinners, "No more winners to process");
        require(currentRound.lastProcessedAddressIndex < holdersList.length-1, "No more addresses to process");
        uint256 processedWeight = currentRound.lastProcessedWeight;
        uint256 lastAddressIdx = Math.min(holdersList.length-1,lastAddressIndex);
        uint8 lastProcessedWinnerIndex = currentRound.lastProcessedWinnerIndex;
        uint256 nextWinnerWeight = winnerWeights[lastProcessedWinnerIndex+1];
        assert(nextWinnerWeight >= processedWeight);    //This asserts that we do not process one winner twice, but note that one winner can be selected more then once
        for(uint256 i = currentRound.lastProcessedAddressIndex+1; i <= lastAddressIdx; i++){
            address ha = holdersList[i];
            uint256 hw = getHolderWeight(ha);
            if(processedWeight+hw >= nextWinnerWeight){
                //we have a winner
                uint256 winnerHas = currentDeposit(ha);
                uint256 maxBuybackPerWinner = currentRound.ethAmount / currentRound.price; //Note that this truncates maxBuybackPerWinner, so real buyback will be always a bit less then available eth
                uint256 buybackTokensAmount = Math.min(winnerHas, maxBuybackPerWinner);
                uint256 buybackEthAmount = buybackTokensAmount * currentRound.price;
                lastProcessedWinnerIndex += 1;
                nextWinnerWeight = winnerWeights[lastProcessedWinnerIndex+1];
                processedWeight += hw;
                boughtTokens += buybackTokensAmount;
                decreaseDeposit(ha, buybackTokensAmount);
                bool transferSuccess = ha.send(buybackEthAmount);  //Note this will NOT fail on error. So if winner can't accept eth, we will skip him. Also, note that reentrancy is not a problem here because we already decreased token amount. Also there is no practical case how it could happen
                if(!transferSuccess){
                    //we need to return his tokens back
                    boughtTokens -= buybackTokensAmount;
                    holders[ha].deposits.push(Deposit({amount: buybackTokensAmount, timestamp: uint64(now)}));
                }
            }else{
                //continue search
                processedWeight += hw;
            }
        }
        if(lastProcessedWinnerIndex < currentRound.totalWinners-1){
            currentRound.lastProcessedWeight        = processedWeight;
            currentRound.lastProcessedAddressIndex  = lastAddressIdx;
            currentRound.lastProcessedWinnerIndex   = lastProcessedWinnerIndex;
        }else{
            //Round processing is finished
            currentRound.price = 0;
            currentRound.totalWinners = 0;
            currentRound.winners.length = 0;
            currentRound.randSeed = 0;
            currentRound.ethAmount = 0;
            currentRound.timestamp = 0;
            currentRound.lastProcessedWeight = 0;
            currentRound.lastProcessedAddressIndex = 0;
            currentRound.lastProcessedWinnerIndex = 0;
        }
    }

    function getHolderWeight(address ha) view internal returns(uint256){
        Holder storage h = holders[ha];
        if(h.priceLimit < currentRound.price) return 0; // Current price is too small for this beneficiary
        uint256 hw = 0;
        for(uint256 i = 0; i < h.deposits.length; i++){
            hw += h.deposits[i].amount * (currentRound.timestamp - h.deposits[i].timestamp);
        }
        return hw;
    }

    /**
     * @notice Claim bought tokens
     */
    function claimBoughtTokens() onlyOwner external {
        require(token.transfer(owner, boughtTokens));
        boughtTokens = 0;
    }

    /**
    * @notice Transfer all Ether held by the contract to the owner.
    */
    function reclaimEther()  onlyOwner external {
        owner.transfer(address(this).balance);
    }

    function isHolder(address beneficiary) view internal returns(bool){
        return holders[beneficiary].priceLimit > 0;
    }

    function arrayIsAscSorted(uint256[] arr) pure internal returns(bool){
        require(arr.length > 0);
        for(uint256 i=0; i < arr.length-1; i++) {
            if(arr[i] > arr[i+1]) return false;
        }
        return true;
    }

    /**
     * Our random generator is based on standart LCG formula X[n+1] = (a*X[n]+b) mod m
     * see https://en.wikipedia.org/wiki/Linear_congruential_generator
     */
    function getRand(uint64 prev) pure public returns(uint64) {
        return uint64((RAND_MULTIPLIER * uint256(prev) + RAND_INCREMENT) % RAND_MODULUS);
    }


}