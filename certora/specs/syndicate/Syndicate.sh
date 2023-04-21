certoraRun \
contracts/syndicate/Syndicate.sol \
contracts/testing/liquid-staking/Sender.sol \
    --verify Syndicate:certora/specs/syndicate/Syndicate.spec \
    --loop_iter 1 --optimistic_loop \
    --msg "Syndicate" \
    --packages @blockswaplab=node_modules/@blockswaplab @openzeppelin=node_modules/@openzeppelin \
    --send_only
