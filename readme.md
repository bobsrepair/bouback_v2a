# Buyback contract v2a

This repository contains contract for BobsRepair Buyback program, version 2 variant a.

## Buyback program rules
* To participate in the buyback program you will need to deposit your BOB Tokens to the smart contract.
* Your chance of being selected as a winner is based on the amount of BOB tokens you have deposited in relation with the total amount of BOB Tokens everyone has deposited. If you have more BOB Tokens in the smart contract you have a greater chance of being selected as a winner. 
* For every buyback round, a certain number of BOB Token holders (exact number decided at time of each round) are randomly selected as winners by the smart contract which in turn purchases a portion of their BOB Tokens in exchange for ETH, at a price set by the company.
* If you would like to withdraw a portion of your BOB Tokens from the smart contract, your original deposit time for the remainder of the tokens does not change and you do not lose the extra weight of having them in the contract for longer.
* If you want to add more tokens to the smart contract, the addition is counted as a new deposit with it's own deposit time. 
* You are given the option of setting the desired minimum selling price for your BOB Tokens, and this selling price will remain the same for all deposits made. You cannot set a different selling price for different deposits made.

## Technical notes
* Buyback process consists of 2 or more transactions:
	1. Setup Buyback round tx, which contains ETH transfer requires for buyback and sets required variables, including random hash of previous block. Previous block is used because current block hash is not available at the time of processing transaction. After this transaction winners are actually selected.
	2. One or more (if one requires too much gas) tx which sends ETH to winners. Last transaction also closes buyback round.
* During buyback round deposits and withdraws are paused
* For selecting winners we use a hash of a block, previous to Setup Buyback round tx, as a source of randomness.
