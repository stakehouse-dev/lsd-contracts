using GiantLP as giantLP

methods {
    // GiantLP envfree
    giantLP.balanceOf(address) returns (uint256) envfree
    giantLP.totalSupply() returns (uint256) envfree

    // GiantMEVAndFeesPool envfree
    batchSize() returns (uint256) envfree
    depositBatchCount() returns (uint256) envfree
    stakedBatchCount() returns (uint256) envfree
    idleETH() returns (uint256) envfree
    totalETHFromLPs() returns (uint256) envfree
    MIN_STAKING_AMOUNT() returns (uint256) envfree
    withdrawableAmountOfETH(address) returns (uint256) envfree
    totalETHFundedPerBatch(address, uint256) returns (uint256) envfree
    accumulatedETHPerLPShare() returns (uint256) envfree
    paused() returns (bool) envfree
    getAssociatedDepositBatchIDAtIndex(address, uint256) returns (uint256) envfree
    ethRecycledFromBatch(uint256) returns (uint256) envfree
    allocatedBlsPubKeyForWithdrawalBatch(uint256) envfree
    allocatedWithdrawalBatchForBlsPubKey(bytes32) envfree

    // GiantMEVAndFeesPoolHarness envfree
    ethBalanceOf(address) returns (uint256) envfree
    thisAddress() returns (address) envfree
    isAssociatedDepositBatchesBoundedSet(address) returns (bool) envfree
    isRecycledDepositBatchesBoundedSet() returns (bool) envfree
    isRecycledStakedBatchesBoundedSet() returns (bool) envfree
    isRecycledStakedBatch(uint256) returns (bool) envfree
    nextFullRecycledStakedBatch() returns (int256) envfree
    isRecycledDepositBatch(uint256) returns (bool) envfree
    totalETHRecycled() returns (uint256) envfree
    isBatchIndexAssociatedToBLSKey(uint256) returns (bool) envfree
    isAssociatedDepositBatch(address, uint256) returns (bool) envfree
    computeWithdrawableAmountOfETH(address) returns (uint256) envfree

    // DISPATCHER(true)
    beforeTokenTransfer(address, address, uint256) => DISPATCHER(true)
    afterTokenTransfer(address, address, uint256) => DISPATCHER(true)
    totalSupply() returns (uint256) => DISPATCHER(true)
    balanceOf(address) returns (uint256) => DISPATCHER(true)
    transferFrom(address, address, uint256) returns(bool) => DISPATCHER(true)
    transfer(address, uint256) returns (bool) => DISPATCHER(true)
    deployer() returns (address) => DISPATCHER(true)
    burn(address,uint256) => DISPATCHER(true)
    mint(address,uint256) => DISPATCHER(true)
    isSavETHVault(address) => DISPATCHER(true)
    deployToken(address, address, string, string) => DISPATCHER(true)

    claimRewards(address, bytes[]) => DISPATCHER(true)
    isStakingFundsVault(address) returns (bool) => DISPATCHER(true)
    blsPublicKeyToLifecycleStatus(bytes) returns uint8 => DISPATCHER(true)
    burnLPTokensForETH(address[], uint256[]) => DISPATCHER(true)
    batchPreviewAccumulatedETH(address, address[]) returns (uint256) => DISPATCHER(true)
    //claimAsStaker(address, bytes[]) => DISPATCHER(true)
}

////////////////////////// Definitions //////////////////////////

definition isUtilityMethod(method f) returns bool =
       f.selector == ethBalanceOf(address).selector
    || f.selector == thisAddress().selector
    || f.selector == isAssociatedDepositBatchesBoundedSet(address).selector
    || f.selector == isRecycledDepositBatchesBoundedSet().selector
    || f.selector == isRecycledStakedBatchesBoundedSet().selector
    || f.selector == isRecycledStakedBatch(uint256).selector
    || f.selector == isRecycledDepositBatch(uint256).selector
    || f.selector == totalETHRecycled().selector
    || f.selector == isBatchIndexAssociatedToBLSKey(uint256).selector;

definition isPublicMethodForInternalUse(method f) returns bool =
    f.selector == afterTokenTransfer(address, address, uint256).selector;

definition isUncheckedMethod(method f) returns bool =
    isUtilityMethod(f)
    || isPublicMethodForInternalUse(f);

definition satisfiesDefinitionOfDepositBatchCount() returns bool =
    depositBatchCount() == (totalETHFromLPs() + totalETHRecycled()) / batchSize();

definition isBatchSizeInBounds() returns bool = batchSize() >= 4 * 10^18 && batchSize() <= 24 * 10^18;

definition ethFundedOrRecycledPerBatch(uint256 batchIndex) returns mathint =
    ethRecycledFromBatch(batchIndex) + totalETHFundedPerBatchSumGivenBatchIndex[batchIndex];

definition isStakedBatch(uint256 batchIndex) returns bool =
    batchIndex < stakedBatchCount() && !isRecycledStakedBatch(batchIndex);

definition isBatchIndexAssociatedToBLSKeyIffStakedAtIndex(uint256 batchIndex) returns bool =
    isBatchIndexAssociatedToBLSKey(batchIndex) <=> isStakedBatch(batchIndex);

definition areBatchIndicesAssociatedToBLSKeyIffStaked0To9() returns bool =
       isBatchIndexAssociatedToBLSKeyIffStakedAtIndex(0)
    && isBatchIndexAssociatedToBLSKeyIffStakedAtIndex(1)
    && isBatchIndexAssociatedToBLSKeyIffStakedAtIndex(2)
    && isBatchIndexAssociatedToBLSKeyIffStakedAtIndex(3)
    && isBatchIndexAssociatedToBLSKeyIffStakedAtIndex(4)
    && isBatchIndexAssociatedToBLSKeyIffStakedAtIndex(5)
    && isBatchIndexAssociatedToBLSKeyIffStakedAtIndex(6)
    && isBatchIndexAssociatedToBLSKeyIffStakedAtIndex(7)
    && isBatchIndexAssociatedToBLSKeyIffStakedAtIndex(8)
    && isBatchIndexAssociatedToBLSKeyIffStakedAtIndex(9);

definition areSetsOfDepositBatchesValidAtDepositBatchCount() returns bool =
       ethRecycledFromBatch(depositBatchCount()) == 0
    && totalETHFundedPerBatchSumGivenBatchIndex[depositBatchCount()] ==
        (totalETHFromLPs() + totalETHRecycled()) % batchSize();

definition areSetsOfDepositBatchesBounded(address user) returns bool =
       isAssociatedDepositBatchesBoundedSet(user)
    && isRecycledDepositBatchesBoundedSet()
    && isRecycledStakedBatchesBoundedSet();

definition areSetsOfDepositBatchesValidAtIndex(address user, uint256 batchIndex) returns bool =
       ethRecycledFromBatch(batchIndex) + totalETHFundedPerBatch(user, batchIndex) <= batchSize()
    && (totalETHFundedPerBatch(user, batchIndex) > 0 <=> isAssociatedDepositBatch(user, batchIndex))
    && (ethRecycledFromBatch(batchIndex) > 0 <=> isRecycledDepositBatch(batchIndex))
    && (isStakedBatch(batchIndex) => ethRecycledFromBatch(batchIndex) == 0)
    && ethFundedOrRecycledPerBatch(batchIndex) <= batchSize()
    && (batchIndex > depositBatchCount() =>
        ethFundedOrRecycledPerBatch(batchIndex) == 0)
    && (batchIndex < depositBatchCount() && !isStakedBatch(batchIndex) =>
        ethFundedOrRecycledPerBatch(batchIndex) == batchSize())
    && totalETHFundedPerBatchSumGivenBatchIndex[batchIndex] >= totalETHFundedPerBatch(user, batchIndex);

definition areSetsOfDepositBatchesValidAt0To9(address user) returns bool =
       areSetsOfDepositBatchesBounded(user)
    && areSetsOfDepositBatchesValidAtDepositBatchCount()
    && areSetsOfDepositBatchesValidAtIndex(user, 0)
    && areSetsOfDepositBatchesValidAtIndex(user, 1)
    && areSetsOfDepositBatchesValidAtIndex(user, 2)
    && areSetsOfDepositBatchesValidAtIndex(user, 3)
    && areSetsOfDepositBatchesValidAtIndex(user, 4)
    && areSetsOfDepositBatchesValidAtIndex(user, 5)
    && areSetsOfDepositBatchesValidAtIndex(user, 6)
    && areSetsOfDepositBatchesValidAtIndex(user, 7)
    && areSetsOfDepositBatchesValidAtIndex(user, 8)
    && areSetsOfDepositBatchesValidAtIndex(user, 9)
    // The final check below is a sanity check, to verify that depositBatchCount is kept
    // sufficiently low for the verification to be sensible. This may require additional
    // restrictions on depositBatchCount, depending on which method is being verified.
    && depositBatchCount() < 8;

definition areSetsOfDepositBatchesValidAt0To2(address user) returns bool =
       areSetsOfDepositBatchesBounded(user)
    && areSetsOfDepositBatchesValidAtDepositBatchCount()
    && areSetsOfDepositBatchesValidAtIndex(user, 0)
    && areSetsOfDepositBatchesValidAtIndex(user, 1)
    && areSetsOfDepositBatchesValidAtIndex(user, 2)
    // The final check below is a sanity check, to verify that depositBatchCount is kept
    // sufficiently low for the verification to be sensible. This may require additional
    // restrictions on depositBatchCount, depending on which method is being verified.
    && depositBatchCount() <= 2;

////////////////////////// Ghosts //////////////////////////

ghost mapping(address => mathint) totalETHFundedPerBatchSumGivenUser {
    init_state axiom forall address a. totalETHFundedPerBatchSumGivenUser[a] == 0;
}

ghost mapping(uint256 => mathint) totalETHFundedPerBatchSumGivenBatchIndex {
    init_state axiom forall uint256 i. totalETHFundedPerBatchSumGivenBatchIndex[i] == 0;
}

////////////////////////// Hooks //////////////////////////

hook Sstore totalETHFundedPerBatch[KEY address a][KEY uint256 i] uint256 y (uint256 old_y) STORAGE {
    totalETHFundedPerBatchSumGivenUser[a] = totalETHFundedPerBatchSumGivenUser[a] - old_y + y;
    totalETHFundedPerBatchSumGivenBatchIndex[i] = totalETHFundedPerBatchSumGivenBatchIndex[i] - old_y + y;
}

////////////////////////// Sanity check //////////////////////////

rule sanityCheckAllShouldFail(method f, env e, calldataarg args)
{
    f(e, args);
    assert false;
}

////////////////////////// depositETH rules //////////////////////////

// PASS https://prover.certora.com/output/73821/592f2170e3b4490aba1263d2e668ccd0/?anonymousKey=3d6465238e6fc58705a16c3bd63eb1e3fe24b683
rule depositETHTransfersETH()
{
    address this = thisAddress();

    env e;
    uint256 amount;
    require e.msg.sender != this;

    uint256 thisBalanceBefore = ethBalanceOf(this);
    uint256 senderBalanceBefore = ethBalanceOf(e.msg.sender);

    depositETH(e, amount);

    uint256 thisBalanceAfter = ethBalanceOf(this);
    uint256 senderBalanceAfter = ethBalanceOf(e.msg.sender);

    assert thisBalanceAfter - thisBalanceBefore == amount;
    assert senderBalanceBefore - senderBalanceAfter == amount;
}

// PASS https://prover.certora.com/output/73821/2d6a1da7c3b343d4911772a4efcc880b/?anonymousKey=7970afacda9f5a57b379d9848235f97ea5751dbf
rule depositETHMintsLPTokens()
{
    env e; uint256 amount;

    uint256 balanceBefore = giantLP.balanceOf(e.msg.sender);

    // Require this ERC20 contract invariant, to avoid an unchecked overflow in the ERC20 contract:
    require balanceBefore <= giantLP.totalSupply();

    depositETH(e, amount);

    uint256 balanceAfter = giantLP.balanceOf(e.msg.sender);

    assert balanceAfter - balanceBefore == amount;
}

// PASS https://prover.certora.com/output/73821/a9128b6d38a6412eb23bc65e43486127/?anonymousKey=c9737f4e69319b67180a335a0a94a5de7aa47e38
rule depositETHIncreasesIdleETH()
{
    uint256 idleBefore = idleETH();

    env e; uint256 amount;
    depositETH(e, amount);

    uint256 idleAfter = idleETH();
    assert idleAfter - idleBefore == amount;
}

// PASS https://prover.certora.com/output/73821/f5bd3c7a23924bf6aab218332d3bb8bb/?anonymousKey=c70de978f5029be0b0083f6b52d787140e62eaf2
rule depositETHIncreasesTotalETHFromLPs()
{
    uint256 ethBefore = totalETHFromLPs();

    env e; uint256 amount;
    depositETH(e, amount);

    uint256 ethAfter = totalETHFromLPs();
    assert ethAfter - ethBefore == amount;
}

// PASS https://prover.certora.com/output/73821/fea75b9c0220431ba5e4ad59dd3ed17f/?anonymousKey=1e90f0f6894c6b5d4626061dbf0efb74c6fe94c6
rule depositETHIncreasesWithdrawableAmountOfETH()
{
    env e; uint256 amount;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 3;
    // Fill up at most 3 batches:
    require amount <= batchSize() * 3;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();

    require areSetsOfDepositBatchesValidAt0To9(e.msg.sender);

    uint256 ethBefore = withdrawableAmountOfETH(e.msg.sender);

    depositETH(e, amount);

    uint256 ethAfter = withdrawableAmountOfETH(e.msg.sender);
    assert ethAfter - ethBefore == amount;
}

// PASS https://prover.certora.com/output/73821/6f83c250537444de89693cbde75dd222/?anonymousKey=73ba2dcb277051668e08a9b27bb2ea716dc8a700
rule depositETHTotalETHFundedPerBatchIsConstant()
{
    address user; uint256 batch;

    require batch < depositBatchCount();
    require !isRecycledDepositBatch(batch);

    uint256 fundedBefore = totalETHFundedPerBatch(user, batch);

    env e; uint256 amount;
    depositETH(e, amount);

    uint256 fundedAfter = totalETHFundedPerBatch(user, batch);

    assert fundedBefore == fundedAfter;
}

////////////////////////// withdrawETH rules //////////////////////////

// PASS https://prover.certora.com/output/73821/6de97a29017f473baba6b1160a16193d/?anonymousKey=71f29584e161e8109b3517ac9a4f3e374ab73315
rule withdrawETHTransfersETH()
{
    address this = thisAddress();

    env e;
    uint256 amount;
    require e.msg.sender != this;

    uint256 thisBalanceBefore = ethBalanceOf(this);
    uint256 senderBalanceBefore = ethBalanceOf(e.msg.sender);

    withdrawETH(e, amount);

    uint256 thisBalanceAfter = ethBalanceOf(this);
    uint256 senderBalanceAfter = ethBalanceOf(e.msg.sender);

    assert thisBalanceBefore - thisBalanceAfter == amount;
    assert senderBalanceAfter - senderBalanceBefore == amount;
}

// PASS https://prover.certora.com/output/73821/b1633112908d4404b201085fc54d521a/?anonymousKey=57908b2e318ba61f32214e72f52c8adf8ca16ccf
rule withdrawETHBurnsLPTokens()
{
    env e; uint256 amount;

    uint256 balanceBefore = giantLP.balanceOf(e.msg.sender);

    // Require this ERC20 contract invariant, to avoid an unchecked overflow in the ERC20 contract:
    require balanceBefore <= giantLP.totalSupply();

    withdrawETH(e, amount);

    uint256 balanceAfter = giantLP.balanceOf(e.msg.sender);

    assert balanceBefore - balanceAfter == amount;
}

// PASS https://prover.certora.com/output/73821/7778ffc061d048faadb98cb7f8764387/?anonymousKey=d7b50c87289c0d1198f213b5dcf439396b4a4846
rule withdrawETHDecreasesIdleETH()
{
    uint256 idleBefore = idleETH();

    env e; uint256 amount;
    withdrawETH(e, amount);

    uint256 idleAfter = idleETH();
    assert idleBefore - idleAfter == amount;
}

// PASS https://prover.certora.com/output/73821/b69f1d1483dd4bab96593ee9838f3f79/?anonymousKey=391ded5363cbdce68670963510a4328495ee3c2c
rule withdrawETHDecreasesTotalETHFromLPs()
{
    uint256 ethBefore = totalETHFromLPs();

    env e; uint256 amount;
    withdrawETH(e, amount);

    uint256 ethAfter = totalETHFromLPs();
    assert ethBefore - ethAfter == amount;
}

// PASS https://prover.certora.com/output/73821/b3692f86204b45a1b85124b0c35e9795/?anonymousKey=1a4a96bd588e7ecdd10a62e3daa87d83b505ecc2
rule withdrawETHDecreasesWithdrawableAmountOfETH()
{
    env e; uint256 amount;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 2;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();

    require areSetsOfDepositBatchesValidAt0To2(e.msg.sender);

    uint256 ethBefore = withdrawableAmountOfETH(e.msg.sender);

    require ethBefore <= amount;

    withdrawETH(e, amount);

    uint256 ethAfter = withdrawableAmountOfETH(e.msg.sender);
    assert ethBefore - ethAfter == amount;
}

// PASS https://prover.certora.com/output/73821/208519d7f4284b3a9041af49dfc784bc/?anonymousKey=3236953660c19ca514c7d22c17b9fcc6dbaee77c
rule withdrawETHRevertsOnLargeWithdraw()
{
    env e; uint256 amount;

    require withdrawableAmountOfETH(e.msg.sender) < amount;

    withdrawETH@withrevert(e, amount);

    assert lastReverted;
}

//////////////////////// withdrawableAmountOfETH rules //////////////////////////

// PASS https://prover.certora.com/output/73821/764af21cf1744a649af7b202427b42e9/?anonymousKey=adafdef1f9b97240aed06163f02a1cb180f63d01
rule definitionOfWithdrawableAmountOfETH(method f)
filtered { f ->
       !isUncheckedMethod(f)
    && f.selector != depositETH(uint256).selector
    // Certora is having issues with onStakeHarness bytes argument:
    && f.selector != onStakeHarness(bytes32).selector }
{
    env e; calldataarg args;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 2;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();
    require areSetsOfDepositBatchesValidAt0To2(e.msg.sender);

    assert withdrawableAmountOfETH(e.msg.sender) == computeWithdrawableAmountOfETH(e.msg.sender);

    f(e, args);

    assert withdrawableAmountOfETH(e.msg.sender) == computeWithdrawableAmountOfETH(e.msg.sender);
}

// PASS https://prover.certora.com/output/73821/5edfeb6c8b64405ba2e12b06a7c8a991/?anonymousKey=6a3dd1cb21470ae18a1b1aa4f14c5b1e42f29b8e
rule definitionOfWithdrawableAmountOfETHForDepositETH()
{
    env e; uint256 amount;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 3;
    // Fill up at most 3 batches:
    require amount <= batchSize() * 3;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();

    require areSetsOfDepositBatchesValidAt0To9(e.msg.sender);

    require withdrawableAmountOfETH(e.msg.sender) == computeWithdrawableAmountOfETH(e.msg.sender);

    depositETH(e, amount);

    assert withdrawableAmountOfETH(e.msg.sender) == computeWithdrawableAmountOfETH(e.msg.sender);
}

//////////////////////////////// On Stake ///////////////////////////////////////////

// PASS https://prover.certora.com/output/73821/e2961743d07f46cd964c8f60aaf39508/?anonymousKey=9e7bf7ae142c5aac9d3897dfac8a41ef7305de50
rule onStakeIncreasesStakedBatchCount()
{
    env e; bytes32 blsKey;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 8;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();
    require areSetsOfDepositBatchesValidAt0To9(e.msg.sender);

    require to_mathint(nextFullRecycledStakedBatch()) == to_mathint(-1);

    uint256 stakedBatchCountBefore = stakedBatchCount();

    onStakeHarness(e, blsKey);

    uint256 stakedBatchCountAfter = stakedBatchCount();

    assert stakedBatchCountAfter == stakedBatchCountBefore + 1;
}

// PASS https://prover.certora.com/output/73821/7c5d6c95cdb34f6c8a2b9ebe07749d2a/?anonymousKey=a1eb5e675b79b527b94743c6ff6fefde005b5483
rule onStakeAllocatesStakedBatchCount()
{
    env e; bytes32 blsKey;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 8;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();
    require areSetsOfDepositBatchesValidAt0To9(e.msg.sender);

    require to_mathint(nextFullRecycledStakedBatch()) == to_mathint(-1);

    onStakeHarness(e, blsKey);

    uint256 batchAfter = allocatedWithdrawalBatchForBlsPubKey(blsKey);

    assert stakedBatchCount() == batchAfter + 1;
}

// PASS https://prover.certora.com/output/73821/ca31717b19154c4b8fa9b8d59c52c52c/?anonymousKey=4b369293b649c4f5eff488ca6c1b13618a583cb5
rule onStakeStakedBatchCountIsConstant()
{
    env e; bytes32 blsKey;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 8;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();
    require areSetsOfDepositBatchesValidAt0To9(e.msg.sender);

    require to_mathint(nextFullRecycledStakedBatch()) != to_mathint(-1);

    uint256 stakedBatchCountBefore = stakedBatchCount();

    onStakeHarness(e, blsKey);

    uint256 stakedBatchCountAfter = stakedBatchCount();

    assert stakedBatchCountAfter == stakedBatchCountBefore;
}

// PASS https://prover.certora.com/output/73821/8c1d029c9893467d92daf25881e6d3fa/?anonymousKey=3bb2cd27eaf27b76954e63ffc67c09307f5a4a4f
rule onStakeAllocatesRecycledStakedBatch()
{
    env e; bytes32 blsKey;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 8;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();
    require areSetsOfDepositBatchesValidAt0To9(e.msg.sender);

    int256 batchToAllocate = nextFullRecycledStakedBatch();
    require to_mathint(batchToAllocate) != to_mathint(-1);

    onStakeHarness(e, blsKey);

    uint256 batchAllocated = allocatedWithdrawalBatchForBlsPubKey(blsKey);

    assert to_mathint(batchAllocated) == to_mathint(batchToAllocate);
}

// PASS https://prover.certora.com/output/73821/c75ccd4c177c4cf6af95b107cc660f81/?anonymousKey=bf2b884d5bc431ea0b5cbfd4b08dbac065be58af
rule onStakeAssociatesBatchToBLSKey()
{
    env e; bytes32 blsKey;

    onStakeHarness(e, blsKey);

    uint256 batch = allocatedWithdrawalBatchForBlsPubKey(blsKey);

    assert isBatchIndexAssociatedToBLSKey(batch);
}

// PASS https://prover.certora.com/output/73821/ffc70d44f1e34dec82f1b3fefc9ee0d0/?anonymousKey=df68f5e7efd3b74e71e7dcfde3beabdfb1972392
rule onStakeDecreasesWithdrawableAmountOfETH()
{
    env e; bytes32 blsKey; address user;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 8;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();
    require areSetsOfDepositBatchesValidAt0To9(user);

    uint256 batchBefore = allocatedWithdrawalBatchForBlsPubKey(blsKey);
    require !isBatchIndexAssociatedToBLSKey(batchBefore);

    uint256 withdrawableBefore = withdrawableAmountOfETH(user);

    onStakeHarness(e, blsKey);

    uint256 withdrawableAfter = withdrawableAmountOfETH(user);

    uint256 batch = allocatedWithdrawalBatchForBlsPubKey(blsKey);

    assert withdrawableBefore - withdrawableAfter == totalETHFundedPerBatch(user, batch);
}

/////////////////// Invariants and invaraints stated as rules ////////////////////////

// PASS https://prover.certora.com/output/73821/cd39ced04f36409faf9498333b183af0/?anonymousKey=c6a89fc7cb0658a467cb16c43533cc1373fd3325
rule batchSizeIsConstantInBounds(method f)
filtered { f -> !isUncheckedMethod(f) }
{
    require isBatchSizeInBounds();

    uint256 batchSizeBefore = batchSize();

    env e;
    calldataarg args;
    f(e, args);

    uint256 batchSizeAfter = batchSize();

    assert batchSizeBefore == batchSizeAfter;
}

// PASS https://prover.certora.com/output/73821/6c90b5553b984dcfa49622e5dd2fe07e/?anonymousKey=5973537fe41d75de0827e1312191ef4990481db6
invariant stakedBatchCountIsUpperBoundedByDepositBatchCount()
    stakedBatchCount() <= depositBatchCount()
filtered { f -> !isUncheckedMethod(f) }

// PASS https://prover.certora.com/output/73821/d0e315d0050b4ddbb2bafe981c80f04f/?anonymousKey=15bfe5ebdcf4970257e9013f9a171c829f1b98b2
invariant totalETHFromLPsIsTotalSupplyOfLPTokens()
    totalETHFromLPs() == giantLP.totalSupply()
filtered { f -> !isUncheckedMethod(f) }

// PASS https://prover.certora.com/output/73821/75adb42161e1492ca3d59f5a06e2859a/?anonymousKey=f9d4b88c2d4313c03b808be5482465346778b61c
invariant batchIndicesAssociatedToBLSKeyIffStaked0To9()
    areBatchIndicesAssociatedToBLSKeyIffStaked0To9()
filtered { f -> !isUncheckedMethod(f) && f.selector != onStakeHarness(bytes32).selector }

// PASS https://prover.certora.com/output/73821/75adb42161e1492ca3d59f5a06e2859a/?anonymousKey=f9d4b88c2d4313c03b808be5482465346778b61c
// Specialisation of batchIndicesAssociatedToBLSKeyIffStaked0To9 for onStakeHarness
rule batchIndicesAssociatedToBLSKeyIffStaked0To9ForOnStake()
{
    env e; bytes32 blsKey; address user;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 9;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    require areSetsOfDepositBatchesValidAt0To9(user);

    require areBatchIndicesAssociatedToBLSKeyIffStaked0To9();

    onStakeHarness(e, blsKey);

    assert areBatchIndicesAssociatedToBLSKeyIffStaked0To9();
}

// PASS https://prover.certora.com/output/73821/140decf5eb0f406e8c4247061d372208/?anonymousKey=78335ab518b8eb5171828dea1a64e98097fa48da
rule setsOfDepositBatchesAreValidAt0To2(method f)
filtered { f ->
       !isUncheckedMethod(f)
    // Filter out depositETH, since it has a special rule for verifying this invariant:
    && f.selector != depositETH(uint256).selector
    && f.selector != jumpTheQueue(uint256, uint256, address).selector }
{
    env e; calldataarg args;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 2;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();

    require areSetsOfDepositBatchesValidAt0To2(e.msg.sender);

    f(e, args);

    assert areSetsOfDepositBatchesValidAt0To2(e.msg.sender);
}

// PASS https://prover.certora.com/output/73821/9457bcc76ef947b3afc5084a67f300e6/?anonymousKey=a9a7eb7c87ca0c2c1bf15de3a8deb9c4deee236a
// Specialisation of setsOfDepositBatchesAreValidAt0To2 to depositETH:
rule setsOfDepositBatchesAreValidAt0To9ForDepositETH()
{
    env e; uint256 amount;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 3;
    // Fill up at most 3 batches:
    require amount <= batchSize() * 3;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();

    require areSetsOfDepositBatchesValidAt0To9(e.msg.sender);

    depositETH(e, amount);

    assert areSetsOfDepositBatchesValidAt0To9(e.msg.sender);
}

// TIMEOUT
// Specialisation of setsOfDepositBatchesAreValidAt0To2 to jumpTheQueue
rule setsOfDepositBatchesAreValidAt0To2ForJumpTheQueue()
{
    env e; uint256 targetPosition; uint256 existingPosition;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 2;
    require targetPosition <= 2;
    require existingPosition <= 2;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();
    require areSetsOfDepositBatchesValidAt0To2(e.msg.sender);

    jumpTheQueue(e, targetPosition, existingPosition, e.msg.sender);

    assert areSetsOfDepositBatchesValidAt0To2(e.msg.sender);
}

// PASS https://prover.certora.com/output/73821/8f936a08c76747d28d9888d8a5f2263b/?anonymousKey=cdeecc72ea403ae42b6c46d6fae7aa2e1c6fda6d
invariant totalETHFundedIsLPTokenBalance(address user)
    totalETHFundedPerBatchSumGivenUser[user] == giantLP.balanceOf(user)
filtered { f -> !isUncheckedMethod(f) && f.selector != depositETH(uint256).selector }

// PASS https://prover.certora.com/output/73821/e79af38b2ae7499787d2536727b2266a/?anonymousKey=cf5a5e10a25df1dc3d0b2e89c1a77c0c3cb36bc2
// Specialisation of totalETHFundedIsLPTokenBalance to depositETH:
rule totalETHFundedIsLPTokenBalanceForDepositETH()
{
    address user;
    require totalETHFundedPerBatchSumGivenUser[user] == giantLP.balanceOf(user);

    env e; uint256 amount;

    // Require this ERC20 contract invariant, to avoid an unchecked overflow in the ERC20 contract:
    require giantLP.balanceOf(user) <= giantLP.totalSupply();

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 3;
    // Fill up at most 3 batches:
    require amount <= batchSize() * 3;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();
    require areSetsOfDepositBatchesValidAt0To9(e.msg.sender);

    depositETH(e, amount);

    assert totalETHFundedPerBatchSumGivenUser[user] == giantLP.balanceOf(user);
}

// PASS https://prover.certora.com/output/73821/b1824441cf7641aab39d1516989036c0/?anonymousKey=ce0f1e0d36abd05e5482687c001ac814221c5b1c
rule definitionOfDepositBatchCount(method f)
filtered { f ->
       !isUncheckedMethod(f)
    && f.selector != depositETH(uint256).selector
    && f.selector != jumpTheQueue(uint256, uint256, address).selector }
{
    env e; calldataarg args;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 2;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();
    require areSetsOfDepositBatchesValidAt0To2(e.msg.sender);

    f(e, args);

    assert satisfiesDefinitionOfDepositBatchCount();
}

// TIMEOUT
// Specialisation of definitionOfDepositBatchCount for jumpTheQueue
rule definitionOfDepositBatchCountForJumpTheQueue()
{
    env e; uint256 targetPosition; uint256 existingPosition;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 2;
    require targetPosition <= 2;
    require existingPosition <= 2;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();
    require areSetsOfDepositBatchesValidAt0To2(e.msg.sender);

    require satisfiesDefinitionOfDepositBatchCount();

    jumpTheQueue(e, targetPosition, existingPosition, e.msg.sender);

    assert satisfiesDefinitionOfDepositBatchCount();
}

// PASS https://prover.certora.com/output/73821/cac7327791524cbcb7683dfc1ec7dcf3/?anonymousKey=aa7659533b6b9d09eaff419735cc16047efd0688
// Specialisation of definitionOfDepositBatchCount for depositETH
rule definitionOfDepositBatchCountForDepositETH()
{
    env e; uint256 amount;

    // Restrict the number of deposit batch indices to check:
    require depositBatchCount() <= 3;
    // Fill up at most 3 batches:
    require amount <= batchSize() * 3;

    require isBatchSizeInBounds();
    requireInvariant stakedBatchCountIsUpperBoundedByDepositBatchCount();
    require satisfiesDefinitionOfDepositBatchCount();
    requireInvariant batchIndicesAssociatedToBLSKeyIffStaked0To9();
    require areSetsOfDepositBatchesValidAt0To9(e.msg.sender);

    depositETH(e, amount);

    assert satisfiesDefinitionOfDepositBatchCount();
}
