pragma solidity ^0.8.13;

// SPDX-License-Identifier: MIT

import "forge-std/console.sol";

import {TestUtils} from "../../utils/TestUtils.sol";

import {MockAccountManager} from "../../../contracts/testing/stakehouse/MockAccountManager.sol";
import {GiantSavETHVaultPool} from "../../../contracts/liquid-staking/GiantSavETHVaultPool.sol";
import {GiantMevAndFeesPool} from "../../../contracts/liquid-staking/GiantMevAndFeesPool.sol";
import {Syndicate} from "../../../contracts/syndicate/Syndicate.sol";
import {LPToken} from "../../../contracts/liquid-staking/LPToken.sol";
import {MockSlotRegistry} from "../../../contracts/testing/stakehouse/MockSlotRegistry.sol";
import {MockSavETHVault} from "../../../contracts/testing/liquid-staking/MockSavETHVault.sol";
import {MockGiantSavETHVaultPool} from "../../../contracts/testing/liquid-staking/MockGiantSavETHVaultPool.sol";
import {StakingFundsVault} from "../../../contracts/liquid-staking/StakingFundsVault.sol";
import {IERC20} from "@blockswaplab/stakehouse-solidity-api/contracts/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockStakingFundsVault} from "../../../contracts/testing/liquid-staking/MockStakingFundsVault.sol";
import {GiantPoolExploit} from "../../../contracts/testing/liquid-staking/GiantPoolExploit.sol";
import {GiantPoolTransferExploiter} from "../../../contracts/testing/liquid-staking/GiantPoolTransferExploiter.sol";
import {GiantPoolSelfTransferExploiter} from "../../../contracts/testing/liquid-staking/GiantPoolSelfTransferExploiter.sol";
import {GiantLP} from "../../../contracts/liquid-staking/GiantLP.sol";
import {MockLiquidStakingManager} from "../../../contracts/testing/liquid-staking/MockLiquidStakingManager.sol";

contract MockLPToken {
    address public stakingFundsVault;

    function setStakingFundsVault(address _stakingFundsVault) external {
        stakingFundsVault = _stakingFundsVault;
    }

    function deployer() external view returns(address) {
        return stakingFundsVault;
    }

    function balanceOf(address) external view returns (uint256) {
        return 10000 ether;
    }
}

contract TakeFromGiantPools4 is TestUtils {
    MockGiantSavETHVaultPool public giantSavETHPool;
    GiantMevAndFeesPool public giantFeesAndMevPool;

    function setUp() public {
        vm.startPrank(accountFive); // this will mean it gets dETH initial supply
        factory = createMockLSDNFactory();
        vm.stopPrank();

        // Deploy 1 network
        manager = deployNewLiquidStakingNetwork(factory, admin, false, "LSDN");

        savETHVault = MockSavETHVault(address(manager.savETHVault()));

        giantFeesAndMevPool = GiantMevAndFeesPool(
            payable(address(factory.giantFeesAndMev()))
        );
        giantSavETHPool = MockGiantSavETHVaultPool(
            payable(address(factory.giantSavETHPool()))
        );

        assertEq(giantSavETHPool.batchSize(), 24 ether);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-06-withdrawing-wrong-lptoken-from-giantpool-leads-to-loss-of-funds
    function testWithdrawingInvalidLP() public {
        // Set up users and ETH
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, 100 ether);
        address feesAndMevUserOne = accountTwo;
        vm.deal(feesAndMevUserOne, 100 ether);
        address feesAndMevUserTwo = accountFive;
        vm.deal(feesAndMevUserTwo, 100 ether);
        address savETHUser = accountThree;
        vm.deal(savETHUser, 100 ether);

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
        blsKeysForVaults[0] = getBytesArrayFromBytes(
            blsPubKeyOne,
            blsPubKeyTwo
        );

        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(
            24 ether,
            24 ether
        );

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

        LPToken blsPubKeyOneLP = manager.stakingFundsVault().lpTokenForKnot(
            blsPubKeyOne
        );

        uint256 associatedWithdrawalBatchForKeyOne = giantFeesAndMevPool
            .allocatedWithdrawalBatchForBlsPubKey(blsPubKeyOne);
        uint256 totalETHFundedForBatchBefore = giantFeesAndMevPool
            .totalETHFundedPerBatch(
                feesAndMevUserOne,
                associatedWithdrawalBatchForKeyOne
            );
        assertEq(totalETHFundedForBatchBefore, 4 ether);

        assertEq(blsPubKeyOneLP.balanceOf(feesAndMevUserOne), 0 ether);
        assertEq(
            giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne),
            64 ether
        );

        // create fake lp token
        MockLPToken fakeLPToken = new MockLPToken();
        fakeLPToken.setStakingFundsVault(stakingFundsVault);

        // try to withdraw fake lp token
        vm.prank(feesAndMevUserOne);
        vm.expectRevert(bytes4(keccak256("NoDerivativesMinted()")));
        giantFeesAndMevPool.withdrawLP(LPToken(address(fakeLPToken)), 2 ether);

        vm.prank(feesAndMevUserOne);
        giantFeesAndMevPool.withdrawLP(blsPubKeyOneLP, 2 ether);

        assertEq(blsPubKeyOneLP.balanceOf(feesAndMevUserOne), 2 ether);
        assertEq(
            giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUserOne),
            62 ether
        );
    }
}
