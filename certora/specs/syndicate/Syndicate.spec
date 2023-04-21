using Sender as sender

methods {
    numberOfRegisteredKnots() returns uint256 envfree
    totalClaimed() returns uint256 envfree
    sender.getBalance(address) returns uint256 envfree
}

rule registerKnotsToSyndicateIncreasesNumberOfRegisteredKnots(env e, bytes blsKey) {
 require blsKey.length == 64;
 bytes[] keys;
 require keys[0] == blsKey;

 uint256 numberOfRegisteredKnotsBefore = numberOfRegisteredKnots();

 registerKnotsToSyndicate(e, keys);

 uint256 numberOfRegisteredKnotsAfter = numberOfRegisteredKnots();

 assert numberOfRegisteredKnotsAfter == numberOfRegisteredKnotsBefore + 1;
}

/// If ETH is sent to the contract, totalRewardsReceived() increases by the transferred amount
rule totalRewardsReceivedIncreasesAfterReceivingETH(env e) {
    require totalClaimed() == 0;
    require totalRewardsReceived() == 0;

    uint256 contractBalanceBefore = sender.getBalance(currentContract);

    uint256 transferAmount;
    require transferAmount > 0;
    sender.sendETH(e, currentContract, transferAmount);

    uint256 contractBalanceAfter = sender.getBalance(currentContract);
    assert contractBalanceAfter == contractBalanceBefore + transferAmount;
}