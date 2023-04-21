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
certora/harness/liquid-staking/GiantPoolBaseHarness.sol \
contracts/liquid-staking/GiantLP.sol \
    --verify GiantPoolBaseHarness:certora/specs/liquid-staking/GiantPoolBase/GiantPoolBase.spec \
    --link GiantPoolBaseHarness:lpTokenETH=GiantLP \
    --optimistic_loop \
    --loop_iter 1 \
    --packages @blockswaplab=node_modules/@blockswaplab @openzeppelin=node_modules/@openzeppelin \
    --send_only \
    --optimize 1 \
    --settings -optimisticFallback=true,-optimisticUnboundedHashing=true,-t=2000,-mediumTimeout=2000,-depth=100 \
    --rule_sanity basic \
    $RULE \
    --msg "GiantPoolBase: $RULE $MSG"
