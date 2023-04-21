pragma solidity ^0.8.13;

import "forge-std/console.sol";

import { SyndicateRewardsProcessor} from "../../../contracts/liquid-staking/SyndicateRewardsProcessor.sol";
import { StakingFundsVault } from "../../../contracts/liquid-staking/StakingFundsVault.sol";
import { LPToken } from "../../../contracts/liquid-staking/LPToken.sol";
import {
    TestUtils,
    MockLSDNFactory,
    MockLiquidStakingManager,
    MockAccountManager,
    IDataStructures
} from "../../utils/TestUtils.sol";

contract StakingFundsVaultTest is TestUtils {

    address operations = accountOne;

    MockLiquidStakingManager liquidStakingManager;
    StakingFundsVault vault;

    uint256 maxStakingAmountPerValidator;

    function maxETHDeposit(address _user, bytes[] memory _blsPubKeys) public {
        uint256[] memory amounts = new uint256[](_blsPubKeys.length);

        for (uint256 i; i < _blsPubKeys.length; ++i) {
            amounts[i] = maxStakingAmountPerValidator;
        }

        depositETH(_user, _blsPubKeys.length * maxStakingAmountPerValidator, amounts, _blsPubKeys);
    }

    function depositETH(address _user, uint256 _totalETH, uint256[] memory _amounts, bytes[] memory _blsPubKeys) public {
        require(_blsPubKeys.length > 0, "Empty array");

        // Give the user ETH
        vm.deal(_user, _totalETH);

        uint256 vaultBalanceBefore = address(vault).balance;

        // Impersonate the user and deposit ETH for all of the BLS keys
        vm.startPrank(_user);
        vault.batchDepositETHForStaking{value: _totalETH}(_blsPubKeys, _amounts);
        vm.stopPrank();

        // Check that the deposit worked
        assertEq(address(vault).balance - vaultBalanceBefore, _totalETH);
    }

    function setUp() public {
        factory = createMockLSDNFactory();
        liquidStakingManager = deployDefaultLiquidStakingNetwork(factory, admin);
        manager = liquidStakingManager;
        vault = liquidStakingManager.stakingFundsVault();
        maxStakingAmountPerValidator = vault.maxStakingAmountPerValidator();

        // set up BLS keys required to initials registered
        MockAccountManager(factory.accountMan()).setLifecycleStatus(blsPubKeyOne, 1);
        MockAccountManager(factory.accountMan()).setLifecycleStatus(blsPubKeyTwo, 1);
        MockAccountManager(factory.accountMan()).setLifecycleStatus(blsPubKeyThree, 1);

        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyTwo, true);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyThree, true);
    }

    function setSetupIsCorrect() public {
        assertEq(maxStakingAmountPerValidator, 4 ether);
    }

    // https://code4rena.com/reports/2022-11-stakehouse#h-18-old-stakers-can-steal-deposits-of-new-stakers-in-stakingfundsvault
    function testStealingOfDepositsByOldStakers_AUDIT() public {
        // Resetting the mocks, we need real action.
        MockAccountManager(factory.accountMan()).setLifecycleStatus(blsPubKeyOne, 0);
        MockAccountManager(factory.accountMan()).setLifecycleStatus(blsPubKeyTwo, 0);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, false);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyTwo, false);
        // Aliasing accounts for better readability.
        address nodeRunner = accountOne;
        address alice = accountTwo;
        address alice2 = accountFour;
        address bob = accountThree;
        // Node runner registers two BLS keys.
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFive);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFive);
        // Alice deposits to the MEV+fees vault of the first key.
        maxETHDeposit(alice, getBytesArrayFromBytes(blsPubKeyOne));
        // Someone else deposits to the savETH vault of the first key.
        liquidStakingManager.savETHVault().depositETHForStaking{value: 24 ether}(blsPubKeyOne, 24 ether);
        // The first validator is registered and the derivatives are minted.
        assertEq(vault.totalShares(), 0);
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        assertEq(vault.totalShares(), 4 ether);
        // Warping to pass the lastInteractedTimestamp checks. and activate knots in syndicate
        vm.warp(block.timestamp + 1 hours);
        vm.roll(block.number + 500);
        // The first key cannot accept new deposits since the maximal amount was deposited
        // and the validator was register. The vault however can still be used to deposit to
        // other keys.
        // Bob deposits to the MEV+fees vault of the second key.
        maxETHDeposit(bob, getBytesArrayFromBytes(blsPubKeyTwo));
        assertEq(address(vault).balance, 4 ether);
        assertEq(bob.balance, 0);
        // Alice is claiming rewards for the first key.
        // Notice that no rewards were distributed to the MEV+fees vault of the first key.
        assertEq(alice2.balance, 0);
        vm.startPrank(alice);
        vm.expectRevert("Nothing received");
        vault.claimRewards(alice2, getBytesArrayFromBytes(blsPubKeyOne));
        vm.stopPrank();
        LPToken lpTokenBLSPubKeyOne = vault.lpTokenForKnot(blsPubKeyOne);
        // Alice has stolen the Bob's deposit. Update: no longer true
        assertEq(alice2.balance, 0 ether);
        assertEq(vault.claimed(alice, address(lpTokenBLSPubKeyOne)), 0 ether);
        assertEq(vault.claimed(alice2, address(lpTokenBLSPubKeyOne)), 0);
        assertEq(address(vault).balance, 4 ether);
        assertEq(bob.balance, 0);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#h-09-incorrect-accounting-in-syndicaterewardsprocessor-results-in-any-lp-token-holder-being-able-to-steal-other-lp-tokens-holders-eth-from-the-fees-and-mev-vault
    function testRepetitiveClaim() public {
        // register BLS key with the network
        registerSingleBLSPubKey(accountTwo, blsPubKeyFour, accountFive);

        vm.label(accountOne, "accountOne");
        vm.label(accountTwo, "accountTwo");
        // Do a deposit of 4 ETH for bls pub key four in the fees and mev pool
        depositETH(accountTwo, maxStakingAmountPerValidator / 2, getUint256ArrayFromValues(maxStakingAmountPerValidator / 2), getBytesArrayFromBytes(blsPubKeyFour));
        depositETH(accountOne, maxStakingAmountPerValidator / 2, getUint256ArrayFromValues(maxStakingAmountPerValidator / 2), getBytesArrayFromBytes(blsPubKeyFour));

        // Do a deposit of 24 ETH for savETH pool
        liquidStakingManager.savETHVault().depositETHForStaking{value : 24 ether}(blsPubKeyFour, 24 ether);

        stakeAndMintDerivativesSingleKey(blsPubKeyFour);

        vm.roll(block.number + 200);

        LPToken lpTokenBLSPubKeyFour = vault.lpTokenForKnot(blsPubKeyFour);
        LPToken[] memory lpTokens = new LPToken[](1);
        lpTokens[0] = lpTokenBLSPubKeyFour;

        vm.warp(block.timestamp + 3 hours);

        // Deal ETH to the staking funds vault
        uint256 rewardsAmount = 1.2 ether;
        console.log("depositing %s wei into the vault.\n", rewardsAmount);
        vm.deal(address(vault), rewardsAmount);
        assertEq(address(vault).balance, rewardsAmount);
        assertEq(vault.batchPreviewAccumulatedETH(accountOne, lpTokens), rewardsAmount / 2);
        assertEq(vault.batchPreviewAccumulatedETH(accountTwo, lpTokens), rewardsAmount / 2);

        logAccounts();

        console.log("Claiming rewards for accountOne.\n");
        vm.prank(accountOne);
        vault.claimRewards(accountOne, getBytesArrayFromBytes(blsPubKeyFour));
        logAccounts();

        console.log("depositing %s wei into the vault.\n", rewardsAmount);
        vm.deal(address(vault), address(vault).balance + rewardsAmount);
        vm.warp(block.timestamp + 3 hours);
        logAccounts();

        console.log("Claiming rewards for accountOne.\n");
        vm.prank(accountOne);
        vault.claimRewards(accountOne, getBytesArrayFromBytes(blsPubKeyFour));
        logAccounts();

        console.log("Claiming rewards for accountOne AGAIN.\n");
        vm.prank(accountOne);
        vm.expectRevert("Nothing received");
        vault.claimRewards(accountOne, getBytesArrayFromBytes(blsPubKeyFour));
        logAccounts();

        console.log("Claiming rewards for accountOne AGAIN.\n");
        vm.prank(accountOne);
        vm.expectRevert("Nothing received");
        vault.claimRewards(accountOne, getBytesArrayFromBytes(blsPubKeyFour));
        logAccounts();

        console.log("Claiming rewards for accountTwo.\n");
        vm.prank(accountTwo);
        vault.claimRewards(accountTwo, getBytesArrayFromBytes(blsPubKeyFour));

    }

    function logAccounts() internal {
        LPToken lpTokenBLSPubKeyFour = vault.lpTokenForKnot(blsPubKeyFour);
        LPToken[] memory lpTokens = new LPToken[](1);
        lpTokens[0] = lpTokenBLSPubKeyFour;

        console.log("accountOne previewAccumulatedETH : %i", vault.batchPreviewAccumulatedETH(accountOne, lpTokens));
        console.log("accountOne claimed               : %i", SyndicateRewardsProcessor(vault).claimed(accountOne, address(vault.lpTokenForKnot(blsPubKeyFour))));
        console.log("accountTwo previewAccumulatedETH : %i", vault.batchPreviewAccumulatedETH(accountTwo, lpTokens));
        console.log("accountTwo claimed               : %i", SyndicateRewardsProcessor(vault).claimed(accountTwo, address(vault.lpTokenForKnot(blsPubKeyFour))));
        console.log("ETH Balances: accountOne: %i, accountTwo: %i, vault: %i\n", accountOne.balance, accountTwo.balance, address(vault).balance);
    }

    function testBatchDepositETHForStakingRevertsWhenETHNotAttached() public {
        vm.expectRevert("Invalid ETH amount attached");
        vault.batchDepositETHForStaking(
            getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo, blsPubKeyThree),
            getUint256ArrayFromValues(maxStakingAmountPerValidator, maxStakingAmountPerValidator, maxStakingAmountPerValidator)
        );
    }

    function testBatchDepositETHForStakingRevertsWhenEmptyArraysAreSupplied() public {
        vm.expectRevert("Empty arrays");
        vault.batchDepositETHForStaking(
            getEmptyBytesArray(),
            getEmptyUint256Array()
        );
    }

    function testBatchDepositETHForStakingRevertsWhenInconsistentArrayLengthsAreSupplied() public {
        vm.expectRevert("Inconsistent array lengths");
        vault.batchDepositETHForStaking(
            getBytesArrayFromBytes(blsPubKeyOne),
            getEmptyUint256Array()
        );
    }

    function testBatchDepositETHForStakingRevertsWhenBLSNotRegisteredWithNetwork() public {
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, false);
        assertEq(liquidStakingManager.isBLSPublicKeyPartOfLSDNetwork(blsPubKeyOne), false);
        assertEq(liquidStakingManager.isBLSPublicKeyBanned(blsPubKeyOne), true);
        vm.expectRevert("BLS public key is not part of LSD network");
        vault.batchDepositETHForStaking{ value: maxStakingAmountPerValidator }(
            getBytesArrayFromBytes(blsPubKeyOne),
            getUint256ArrayFromValues(maxStakingAmountPerValidator)
        );
    }

    function testBatchDepositETHForStakingRevertsWhenBLSNotLifecycleStatusOne() public {
        assertEq(liquidStakingManager.isBLSPublicKeyPartOfLSDNetwork(blsPubKeyOne), true);
        assertEq(liquidStakingManager.isBLSPublicKeyBanned(blsPubKeyOne), false);

        MockAccountManager(liquidStakingManager.accountMan()).setLifecycleStatus(blsPubKeyOne, 0);

        vm.expectRevert("Lifecycle status must be one");
        vault.batchDepositETHForStaking{ value: maxStakingAmountPerValidator }(
            getBytesArrayFromBytes(blsPubKeyOne),
            getUint256ArrayFromValues(maxStakingAmountPerValidator)
        );
    }

    function testBatchDepositETHForStakingCanSuccessfullyDepositForMultipleValidators() public {
        bytes[] memory blsKeys = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo, blsPubKeyThree);

        vm.deal(accountThree, 3 * maxStakingAmountPerValidator);
        vm.prank(accountThree);
        vault.batchDepositETHForStaking{ value: 3 * maxStakingAmountPerValidator }(
            blsKeys,
            getUint256ArrayFromValues(maxStakingAmountPerValidator, maxStakingAmountPerValidator, maxStakingAmountPerValidator)
        );

        assertEq(address(vault).balance, 3 * maxStakingAmountPerValidator);

        for (uint256 i; i < blsKeys.length; ++i) {
            bytes memory blsKey = blsKeys[i];
            LPToken token = vault.lpTokenForKnot(blsKey);
            assertTrue(address(token) != address(0));
            assertEq(token.totalSupply(), maxStakingAmountPerValidator);
            assertEq(token.balanceOf(accountThree), maxStakingAmountPerValidator);
        }

        // now try and withdraw
        assertEq(operations.balance, 0);

        vm.prank(address(liquidStakingManager));
        vault.withdrawETH(operations, 4 ether);
        assertEq(operations.balance, 4 ether);
    }

    function testDepositETHForStaking() public {
        vm.deal(accountOne, maxStakingAmountPerValidator);
        vm.deal(accountTwo, maxStakingAmountPerValidator);
        vm.deal(accountThree, maxStakingAmountPerValidator);

        uint256 stakeAmount = maxStakingAmountPerValidator / 2;
        vm.prank(accountOne);
        vault.depositETHForStaking{value: stakeAmount}(blsPubKeyOne, stakeAmount);
        assertEq(vault.lpTokenForKnot(blsPubKeyOne).balanceOf(accountOne), stakeAmount);
        assertEq(vault.lpTokenForKnot(blsPubKeyOne).totalSupply(), stakeAmount);

        vm.prank(accountTwo);
        vault.depositETHForStaking{value: stakeAmount}(blsPubKeyTwo, stakeAmount);
        assertEq(vault.lpTokenForKnot(blsPubKeyOne).balanceOf(accountOne), stakeAmount);
        assertEq(vault.lpTokenForKnot(blsPubKeyTwo).balanceOf(accountTwo), stakeAmount);
        assertEq(vault.lpTokenForKnot(blsPubKeyOne).totalSupply(), stakeAmount);
        assertEq(vault.lpTokenForKnot(blsPubKeyTwo).totalSupply(), stakeAmount);

        vm.prank(accountThree);
        vault.depositETHForStaking{value: stakeAmount}(blsPubKeyOne, stakeAmount);
        assertEq(vault.lpTokenForKnot(blsPubKeyOne).totalSupply(), maxStakingAmountPerValidator);
        assertEq(vault.lpTokenForKnot(blsPubKeyTwo).totalSupply(), stakeAmount);

        assertEq(address(vault).balance, maxStakingAmountPerValidator + maxStakingAmountPerValidator / 2);

        vm.expectRevert("Amount exceeds the staking limit for the validator");
        vm.prank(accountThree);
        vault.depositETHForStaking{value: stakeAmount}(blsPubKeyOne, stakeAmount);
    }

    function testDepositETHForStakingRevertsWhenBLSKeyIsNotRegistered() public {
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, false);
        vm.expectRevert("BLS public key is banned or not a part of LSD network");
        vault.depositETHForStaking(
            blsPubKeyOne,
            maxStakingAmountPerValidator
        );
    }

    function testDepositETHForStakingRevertsWhenBLSKeyIsBanned() public {
        vm.expectRevert("BLS public key is banned or not a part of LSD network");
        vault.depositETHForStaking{value: maxStakingAmountPerValidator}(
            blsPubKeyFour,
            maxStakingAmountPerValidator
        );
    }

    function testDepositETHForStakingRevertsWhenLifecycleIsNotInitialsRegistered() public {
        MockAccountManager(factory.accountMan()).setLifecycleStatus(blsPubKeyTwo, 3);
        vm.expectRevert("Lifecycle status must be one");
        vault.depositETHForStaking(
            blsPubKeyTwo,
            maxStakingAmountPerValidator
        );
    }

    function testDepositETHForStakingRevertsWhenNoETHAttached() public {
        vm.expectRevert("Must provide correct amount of ETH");
        vault.depositETHForStaking(
            blsPubKeyTwo,
            maxStakingAmountPerValidator
        );
    }

    function testBurnLPTokensByBLSRevertsWhenArraysAreEmpty() public {
        vm.expectRevert("Empty arrays");
        vault.burnLPTokensForETHByBLS(
            getEmptyBytesArray(),
            getEmptyUint256Array()
        );
    }

    function testBurnLPTokensByBLSRevertsWhenArraysAreInconsistentLength() public {
        vm.expectRevert("Inconsistent array length");
        vault.burnLPTokensForETHByBLS(
            getBytesArrayFromBytes(blsPubKeyOne),
            getEmptyUint256Array()
        );
    }

    function testBurnLPTokensByBLSRevertsWhenNothingStakedForBLS() public {
        vm.expectRevert("No ETH staked for specified BLS key");
        vault.burnLPTokensForETHByBLS(
            getBytesArrayFromBytes(blsPubKeyOne),
            getUint256ArrayFromValues(maxStakingAmountPerValidator)
        );
    }

    function testBurnLPTokensRevertsWhenArrayIsEmpty() public {
        LPToken[] memory tokens = new LPToken[](0);
        vm.expectRevert("Empty arrays");
        vault.burnLPTokensForETH(
            tokens,
            getEmptyUint256Array()
        );
    }

    function testBurnLPTokensRevertsWhenArrayLengthsAreInconsistent() public {
        LPToken[] memory tokens = new LPToken[](1);
        tokens[0] = LPToken(msg.sender);
        vm.expectRevert("Inconsistent array length");
        vault.burnLPTokensForETH(
            tokens,
            getEmptyUint256Array()
        );
    }

    function testBurnLPTokensWorksAsExpectedForMultipleValidators() public {
        maxETHDeposit(accountThree, getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo, blsPubKeyThree));

        assertEq(address(vault).balance, 3 * 4 ether);

        vm.warp(block.timestamp + 3 hours);

        vm.prank(accountThree);
        vault.burnLPTokensForETHByBLS(
            getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo, blsPubKeyThree),
            getUint256ArrayFromValues(maxStakingAmountPerValidator, maxStakingAmountPerValidator, maxStakingAmountPerValidator)
        );

        assertEq(address(vault).balance, 0);
    }

    function testBurnLPForETHWorksAsExpected() public {
        maxETHDeposit(accountFive, getBytesArrayFromBytes(blsPubKeyOne));

        // warp speed ahead
        vm.warp(block.timestamp + 3 hours);

        vm.startPrank(accountFive);
        vault.burnLPForETH(vault.lpTokenForKnot(blsPubKeyOne), maxStakingAmountPerValidator);
        vm.stopPrank();

        assertEq(vault.lpTokenForKnot(blsPubKeyOne).totalSupply(), 0);
        assertEq(vault.lpTokenForKnot(blsPubKeyOne).balanceOf(accountFive), 0);
        assertEq(address(vault).balance, 0);
        assertEq(accountFive.balance, maxStakingAmountPerValidator);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-28-funds-are-not-claimed-from-syndicate-for-valid-bls-keys-of-first-key-is-invalid-no-longer-part-of-syndicate
    // https://code4rena.com/reports/2022-11-stakehouse/#m-29-user-receives-less-rewards-than-they-are-eligible-for-if-first-passed-bls-key-is-inactive
    function testReceiveETHAndDistributeToLPsLinkedToKnotsThatMintedDerivatives() public {
        // register BLS key with the network
        registerSingleBLSPubKey(accountTwo, blsPubKeyFour, accountFive);

        // Do a deposit of 4 ETH for bls pub key four in the fees and mev pool
        maxETHDeposit(accountTwo, getBytesArrayFromBytes(blsPubKeyFour));

        // Do a deposit of 24 ETH for savETH pool
        liquidStakingManager.savETHVault().depositETHForStaking{value: 24 ether}(blsPubKeyFour, 24 ether);

        stakeAndMintDerivativesSingleKey(blsPubKeyFour);

        vm.roll(block.number + 1 + (5*32));

        LPToken lpTokenBLSPubKeyFour = vault.lpTokenForKnot(blsPubKeyFour);

        vm.warp(block.timestamp + 3 hours);

        // Deal ETH to the staking funds vault
        uint256 rewardsAmount = 1.2 ether;
        vm.deal(address(vault), rewardsAmount);
        assertEq(address(vault).balance, rewardsAmount);

        LPToken[] memory tokens = new LPToken[](1);
        tokens[0] = lpTokenBLSPubKeyFour;
        assertEq(vault.batchPreviewAccumulatedETH(accountTwo, tokens), rewardsAmount);

        vm.prank(accountTwo);
        vault.claimRewards(accountThree, getBytesArrayFromBytes(blsPubKeyFour));

        assertEq(vault.batchPreviewAccumulatedETH(accountTwo, tokens), 0);
        assertEq(address(vault).balance, 0);
        assertEq(accountThree.balance, rewardsAmount);
        assertEq(vault.claimed(accountTwo, address(lpTokenBLSPubKeyFour)), rewardsAmount);
        assertEq(vault.claimed(accountThree, address(lpTokenBLSPubKeyFour)), 0);
    }

    function testReceiveETHAndDistributeToLPsLinkedToKnotsThatMintedDerivativesWhenCommissionIsActivated() public {
        liquidStakingManager = deployNewLiquidStakingNetworkWithCommission(factory, 10_00000, admin, false, "MINE");
        manager = liquidStakingManager;
        vault = liquidStakingManager.stakingFundsVault();
        maxStakingAmountPerValidator = vault.maxStakingAmountPerValidator();
        assertEq(liquidStakingManager.daoCommissionPercentage(), 10_00000);

        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyTwo, true);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyThree, true);

        // make 'admin' the 'DAO'
        vm.prank(address(factory));
        liquidStakingManager.updateDAOAddress(admin);

        // register BLS key with the network
        registerSingleBLSPubKey(accountTwo, blsPubKeyFour, accountFive, liquidStakingManager);

        // Do a deposit of 4 ETH for bls pub key four in the fees and mev pool
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = maxStakingAmountPerValidator;

        depositETH(accountTwo, maxStakingAmountPerValidator, amounts, getBytesArrayFromBytes(blsPubKeyFour));

        // Do a deposit of 24 ETH for savETH pool
        liquidStakingManager.savETHVault().depositETHForStaking{value: 24 ether}(blsPubKeyFour, 24 ether);

        stakeAndMintDerivativesSingleKey(blsPubKeyFour, liquidStakingManager);

        vm.roll(block.number + 1 + (5*32));

        LPToken lpTokenBLSPubKeyFour = vault.lpTokenForKnot(blsPubKeyFour);

        vm.warp(block.timestamp + 3 hours);

        // Deal ETH to the staking funds vault
        uint256 rewardsAmount = 1.2 ether;
        vm.deal(address(vault), rewardsAmount);
        assertEq(address(vault).balance, rewardsAmount);

        LPToken[] memory tokens = new LPToken[](1);
        tokens[0] = lpTokenBLSPubKeyFour;
        assertEq(vault.batchPreviewAccumulatedETH(accountTwo, tokens), (rewardsAmount) - (((rewardsAmount) * 10) / 100));
        return;

        vm.prank(accountTwo);
        vault.claimRewards(accountThree, getBytesArrayFromBytes(blsPubKeyFour));

        assertEq(vault.batchPreviewAccumulatedETH(accountTwo, tokens), 0);
        assertEq(address(vault).balance, 0);
        assertEq(accountThree.balance, rewardsAmount - 0.12 ether); // 10% haircut
        assertEq(admin.balance, 0.12 ether); // 10% haircut
        assertEq(vault.claimed(accountTwo, address(lpTokenBLSPubKeyFour)), rewardsAmount);
        assertEq(vault.claimed(accountThree, address(lpTokenBLSPubKeyFour)), 0);
    }

    function testReceiveETHAndDistributeToLPsLinkedToKnotsThatMintedDerivativesWhenCommissionIsActivatedDuringTransfer() public {
        liquidStakingManager = deployNewLiquidStakingNetworkWithCommission(factory, 10_00000, admin, false, "MINE");
        manager = liquidStakingManager;
        vault = liquidStakingManager.stakingFundsVault();
        maxStakingAmountPerValidator = vault.maxStakingAmountPerValidator();
        assertEq(liquidStakingManager.daoCommissionPercentage(), 10_00000);

        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyTwo, true);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyThree, true);

        // make 'admin' the 'DAO'
        vm.prank(address(factory));
        liquidStakingManager.updateDAOAddress(admin);

        // register BLS key with the network
        registerSingleBLSPubKey(accountTwo, blsPubKeyFour, accountFive, liquidStakingManager);

        // Do a deposit of 4 ETH for bls pub key four in the fees and mev pool
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = maxStakingAmountPerValidator;

        depositETH(accountTwo, maxStakingAmountPerValidator, amounts, getBytesArrayFromBytes(blsPubKeyFour));

        // Do a deposit of 24 ETH for savETH pool
        liquidStakingManager.savETHVault().depositETHForStaking{value: 24 ether}(blsPubKeyFour, 24 ether);

        stakeAndMintDerivativesSingleKey(blsPubKeyFour, liquidStakingManager);

        vm.roll(block.number + 1 + (5*32));

        LPToken lpTokenBLSPubKeyFour = vault.lpTokenForKnot(blsPubKeyFour);

        vm.warp(block.timestamp + 3 hours);

        vm.startPrank(accountTwo);
        lpTokenBLSPubKeyFour.transfer(accountThree, lpTokenBLSPubKeyFour.balanceOf(accountTwo) / 2);
        vm.stopPrank();

        // Deal ETH to the staking funds vault
        uint256 rewardsAmount = 1.2 ether;
        vm.deal(address(vault), rewardsAmount);
        assertEq(address(vault).balance, rewardsAmount);

        LPToken[] memory tokens = new LPToken[](1);
        tokens[0] = lpTokenBLSPubKeyFour;
        assertEq(vault.batchPreviewAccumulatedETH(accountTwo, tokens), (rewardsAmount / 2) - (((rewardsAmount / 2) * 10) / 100));
        assertEq(vault.batchPreviewAccumulatedETH(accountThree, tokens), (rewardsAmount / 2) - (((rewardsAmount / 2) * 10) / 100));

        uint256 accountThreeBalBefore = accountThree.balance;
        vm.startPrank(accountTwo);
        lpTokenBLSPubKeyFour.transfer(accountThree, lpTokenBLSPubKeyFour.balanceOf(accountTwo));
        vm.stopPrank();

        assertEq(vault.batchPreviewAccumulatedETH(accountTwo, tokens), 0);
        assertEq(address(vault).balance, 0);

        assertEq(accountThree.balance - accountThreeBalBefore, (rewardsAmount / 2) - (((rewardsAmount / 2) * 10) / 100)); // 10% haircut
        assertEq(admin.balance, 0.12 ether); // 10% haircut
        assertEq(vault.claimed(accountThree, address(lpTokenBLSPubKeyFour)), rewardsAmount);
        assertEq(vault.claimed(accountTwo, address(lpTokenBLSPubKeyFour)), 0);

    }

    function testReceiveETHAndDistributeToMultipleLPs() public {
        // register BLS key with the network
        registerSingleBLSPubKey(accountTwo, blsPubKeyFour, accountFive);

        // Do a deposit of 4 ETH for bls pub key four in the fees and mev pool
        depositETH(accountTwo, maxStakingAmountPerValidator / 2, getUint256ArrayFromValues(maxStakingAmountPerValidator / 2), getBytesArrayFromBytes(blsPubKeyFour));
        depositETH(accountOne, maxStakingAmountPerValidator / 2, getUint256ArrayFromValues(maxStakingAmountPerValidator / 2), getBytesArrayFromBytes(blsPubKeyFour));

        // Do a deposit of 24 ETH for savETH pool
        liquidStakingManager.savETHVault().depositETHForStaking{value: 24 ether}(blsPubKeyFour, 24 ether);

        stakeAndMintDerivativesSingleKey(blsPubKeyFour);

        vm.roll(block.number + 1 + (5*32));

        LPToken lpTokenBLSPubKeyFour = vault.lpTokenForKnot(blsPubKeyFour);

        vm.warp(block.timestamp + 3 hours);

        // Deal ETH to the staking funds vault
        uint256 rewardsAmount = 1.2 ether;
        vm.deal(address(vault), rewardsAmount);
        assertEq(address(vault).balance, rewardsAmount);

        LPToken[] memory tokens = new LPToken[](1);
        tokens[0] = vault.lpTokenForKnot(blsPubKeyFour);
        assertEq(vault.batchPreviewAccumulatedETH(accountTwo, tokens), rewardsAmount / 2);
        assertEq(vault.batchPreviewAccumulatedETH(accountOne, tokens), rewardsAmount / 2);

        vm.prank(accountTwo);
        vault.claimRewards(accountThree, getBytesArrayFromBytes(blsPubKeyFour));

        assertEq(vault.batchPreviewAccumulatedETH(accountTwo, tokens), 0);
        assertEq(address(vault).balance, rewardsAmount / 2);
        assertEq(accountThree.balance, rewardsAmount / 2);
        assertEq(vault.claimed(accountTwo, address(lpTokenBLSPubKeyFour)), rewardsAmount / 2);
        assertEq(vault.claimed(accountThree, address(lpTokenBLSPubKeyFour)), 0);

        vm.warp(block.timestamp + 3 hours);

        vm.prank(accountOne);
        vault.claimRewards(accountOne, getBytesArrayFromBytes(blsPubKeyFour));

        assertEq(accountOne.balance, rewardsAmount / 2);
        assertEq(vault.batchPreviewAccumulatedETH(accountOne, tokens), 0);
        assertEq(address(vault).balance, 0);
        assertEq(vault.claimed(accountOne, address(lpTokenBLSPubKeyFour)), rewardsAmount / 2);
        assertEq(vault.claimed(accountTwo, address(lpTokenBLSPubKeyFour)), rewardsAmount / 2);
        assertEq(vault.totalClaimed(), rewardsAmount);
        assertEq(vault.totalRewardsReceived(), rewardsAmount);
    }

    function testReceiveETHAndDistributeDuringLPTransfers() public {
        // register BLS key with the network
        registerSingleBLSPubKey(accountTwo, blsPubKeyFour, accountFive);

        // Do a deposit of 4 ETH for bls pub key four in the fees and mev pool
        depositETH(accountTwo, maxStakingAmountPerValidator / 2, getUint256ArrayFromValues(maxStakingAmountPerValidator / 2), getBytesArrayFromBytes(blsPubKeyFour));
        depositETH(accountOne, maxStakingAmountPerValidator / 2, getUint256ArrayFromValues(maxStakingAmountPerValidator / 2), getBytesArrayFromBytes(blsPubKeyFour));

        // Do a deposit of 24 ETH for savETH pool
        liquidStakingManager.savETHVault().depositETHForStaking{value: 24 ether}(blsPubKeyFour, 24 ether);

        stakeAndMintDerivativesSingleKey(blsPubKeyFour);

        // Push forward to activate knot in syndicate
        vm.roll(block.number + 1 + (5*32));

        LPToken lpTokenBLSPubKeyFour = vault.lpTokenForKnot(blsPubKeyFour);

        vm.warp(block.timestamp + 3 hours);

        // Deal ETH to the staking funds vault
        uint256 rewardsAmount = 1.2 ether;
        vm.deal(address(vault), rewardsAmount);
        assertEq(address(vault).balance, rewardsAmount);

        LPToken[] memory tokens = new LPToken[](1);
        tokens[0] = vault.lpTokenForKnot(blsPubKeyFour);

        assertEq(vault.batchPreviewAccumulatedETH(accountTwo, tokens), rewardsAmount / 2);
        assertEq(vault.batchPreviewAccumulatedETH(accountOne, tokens), rewardsAmount / 2);

        vm.prank(accountTwo);
        vault.claimRewards(accountThree, getBytesArrayFromBytes(blsPubKeyFour));

        assertEq(vault.batchPreviewAccumulatedETH(accountTwo, tokens), 0);
        assertEq(address(vault).balance, rewardsAmount / 2);
        assertEq(accountThree.balance, rewardsAmount / 2);
        assertEq(vault.claimed(accountTwo, address(lpTokenBLSPubKeyFour)), rewardsAmount / 2);
        assertEq(vault.claimed(accountThree, address(lpTokenBLSPubKeyFour)), 0);
        assertEq(vault.claimed(accountFive, address(lpTokenBLSPubKeyFour)), 0);

        vm.warp(block.timestamp + 3 hours);

        vm.startPrank(accountOne);
        lpTokenBLSPubKeyFour.transfer(accountFive, 2 ether);
        vm.stopPrank();
        assertEq(lpTokenBLSPubKeyFour.balanceOf(accountOne), 0);

        assertEq(vault.batchPreviewAccumulatedETH(accountOne, tokens), 0);
        assertEq(address(vault).balance, 0);
        assertEq(accountOne.balance, rewardsAmount / 2);
        assertEq(vault.claimed(accountOne, address(lpTokenBLSPubKeyFour)), 0);
        assertEq(vault.claimed(accountTwo, address(lpTokenBLSPubKeyFour)), rewardsAmount / 2);
        assertEq(vault.claimed(accountFive, address(lpTokenBLSPubKeyFour)), rewardsAmount / 2);
        assertEq(vault.totalClaimed(), rewardsAmount);
        assertEq(vault.totalRewardsReceived(), rewardsAmount);
    }
}