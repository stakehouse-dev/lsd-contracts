# Liquid Staking Derivative Networks Smart Contracts
# Overview

Liquid Staking Derivative (LSD) Networks are permissionless networks deployed on top of the Stakehouse protocol that serves as an abstraction for consensus layer assets. LSD participants can enjoy fractionalized validator ownership with deposits as little as 0.001 ether. 

Liquidity provisioning is made easier thanks to giant liquidity pools that can supply the ether required for any validator being created in any liquid staking network. Stakehouse protocol derivatives minted within LSDs all benefit from shared dETH liquidity allowing for maximum Ethereum decentralization whilst the rising tide of dETH liquidity raises all boats.

Blockswap Labs is the core contributor of the Liquid Staking Derivatives suite of contracts and is heavily testing the smart contracts in parallel to any external efforts to find and fix bugs as safety of user's funds prevails above launching a new offering.

## Contracts overview
<img width="1222" alt="image" src="https://user-images.githubusercontent.com/70540321/199479093-ec45cadd-91d7-47f0-811f-1d0016b95189.png">

LSD network instances are instantiated from the LSD network factory. This will deploy the contracts required for the operation of a LSD network:
- SavETH Vault - protected staking vault where up to 24 ETH per validator can be staked for dETH 
- Staking Funds - Staking funds for fees and MEV collecting 50% of all cashflow from EIP1559

Contracts deployed on demand:
- Node Runner smart wallets for facilitating Ethereum Deposit Contract staking via the Stakehouse protocol
- Syndicate for facilitating distribution of EIP1559 rewards 50% to node runners and 50% to the Staking Funds Vault
- LP tokens for either Giant pool liquidity or liquidity for individual LSD networks

## Mechanics and design - 3 pool strategy for curating 32 ETH
Node runners can register a validator BLS public key if they supply `4 ETH`.

For every registered BLS public key, rest of the ETH is crowd sourced as follows:
- SavETH Vault - users can pool up to `24 ETH` where protected staking ensures no-loss. dETH can be redeemed after staking
- Staking funds vault - users can pool up to `4 ETH` where the user's share of LP token will entitle them to a percentage of half of all network revenue

Once the 3 pool strategy reaches its 32 ETH target per validator, node runners can proceed to trigger sending of the queued funds to the Ethereum Deposit Contract after being registered by the Stakehouse protocol. 

Finally, once certified by the beacon chain, Stakehouse protocol derivatives can be minted which automatically takes care of a number of actions:
- Allocate savETH <> dETH to `savETH Vault` (24 dETH)
- Register validator to syndicate so that the node runner can get 50% of network revenue and staking funds LPs can get a pro rata share of the other 50% thanks to SLOT tokens

All 3 pools own a fraction of a regular 32 ETH validator with the consensus and network revenue split amongst the 3 pools.

## Flow for creating an LSD validator within the Stakehouse protocol

1) Node runner registers validator credentials and supplies first 4 ETH
2) SavETH Vault and Staking Funds Vault fills up with ETH for the KNOT until total of 32 ETH is reached (if needed, liquidity from Giant pool can be sourced)
3) Node runner with their representative stake the validator
4) After Consensus Layer approves validator, derivatives can be minted

## Node runner risks

Node runners must supply exactly 4 ETH per validator credentials in order to shield the protocol from risks of mismanaging node. Should there be an error in node running, the node runner's capital is at risk of being slashed by anyone on the market via the Stakehouse protocol.

# Video Walkthrough + External documentation

Walkthrough: https://www.youtube.com/watch?v=7UHDUA9l6Ek

Documentation: https://docs.joinstakehouse.com/lsd/overview

# Installing Dependencies

`yarn` or `yarn install` will do the trick.

# Tests

Foundry tests can be run with the following command:
```
yarn test
```

If anything requires more verbose logging, then the following can be run:
```
yarn test-debug
```
