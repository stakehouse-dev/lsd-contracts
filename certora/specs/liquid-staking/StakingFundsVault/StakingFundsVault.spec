using Sender as sender

methods {
    totalRewardsReceived() returns uint256 envfree
    mint(address,uint256) => DISPATCHER(true)
    deployLPToken(address,address,string,string) => DISPATCHER(true)
    init(address,address,string,string) => DISPATCHER(true)
    beforeTokenTransfer(address,address,uint256) => DISPATCHER(true)
    afterTokenTransfer(address,address,uint256) => DISPATCHER(true)
    sendTo() => DISPATCHER(true)
    totalETHFromLPs() returns uint256 envfree
    burn(address, uint256) => DISPATCHER(true)
    depositETHForStaking(bytes, uint256) returns uint256
    getBalance(address) returns uint256 envfree
    getLPTokenBalance(address, bytes) returns uint256 envfree
    totalClaimed() returns uint256 envfree
    blsPublicKeyToLifecycleStatus(bytes) returns uint256 => DISPATCHER(true)
    getTotalSupplyOfLPAssociatedWithBLSPubKey(bytes) returns uint256 envfree
}

rule whoChangedTotalRewardsReceived(env e, method f, calldataarg args)
{
    uint256 rewardsReceivedBefore = totalRewardsReceived();
    f(e, args);
    uint256 rewardsReceivedAfter = totalRewardsReceived();
    assert rewardsReceivedAfter == rewardsReceivedBefore;
}

// TODO - this rule is failing
rule totalSupplyOfAnyLPTokenNeverExceedsFourEtherForFeesAndMev(env e, method f, calldataarg args)
{
    bytes blsPubKey; require blsPubKey.length == 64;
    //bytes blsPubKeyTwo; require blsPubKeyTwo.length == 64;
    f(e, args);
    assert getTotalSupplyOfLPAssociatedWithBLSPubKey(blsPubKey) <= 4000000000000000000;
}

// totalRewardsReceived() is an always increasing value
rule totalRewardsReceivedAlwaysIncreasing(env e, method f, calldataarg args)
{
    uint256 rewardsReceivedBefore = totalRewardsReceived();
    f(e, args);
    uint256 rewardsReceivedAfter = totalRewardsReceived();
    assert rewardsReceivedAfter >= rewardsReceivedBefore;
}

rule totalRewardsReceivedAndIdleETHShouldBeMutuallyIndependent(env e, method f, calldataarg args) 
{
    uint256 idleETHBefore = totalETHFromLPs();
    uint256 rewardsReceivedBefore = totalRewardsReceived();
    f(e, args);
    uint256 idleETHAfter = totalETHFromLPs();
    uint256 rewardsReceivedAfter = totalRewardsReceived();
    
    assert idleETHAfter != idleETHBefore => to_uint256(rewardsReceivedAfter - rewardsReceivedBefore) == 0, "Rewards should not have changed";
    assert rewardsReceivedAfter != rewardsReceivedBefore => to_uint256(idleETHAfter - idleETHBefore) == 0, "Idle ETH should not have changed";
}

rule shouldDepositETHForStaking(env e, method f, calldataarg args, bytes blsPublicKey)
{
    require blsPublicKey.length == 64;
    uint256 ethBalanceBefore = e.msg.value;
    uint256 lpTokenBalanceBefore = getLPTokenBalance(e.msg.sender, blsPublicKey);

    depositETHForStaking(e, blsPublicKey, ethBalanceBefore);

    uint256 ethBbalanceAfter = getBalance(e.msg.sender);
    uint256 lpTokenBalanceAfter = getLPTokenBalance(e.msg.sender, blsPublicKey);

    assert ethBalanceBefore - ethBbalanceAfter == lpTokenBalanceAfter - lpTokenBalanceBefore, "Incorrect amount of LP token minted";
}

// TODO - fix this
rule previewAndClaimShouldMatch(env e, bytes blsPublicKey) {
    require blsPublicKey.length == 64;
    require totalClaimed() == 0;
    require totalETHFromLPs() == 0;
    require totalRewardsReceived() > 10 ^ 18;
    require getBalance(currentContract) == totalRewardsReceived();

    uint256 balBefore = getBalance(e.msg.sender);

    address lpToken = lpTokenForKnot(e, blsPublicKey);
    address[] lpTokens = [lpToken];
    uint256 preview = batchPreviewAccumulatedETH(e, e.msg.sender, lpTokens);

    //claimReward(e, e.msg.sender, lpToken);
    uint256 balAfter = getBalance(e.msg.sender);

    assert totalRewardsReceived() == preview;
}

/// If ETH is sent to the contract, totalRewardsReceived() increases by the transferred amount
rule totalRewardsReceivedIncreasesAfterReceivingETH(env e) {
    require totalClaimed() == 0;
    require totalETHFromLPs() == 0;
    require totalRewardsReceived() == 0;

    uint256 contractBalanceBefore = getBalance(currentContract);

    uint256 transferAmount;
    require transferAmount > 0;
    sender.sendETH(e, currentContract, transferAmount);

    uint256 contractBalanceAfter = getBalance(currentContract);
    assert contractBalanceAfter == contractBalanceBefore + transferAmount;
}

/// TODO 2) We want to make sure that batchPreviewAccumulatedETH updates correctly after receiving ETH
/// TODO 3) When we claim rewards, they should be equal to amount of preview ETH
