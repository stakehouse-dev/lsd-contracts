certoraRun \
certora/specs/liquid-staking/StakingFundsVault/CertoraMockStakingFundsVault.sol \
contracts/smart-wallet/OwnableSmartWallet.sol \
contracts/liquid-staking/LPTokenFactory.sol \
contracts/liquid-staking/LPToken.sol \
contracts/syndicate/Syndicate.sol \
contracts/testing/liquid-staking/Receiver.sol \
contracts/testing/stakehouse/MockAccountManager.sol \
contracts/testing/liquid-staking/Sender.sol \
    --verify CertoraMockStakingFundsVault:certora/specs/liquid-staking/StakingFundsVault/StakingFundsVault.spec \
    --loop_iter 1 --optimistic_loop \
    --msg "StakingFundsVault" \
    --packages @blockswaplab=node_modules/@blockswaplab @openzeppelin=node_modules/@openzeppelin \
    --send_only \
    --optimize 1 \
    --rule totalSupplyOfAnyLPTokenNeverExceedsFourEtherForFeesAndMev \
    --settings -optimisticFallback=true
