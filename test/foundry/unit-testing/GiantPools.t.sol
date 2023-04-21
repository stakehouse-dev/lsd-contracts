pragma solidity ^0.8.13;

// SPDX-License-Identifier: MIT

import "forge-std/console.sol";

import { TestUtils } from "../../utils/TestUtils.sol";

import { MockAccountManager } from "../../../contracts/testing/stakehouse/MockAccountManager.sol";
import { GiantSavETHVaultPool } from "../../../contracts/liquid-staking/GiantSavETHVaultPool.sol";
import { GiantMevAndFeesPool } from "../../../contracts/liquid-staking/GiantMevAndFeesPool.sol";
import { Syndicate } from "../../../contracts/syndicate/Syndicate.sol";
import { LPToken } from "../../../contracts/liquid-staking/LPToken.sol";
import { MockSlotRegistry } from "../../../contracts/testing/stakehouse/MockSlotRegistry.sol";
import { MockSavETHVault } from "../../../contracts/testing/liquid-staking/MockSavETHVault.sol";
import { MockGiantSavETHVaultPool } from "../../../contracts/testing/liquid-staking/MockGiantSavETHVaultPool.sol";
import { StakingFundsVault } from "../../../contracts/liquid-staking/StakingFundsVault.sol";
import { IERC20 } from "@blockswaplab/stakehouse-solidity-api/contracts/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockStakingFundsVault } from "../../../contracts/testing/liquid-staking/MockStakingFundsVault.sol";
import { GiantPoolExploit } from "../../../contracts/testing/liquid-staking/GiantPoolExploit.sol";
import { GiantPoolTransferExploiter } from "../../../contracts/testing/liquid-staking/GiantPoolTransferExploiter.sol";
import { GiantPoolSelfTransferExploiter } from "../../../contracts/testing/liquid-staking/GiantPoolSelfTransferExploiter.sol";
import { GiantLP } from "../../../contracts/liquid-staking/GiantLP.sol";
import { MockLiquidStakingManager } from "../../../contracts/testing/liquid-staking/MockLiquidStakingManager.sol";

contract GiantPoolTests is TestUtils {

    MockGiantSavETHVaultPool public giantSavETHPool;
    GiantMevAndFeesPool public giantFeesAndMevPool;

    function setUp() public {
        vm.startPrank(accountFive); // this will mean it gets dETH initial supply
        factory = createMockLSDNFactory();
        vm.stopPrank();

        // Deploy 1 network
        manager = deployNewLiquidStakingNetwork(
            factory,
            admin,
            false,
            "LSDN"
        );

        savETHVault = MockSavETHVault(address(manager.savETHVault()));

        giantFeesAndMevPool = GiantMevAndFeesPool(payable(address(factory.giantFeesAndMev())));
        giantSavETHPool = MockGiantSavETHVaultPool(payable(address(factory.giantSavETHPool())));

        assertEq(giantSavETHPool.batchSize(), 24 ether);
    }

    // https://code4rena.com/reports/2022-11-stakehouse#h-17-giant-pools-can-be-drained-due-to-weak-vault-authenticity-check
    function testPoolDraining_AUDIT() public {
        // Register BLS key
        address nodeRunner = accountOne; vm.deal(nodeRunner, 12 ether);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        // Set up users and ETH
        address savETHUser = accountThree; vm.deal(savETHUser, 24 ether);
        address attacker = address(0x1337);
        vm.label(attacker, "attacker");
        vm.deal(attacker, 1 ether);
        // User deposits ETH into Giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);
        assertEq(giantSavETHPool.lpTokenETH().balanceOf(savETHUser), 24 ether);
        assertEq(address(giantSavETHPool).balance, 24 ether);
        // Attacker deploys an exploit.
        vm.startPrank(attacker);
        GiantPoolExploit exploit = new GiantPoolExploit(address(manager));
        vm.stopPrank();
        // Attacker calls `batchDepositETHForStaking` to deposit ETH to their exploit contract.
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne);
        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);

        vm.expectRevert(bytes4(keccak256("InvalidSavETHVault()"))); // Update: we now revert
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(exploit)),
            getUint256ArrayFromValues(24 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        // Vault got nothing.
        assertEq(address(manager.savETHVault()).balance, 0 ether);
        // Attacker gets nothing too now. THey still have their 1 eth balance.
        assertEq(attacker.balance, 1 ether);
    }

    // bringUnusedETHBackIntoGiantPool() CAN CAUSE STUCK ETHER FUNDS IN GIANT FEES AND MEV POOL
    // https://code4rena.com/reports/2022-11-stakehouse#h-06-bringunusedethbackintogiantpool-can-cause-stuck-ether-funds-in-giant-pool
    // https://code4rena.com/reports/2022-11-stakehouse/#h-14-fund-lose-in-function-bringunusedethbackintogiantpool-of-giantsavethvaultpool-eth-gets-back-to-giant-pool-but-the-value-of-idleeth-dont-increase
    function testStuckFundsInGiantMEV() public {

        stakingFundsVault = MockStakingFundsVault(payable(manager.stakingFundsVault()));
        address nodeRunner = accountOne; vm.deal(nodeRunner, 4 ether);
        address victim = accountFour; vm.deal(victim, 4 ether);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        emit log_address(address(giantFeesAndMevPool));
        vm.startPrank(victim);

        emit log_uint(victim.balance);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(getAddressArrayFromValues(address(stakingFundsVault)),getUint256ArrayFromValues(4 ether) , blsKeysForVaults, stakeAmountsForVaults);

        emit log_uint(victim.balance);

        vm.warp(block.timestamp + 60 minutes);
        LPToken lp = (stakingFundsVault.lpTokenForKnot(blsKeysForVaults[0][0]));
        LPToken [][] memory lpToken = new LPToken[][](1);
        LPToken[] memory temp  = new LPToken[](1);
        temp[0] = lp;
        lpToken[0] = temp;

        emit log_uint(address(giantFeesAndMevPool).balance);
        giantFeesAndMevPool.bringUnusedETHBackIntoGiantPool(getAddressArrayFromValues(address(stakingFundsVault)),lpToken, stakeAmountsForVaults);

        emit log_uint(address(giantFeesAndMevPool).balance);

        //vm.expectRevert();
        // Call not expected to revert any more
        giantFeesAndMevPool.batchDepositETHForStaking(getAddressArrayFromValues(address(stakingFundsVault)),getUint256ArrayFromValues(4 ether) , blsKeysForVaults, stakeAmountsForVaults);

        vm.warp(block.timestamp + 60 minutes);
        giantFeesAndMevPool.bringUnusedETHBackIntoGiantPool(getAddressArrayFromValues(address(stakingFundsVault)),lpToken, stakeAmountsForVaults);

        vm.warp(block.timestamp + 60 minutes);

        //vm.expectRevert();
        // Call not expected to revert any more
        giantFeesAndMevPool.withdrawETH(4 ether);

        vm.stopPrank();
    }

    // bringUnusedETHBackIntoGiantPool() CAN CAUSE STUCK ETHER FUNDS IN GIANT savETH POOL
    // https://code4rena.com/reports/2022-11-stakehouse#h-06-bringunusedethbackintogiantpool-can-cause-stuck-ether-funds-in-giant-pool
    // https://code4rena.com/reports/2022-11-stakehouse/#h-14-fund-lose-in-function-bringunusedethbackintogiantpool-of-giantsavethvaultpool-eth-gets-back-to-giant-pool-but-the-value-of-idleeth-dont-increase
    // https://code4rena.com/reports/2022-11-stakehouse/#m-03-giant-pools-cannot-receive-eth-from-vaults
    function testStuckFundsInGiantSavETHPool() public {

        address savETHVaultAddress = address(manager.savETHVault());
        address nodeRunner = accountOne; vm.deal(nodeRunner, 24 ether);
        address victim = accountFour; vm.deal(victim, 56 ether);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        emit log_address(address(giantSavETHPool));
        vm.startPrank(victim);

        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);

        emit log_uint(victim.balance);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);
        giantSavETHPool.batchDepositETHForStaking(getAddressArrayFromValues(address(savETHVaultAddress)),getUint256ArrayFromValues(24 ether) , blsKeysForVaults, stakeAmountsForVaults);

        emit log_uint(victim.balance);

        vm.warp(block.timestamp + 60 minutes);
        LPToken lp = (MockSavETHVault(savETHVaultAddress).lpTokenForKnot(blsKeysForVaults[0][0]));
        LPToken [][] memory lpToken = new LPToken[][](1);
        LPToken[] memory temp  = new LPToken[](1);
        temp[0] = lp;
        lpToken[0] = temp;

        emit log_uint(address(giantSavETHPool).balance);
        giantSavETHPool.bringUnusedETHBackIntoGiantPool(getAddressArrayFromValues(address(savETHVaultAddress)),lpToken, stakeAmountsForVaults);

        emit log_uint(address(giantSavETHPool).balance);

        //vm.expectRevert();
        // Call not expected to revert any more
        giantSavETHPool.batchDepositETHForStaking(getAddressArrayFromValues(address(savETHVaultAddress)),getUint256ArrayFromValues(24 ether) , blsKeysForVaults, stakeAmountsForVaults);

        vm.warp(block.timestamp + 60 minutes);
        giantSavETHPool.bringUnusedETHBackIntoGiantPool(getAddressArrayFromValues(address(savETHVaultAddress)),lpToken, stakeAmountsForVaults);

        vm.warp(block.timestamp + 60 minutes);

        //vm.expectRevert();
        // Call not expected to revert any more
        giantSavETHPool.withdrawETH(24 ether);

        vm.stopPrank();
    }

    function testUUPSUpgradeable() public {
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        // setup upgrade manager
        address upgradeManager = accountFive; vm.deal(upgradeManager, 100 ether);

        // upgrade to new implementation address
        vm.startPrank(upgradeManager);
        GiantMevAndFeesPool newGMevImplementation = new GiantMevAndFeesPool();
        giantFeesAndMevPool.upgradeTo(address(newGMevImplementation));
        vm.stopPrank();
        assertEq(address(uint160(uint256(vm.load(address(giantFeesAndMevPool), implementationSlot)))), address(newGMevImplementation));

        vm.startPrank(upgradeManager);
        GiantSavETHVaultPool newGSavETHVaultImplementation = new GiantSavETHVaultPool();
        giantSavETHPool.upgradeTo(address(newGSavETHVaultImplementation));
        vm.stopPrank();
        assertEq(address(uint160(uint256(vm.load(address(giantSavETHPool), implementationSlot)))), address(newGSavETHVaultImplementation));

        // test upgrade after renounce ownership
        vm.startPrank(upgradeManager);
        giantFeesAndMevPool.renounceOwnership();
        vm.stopPrank();
        assertEq(giantFeesAndMevPool.owner(), address(0));

        vm.startPrank(upgradeManager);
        vm.expectRevert("Ownable: caller is not the owner");
        giantFeesAndMevPool.upgradeTo(address(newGSavETHVaultImplementation));
        vm.stopPrank();

        vm.startPrank(upgradeManager);
        giantSavETHPool.renounceOwnership();
        vm.stopPrank();
        assertEq(giantSavETHPool.owner(), address(0));

        vm.startPrank(upgradeManager);
        vm.expectRevert("Ownable: caller is not the owner");
        giantSavETHPool.upgradeTo(address(newGSavETHVaultImplementation));
        vm.stopPrank();
    }

    function testWithdrawETHManagesReleasingRedemption() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);
        address savETHUserTwo = accountFive; vm.deal(savETHUserTwo, 100 ether);
        address savETHUserThree = accountSix; vm.deal(savETHUserThree, 100 ether);

        address savETHVaultAddress = address(manager.savETHVault());

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        // Fund the giant pool in waves
        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 10 ether}(10 ether);
        vm.stopPrank();

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 14 ether}(14 ether);
        vm.stopPrank();

        vm.startPrank(savETHUserThree);
        giantSavETHPool.depositETH{value: 25 ether}(25 ether);
        vm.stopPrank();

        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 12 ether}(12 ether);
        vm.stopPrank();

        // Inject money into LSD network from giant pool
        bytes[][] memory allKnots = new bytes[][](1);
        uint256[][] memory allAmounts = new uint256[][](1);
        allKnots[0] = getBytesArrayFromBytes(blsPubKeyOne);
        allAmounts[0] = getUint256ArrayFromValues(24 ether);
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(savETHVaultAddress),
            getUint256ArrayFromValues(24 ether),
            allKnots,
            allAmounts
        );

        allAmounts[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            getUint256ArrayFromValues(4 ether),
            allKnots,
            allAmounts
        );

        // Stake and mint for all keys
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);   // savETHUser and savETHUserTwo funded this batch

        // Try and withdraw ETH when it is assigned to a redemption batch
        vm.startPrank(savETHUser);
        vm.expectRevert(0x59a897b1); // Come back later error as function selector
        giantSavETHPool.withdrawETH(10 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 1.1 days);
        vm.startPrank(savETHUser);
        vm.expectRevert(bytes4(keccak256("ErrorWithdrawing()"))); // eth is staked error as function selector
        giantSavETHPool.withdrawETH(10 ether);
        vm.stopPrank();

        // Try and withdraw ETH that has not been assigned to a redemption batch
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserThree), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 0), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 1), 2);

        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 1), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 2), 1 ether);

        vm.warp(block.timestamp + 1.1 days);
        vm.startPrank(savETHUserThree);
        giantSavETHPool.withdrawETH(10 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserThree), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 0), 1);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 1), 15 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 2), 0 ether);

        vm.warp(block.timestamp + 1.1 days);
        vm.startPrank(savETHUserThree);
        giantSavETHPool.withdrawETH(15 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserThree), 0);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 1), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 2), 0 ether);
    }

    function testGiantPoolDepositQueue() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);
        address savETHUserTwo = accountFive; vm.deal(savETHUserTwo, 100 ether);
        address savETHUserThree = accountSix; vm.deal(savETHUserThree, 100 ether);

        address savETHVaultAddress = address(manager.savETHVault());
        IERC20 dETHToken = savETHVault.dETHToken();

        vm.startPrank(accountFive);
        dETHToken.transfer(address(savETHVault.saveETHRegistry()), 96 ether);
        vm.stopPrank();

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Fund the giant pool in waves
        assertEq(giantSavETHPool.totalETHFromLPs(), 0);
        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 10 ether}(10 ether);
        vm.stopPrank();
        assertEq(giantSavETHPool.totalETHFromLPs(), 10 ether);
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 10 ether);
        assertEq(giantSavETHPool.depositBatchCount(), 0);

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 14 ether}(14 ether);
        vm.stopPrank();
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 1);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 0), 14 ether);
        assertEq(giantSavETHPool.depositBatchCount(), 1);

        vm.startPrank(savETHUserThree);
        giantSavETHPool.depositETH{value: 25 ether}(25 ether);
        vm.stopPrank();
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserThree), 2);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 1), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 2), 1 ether);
        assertEq(giantSavETHPool.depositBatchCount(), 2);

        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 47.17 ether}(47.17 ether);
        vm.stopPrank();
        assertEq(giantSavETHPool.depositBatchCount(), 4);
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 4);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 1), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 2), 3);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 3), 4);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 10 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 2), 23 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 3), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 4), 0.17 ether);

        vm.warp(block.timestamp + 50 minutes);

        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawETH(12.49 ether);
        vm.stopPrank();
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 10 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 2), 23 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 3), 24 ether - 12.32 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 4), 0 ether);
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 3);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 1), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 2), 3);
        assertEq(giantSavETHPool.depositBatchCount(), 4); // Since recycled batches take care of gaps

        vm.startPrank(savETHUser);
        giantSavETHPool.lpTokenETH().transfer(savETHUserTwo, 11.68 ether);
        vm.stopPrank();
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 10 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 2), 23 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 3), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 4), 0 ether);
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 1), 2);
        assertEq(giantSavETHPool.depositBatchCount(), 4);

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 2);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 0), 14 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 3), 11.68 ether);
    }

    function testSavETHRedemptionQueueRightsCorrectlyTransferredWhenGiantLPTransferred() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);
        address savETHUserTwo = accountFive; vm.deal(savETHUserTwo, 100 ether);
        address savETHUserThree = accountSix; vm.deal(savETHUserThree, 100 ether);

        address savETHVaultAddress = address(manager.savETHVault());
        IERC20 dETHToken = savETHVault.dETHToken();

        vm.startPrank(accountFive);
        dETHToken.transfer(address(savETHVault.saveETHRegistry()), 96 ether);
        vm.stopPrank();

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Fund the giant pool in waves
        assertEq(giantSavETHPool.totalETHFromLPs(), 0);
        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 10 ether}(10 ether);
        vm.stopPrank();
        assertEq(giantSavETHPool.totalETHFromLPs(), 10 ether);
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 10 ether);
        assertEq(giantSavETHPool.depositBatchCount(), 0);

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 14 ether}(14 ether);
        vm.stopPrank();
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 1);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 0), 14 ether);
        assertEq(giantSavETHPool.depositBatchCount(), 1);

        vm.startPrank(savETHUserThree);
        giantSavETHPool.depositETH{value: 25 ether}(25 ether);
        vm.stopPrank();
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserThree), 2);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 1), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 2), 1 ether);
        assertEq(giantSavETHPool.depositBatchCount(), 2);

        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 12 ether}(12 ether);
        vm.stopPrank();

        // Inject money into LSD network from giant pool
        bytes[][] memory allKnots = new bytes[][](1);
        uint256[][] memory allAmounts = new uint256[][](1);
        allKnots[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);
        allAmounts[0] = getUint256ArrayFromValues(24 ether, 24 ether);
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(savETHVaultAddress),
            getUint256ArrayFromValues(48 ether),
            allKnots,
            allAmounts
        );

        allAmounts[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            getUint256ArrayFromValues(8 ether),
            allKnots,
            allAmounts
        );

        // Stake and mint for all 3 keys
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);   // savETHUser and savETHUserTwo funded this batch
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);   // savETHUserThree

        // Now try and redeem
        LPToken[][] memory allTokensToRedeem = new LPToken[][](1);
        LPToken[] memory lpTokensForVault = new LPToken[](1);
        lpTokensForVault[0] = manager.savETHVault().lpTokenForKnot(blsPubKeyOne);
        allTokensToRedeem[0] = lpTokensForVault;

        /// savETHUserThree did not supply liquidity to the first batch so it should revert
        allAmounts[0] = getUint256ArrayFromValues(24 ether);
        vm.startPrank(savETHUserThree);
        vm.expectRevert();
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(savETHVaultAddress),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();

        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 0), 0 ether);
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserThree), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 0), 1);

        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 10 ether);
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);

        // let savETH user transfer their tokens to savETH user three
        vm.startPrank(savETHUser);
        giantSavETHPool.lpTokenETH().transfer(savETHUserThree, 10 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 0), 10 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 0 ether);

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 0);
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserThree), 3);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 0), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 1), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 2), 0);

        allAmounts[0] = getUint256ArrayFromValues(10 ether);
        vm.startPrank(savETHUserThree);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(savETHVaultAddress),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();
        assertEq(dETHToken.balanceOf(savETHUserThree), 10 ether);

        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 0), 0 ether);

        // give user three another 10 eth and see if they can withdraw again
        vm.startPrank(savETHUserTwo);
        giantSavETHPool.lpTokenETH().transfer(savETHUserThree, 10 ether);
        vm.stopPrank();

        allAmounts[0] = getUint256ArrayFromValues(10 ether);
        vm.startPrank(savETHUserThree);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(savETHVaultAddress),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();
        assertEq(dETHToken.balanceOf(savETHUserThree), 20 ether);

        // savETH user two should be able to withdraw 4 dETH from the 4 giant LP they never transferred
        uint256 dETHBalBefore = dETHToken.balanceOf(savETHUserTwo);
        allAmounts[0] = getUint256ArrayFromValues(4 ether);
        vm.startPrank(savETHUserTwo);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(savETHVaultAddress),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();
        assertEq(dETHToken.balanceOf(savETHUserTwo), dETHBalBefore + 4 ether);
    }

    function testWithdrawingLPToken() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 64 ether}(64 ether);

        address stakingFundsVault = address(manager.stakingFundsVault());
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(address(manager.savETHVault()).balance, 48 ether);

        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        vm.roll(block.number + 500);

        LPToken blsPubKeyOneLP = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        uint256 associatedWithdrawalBatchForKeyOne = giantFeesAndMevPool.allocatedWithdrawalBatchForBlsPubKey(blsPubKeyOne);
        uint256 totalETHFundedForBatchBefore = giantFeesAndMevPool.totalETHFundedPerBatch(feesAndMevUserOne, associatedWithdrawalBatchForKeyOne);
        assertEq(totalETHFundedForBatchBefore, 4 ether);

        assertEq(blsPubKeyOneLP.balanceOf(feesAndMevUserOne), 0 ether);
        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne), 64 ether);
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.withdrawLP(blsPubKeyOneLP, 2 ether);
        vm.stopPrank();
        assertEq(blsPubKeyOneLP.balanceOf(feesAndMevUserOne), 2 ether);
        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne), 62 ether);

        uint256 totalETHFundedForBatchAfter = giantFeesAndMevPool.totalETHFundedPerBatch(feesAndMevUserOne, associatedWithdrawalBatchForKeyOne);
        assertEq(totalETHFundedForBatchAfter, 2 ether);
        assertEq(giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(feesAndMevUserOne), 6 ether);

        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.withdrawLP(blsPubKeyOneLP, 2 ether);
        vm.stopPrank();

        assertEq(giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(feesAndMevUserOne), 4 ether);
    }

    function testWithdrawingLPTokenAndSETHFromLiquidStakingNetwork() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 64 ether}(64 ether);

        address stakingFundsVault = address(manager.stakingFundsVault());
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(address(manager.savETHVault()).balance, 48 ether);

        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        vm.roll(block.number + 500);

        LPToken blsPubKeyOneLP = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        uint256 associatedWithdrawalBatchForKeyOne = giantFeesAndMevPool.allocatedWithdrawalBatchForBlsPubKey(blsPubKeyOne);
        uint256 totalETHFundedForBatchBefore = giantFeesAndMevPool.totalETHFundedPerBatch(feesAndMevUserOne, associatedWithdrawalBatchForKeyOne);
        assertEq(totalETHFundedForBatchBefore, 4 ether);

        assertEq(blsPubKeyOneLP.balanceOf(feesAndMevUserOne), 0 ether);
        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne), 64 ether);
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.withdrawLP(blsPubKeyOneLP, 2 ether);
        vm.stopPrank();
        assertEq(blsPubKeyOneLP.balanceOf(feesAndMevUserOne), 2 ether);
        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne), 62 ether);

        uint256 totalETHFundedForBatchAfter = giantFeesAndMevPool.totalETHFundedPerBatch(feesAndMevUserOne, associatedWithdrawalBatchForKeyOne);
        assertEq(totalETHFundedForBatchAfter, 2 ether);
        assertEq(giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(feesAndMevUserOne), 6 ether);

        MockSlotRegistry slotRegistry = MockSlotRegistry(manager.slot());
        IERC20 sETHToken = IERC20(slotRegistry.stakeHouseShareTokens(manager.stakehouse()));
        assertEq(sETHToken.balanceOf(feesAndMevUserOne), 0 ether);

        assertEq(manager.stakingFundsVault().totalShares(), 8 ether);

        vm.startPrank(feesAndMevUserOne);
        bytes[] memory blsKeysForVault = new bytes[](1);
        blsKeysForVault[0] = blsPubKeyOne;
        manager.stakingFundsVault().unstakeSyndicateSETHByBurningLP(
            blsKeysForVault,
            2 ether
        );
        vm.stopPrank();
        assertEq(blsPubKeyOneLP.balanceOf(feesAndMevUserOne), 0 ether);

        assertEq(sETHToken.balanceOf(feesAndMevUserOne), 6 ether);
        assertEq(manager.stakingFundsVault().totalShares(), 6 ether);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-25-incorrect-checking-in-_assertuserhasenoughgiantlptoclaimvaultlp
    function testSavETHRedemptionQueue() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);
        address savETHUserTwo = accountFive; vm.deal(savETHUserTwo, 100 ether);
        address savETHUserThree = accountSix; vm.deal(savETHUserThree, 100 ether);

        address savETHVaultAddress = address(manager.savETHVault());
        IERC20 dETHToken = savETHVault.dETHToken();

        vm.startPrank(accountFive);
        dETHToken.transfer(address(savETHVault.saveETHRegistry()), 96 ether);
        vm.stopPrank();

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyThree, accountFour);

        // Fund the giant pool in waves
        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 10 ether}(10 ether);
        vm.stopPrank();

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 14 ether}(14 ether);
        vm.stopPrank();

        vm.startPrank(savETHUserThree);
        giantSavETHPool.depositETH{value: 0.72 ether}(0.72 ether);
        vm.stopPrank();

        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 23.28 ether}(23.28 ether);
        vm.stopPrank();

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 11.5 ether}(11.5 ether);
        vm.stopPrank();

        vm.startPrank(savETHUserThree);
        giantSavETHPool.depositETH{value: 0.26 ether}(0.26 ether);
        vm.stopPrank();

        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 12.24 ether}(12.24 ether);
        vm.stopPrank();

        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 12 ether}(12 ether);
        vm.stopPrank();

        // Inject money into LSD network from giant pool
        bytes[][] memory allKnots = new bytes[][](1);
        uint256[][] memory allAmounts = new uint256[][](1);
        allKnots[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo, blsPubKeyThree);
        allAmounts[0] = getUint256ArrayFromValues(24 ether, 24 ether, 24 ether);
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(72 ether),
            allKnots,
            allAmounts
        );

        allAmounts[0] = getUint256ArrayFromValues(4 ether, 4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            getUint256ArrayFromValues(12 ether),
            allKnots,
            allAmounts
        );

        // Stake and mint for all 3 keys
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);   // savETHUser and savETHUserTwo funded this batch
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);   // savETHUserThree and savETHUser funded this batch
        stakeAndMintDerivativesSingleKey(blsPubKeyThree); // savETHUserTwo, savETHUserThree and savETHUser funded this batch

        // Now try and redeem
        LPToken[][] memory allTokensToRedeem = new LPToken[][](1);
        LPToken[] memory lpTokensForVault = new LPToken[](1);
        lpTokensForVault[0] = manager.savETHVault().lpTokenForKnot(blsPubKeyOne);
        allTokensToRedeem[0] = lpTokensForVault;
        allAmounts[0] = getUint256ArrayFromValues(0.98 ether);

        /// savETHUserThree did not supply liquidity to the first batch so it should revert
        vm.startPrank(savETHUserThree);
        vm.expectRevert();
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(savETHVaultAddress),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();

        // savETH user and savETHUserTwo should be able to withdraw dETH
        assertEq(dETHToken.balanceOf(savETHUser), 0 ether);
        allAmounts[0] = getUint256ArrayFromValues(10 ether);
        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(address(manager.savETHVault())),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();
        assertEq(dETHToken.balanceOf(savETHUser), 10 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 0 ether);

        uint256 dETHBalBefore = dETHToken.balanceOf(savETHUserTwo);
        allAmounts[0] = getUint256ArrayFromValues(14 ether);
        vm.startPrank(savETHUserTwo);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(address(manager.savETHVault())),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();
        assertEq(dETHToken.balanceOf(savETHUserTwo), dETHBalBefore + 14 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 0), 0 ether);

        lpTokensForVault[0] = manager.savETHVault().lpTokenForKnot(blsPubKeyTwo);
        allTokensToRedeem[0] = lpTokensForVault;
        assertEq(dETHToken.balanceOf(savETHUserThree), 0 ether);
        allAmounts[0] = getUint256ArrayFromValues(0.72 ether);
        vm.startPrank(savETHUserThree);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(address(manager.savETHVault())),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();
        assertEq(dETHToken.balanceOf(savETHUserThree), 0.72 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 1), 0 ether);

        dETHBalBefore = dETHToken.balanceOf(savETHUser);
        allAmounts[0] = getUint256ArrayFromValues(23.28 ether);
        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(address(manager.savETHVault())),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();
        assertEq(dETHToken.balanceOf(savETHUser), dETHBalBefore + 23.28 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 1), 0 ether);

        lpTokensForVault[0] = manager.savETHVault().lpTokenForKnot(blsPubKeyThree);
        allTokensToRedeem[0] = lpTokensForVault;

        dETHBalBefore = dETHToken.balanceOf(savETHUser);
        allAmounts[0] = getUint256ArrayFromValues(12.24 ether);
        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(address(manager.savETHVault())),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();
        assertEq(dETHToken.balanceOf(savETHUser), dETHBalBefore + 12.24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 2), 0 ether);

        dETHBalBefore = dETHToken.balanceOf(savETHUserTwo);
        allAmounts[0] = getUint256ArrayFromValues(11.5 ether);
        vm.startPrank(savETHUserTwo);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(address(manager.savETHVault())),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();
        assertEq(dETHToken.balanceOf(savETHUserTwo), dETHBalBefore + 11.5 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 2), 0 ether);

        dETHBalBefore = dETHToken.balanceOf(savETHUserThree);
        allAmounts[0] = getUint256ArrayFromValues(0.26 ether);
        vm.startPrank(savETHUserThree);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(address(manager.savETHVault())),
            allTokensToRedeem,
            allAmounts
        );
        vm.stopPrank();
        assertEq(dETHToken.balanceOf(savETHUserThree), dETHBalBefore + 0.26 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 2), 0 ether);
    }

    function testWithdrawalAllocation() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);
        address savETHUserTwo = accountFive; vm.deal(savETHUserTwo, 100 ether);
        address savETHUserThree = accountSix; vm.deal(savETHUserThree, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyThree, accountFour);

        assertEq(giantSavETHPool.depositBatchCount(), 0);

        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 12 ether}(12 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.depositBatchCount(), 0);
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);

        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 12 ether}(12 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.depositBatchCount(), 1);
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 25 ether}(25 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.depositBatchCount(), 2);
        assertEq(giantSavETHPool.stakedBatchCount(), 0);

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 24 ether);

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 0), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 1), 2);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 1), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 2), 1 ether);

        vm.startPrank(savETHUserThree);
        giantSavETHPool.depositETH{value: 23.5 ether}(23.5 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.depositBatchCount(), 3);

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 0), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 1), 2);

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserThree), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 0), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 1), 3);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 2), 23 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 3), 0.5 ether);

        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 12 ether}(12 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 1), 3);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 3), 12 ether);

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 11.5 ether}(11.5 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 3);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 0), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 1), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 2), 3);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 1), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 2), 1 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 3), 11.5 ether);

        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 12 ether}(12 ether);
        vm.stopPrank();

        assertEq(giantFeesAndMevPool.getSetOfAssociatedDepositBatchesSize(feesAndMevUserOne), 3);
        assertEq(giantFeesAndMevPool.getAssociatedDepositBatchIDAtIndex(feesAndMevUserOne, 0), 0);
        assertEq(giantFeesAndMevPool.getAssociatedDepositBatchIDAtIndex(feesAndMevUserOne, 1), 1);
        assertEq(giantFeesAndMevPool.getAssociatedDepositBatchIDAtIndex(feesAndMevUserOne, 2), 2);
        assertEq(giantFeesAndMevPool.totalETHFundedPerBatch(feesAndMevUserOne, 0), 4 ether);
        assertEq(giantFeesAndMevPool.totalETHFundedPerBatch(feesAndMevUserOne, 1), 4 ether);
        assertEq(giantFeesAndMevPool.totalETHFundedPerBatch(feesAndMevUserOne, 2), 4 ether);

        bytes[][] memory allKnots = new bytes[][](1);
        uint256[][] memory allAmounts = new uint256[][](1);
        allKnots[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo, blsPubKeyThree);
        allAmounts[0] = getUint256ArrayFromValues(24 ether, 24 ether, 24 ether);
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(72 ether),
            allKnots,
            allAmounts
        );

        assertEq(giantSavETHPool.stakedBatchCount(), 3);
        assertEq(giantFeesAndMevPool.stakedBatchCount(), 0);
        assertEq(giantSavETHPool.allocatedWithdrawalBatchForBlsPubKey(blsPubKeyOne), 0);
        assertEq(giantSavETHPool.allocatedBlsPubKeyForWithdrawalBatch(0).length, 48);

        assertEq(giantSavETHPool.allocatedWithdrawalBatchForBlsPubKey(blsPubKeyTwo), 1);
        assertEq(giantSavETHPool.allocatedBlsPubKeyForWithdrawalBatch(1).length, 48);

        assertEq(giantSavETHPool.allocatedWithdrawalBatchForBlsPubKey(blsPubKeyThree), 2);
        assertEq(giantSavETHPool.allocatedBlsPubKeyForWithdrawalBatch(2).length, 48);

        allAmounts[0] = getUint256ArrayFromValues(4 ether, 4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            getUint256ArrayFromValues(12 ether),
            allKnots,
            allAmounts
        );

        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);
        stakeAndMintDerivativesSingleKey(blsPubKeyThree);

        assertEq(giantSavETHPool.stakedBatchCount(), 3);
        assertEq(giantFeesAndMevPool.stakedBatchCount(), 3);
        assertEq(giantSavETHPool.allocatedWithdrawalBatchForBlsPubKey(blsPubKeyOne), 0);
        assertEq(giantSavETHPool.allocatedBlsPubKeyForWithdrawalBatch(0).length, 48);
        assertEq(keccak256(giantSavETHPool.allocatedBlsPubKeyForWithdrawalBatch(0)), keccak256(blsPubKeyOne));

        assertEq(giantSavETHPool.allocatedWithdrawalBatchForBlsPubKey(blsPubKeyTwo), 1);
        assertEq(giantSavETHPool.allocatedBlsPubKeyForWithdrawalBatch(1).length, 48);
        assertEq(keccak256(giantSavETHPool.allocatedBlsPubKeyForWithdrawalBatch(1)), keccak256(blsPubKeyTwo));

        assertEq(giantSavETHPool.allocatedWithdrawalBatchForBlsPubKey(blsPubKeyThree), 2);
        assertEq(giantSavETHPool.allocatedBlsPubKeyForWithdrawalBatch(2).length, 48);
        assertEq(keccak256(giantSavETHPool.allocatedBlsPubKeyForWithdrawalBatch(2)), keccak256(blsPubKeyThree));
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-01-freezing-of-funds---hacker-can-prevent-users-withdraws-in-giant-pools
    function testPreventWithdraw() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 12 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 4 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 24 ether);
        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        // Deposit 4 ETH into giant fees and mev
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();
        // Deposit 24 ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);
        assertEq(giantSavETHPool.lpTokenETH().balanceOf(savETHUser), 24 ether);
        assertEq(address(giantSavETHPool).balance, 24 ether);
        // Deploy 24 ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne);
        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(24 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(address(manager.savETHVault()).balance, 24 ether);

        assertEq(address(giantFeesAndMevPool).balance, 4 ether);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            getUint256ArrayFromValues(4 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        IERC20 dETHToken = savETHVault.dETHToken();
        vm.startPrank(accountFive);
        dETHToken.transfer(address(savETHVault.saveETHRegistry()), 24 ether);
        vm.stopPrank();
        LPToken[] memory tokens = new LPToken[](1);
        tokens[0] = savETHVault.lpTokenForKnot(blsPubKeyOne);
        LPToken[][] memory allTokens = new LPToken[][](1);
        allTokens[0] = tokens;
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);
        // User will not have any dETH to start
        assertEq(dETHToken.balanceOf(savETHUser), 0);
        // Warp ahead -> savETHUser eligible to dETH
        vm.warp(block.timestamp + 2 days);
        // Send 0 tokens to savETHUser so he cannot withdrawDETH
        address hacker = address(0xdeadbeef);
        vm.startPrank(hacker);
        GiantLP lp = giantSavETHPool.lpTokenETH();
        vm.expectRevert("Transfer Error"); // Update: We now revert
        lp.transfer(savETHUser, 0);
        vm.stopPrank();
        address[] memory addresses = getAddressArrayFromValues(address(manager.savETHVault()));
        vm.startPrank(savETHUser);
        // Validate withdrawDETH will not revert
        //vm.expectRevert("Too new");
        giantSavETHPool.withdrawDETH(addresses, allTokens, stakeAmountsForVaults);
        vm.stopPrank();
    }

    // https://code4rena.com/reports/2022-11-stakehouse#h-19-withdraweth-in-giantpoolbase-dont-call-_distributeethrewardstouserfortoken-or-_onwithdraw-which-would-make-users-to-lose-their-remaining-rewards-
    function testRewardsGivenToUserWhenWithdrawingETH() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 64 ether}(64 ether);

        address stakingFundsVault = address(manager.stakingFundsVault());
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(address(manager.savETHVault()).balance, 48 ether);

        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(giantFeesAndMevPool.idleETH(), 64 ether - 8 ether);
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 0 ether);
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0 ether);
        assertEq(address(giantFeesAndMevPool).balance, 64 ether - 8 ether);

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        // Push forward to activate knots in syndicates
        vm.roll(block.number + 1 + (8*32));

        sendEIP1559RewardsToSyndicateAtAddress(0.32 ether, manager.syndicate());

        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 0 ether);
        assertEq(address(giantFeesAndMevPool).balance, 64 ether - 8 ether);

        vm.warp(block.timestamp + 2 days);

        LPToken lpBlsPubKeyOne = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        LPToken lpBlsPubKeyTwo = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyTwo);
        LPToken[][] memory allTokens = new LPToken[][](1);
        LPToken[] memory lpTokens = new LPToken[](2);
        lpTokens[0] = lpBlsPubKeyOne;
        lpTokens[1] = lpBlsPubKeyTwo;
        allTokens[0] = lpTokens;

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256 preview = giantFeesAndMevPool.previewAccumulatedETH(
            feesAndMevUserOne,
            getAddressArrayFromValues(stakingFundsVault),
            allTokens
        );

        assertEq(preview, 0.16 ether - 2);

        giantFeesAndMevPool.fetchGiantPoolRewards(
            getAddressArrayFromValues(stakingFundsVault),
            blsKeysForVaults
        );

        uint256 feesAndMevUserOneBalBefore = feesAndMevUserOne.balance;
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.withdrawETH(2 ether);
        vm.stopPrank();
        uint256 feesAndMevUserOneBalAfter = feesAndMevUserOne.balance;
        assertEq(feesAndMevUserOneBalAfter - feesAndMevUserOneBalBefore, 2.16 ether - 2);
    }

    function testClaimMevRewardsIfETHSentToSyndicateLSDAndGiantPoolAtSameTime() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 16 ether}(16 ether);
        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne), 16 ether);

        address stakingFundsVault = address(manager.stakingFundsVault());
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(address(manager.savETHVault()).balance, 48 ether);

        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(giantFeesAndMevPool.idleETH(), 8 ether);
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 0 ether);
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0 ether);
        assertEq(address(giantFeesAndMevPool).balance, 8 ether);

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        // Push forward to activate knots in syndicates
        vm.roll(block.number + 1 + (8*32));

        sendEIP1559RewardsToSyndicateAtAddress(0.32 ether, manager.syndicate());

        vm.deal(address(manager.stakingFundsVault()), 0.11 ether);
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0.11 ether);

        //vm.deal(address(giantFeesAndMevPool), 0.1651 ether);
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 0 ether);

        assertEq(address(giantFeesAndMevPool).balance, 8 ether);

        uint256 totalRewardsSentTo3Pools = 0.16 ether + 0.11 ether + 0 ether;

        vm.warp(block.timestamp + 2 days);

        LPToken lpBlsPubKeyOne = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        LPToken lpBlsPubKeyTwo = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyTwo);
        LPToken[][] memory allTokens = new LPToken[][](1);
        LPToken[] memory lpTokens = new LPToken[](2);
        lpTokens[0] = lpBlsPubKeyOne;
        lpTokens[1] = lpBlsPubKeyTwo;
        allTokens[0] = lpTokens;

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256 preview = giantFeesAndMevPool.previewAccumulatedETH(
            feesAndMevUserOne,
            getAddressArrayFromValues(stakingFundsVault),
            allTokens
        );

        uint256 balFeesUserOneBefore = feesAndMevUserOne.balance;
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.claimRewards(
            feesAndMevUserOne,
            getAddressArrayFromValues(stakingFundsVault),
            blsKeysForVaults
        );
        vm.stopPrank();
        uint256 balFeesUserOneAfter = feesAndMevUserOne.balance;

        assertEq(giantFeesAndMevPool.totalRewardsReceived(), totalRewardsSentTo3Pools - 2);
        assertEq(balFeesUserOneAfter - balFeesUserOneBefore, totalRewardsSentTo3Pools - 2);
        assertEq(balFeesUserOneAfter - balFeesUserOneBefore, preview);

        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0.16 ether + 0.11 ether - 2);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-15-giantmevandfeespoolpreviewaccumulatedeth-function-accumulated-variable-is-not-updated-correctly-in-for-loop-leading-to-result-that-is-too-low
    function testClaimETHFromGiantFeesAndMevMultipleTimes() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 16 ether}(16 ether);
        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne), 16 ether);
        assertEq(giantFeesAndMevPool.idleETH(), 16 ether);
        assertEq(giantFeesAndMevPool.getSetOfAssociatedDepositBatchesSize(feesAndMevUserOne), 4);
        assertEq(giantFeesAndMevPool.getAssociatedDepositBatchIDAtIndex(feesAndMevUserOne, 0), 0);
        assertEq(giantFeesAndMevPool.getAssociatedDepositBatchIDAtIndex(feesAndMevUserOne, 1), 1);
        assertEq(giantFeesAndMevPool.getAssociatedDepositBatchIDAtIndex(feesAndMevUserOne, 2), 2);
        assertEq(giantFeesAndMevPool.getAssociatedDepositBatchIDAtIndex(feesAndMevUserOne, 3), 3);
        assertEq(giantFeesAndMevPool.depositBatchCount(), 4);

        address stakingFundsVault = address(manager.stakingFundsVault());
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(address(manager.savETHVault()).balance, 48 ether);

        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(giantFeesAndMevPool.idleETH(), 8 ether);
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 0 ether);
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0 ether);
        assertEq(address(giantFeesAndMevPool).balance, 8 ether);

        // cannot claim if no derivatives minted
        vm.expectRevert(bytes4(keccak256("NoDerivativesMinted()")));
        giantFeesAndMevPool.claimRewards(
            address(this),
            getAddressArrayFromValues(stakingFundsVault),
            blsKeysForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        // Push forward to activate knots in syndicates
        vm.roll(block.number + 1 + (8*32));

        sendEIP1559RewardsToSyndicateAtAddress(0.32 ether, manager.syndicate());

        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 0 ether);
        assertEq(address(giantFeesAndMevPool).balance, 8 ether);

        vm.warp(block.timestamp + 2 days);

        LPToken lpBlsPubKeyOne = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        LPToken lpBlsPubKeyTwo = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyTwo);
        LPToken[][] memory allTokens = new LPToken[][](1);
        LPToken[] memory lpTokens = new LPToken[](2);
        lpTokens[0] = lpBlsPubKeyOne;
        lpTokens[1] = lpBlsPubKeyTwo;
        allTokens[0] = lpTokens;

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        // preview function checks array length consistency
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantFeesAndMevPool.previewAccumulatedETH(
            feesAndMevUserOne,
            getAddressArrayFromValues(stakingFundsVault),
            new LPToken[][](0)
        );

        uint256 preview = giantFeesAndMevPool.previewAccumulatedETH(
            feesAndMevUserOne,
            getAddressArrayFromValues(stakingFundsVault),
            allTokens
        );

        uint256 balFeesUserOneBefore = feesAndMevUserOne.balance;
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.claimRewards(
            feesAndMevUserOne,
            getAddressArrayFromValues(stakingFundsVault),
            blsKeysForVaults
        );
        vm.stopPrank();
        uint256 balFeesUserOneAfter = feesAndMevUserOne.balance;
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 0.16 ether - 2);
        assertEq(balFeesUserOneAfter - balFeesUserOneBefore, 0.16 ether - 2);
        assertEq(balFeesUserOneAfter - balFeesUserOneBefore, preview);
        assertEq(manager.stakingFundsVault().totalShares(), 8 ether);

        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0.16 ether - 2);
        assertEq(giantFeesAndMevPool.claimed(feesAndMevUserOne, address(giantFeesAndMevPool.lpTokenETH())), 0.16 ether - 2);

        balFeesUserOneBefore = feesAndMevUserOne.balance;
        vm.startPrank(feesAndMevUserOne);
        vm.expectRevert("Nothing received");
        giantFeesAndMevPool.claimRewards(
            feesAndMevUserOne,
            getAddressArrayFromValues(stakingFundsVault),
            blsKeysForVaults
        );
        vm.stopPrank();
        balFeesUserOneAfter = feesAndMevUserOne.balance;
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 0.16 ether - 2);
        assertEq(balFeesUserOneAfter - balFeesUserOneBefore, 0);
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0.16 ether - 2);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyThree, accountFour);

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyThree);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(4 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0.16 ether - 2);

        vm.warp(block.timestamp + 40 minutes);

        lpTokens = new LPToken[](1);
        lpTokens[0] = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyThree);
        allTokens[0] = lpTokens;

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);

        sendEIP1559RewardsToSyndicateAtAddress(0.32 ether, manager.syndicate());
        manager.stakingFundsVault().claimFundsFromSyndicateForDistribution(getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo));
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0.32 ether - 2);
        assertEq(address(manager.syndicate()).balance, 0.32 ether + 2);
        assertEq(giantFeesAndMevPool.claimed(feesAndMevUserOne, address(giantFeesAndMevPool.lpTokenETH())), 0.16 ether - 2);
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 0.16 ether - 2);

        giantFeesAndMevPool.bringUnusedETHBackIntoGiantPool(
            getAddressArrayFromValues(stakingFundsVault),
            allTokens,
            stakeAmountsForVaults
        );

        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0.32 ether - 2);
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 0.16 ether - 2);
        assertEq(stakingFundsVault.balance, 0.16 ether);

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyThree);

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(24 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(4 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        assertEq(address(giantFeesAndMevPool).balance, 4 ether);

        stakeAndMintDerivativesSingleKey(blsPubKeyThree);

        // Push forward to activate knots in syndicates
        vm.roll(block.number + 1 + (8*32));

        assertEq(address(giantFeesAndMevPool).balance, 4 ether);

        assertEq(giantFeesAndMevPool.totalLPAssociatedWithDerivativesMinted(), 12 ether);

        vm.warp(block.timestamp + 2 days);

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo, blsPubKeyThree);

        assertEq(giantFeesAndMevPool.claimed(feesAndMevUserOne, address(giantFeesAndMevPool.lpTokenETH())), 0.16 ether - 2);

        assertEq(stakingFundsVault.balance, 0.16 ether);
        assertEq(address(giantFeesAndMevPool).balance, 4 ether);
        delete balFeesUserOneBefore;
        balFeesUserOneBefore = feesAndMevUserOne.balance;
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.claimRewards(
            feesAndMevUserOne,
            getAddressArrayFromValues(stakingFundsVault),
            blsKeysForVaults
        );
        vm.stopPrank();
        delete balFeesUserOneAfter;
        balFeesUserOneAfter = feesAndMevUserOne.balance;
        assertEq(balFeesUserOneAfter - balFeesUserOneBefore, 0.16 ether - 1);
        assertEq(stakingFundsVault.balance, 0 ether);
        assertEq(address(giantFeesAndMevPool).balance, 4 ether + 1);

        assertEq(address(giantFeesAndMevPool).balance, 4 ether + 1);
        stakingFundsVault.call{value: 0.12 ether}("");
        address(giantFeesAndMevPool).call{value: 0.12 ether}("");

        uint256 giantTotalSeenBefore = giantFeesAndMevPool.totalETHSeen();
        balFeesUserOneBefore = feesAndMevUserOne.balance;
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.claimRewards(
            feesAndMevUserOne,
            getAddressArrayFromValues(stakingFundsVault),
            blsKeysForVaults
        );
        vm.stopPrank();
        balFeesUserOneAfter = feesAndMevUserOne.balance;
        assertEq(giantFeesAndMevPool.totalETHSeen(), giantTotalSeenBefore + 0.24 ether);
        assertEq(address(giantFeesAndMevPool).balance, 4 ether + 1);
        assertEq(balFeesUserOneAfter - balFeesUserOneBefore, 0.24 ether);
    }

    function testingETHSuppliedToStakingFundsVaultAfterMintingDerivativesOfAnyKnotRoundOne() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 24 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 24 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 24 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);

        // Deposit ETH into giant fees and mev
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(24 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(address(manager.savETHVault()).balance, 24 ether);

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            getUint256ArrayFromValues(4 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);

        assertEq(manager.stakingFundsVault().totalETHSeen(), 0);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        vm.startPrank(feesAndMevUserOne);
        manager.stakingFundsVault().depositETHForStaking{value: 2 ether}(blsPubKeyTwo, 2 ether);
        vm.stopPrank();

        assertEq(manager.stakingFundsVault().totalETHSeen(), 0);
    }

    function testingETHSuppliedToStakingFundsVaultAfterMintingDerivativesOfAnyKnotRoundTwo() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 24 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 24 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 24 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);

        // Deposit ETH into giant fees and mev
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(24 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(address(manager.savETHVault()).balance, 24 ether);

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            getUint256ArrayFromValues(4 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);

        assertEq(manager.stakingFundsVault().totalETHSeen(), 0);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        vm.startPrank(feesAndMevUserOne);
        manager.stakingFundsVault().batchDepositETHForStaking{value: 3 ether}(
            getBytesArrayFromBytes(blsPubKeyTwo),
            getUint256ArrayFromValues(3 ether)
        );
        vm.stopPrank();

        assertEq(manager.stakingFundsVault().totalETHSeen(), 0);
    }

    function testETHSuppliedFromGiantPoolCanBeUsedInFactoryDeployedLSDN() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 12 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 4 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 12 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 24 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);
        assertEq(giantSavETHPool.lpTokenETH().balanceOf(savETHUser), 24 ether);
        assertEq(address(giantSavETHPool).balance, 24 ether);

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);

        // Deposit ETH into giant fees and mev
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();

        vm.startPrank(feesAndMevUserTwo);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(24 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(address(manager.savETHVault()).balance, 24 ether);

        assertEq(giantFeesAndMevPool.totalETHSeen(), 0);

        vm.warp(block.timestamp + 2 days);

        vm.prank(feesAndMevUserTwo); giantFeesAndMevPool.withdrawETH(4 ether);

        assertEq(giantFeesAndMevPool.totalETHSeen(), 0);

        vm.startPrank(feesAndMevUserTwo);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();

        assertEq(giantFeesAndMevPool.totalETHSeen(), 0);

        assertEq(address(giantFeesAndMevPool).balance, 8 ether);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            getUint256ArrayFromValues(4 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);

        IERC20 dETHToken = savETHVault.dETHToken();

        vm.startPrank(accountFive);
        dETHToken.transfer(address(savETHVault.saveETHRegistry()), 24 ether);
        vm.stopPrank();

        LPToken[] memory tokens = new LPToken[](1);
        tokens[0] = savETHVault.lpTokenForKnot(blsPubKeyOne);

        LPToken[][] memory allTokens = new LPToken[][](1);
        allTokens[0] = tokens;

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);

        // User will not have any dETH to start
        assertEq(dETHToken.balanceOf(savETHUser), 0);

        // Warp ahead
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(address(manager.savETHVault())),
            allTokens,
            stakeAmountsForVaults
        );
        vm.stopPrank();

        assertEq(dETHToken.balanceOf(savETHUser), 24 ether);
    }

    function testDepositETHInvalidAmount() public {
        address savETHUser = accountOne; vm.deal(savETHUser, 100 ether);
        
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        giantSavETHPool.depositETH{value: 0.0001 ether}(0.0001 ether);
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        giantSavETHPool.depositETH{value: 0.0011 ether}(0.0011 ether);
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        giantSavETHPool.depositETH{value: 2 ether}(1 ether);

        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 10 ether}(10 ether);
        vm.stopPrank();
    }

    function testWithdrawETHInvalidAmount() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);
        vm.stopPrank();

        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 16 ether}(16 ether);
        vm.stopPrank();

        StakingFundsVault stakingFundsVault = manager.stakingFundsVault();

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);
        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(stakingFundsVault)),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Warp ahead
        vm.warp(block.timestamp + 2 days);
        
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawETH(0);
        vm.stopPrank();

        vm.expectRevert(bytes4(keccak256("InvalidBalance()")));
        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawETH(73 ether);
        vm.stopPrank();

        vm.expectRevert(bytes4(keccak256("NotEnoughIdleETH()")));
        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawETH(25 ether);
        vm.stopPrank();

        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawETH(23 ether);
        vm.stopPrank();
    }

    function testWithdrawableAmountOfETH() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 60 ether}(60 ether);
        vm.stopPrank();
        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 12 ether}(12 ether);
        vm.stopPrank();

        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 16 ether}(16 ether);
        vm.stopPrank();

        StakingFundsVault stakingFundsVault = manager.stakingFundsVault();

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);
        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(stakingFundsVault)),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        assertEq(giantSavETHPool.withdrawableAmountOfETH(savETHUser), 24 ether);
        assertEq(giantFeesAndMevPool.withdrawableAmountOfETH(feesAndMevUserOne), 8 ether);

        vm.warp(block.timestamp + 45 minutes);

        LPToken[][] memory allTokens = new LPToken[][](1);
        LPToken[] memory lpTokens = new LPToken[](2);
        lpTokens[0] = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        lpTokens[1] = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyTwo);
        allTokens[0] = lpTokens;
        giantFeesAndMevPool.bringUnusedETHBackIntoGiantPool(
            getAddressArrayFromValues(address(stakingFundsVault)),
            allTokens,
            stakeAmountsForVaults
        );

        assertEq(giantFeesAndMevPool.withdrawableAmountOfETH(feesAndMevUserOne), 16 ether);

        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(stakingFundsVault)),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        assertEq(giantSavETHPool.withdrawableAmountOfETH(savETHUser), 24 ether);
        assertEq(giantFeesAndMevPool.withdrawableAmountOfETH(feesAndMevUserOne), 8 ether);

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        assertEq(giantSavETHPool.withdrawableAmountOfETH(savETHUser), 24 ether);
        assertEq(giantFeesAndMevPool.withdrawableAmountOfETH(feesAndMevUserOne), 8 ether);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyThree, accountFour);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyThree);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(24 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        assertEq(giantSavETHPool.withdrawableAmountOfETH(savETHUser), 0);
        assertEq(giantFeesAndMevPool.withdrawableAmountOfETH(feesAndMevUserOne), 8 ether);

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(stakingFundsVault)),
            getUint256ArrayFromValues(4 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(giantFeesAndMevPool.withdrawableAmountOfETH(feesAndMevUserOne), 4 ether);

        stakeAndMintDerivativesSingleKey(blsPubKeyThree);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyFour, accountFour);

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyFour);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(stakingFundsVault)),
            getUint256ArrayFromValues(4 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(giantFeesAndMevPool.withdrawableAmountOfETH(feesAndMevUserOne), 0);

        vm.startPrank(feesAndMevUserTwo);
        giantFeesAndMevPool.depositETH{value: 19 ether}(19 ether);
        vm.stopPrank();

        assertEq(giantFeesAndMevPool.withdrawableAmountOfETH(feesAndMevUserOne), 0);
        assertEq(giantFeesAndMevPool.withdrawableAmountOfETH(feesAndMevUserTwo), 19 ether);
        assertEq(giantSavETHPool.withdrawableAmountOfETH(savETHUser), 0);
    }

    function testBatchDepositETHForStakingRevertReasons() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);
        address savETHUserTwo = accountFive; vm.deal(savETHUserTwo, 100 ether);
        address savETHUserThree = accountSix; vm.deal(savETHUserThree, 100 ether);

        address savETHVaultAddress = address(manager.savETHVault());

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        
        // 1. Check GiantSavETHVaultPool

        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 10 ether}(10 ether);
        vm.stopPrank();
        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 14 ether}(14 ether);
        vm.stopPrank();
        vm.startPrank(savETHUserThree);
        giantSavETHPool.depositETH{value: 25 ether}(25 ether);
        vm.stopPrank();

        bytes[][] memory allKnots = new bytes[][](1);
        uint256[][] memory allAmounts = new uint256[][](1);
        allKnots[0] = getBytesArrayFromBytes(blsPubKeyOne);
        allAmounts[0] = getUint256ArrayFromValues(24 ether);

        // - check invalid params
        vm.expectRevert(bytes4(keccak256("EmptyArray()")));
        giantSavETHPool.batchDepositETHForStaking(
            new address[](0),
            getUint256ArrayFromValues(24 ether),
            allKnots,
            allAmounts
        );
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(savETHVaultAddress),
            new uint256[](0),
            allKnots,
            allAmounts
        );
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(savETHVaultAddress),
            getUint256ArrayFromValues(24 ether),
            new bytes[][](0),
            allAmounts
        );
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(savETHVaultAddress),
            getUint256ArrayFromValues(24 ether),
            allKnots,
            new uint256[][](0)
        );
        // https://code4rena.com/reports/2022-11-stakehouse/#h-13-possible-reentrancy-and-fund-theft-in-withdrawdeth-of-giantsavethvaultpool-because-there-is-no-whitelist-check-for-user-provided-vaults-and-there-is-no-reentrancy-defense
        vm.expectRevert(bytes4(keccak256("InvalidSavETHVault()")));
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(0)),
            getUint256ArrayFromValues(24 ether),
            allKnots,
            allAmounts
        );
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        allAmounts[0] = getUint256ArrayFromValues(23.9 ether);
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(savETHVaultAddress),
            getUint256ArrayFromValues(23.9 ether),
            allKnots,
            allAmounts
        );
        vm.expectRevert(bytes4(keccak256("FeesAndMevPoolCannotMatch()")));
        allAmounts[0] = getUint256ArrayFromValues(24 ether);
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(savETHVaultAddress),
            getUint256ArrayFromValues(24 ether),
            allKnots,
            allAmounts
        );

        // - batchDepositETHForStaking passed
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 12 ether}(12 ether);
        vm.stopPrank();
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(savETHVaultAddress),
            getUint256ArrayFromValues(24 ether),
            allKnots,
            allAmounts
        );

        // 2. Check GiantMevAndFeesPool
        // - check invalid params
        address stakingFundsVault = address(manager.stakingFundsVault());
        vm.expectRevert(bytes4(keccak256("EmptyArray()")));
        giantFeesAndMevPool.batchDepositETHForStaking(
            new address[](0),
            getUint256ArrayFromValues(4 ether),
            allKnots,
            allAmounts
        );
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            new uint256[](0),
            allKnots,
            allAmounts
        );
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(4 ether),
            new bytes[][](0),
            allAmounts
        );
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(4 ether),
            allKnots,
            new uint256[][](0)
        );
        // https://code4rena.com/reports/2022-11-stakehouse/#h-13-possible-reentrancy-and-fund-theft-in-withdrawdeth-of-giantsavethvaultpool-because-there-is-no-whitelist-check-for-user-provided-vaults-and-there-is-no-reentrancy-defense
        vm.expectRevert(bytes4(keccak256("InvalidStakingFundsVault()")));
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(0)),
            getUint256ArrayFromValues(4 ether),
            allKnots,
            allAmounts
        );
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        allAmounts[0] = getUint256ArrayFromValues(3.9 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(3.9 ether),
            allKnots,
            allAmounts
        );

        // - batchDepositETHForStaking passed
        allAmounts[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(4 ether),
            allKnots,
            allAmounts
        );
    }

    function testWithdrawDETHFromSaveEthVaultPool() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 12 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 4 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 24 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        address savETHVaultAddress = address(manager.savETHVault());

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);

        // Deposit ETH into giant fees and mev
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();

        // deposit ETH for staking
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(savETHVaultAddress),
            getUint256ArrayFromValues(24 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            getUint256ArrayFromValues(4 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);

        IERC20 dETHToken = savETHVault.dETHToken();

        vm.startPrank(accountFive);
        dETHToken.transfer(address(savETHVault.saveETHRegistry()), 24 ether);
        vm.stopPrank();

        // No dETH at start
        assertEq(dETHToken.balanceOf(savETHUser), 0);

        // Warp ahead
        vm.warp(block.timestamp + 2 days);

        LPToken[] memory tokens = new LPToken[](1);
        tokens[0] = savETHVault.lpTokenForKnot(blsPubKeyOne);
        LPToken[][] memory allTokens = new LPToken[][](1);
        allTokens[0] = tokens;

        vm.expectRevert(bytes4(keccak256("EmptyArray()")));
        giantSavETHPool.withdrawDETH(
            new address[](0),
            allTokens,
            stakeAmountsForVaults
        );
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(savETHVaultAddress),
            new LPToken[][](0),
            stakeAmountsForVaults
        );
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(savETHVaultAddress),
            allTokens,
            new uint256[][](0)
        );

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(0.0001 ether);
        vm.startPrank(savETHUser);
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(savETHVaultAddress),
            allTokens,
            stakeAmountsForVaults
        );
        vm.stopPrank();

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(25 ether);
        vm.startPrank(savETHUser);
        vm.expectRevert(bytes4(keccak256("InvalidBalance()")));
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(savETHVaultAddress),
            allTokens,
            stakeAmountsForVaults
        );
        vm.stopPrank();

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);
        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawDETH(
            getAddressArrayFromValues(savETHVaultAddress),
            allTokens,
            stakeAmountsForVaults
        );
        vm.stopPrank();

        assertEq(dETHToken.balanceOf(savETHUser), 24 ether);
    }

    function testBringUnusedETHBackIntoGiantPool() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);
        address savETHUserTwo = accountFive; vm.deal(savETHUserTwo, 100 ether);
        address savETHUserThree = accountSix; vm.deal(savETHUserThree, 100 ether);

        address savETHVaultAddress = address(manager.savETHVault());
        address stakingFundsVault = address(manager.stakingFundsVault());

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Fund the giant pool in waves
        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 10 ether}(10 ether);
        vm.stopPrank();

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 14 ether}(14 ether);
        vm.stopPrank();

        vm.startPrank(savETHUserThree);
        giantSavETHPool.depositETH{value: 25 ether}(25 ether);
        vm.stopPrank();

        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 12 ether}(12 ether);
        vm.stopPrank();

        // Inject money into LSD network from giant pool
        bytes[][] memory allKnots = new bytes[][](1);
        uint256[][] memory allAmounts = new uint256[][](1);
        allKnots[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);
        allAmounts[0] = getUint256ArrayFromValues(24 ether, 24 ether);
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(savETHVaultAddress),
            getUint256ArrayFromValues(48 ether),
            allKnots,
            allAmounts
        );
        allAmounts[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            allKnots,
            allAmounts
        );

        // Warp ahead
        vm.warp(block.timestamp + 2 days);

        // GiantSavETHVaultPool has 1 ether before
        assertEq(address(giantSavETHPool).balance, 1 ether);

        LPToken[][] memory lpTokens = new LPToken[][](1);
        lpTokens[0] = new LPToken[](1);
        lpTokens[0][0] = manager.savETHVault().lpTokenForKnot(blsPubKeyOne);
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 10 ether;

        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantSavETHPool.bringUnusedETHBackIntoGiantPool(
            getAddressArrayFromValues(savETHVaultAddress),
            new LPToken[][](0),
            amounts
        );
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantSavETHPool.bringUnusedETHBackIntoGiantPool(
            getAddressArrayFromValues(savETHVaultAddress),
            lpTokens,
            new uint256[][](0)
        );
        vm.expectRevert("Empty arrays");
        giantSavETHPool.bringUnusedETHBackIntoGiantPool(
            getAddressArrayFromValues(savETHVaultAddress),
            new LPToken[][](1),
            new uint256[][](1)
        );
        vm.expectRevert("Inconsisent array length");
        uint256[][] memory invalidAmounts = new uint256[][](1);
        invalidAmounts[0] = new uint256[](2);
        invalidAmounts[0][0] = 10 ether;
        invalidAmounts[0][1] = 10 ether;
        giantSavETHPool.bringUnusedETHBackIntoGiantPool(
            getAddressArrayFromValues(savETHVaultAddress),
            lpTokens,
            invalidAmounts
        );
        giantSavETHPool.bringUnusedETHBackIntoGiantPool(
            getAddressArrayFromValues(savETHVaultAddress),
            lpTokens,
            amounts
        );

        // GiantSavETHVaultPool has 11 ether after
        assertEq(address(giantSavETHPool).balance, 11 ether);

        // GiantMevAndFeesPool has 4 ether before
        assertEq(address(giantFeesAndMevPool).balance, 4 ether);

        lpTokens[0][0] = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        amounts[0][0] = 2 ether;

        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantFeesAndMevPool.bringUnusedETHBackIntoGiantPool(
            getAddressArrayFromValues(stakingFundsVault),
            new LPToken[][](0),
            amounts
        );
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantFeesAndMevPool.bringUnusedETHBackIntoGiantPool(
            getAddressArrayFromValues(stakingFundsVault),
            lpTokens,
            new uint256[][](0)
        );
        giantFeesAndMevPool.bringUnusedETHBackIntoGiantPool(
            getAddressArrayFromValues(stakingFundsVault),
            lpTokens,
            amounts
        );

        // GiantMevAndFeesPool has 6 ether after
        assertEq(address(giantFeesAndMevPool).balance, 6 ether);
    }

    function testFetchGiantPoolRewards() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 16 ether}(16 ether);

        address stakingFundsVault = address(manager.stakingFundsVault());

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        assertEq(giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(feesAndMevUserOne), 0);

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        // Push forward to activate knots in syndicate
        vm.roll(block.number + 1 + (20*32));

        sendEIP1559RewardsToSyndicateAtAddress(0.32 ether, manager.syndicate());

        assertEq(giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(feesAndMevUserOne), 8 ether);

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(bytes4(keccak256("EmptyArray()")));
        giantFeesAndMevPool.fetchGiantPoolRewards(
            new address[](0),
            blsKeysForVaults
        );
        vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
        giantFeesAndMevPool.fetchGiantPoolRewards(
            getAddressArrayFromValues(stakingFundsVault),
            new bytes[][](0)
        );

        giantFeesAndMevPool.fetchGiantPoolRewards(
            getAddressArrayFromValues(stakingFundsVault),
            blsKeysForVaults
        );
    }

    function testWithdrawETHAfterDerivativesMinted() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 16 ether}(16 ether);

        address stakingFundsVault = address(manager.stakingFundsVault());

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);
        sendEIP1559RewardsToSyndicateAtAddress(0.32 ether, manager.syndicate());

        vm.warp(block.timestamp + 2 days);

        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne), 16 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.withdrawETH(4 ether);

        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne), 12 ether);
    }

    function testDepositETHAfterDerivativesMinted() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 8 ether}(8 ether);
        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 8 ether}(8 ether);

        address stakingFundsVault = address(manager.stakingFundsVault());

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);
        sendEIP1559RewardsToSyndicateAtAddress(0.32 ether, manager.syndicate());

        vm.warp(block.timestamp + 2 days);

        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne), 16 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 16 ether}(16 ether);

        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne), 32 ether);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#h-07-giantlp-with-a-transferhookprocessor-cant-be-burned-users-funds-will-be-stuck-in-the-giant-pool
    function testburn() public{
        address feesAndMevUserOne = accountOne; vm.deal(feesAndMevUserOne, 4 ether);
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.warp(block.timestamp + 46 minutes);
        giantFeesAndMevPool.withdrawETH(4 ether);
        vm.stopPrank();
    }

    function addNewLSM(address payable giantFeesAndMevPool, bytes memory blsPubKey, string memory ticker) public returns (address payable) {
        MockLiquidStakingManager man = deployNewLiquidStakingNetwork(
            factory,
            admin,
            false,
            ticker
        );

        // Set up users and ETH
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, 12 ether);
        address savETHUser = accountThree;
        vm.deal(savETHUser, 24 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKey, accountFour, man);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value : 24 ether}(24 ether);

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKey);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(man.savETHVault())),
            getUint256ArrayFromValues(24 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(address(man.savETHVault()).balance, 24 ether);

        assert(giantFeesAndMevPool.balance >= 4 ether);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        GiantMevAndFeesPool(giantFeesAndMevPool).batchDepositETHForStaking(
            getAddressArrayFromValues(address(man.stakingFundsVault())),
            getUint256ArrayFromValues(4 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKey, man);

        vm.roll(block.number + 500);

        return payable(man);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-19-when-users-transfer-giantlp-some-rewards-may-be-lost
    // https://code4rena.com/reports/2022-11-stakehouse/#h-12-sender-transferring-giantmevandfeespool-tokens-can-afterward-experience-pool-dos-and-orphaning-of-future-rewards
    function testTransferDOSUserOrphansFutureRewards() public {

        address feesAndMevUserOne = accountTwo;
        vm.deal(feesAndMevUserOne, 8 ether);
        address feesAndMevUserTwo = accountFour;

        // Deposit ETH into giant fees and mev
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value : 8 ether}(8 ether);
        vm.stopPrank();

        MockLiquidStakingManager manager1 = MockLiquidStakingManager(addNewLSM(payable(giantFeesAndMevPool), blsPubKeyOne, "ONE"));
        MockLiquidStakingManager manager2 = MockLiquidStakingManager(addNewLSM(payable(giantFeesAndMevPool), blsPubKeyTwo, "TWO"));

        bytes[][] memory blsPubKeyOneInput = new bytes[][](1);
        blsPubKeyOneInput[0] = getBytesArrayFromBytes(blsPubKeyOne);

        bytes[][] memory blsPubKeyTwoInput = new bytes[][](1);
        blsPubKeyTwoInput[0] = getBytesArrayFromBytes(blsPubKeyTwo);

        vm.warp(block.timestamp + 3 hours);

        // Add 2 eth rewards to manager1's staking funds vault.
        vm.deal(address(manager1.stakingFundsVault()), 2 ether);

        // Claim rewards into the giant pool and distribute them to user one.
        vm.startPrank(feesAndMevUserOne);
        blsPubKeyOneInput[0] = getBytesArrayFromBytes(blsPubKeyOne);
        giantFeesAndMevPool.claimRewards(
            feesAndMevUserOne,
            getAddressArrayFromValues(address(manager1.stakingFundsVault())),
            blsPubKeyOneInput);
        vm.stopPrank();

        // User one has received all the rewards and has no more previewed rewards.
        assertEq(feesAndMevUserOne.balance, 2 ether);
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 2 ether);
        assertEq((address(giantFeesAndMevPool)).balance, 0 ether);
        assertEq(
            giantFeesAndMevPool.previewAccumulatedETH(
                feesAndMevUserOne,
                new address[](0),
                new LPToken[][](0)),
            0);

        // Check the claimed[] value for user 1. It is correct.
        assertEq(
            giantFeesAndMevPool.claimed(feesAndMevUserOne, address(giantFeesAndMevPool.lpTokenETH())),
            2 ether);

        // User one transfers half their giant tokens to user 2.
        assertEq(giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(feesAndMevUserOne), 8 ether);
        assertEq(giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(feesAndMevUserTwo), 0 ether);
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.lpTokenETH().transfer(feesAndMevUserTwo, 4 ether);
        vm.stopPrank();
        assertEq(giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(feesAndMevUserOne), 4 ether);
        assertEq(giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(feesAndMevUserTwo), 4 ether);

        // After the tokens have been transferred to user 2, user 1's claimed[] remains
        // unchanged - and is higher than the accumulated payout per share for user 1's
        // current number of shares.
        // Update - this is now fixed
        assertEq(
            giantFeesAndMevPool.claimed(feesAndMevUserOne, address(giantFeesAndMevPool.lpTokenETH())),
            1 ether);

        assertEq(
            giantFeesAndMevPool.claimed(feesAndMevUserTwo, address(giantFeesAndMevPool.lpTokenETH())),
            1 ether);

        // With this incorrect value of claimed[] causing a subtraction underflow, user one
        // cannot preview accumulated eth or perform any action that attempts to claim their
        // rewards such as transferring their tokens.
        // Update: this has been fixed
        vm.startPrank(feesAndMevUserOne);
        //vm.expectRevert();
        uint256 preview = giantFeesAndMevPool.previewAccumulatedETH(
            feesAndMevUserOne,
            new address[](0),
            new LPToken[][](0));
        assertEq(preview, 0);

        console.log("the revert no longer expected now");
        GiantLP token = giantFeesAndMevPool.lpTokenETH();
        //vm.expectRevert();
        token.transfer(feesAndMevUserTwo, 1 ether);
        vm.stopPrank();

        assertEq(giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(feesAndMevUserOne), 3 ether);
        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne), 3 ether);
        assertEq(giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(feesAndMevUserTwo), 5 ether);
        assertEq(giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserTwo), 5 ether);

        // Add 1 eth rewards to manager2's staking funds vault.
        vm.deal(address(manager2.stakingFundsVault()), 2 ether);

        // User 2 claims rewards into the giant pool and obtains its 5/8 share.
        vm.startPrank(feesAndMevUserTwo);
        giantFeesAndMevPool.claimRewards(
            feesAndMevUserTwo,
            getAddressArrayFromValues(address(manager2.stakingFundsVault())),
            blsPubKeyTwoInput);
        vm.stopPrank();
        assertEq(feesAndMevUserTwo.balance, 1.25 ether);

        // At this point, user 1 ought to have accumulated 3/8 * 2 ether from the rewards,
        // however accumulated eth is listed as 0.
        // The reason is that when the giant pool tokens were transferred to
        // user two, the claimed[] value for user one was left unchanged.
        assertEq(
            giantFeesAndMevPool.previewAccumulatedETH(
                feesAndMevUserOne,
                new address[](0),
                new LPToken[][](0)),
            0.75 ether);

        // The pool has received 4 eth rewards and paid out 3, but no users
        // are listed as having accumulated the eth. It is orphaned.
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 4 ether);
        assertEq(giantFeesAndMevPool.totalClaimed(), 3.25 ether);

        assertEq(
            giantFeesAndMevPool.previewAccumulatedETH(
                feesAndMevUserTwo,
                new address[](0),
                new LPToken[][](0)),
            0);

        // update: nothing orphaned
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.claimExistingRewards(feesAndMevUserOne);
        vm.stopPrank();
        assertEq(giantFeesAndMevPool.totalRewardsReceived(), 4 ether);
        assertEq(giantFeesAndMevPool.totalClaimed(), 4 ether);
        assertEq(feesAndMevUserOne.balance, 2.75 ether);

        assertEq(
            giantFeesAndMevPool.previewAccumulatedETH(
                feesAndMevUserOne,
                new address[](0),
                new LPToken[][](0)),
            0 ether);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#h-15-user-loses-remaining-rewards-in-giantmevandfeespool-when-new-deposits-happen-because-_ondepositeth-set-claimed-to-max-without-transferring-user-remaining-rewards
    function testDepositETHDoesNotLoseRemainingRewards() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 16 ether}(16 ether);

        address stakingFundsVault = address(manager.stakingFundsVault());

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        // Push forward to activate knots in syndicates
        vm.roll(block.number + 1 + (8*32));

        sendEIP1559RewardsToSyndicateAtAddress(0.32 ether, manager.syndicate());

        vm.deal(address(manager.stakingFundsVault()), 0.11 ether);

        uint256 totalRewardsSentTo3Pools = 0.16 ether + 0.11 ether + 0 ether;

        vm.warp(block.timestamp + 2 days);

        LPToken lpBlsPubKeyOne = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        LPToken lpBlsPubKeyTwo = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyTwo);
        LPToken[][] memory allTokens = new LPToken[][](1);
        LPToken[] memory lpTokens = new LPToken[](2);
        lpTokens[0] = lpBlsPubKeyOne;
        lpTokens[1] = lpBlsPubKeyTwo;
        allTokens[0] = lpTokens;

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256 preview = giantFeesAndMevPool.previewAccumulatedETH(
            feesAndMevUserOne,
            getAddressArrayFromValues(stakingFundsVault),
            allTokens
        );

        uint256 balFeesUserOneBefore = feesAndMevUserOne.balance;
        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.fetchGiantPoolRewards(
            getAddressArrayFromValues(stakingFundsVault),
            blsKeysForVaults
        );
        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 16 ether}(16 ether);
        uint256 balFeesUserOneAfter = feesAndMevUserOne.balance;

        assertEq(giantFeesAndMevPool.totalRewardsReceived(), totalRewardsSentTo3Pools - 2);
        assertEq(balFeesUserOneAfter + 16 ether - balFeesUserOneBefore, totalRewardsSentTo3Pools - 2);
        assertEq(balFeesUserOneAfter + 16 ether - balFeesUserOneBefore, preview);

        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0.16 ether + 0.11 ether - 2);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#h-21-bringunusedethbackintogiantpool-in-giantmevandfeespool-can-be-used-to-steal-lptokens
    function testBringUnusedETHBackIntoGiantPoolWithInvalidStakingFundVault() public {
        stakingFundsVault = MockStakingFundsVault(payable(manager.stakingFundsVault()));
        address nodeRunner = accountOne; vm.deal(nodeRunner, 4 ether);
        address user = accountFour; vm.deal(user, 4 ether);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        vm.startPrank(user);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(getAddressArrayFromValues(address(stakingFundsVault)), getUint256ArrayFromValues(4 ether), blsKeysForVaults, stakeAmountsForVaults);

        vm.warp(block.timestamp + 60 minutes);
        LPToken lp = (stakingFundsVault.lpTokenForKnot(blsKeysForVaults[0][0]));
        LPToken [][] memory lpToken = new LPToken[][](1);
        LPToken[] memory temp  = new LPToken[](1);
        temp[0] = lp;
        lpToken[0] = temp;
        vm.stopPrank();

        // create new factory and get new stakingFundVault
        vm.startPrank(accountFive); // this will mean it gets dETH initial supply
        factory = createMockLSDNFactory();
        vm.stopPrank();
        manager = deployNewLiquidStakingNetwork(
            factory,
            admin,
            false,
            "LSDN"
        );
        MockStakingFundsVault newStakingFundsVault = MockStakingFundsVault(payable(manager.stakingFundsVault()));

        vm.startPrank(user);
        vm.expectRevert(bytes4(keccak256("InvalidStakingFundsVault()")));
        giantFeesAndMevPool.bringUnusedETHBackIntoGiantPool(getAddressArrayFromValues(address(newStakingFundsVault)), lpToken, stakeAmountsForVaults);

        assertEq(address(giantFeesAndMevPool).balance, 0);
        giantFeesAndMevPool.bringUnusedETHBackIntoGiantPool(getAddressArrayFromValues(address(stakingFundsVault)), lpToken, stakeAmountsForVaults);
        assertEq(address(giantFeesAndMevPool).balance, 4 ether);
        vm.stopPrank();
    }


    // https://code4rena.com/reports/2022-11-stakehouse/#h-20-possibly-reentrancy-attacks-in-_distributeethrewardstouserfortoken-function
    function testReentrancyOfTransferringTokensWhenWithdrawingETH() public {
        GiantPoolTransferExploiter exploiter = new GiantPoolTransferExploiter();

        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        exploiter.depositETH{value: 16 ether}(address(giantFeesAndMevPool));

        address stakingFundsVault = address(manager.stakingFundsVault());

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        // Push forward to activate knots in syndicates
        vm.roll(block.number + 1 + (8*32));

        sendEIP1559RewardsToSyndicateAtAddress(0.32 ether, manager.syndicate());

        vm.deal(address(manager.stakingFundsVault()), 0.11 ether);

        uint256 totalRewardsSentTo3Pools = 0.16 ether + 0.11 ether + 0 ether;

        vm.warp(block.timestamp + 2 days);

        LPToken lpBlsPubKeyOne = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        LPToken lpBlsPubKeyTwo = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyTwo);
        LPToken[][] memory allTokens = new LPToken[][](1);
        LPToken[] memory lpTokens = new LPToken[](2);
        lpTokens[0] = lpBlsPubKeyOne;
        lpTokens[1] = lpBlsPubKeyTwo;
        allTokens[0] = lpTokens;

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        vm.prank(feesAndMevUserOne);
        exploiter.depositETH{value: 16 ether}(address(giantFeesAndMevPool));

        uint256 balFeesUserOneBefore = feesAndMevUserOne.balance;
        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.fetchGiantPoolRewards(
            getAddressArrayFromValues(stakingFundsVault),
            blsKeysForVaults
        );

        vm.warp(block.timestamp + 1 hours);

        vm.expectRevert(bytes4(keccak256("ReentrancyCall()")));
        exploiter.withdrawETH(16 ether);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#h-20-possibly-reentrancy-attacks-in-_distributeethrewardstouserfortoken-function
    function testReentrancyOfSelfTransferringTokensWhenWithdrawingETH() public {
        GiantPoolSelfTransferExploiter exploiter = new GiantPoolSelfTransferExploiter();

        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        exploiter.depositETH{value: 16 ether}(address(giantFeesAndMevPool));

        address stakingFundsVault = address(manager.stakingFundsVault());

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(48 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(8 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        // Push forward to activate knots in syndicates
        vm.roll(block.number + 1 + (8*32));

        sendEIP1559RewardsToSyndicateAtAddress(0.32 ether, manager.syndicate());

        vm.deal(address(manager.stakingFundsVault()), 0.11 ether);

        uint256 totalRewardsSentTo3Pools = 0.16 ether + 0.11 ether + 0 ether;

        vm.warp(block.timestamp + 2 days);

        LPToken lpBlsPubKeyOne = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        LPToken lpBlsPubKeyTwo = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyTwo);
        LPToken[][] memory allTokens = new LPToken[][](1);
        LPToken[] memory lpTokens = new LPToken[](2);
        lpTokens[0] = lpBlsPubKeyOne;
        lpTokens[1] = lpBlsPubKeyTwo;
        allTokens[0] = lpTokens;

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo);

        vm.prank(feesAndMevUserOne);
        exploiter.depositETH{value: 16 ether}(address(giantFeesAndMevPool));

        uint256 balFeesUserOneBefore = feesAndMevUserOne.balance;
        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.fetchGiantPoolRewards(
            getAddressArrayFromValues(stakingFundsVault),
            blsKeysForVaults
        );

        vm.warp(block.timestamp + 1 hours);

        vm.expectRevert(bytes4(keccak256("FailedToTransfer()")));
        exploiter.withdrawETH(16 ether);
    }

    function testBreakGiantPoolQueue() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 200 ether);
        address savETHUserTwo = accountFive; vm.deal(savETHUserTwo, 200 ether);
        address savETHUserThree = accountSix; vm.deal(savETHUserThree, 200 ether);

        address savETHVaultAddress = address(manager.savETHVault());

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        // Fund the giant pool in waves
        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 48 ether}(48 ether);
        vm.stopPrank();

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);
        vm.stopPrank();

        // Check everything starts as expected for savETHUser
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 1), 1);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 1), 24 ether);

        // Check everything starts as expected for savETHUserTwo
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 0), 2);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 0), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 1), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 2), 24 ether);

        // Withdraw all of savETHUser's ETH
        vm.warp(block.timestamp + 1.1 days);
        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawETH(48 ether);
        vm.stopPrank();

        // Deposit 24 ETH for savETHUserThree
        vm.startPrank(savETHUserThree);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);
        vm.stopPrank();

        // Now savETHUserThree is before savETHUserTwo in the queue! It used the recycled batch
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserThree), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 0), 1);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 0), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 1), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 2), 0 ether);

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 0), 2);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 0), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 1), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 2), 24 ether);

        // Deposit 24 ETH for savETHUser
        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 1), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 2), 0 ether);

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 0), 2);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 0), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 1), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 2), 24 ether);

        // Now that recycled batches have been used, use new batches
        vm.startPrank(savETHUserThree);
        giantSavETHPool.depositETH{value: 25.6 ether}(25.6 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserThree), 3);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 0), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 1), 3);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserThree, 2), 4);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 0), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 1), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 2), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 3), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 4), 1.6 ether);
    }

    function testQueueJump() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 200 ether);
        address savETHUserTwo = accountFive; vm.deal(savETHUserTwo, 200 ether);
        address savETHUserThree = accountSix; vm.deal(savETHUserThree, 200 ether);

        // Fund the giant pool in waves
        vm.startPrank(savETHUser);
        giantSavETHPool.depositETH{value: 48 ether}(48 ether);
        vm.stopPrank();

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);
        vm.stopPrank();

        // Check everything starts as expected for savETHUser
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 2);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 0), 0);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUser, 1), 1);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 1), 24 ether);

        // Check everything starts as expected for savETHUserTwo
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 0), 2);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 0), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 1), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 2), 24 ether);

        // Check recycled deposit batches before
        assertEq(giantSavETHPool.getRecycledDepositBatchesSize(), 0);

        // Withdraw all of savETHUser's ETH
        vm.warp(block.timestamp + 1.1 days);
        vm.startPrank(savETHUser);
        giantSavETHPool.withdrawETH(48 ether);
        vm.stopPrank();

        // Check user has withdrawn
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUser), 0);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 0), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUser, 1), 0 ether);
        assertEq(giantSavETHPool.ethRecycledFromBatch(0), 24 ether);
        assertEq(giantSavETHPool.ethRecycledFromBatch(1), 24 ether);

        // Check everything again for savETHUserTwo
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 0), 2);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 0), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 1), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 2), 24 ether);

        // Check deposit count
        assertEq(giantSavETHPool.depositBatchCount(), 3);

        // Check recycled deposit batches
        assertEq(giantSavETHPool.getRecycledDepositBatchesSize(), 2);
        assertEq(giantSavETHPool.getRecycledDepositBatchIDAtIndex(0), 1);
        assertEq(giantSavETHPool.getRecycledDepositBatchIDAtIndex(1), 0);

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.jumpTheQueue(1, 2, savETHUserTwo);
        vm.stopPrank();

        // check recycled
        assertEq(giantSavETHPool.ethRecycledFromBatch(0), 24 ether);
        assertEq(giantSavETHPool.ethRecycledFromBatch(1), 0 ether);
        assertEq(giantSavETHPool.ethRecycledFromBatch(2), 24 ether);

        // Check everything again for savETHUserTwo
        assertEq(giantSavETHPool.getSetOfAssociatedDepositBatchesSize(savETHUserTwo), 1);
        assertEq(giantSavETHPool.getAssociatedDepositBatchIDAtIndex(savETHUserTwo, 0), 1);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 0), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 1), 24 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 2), 0 ether);
        assertEq(giantSavETHPool.idleETH(), 24 ether);

        // Check recycled deposit batches
        assertEq(giantSavETHPool.getRecycledDepositBatchesSize(), 2);
        assertEq(giantSavETHPool.getRecycledDepositBatchIDAtIndex(0), 0);
        assertEq(giantSavETHPool.getRecycledDepositBatchIDAtIndex(1), 2);

        // Check staked batch count
        assertEq(giantSavETHPool.stakedBatchCount(), 0);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        giantFeesAndMevPool.depositETH{value: 12 ether}(12 ether);

        bytes[][] memory blsKeysForVaults = new bytes[][](1);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);

        address savETHVaultAddress = address(manager.savETHVault());

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne);
        giantSavETHPool.batchDepositETHForStaking(getAddressArrayFromValues(address(savETHVaultAddress)),getUint256ArrayFromValues(24 ether) , blsKeysForVaults, stakeAmountsForVaults);

        // Check staked batch count
        assertEq(giantSavETHPool.stakedBatchCount(), 2);
        assertEq(giantSavETHPool.allocatedWithdrawalBatchForBlsPubKey(blsPubKeyOne), 1);
        assertEq(giantSavETHPool.getRecycledStakedBatchesSize(), 1);
        assertEq(giantSavETHPool.getRecycledStakedBatchIDAtIndex(0), 0);

        vm.startPrank(savETHUserThree);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);
        vm.stopPrank();
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserThree, 0), 24 ether);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyTwo);
        giantSavETHPool.batchDepositETHForStaking(getAddressArrayFromValues(address(savETHVaultAddress)),getUint256ArrayFromValues(24 ether) , blsKeysForVaults, stakeAmountsForVaults);

        assertEq(giantSavETHPool.stakedBatchCount(), 2);
        assertEq(giantSavETHPool.allocatedWithdrawalBatchForBlsPubKey(blsPubKeyOne), 1);
        assertEq(giantSavETHPool.allocatedWithdrawalBatchForBlsPubKey(blsPubKeyTwo), 0);
        assertEq(giantSavETHPool.getRecycledStakedBatchesSize(), 0);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-12-attacker-can-grift-syndicate-staking-by-staking-a-small-amount
    function testSyndicateStakeBeforeLiquidStakingManager() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 100 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyThree, accountFour);

        // Deposit ETH into giant savETH
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 72 ether}(72 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 64 ether}(64 ether);

        address stakingFundsVault = address(manager.stakingFundsVault());
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        // Deploy ETH from giant LP into savETH pool of LSDN instance
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo, blsPubKeyThree);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether, 24 ether, 24 ether);

        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.savETHVault())),
            getUint256ArrayFromValues(72 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        assertEq(address(manager.savETHVault()).balance, 72 ether);

        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether, 4 ether, 4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(stakingFundsVault),
            getUint256ArrayFromValues(12 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );

        // Ensure we can stake and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        vm.roll(block.number + 500);

        // withdraw LP token
        LPToken blsPubKeyOneLP = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.withdrawLP(blsPubKeyOneLP, 2 ether);
        vm.stopPrank();

        MockSlotRegistry slotRegistry = MockSlotRegistry(manager.slot());
        IERC20 sETHToken = IERC20(slotRegistry.stakeHouseShareTokens(manager.stakehouse()));
        assertEq(sETHToken.balanceOf(feesAndMevUserOne), 0 ether);
        assertEq(manager.stakingFundsVault().totalShares(), 8 ether);

        // get some sETH tokens by burning LP tokens
        vm.startPrank(feesAndMevUserOne);
        bytes[] memory blsKeysForVault = new bytes[](1);
        blsKeysForVault[0] = blsPubKeyOne;
        manager.stakingFundsVault().unstakeSyndicateSETHByBurningLP(
            blsKeysForVault,
            2 ether
        );
        vm.stopPrank();

        assertEq(sETHToken.balanceOf(feesAndMevUserOne), 6 ether);
        assertEq(manager.stakingFundsVault().totalShares(), 6 ether);

        // try to stake for third bls public key before liquid staking manager
        Syndicate syndicate = Syndicate(payable(manager.syndicate()));
        vm.startPrank(feesAndMevUserOne);
        sETHToken.approve(address(syndicate), 2 ether);
        vm.expectRevert(bytes4(keccak256("KnotIsNotRegisteredWithSyndicate()")));
        syndicate.stake(
            getBytesArrayFromBytes(blsPubKeyThree),
            getUint256ArrayFromValues(2 ether),
            feesAndMevUserOne
        );
        vm.stopPrank();

        // mint derivatives for third public key
        stakeAndMintDerivativesSingleKey(blsPubKeyThree);
        vm.roll(block.number + 500);

        // try to stake for third bls public key after liquid staking manager
        vm.startPrank(feesAndMevUserOne);
        vm.expectRevert(bytes4(keccak256("KnotIsFullyStakedWithFreeFloatingSlotTokens()")));
        syndicate.stake(
            getBytesArrayFromBytes(blsPubKeyThree),
            getUint256ArrayFromValues(2 ether),
            feesAndMevUserOne
        );
        vm.stopPrank();
    }
    
    function testGiantPoolMintRevertWhenCallerIsNotPool() public{
        address feesAndMevUserOne = accountOne;
        vm.deal(feesAndMevUserOne, 4 ether);

        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();

        GiantLP token = giantFeesAndMevPool.lpTokenETH();

        vm.expectRevert("Only pool");
        token.mint(feesAndMevUserOne, 1 ether);
    }
    
    function testGiantPoolBurnRevertWhenCallerIsNotPool() public{
        address feesAndMevUserOne = accountOne;
        vm.deal(feesAndMevUserOne, 4 ether);

        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();

        GiantLP token = giantFeesAndMevPool.lpTokenETH();

        vm.expectRevert("Only pool");
        token.burn(feesAndMevUserOne, 1 ether);
    }

    function testRevertWhenNoFullBatch() public {
        address nodeRunner = accountOne; vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 100 ether);
        address savETHUserOne = accountThree; vm.deal(savETHUserOne, 100 ether);
        address savETHUserTwo = accountFive; vm.deal(savETHUserTwo, 100 ether);

        address savETHVaultAddress = address(manager.savETHVault());

        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        vm.startPrank(savETHUserOne);
        giantSavETHPool.depositETH{value: 24 ether}(24 ether);
        vm.stopPrank();

        vm.startPrank(savETHUserTwo);
        giantSavETHPool.depositETH{value: 1 ether}(1 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 1.1 days);
        vm.startPrank(savETHUserOne);
        giantSavETHPool.withdrawETH(1 ether);
        vm.stopPrank();

        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();

        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserOne, 0), 23 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 0), 0 ether);

        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserOne, 1), 0 ether);
        assertEq(giantSavETHPool.totalETHFundedPerBatch(savETHUserTwo, 1), 1 ether);

        bytes[][] memory allKnots = new bytes[][](1);
        uint256[][] memory allAmounts = new uint256[][](1);
        allKnots[0] = getBytesArrayFromBytes(blsPubKeyOne);
        allAmounts[0] = getUint256ArrayFromValues(24 ether);

        vm.expectRevert(bytes4(keccak256("NoFullBatchAvailable()")));
        giantSavETHPool.batchDepositETHForStaking(
            getAddressArrayFromValues(savETHVaultAddress),
            getUint256ArrayFromValues(24 ether),
            allKnots,
            allAmounts
        );
    }
}