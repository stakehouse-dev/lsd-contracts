unset RULE
unset MSG

if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG="- $2"
fi

certoraRun \
certora/harness/liquid-staking/GiantSavETHVaultPoolHarness.sol \
contracts/liquid-staking/SavETHVault.sol \
contracts/liquid-staking/GiantLP.sol \
contracts/liquid-staking/GiantLPDeployer.sol \
contracts/liquid-staking/LPToken.sol \
contracts/testing/stakehouse/MockAccountManager.sol \
contracts/syndicate/Syndicate.sol \
contracts/liquid-staking/LSDNFactory.sol \
    --verify GiantSavETHVaultPoolHarness:certora/specs/liquid-staking/GiantSavETHVaultPool/GiantSavETHVaultPool.spec \
    --link GiantLP:transferHookProcessor=GiantSavETHVaultPoolHarness \
            LPToken:transferHookProcessor=SavETHVault \
            GiantSavETHVaultPoolHarness:lpTokenETH=GiantLP \
    --optimistic_loop \
    --loop_iter 1 \
    --packages @blockswaplab=node_modules/@blockswaplab @openzeppelin=node_modules/@openzeppelin \
    --send_only \
    --optimize 1 \
    --settings -optimisticFallback=true,-optimisticUnboundedHashing=true,-t=2000,-mediumTimeout=2000,-depth=100 \
    --rule_sanity basic \
    $RULE \
    --msg "GiantSavETHVaultPool: $RULE $MSG"
