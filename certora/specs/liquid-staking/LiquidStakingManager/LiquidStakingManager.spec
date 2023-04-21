
methods {
    isNodeRunnerWhitelisted(address) returns bool envfree
    smartWalletRepresentative(address) returns address envfree
    smartWalletOfKnot(bytes) returns address envfree
    smartWalletOfNodeRunner(address) returns address envfree
    nodeRunnerOfSmartWallet(address) returns address envfree
    stakedKnotsOfSmartWallet(address) returns uint256 envfree
    smartWalletDormantRepresentative(address) returns address envfree
    bannedBLSPublicKeys(bytes) returns address envfree
    bannedNodeRunners(address) returns bool envfree
    numberOfKnots() returns uint256 envfree
    daoCommissionPercentage() returns uint256 envfree
    dao() returns address envfree
    stakehouseTicker() returns string envfree
    enableWhitelisting() returns bool envfree
    isBLSPublicKeyPartOfLSDNetwork(bytes) returns bool envfree
    isBLSPublicKeyBanned(bytes) returns bool envfree
    isNodeRunnerBanned(address) returns bool envfree
    getBalance(address) returns uint256 envfree

    execute(address,bytes) returns bytes => DISPATCHER(true)
}

rule shouldUpdateDAOAddress(env e, address newDAO) {
    address previousDAO = dao();
    updateDAOAddress(e, newDAO);
    address updatedDAO = dao();

    assert previousDAO != updatedDAO, "DAO address not changed";
    assert newDAO == updatedDAO, "Unknown DAO address set";
}

rule shouldUpdateDAOCommissionPercentage(env e, uint256 newCommission) {
    uint256 oldPercentage = daoCommissionPercentage();
    updateDAORevenueCommission(e, newCommission);
    uint256 newPercentage = daoCommissionPercentage();

    assert oldPercentage != newPercentage, "Update to same revenue percentage";
    assert newPercentage == newCommission, "Update unsuccessful";
}
/*
rule shouldUpdateStakehouseTicker(env e, string newTicker) {
    require newTicker.length >= 3 && newTicker.length <= 5;

    string oldTicker = stakehouseTicker();
    assert oldTicker.length >=3 && oldTicker.length <= 5, "Invalid ticker length";

    updateTicker(e, newTicker);
    string updatedTicker = stakehouseTicker();

    assert oldTicker != updatedTicker, "Ticker not updated";
    assert updatedTicker == newTicker, "Update to invalid ticker";
}
*/
rule shouldUpdateWhitelisting(env e, bool whitelistStatus) {
    bool previousStatus = enableWhitelisting();
    updateWhitelisting(e, whitelistStatus);
    bool newStatus = enableWhitelisting();

    assert whitelistStatus == newStatus, "Update to invalid status";
    assert previousStatus != newStatus, "Status did not update";
}

rule shouldUpdateNodeRunnerWhitelistingStatus(env e, address nodeRunner, bool whitelistStatus) {
    bool previousStatus = isNodeRunnerWhitelisted(nodeRunner);
    updateNodeRunnerWhitelistStatus(e, nodeRunner, whitelistStatus);
    bool updatedStatus = isNodeRunnerWhitelisted(nodeRunner);

    assert previousStatus != updatedStatus, "Status not updated";
    assert updatedStatus == whitelistStatus, "Invalid status update";
}

rule shouldUpdateEOARepresentative(env e, address newRepresentative) {
    address smartWallet = smartWalletOfNodeRunner(e.msg.sender);
    address oldRepresentative = smartWalletRepresentative(smartWallet);

    rotateEOARepresentative(e, newRepresentative);

    assert oldRepresentative != newRepresentative, "Same representative";
    assert smartWalletRepresentative(smartWallet) == newRepresentative, "Representative not rotated";
}

rule shouldWithdrawETHForKnot(env e, address receiver, bytes blsPublicKey) {
    require blsPublicKey.length == 64;
    uint256 balanceBefore = getBalance(receiver);

    withdrawETHForKnot(e, receiver, blsPublicKey);
    uint256 balanceAfter = getBalance(receiver);

    bool banStatus = isBLSPublicKeyBanned(blsPublicKey);

    assert balanceAfter - balanceBefore == 4000000000000000000, "Incorrect balance update";
    assert banStatus == true, "BLS public key not banned";
}

// TODO - this is failing still - figure out why
rule shouldClaimRewardsAsNodeRunner(env e, address nodeRunner, bytes[] blsPublicKeys) {

    uint256 nodeRunnerBalanceBefore = getBalance(nodeRunner);

    // Call claim
    claimRewardsAsNodeRunner(e, nodeRunner, blsPublicKeys);

    // Check claim was successful
    uint256 nodeRunnerBalanceAfter = getBalance(nodeRunner);
    assert nodeRunnerBalanceAfter > nodeRunnerBalanceBefore;

    // Call again
    env e2;
    claimRewardsAsNodeRunner@withrevert(e2, nodeRunner, blsPublicKeys);

    // Assert revert
    assert lastReverted;
}

rule sanity(env e, method f) {
    calldataarg args;
    f(e, args);
    assert false;
}