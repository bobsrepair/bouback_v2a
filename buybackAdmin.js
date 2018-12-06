var $ = jQuery;
jQuery(document).ready(function($) {

    let web3 = null;
    let tokenContract = null;
    let buybackContract = null;

    let ethereumPrice = null;


    setTimeout(init, 1000);
    async function init(){
        web3 = await loadWeb3();
        if(web3 === null) {
            setTimeout(init, 5000);
            return;
        }else if(web3 === false){
            return;
        }
        loadContract('./build/contracts/ERC20.json', function(data){
            tokenContract = data;
            $('#tokenABI').text(JSON.stringify(data.abi));
        });
        loadContract('./build/contracts/BobBuyback.json', function(data){
            buybackContract = data;
            $('#buybackABI').text(JSON.stringify(data.abi));
            initManageForm();
        });


        $.ajax('https://api.coinmarketcap.com/v1/ticker/ethereum/', {'dataType':'json', 'cache':'false', 'data':{'t':Date.now()}})
        .done(function(result){
            console.log('Ethereum ticker from CoinMarketCap:', result);
            ethereumPrice = Number(result[0].price_usd);
            $('#ethereumPrice').html(ethereumPrice.toFixed(2));
        });
        setInterval(function(){$('#clock').val( (new Date()).toISOString() )}, 1000);

        initPublishForm();
    }

    function initPublishForm(){
        let form = $('#publishContractForm');

    }
    function initManageForm(){
        let tokenAddress = getUrlParam('token');
        if(web3.utils.isAddress(tokenAddress)){
            $('input[name=token]', '#publishContractForm').val(tokenAddress);
        }

        let buybackAddress = getUrlParam('buyback');
        if(web3.utils.isAddress(buybackAddress)){
            $('input[name=buybackAddress]', '#manageBuyback').val(buybackAddress);
            $('#loadInfo').click();
        }

    }

    $('#publishBuyback').click(function(){
        if(buybackContract == null) return;
        printError('');
        let form = $('#publishContractForm');

        let token  = $('input[name=token]',form).val()
        if(!web3.utils.isAddress(token)){printError('Bad token address'); return;}


        let args = [token];
        console.log('Publishing '+buybackContract.contractName+' with arguments:', args);

        let buybackObj = new web3.eth.Contract(buybackContract.abi);
        buybackObj.deploy({
            data: buybackContract.bytecode,
            arguments: args
        })
        .send({
            from: web3.eth.defaultAccount,
        })
        .on('error',function(error){
            console.log('Publishing failed: ', error);
            printError(error);
        })
        .on('transactionHash',function(tx){
            $('input[name=publishedTx]',form).val(tx);
        })
        .on('receipt',function(receipt){
            let publishedAddress = receipt.contractAddress;
            $('input[name=publishedAddress]',form).val(publishedAddress);
            $('input[name=buybackAddress]','#manageBuyback').val(publishedAddress);
            //$('#loadInfo').click();
            window.location.href = window.location.origin+window.location.pathname+"?buyback="+publishedAddress;
        })
        .then(function(contractInstance){
            console.log('Buyback contract address: ', contractInstance.options.address) // instance with the new contract address
        });

    });


    $('#loadInfo').click(async function(){
        if(buybackContract == null) return;
        printError('');
        let form = $('#manageBuyback');

        let buybackAddress = $('input[name=buybackAddress]',form).val();
        let buybackInstance = loadContractInstance(buybackContract, buybackAddress);
        if(buybackInstance == null) return;

        let tokenAddress = await buybackInstance.methods.token().call();
        let tokenInstance = loadContractInstance(tokenContract, tokenAddress);
        $('input[name=tokenAddress]',form).val(tokenAddress);
        
        tokenInstance.methods.balanceOf(buybackAddress).call().then(function(result){
            $('input[name=bobBalance]',form).val(web3.utils.fromWei(result));
        });
        web3.eth.getBalance(buybackAddress).then(function(result){
            $('input[name=ethBalance]',form).val(web3.utils.fromWei(result));
        });


    });


    //====================================================

    async function loadWeb3(){
        printError('');
        // Modern dapp browsers...
        if (window.ethereum) {
            window.web3 = new Web3(ethereum);
            try {
                // Request account access if needed
                await ethereum.enable();
                // Acccounts now exposed
                let accounts = await web3.eth.getAccounts();
                if(typeof accounts[0] == 'undefined'){
                    printError('Please, unlock MetaMask');
                    return null;
                }else{
                    web3.eth.defaultAccount =  accounts[0];
                    window.web3 = web3;
                    return web3;
                }
            } catch (error) {
                printError('Please, reload the page and allow MetaMask to access accounts.');
                return false;
            }
        }
        // Legacy dapp browsers...
        else if (window.web3) {
            window.web3 = new Web3(web3.currentProvider);
            // Acccounts always exposed
            if(typeof accounts[0] == 'undefined'){
                printError('Please, unlock MetaMask');
                return null;
            }else{
                web3.eth.defaultAccount =  accounts[0];
                window.web3 = web3;
                return web3;
            }
        }
        // Non-dapp browsers...
        else {
            printError('Please, install MetaMask');
            return null;
        }
    }
    function loadContract(url, callback){
        $.ajax(url,{'dataType':'json', 'cache':'false', 'data':{'t':Date.now()}}).done(callback);
    }

    function loadContractInstance(contractDef, address){
        if(typeof contractDef == 'undefined' || contractDef == null) return null;
        if(!web3.utils.isAddress(address)){printError('Contract '+contractDef.contract_name+' address '+address+' is not an Ethereum address'); return null;}
        return new web3.eth.Contract(contractDef.abi, address);
    }

    function timeStringToTimestamp(str){
        return Math.round(Date.parse(str)/1000);
    }
    function timestmapToString(timestamp){
        return (new Date(timestamp*1000)).toISOString();
    }

    /**
    * Take GET parameter from current page URL
    */
    function getUrlParam(name){
        if(window.location.search == '') return null;
        let params = window.location.search.substr(1).split('&').map(function(item){return item.split("=").map(decodeURIComponent);});
        let found = params.find(function(item){return item[0] == name});
        return (typeof found == "undefined")?null:found[1];
    }

    function htmlEntities(str) {
        return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function printError(msg){
        if(msg == null || msg == ''){
            $('#errormsg').html('');    
        }else{
            console.error(msg);
            $('#errormsg').html(msg);
        }
    }
});
