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
        manager = deployNewLiquidStakingNetworkWithCommission(
            factory,
            30000, // 0.3 % haircut
            admin,
            false,
            "DREAM"
        );

        savETHVault = MockSavETHVault(address(manager.savETHVault()));

        giantFeesAndMevPool = GiantMevAndFeesPool(payable(address(factory.giantFeesAndMev())));
        giantSavETHPool = MockGiantSavETHVaultPool(payable(address(factory.giantSavETHPool())));

        assertEq(giantSavETHPool.batchSize(), 24 ether);

        // make 'admin' the 'DAO'
        vm.prank(address(factory));
        manager.updateDAOAddress(admin);
    }

    function testDreamScenario() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 120 ether);
        address nodeRunnerTwo = houseOne; vm.deal(accountSix, 120 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 120 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 120 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 120 ether);

        // Register BLS keys. 3 for one node runner, 1 for another
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyThree, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyFour, accountFour);

        // Deposit ETH into giant pools
        vm.prank(savETHUser);
        giantSavETHPool.depositETH{value: 120 ether}(120 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 20 ether}(20 ether);

        // Stake first bls key
        stakeWithEDC(blsPubKeyOne);

        // on paper, no knots are activated even though activateable
        Syndicate syn = Syndicate(payable(manager.syndicate()));
        assertEq(syn.numberOfActiveKnots(), 0);

        stakeWithEDC(blsPubKeyTwo);

        // Registration of second bls public key causes the activation of the first but no snapshotting
        assertEq(syn.numberOfActiveKnots(), 1);
        assertEq(syn.lastSeenETHPerCollateralizedSlotPerKnot(), 0);

        stakeWithEDC(blsPubKeyThree);
        assertEq(syn.numberOfActiveKnots(), 2);
        assertEq(syn.lastSeenETHPerCollateralizedSlotPerKnot(), 0);

        stakeWithEDC(blsPubKeyFour);
        assertEq(syn.numberOfActiveKnots(), 3);
        assertEq(syn.lastSeenETHPerCollateralizedSlotPerKnot(), 0);

        // Now, ETH arrives from a magical unlikely block from the last registered proposer. Better than that, it's a whopping 4.34 ETH
        // https://etherscan.io/tx/0xe0214323c7b5ba95e60b71b64660322a0daff14ebc9eef550c2e16d6cb96d867
        uint256 blockBounty = 4.34133979954556006 ether;
        vm.deal(address(syn), blockBounty);
        assertEq(syn.totalETHReceived(), blockBounty);

        bytes[] memory blsKeys = new bytes[](3);
        blsKeys[0] = blsPubKeyOne;
        blsKeys[1] = blsPubKeyTwo;
        blsKeys[2] = blsPubKeyThree;

        assertEq(syn.totalClaimed(), 0);

        uint256 nodeRunnerBalanceBefore = nodeRunner.balance;

        address smartWalletOfNodeRunner = manager.smartWalletOfNodeRunner(nodeRunner);
        uint256 previewNodeRunnerRewards = syn.batchPreviewUnclaimedETHAsCollateralizedSlotOwner(
            smartWalletOfNodeRunner,
            blsKeys
        );

        vm.prank(nodeRunner);
        manager.claimRewardsAsNodeRunner(
            nodeRunner,
            blsKeys
        );

        // node runner successfully claims ~1.6 ETH instead of 2.17 because it's been split 4 ways
        assertEq(nodeRunner.balance - nodeRunnerBalanceBefore, 1.623118417555096266 ether); // this includes 0.3% haircut
        assertEq(previewNodeRunnerRewards, syn.totalClaimed());
        assertEq(syn.numberOfActiveKnots(), 4);
        assertEq(syn.totalClaimed(), 1.628002424829585021 ether); // Tracking pre-haircut
        assertEq(syn.accumulatedETHPerCollateralizedSlotPerKnot(), (blockBounty / 2) / 4);

        vm.prank(nodeRunner);
        manager.claimRewardsAsNodeRunner(
            nodeRunner,
            getBytesArrayFromBytes(blsPubKeyFour)
        );
        uint256 claimedBefore = 2.170669899772780028 ether;
        assertEq(syn.totalClaimed(), claimedBefore);
        assertEq(nodeRunner.balance - nodeRunnerBalanceBefore, 2.164157890073461688 ether);

        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(
            blsPubKeyOne,
            blsPubKeyTwo,
            blsPubKeyThree,
            blsPubKeyFour
        );

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.claimRewards(
            feesAndMevUserOne,
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            blsKeysForVaults
        );
        assertEq(address(syn).balance, 4);

        // Now from this point onwards, ETH arriving into the contract will go to existing activated guys before going to new ones
        registerSingleBLSPubKey(nodeRunner, blsPubKeyFive, accountFour);
        stakeWithEDC(blsPubKeyFive);

        assertEq(syn.numberOfActiveKnots(), 4);

        vm.deal(address(syn), blockBounty);
        assertEq(address(syn).balance, blockBounty);

        nodeRunnerBalanceBefore = nodeRunner.balance;
        vm.startPrank(nodeRunner);
        manager.claimRewardsAsNodeRunner(
            nodeRunner,
            getBytesArrayFromBytes(
                blsPubKeyOne,
                blsPubKeyTwo,
                blsPubKeyThree,
                blsPubKeyFour
            )
        );
        vm.stopPrank();

        assertEq(address(syn).balance, 2.170669899772780032 ether); // for free floating

        assertEq(syn.numberOfActiveKnots(), 5);
        assertEq(nodeRunner.balance - nodeRunnerBalanceBefore, 2.164157890073461688 ether);
    }

    function stakeWithEDC(bytes memory _blsPubKey) internal {
        address stakingFundsVault = address(manager.stakingFundsVault());

        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(_blsPubKey);

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);

        // Stake with EDC one by one
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

        stakeAndMintDerivativesSingleKey(_blsPubKey);

        // Push forward to activate knot in syndicates
        vm.roll(block.number + 1 + (8*32));
    }
}