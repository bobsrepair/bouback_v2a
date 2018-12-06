# Buyback contract v2a

This repository contains contract for BobsRepair Buyback program, version 2 variant a.

## Buyback program rules
* To participate in buyback program you need to deposit you BOB tokens to your balance on Buyback contract. When you do it you can also specify a minimum price (in ETH) you would like to sell your BOB tokens.
* Your chance to be selected as winner of current buyback round is proportional to amount of BOB tokens on your account inside Buyback contract and the time passed from your deposits to current round.
* You can be selected as a winner only if the price you want to sell your BOB is lower then current buyback round price.
* You can change that desired sell price at any time without loosing your chances to be selected as a winner.
* If you want to withdraw tokens from deposit, only the rest amount is counted, and time of deposit is not changed.
* If you want to add more tokens to a deposit, it is counted as a new deposit with it's own deposit time. Desired sell price is common for all deposits.

## Technical notes
* For selecting winners we use a hash of a block, previous to start current round tx, as a source of randomness.
* Buyback process consists of 2 or more transactions:
	1. Setup Buyback round tx, which contains ETH transfer requires for buyback and sets required variables, including random hash of previous block. Previous block is used because current block hash is not available at the time of processing transaction. After this transaction winners are actually selected.
	2. One or more (if one requires too much gas) tx which sends ETH to winners. Last transaction also closes buyback round.
* During buyback round deposits and withdraws are paused