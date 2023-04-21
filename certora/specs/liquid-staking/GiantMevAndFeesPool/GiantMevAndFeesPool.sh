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
certora/harness/liquid-staking/GiantMevAndFeesPoolHarness.sol \
contracts/liquid-staking/StakingFundsVault.sol \
contracts/liquid-staking/GiantLP.sol \
contracts/liquid-staking/LPToken.sol \
contracts/testing/stakehouse/MockAccountManager.sol \
contracts/syndicate/Syndicate.sol \
contracts/liquid-staking/LSDNFactory.sol \
    --verify GiantMevAndFeesPoolHarness:certora/specs/liquid-staking/GiantMevAndFeesPool/GiantMevAndFeesPool.spec \
    --link GiantLP:transferHookProcessor=GiantMevAndFeesPoolHarness \
            LPToken:transferHookProcessor=StakingFundsVault \
            GiantMevAndFeesPoolHarness:lpTokenETH=GiantLP \
    --optimistic_loop \
    --loop_iter 1 \
    --packages @blockswaplab=node_modules/@blockswaplab @openzeppelin=node_modules/@openzeppelin \
    --send_only \
    --optimize 1 \
    --settings -optimisticFallback=true,-optimisticUnboundedHashing=true,-t=2000,-mediumTimeout=2000,-depth=100 \
    --rule_sanity basic \
    $RULE \
    --msg "GiantMevAndFeesPool: $RULE $MSG"
