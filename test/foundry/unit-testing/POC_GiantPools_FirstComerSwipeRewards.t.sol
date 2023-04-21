pragma solidity ^0.8.13;

// SPDX-License-Identifier: MIT

import "forge-std/console.sol";
import { TestUtils } from "../../utils/TestUtils.sol";

import { GiantSavETHVaultPool } from "../../../contracts/liquid-staking/GiantSavETHVaultPool.sol";
import { GiantMevAndFeesPool } from "../../../contracts/liquid-staking/GiantMevAndFeesPool.sol";
import { LPToken } from "../../../contracts/liquid-staking/LPToken.sol";
import { MockSlotRegistry } from "../../../contracts/testing/stakehouse/MockSlotRegistry.sol";
import { MockSavETHVault } from "../../../contracts/testing/liquid-staking/MockSavETHVault.sol";
import { MockGiantSavETHVaultPool } from "../../../contracts/testing/liquid-staking/MockGiantSavETHVaultPool.sol";
import { IERC20 } from "@blockswaplab/stakehouse-solidity-api/contracts/IERC20.sol";
import { MockLiquidStakingManager } from "../../../contracts/testing/liquid-staking/MockLiquidStakingManager.sol";

// NoopContract is a contract that does nothing but that is necessary to pass some require statements.
contract NoopContract {
    function claimRewards(
        address _recipient,
        bytes[] calldata _blsPubKeys
    ) external {
        // does nothing, just to pass the for loop
    }
}

// Ensuring new depositors cannot steal historical deposits
// https://code4rena.com/reports/2022-11-stakehouse/#h-01-any-user-being-the-first-to-claim-rewards-from-giantmevandfeespool-can-unexepectedly-collect-them-all
contract GiantPoolWithdrawTests is TestUtils {
    MockGiantSavETHVaultPool public giantSavETHPool;
    GiantMevAndFeesPool public giantFeesAndMevPool;
    MockLiquidStakingManager public liquidStakingManager;
    NoopContract public noopContract;

    function setUp() public {
        noopContract = new NoopContract();

        vm.startPrank(accountFive); // this will mean it gets dETH initial supply
        factory = createMockLSDNFactory();
        vm.stopPrank();

        // Deploy 1 network
        manager = deployNewLiquidStakingNetwork(
            factory,
            admin,
            true,
            "LSDN"
        );

        liquidStakingManager = manager;

        savETHVault = MockSavETHVault(address(manager.savETHVault()));

        giantFeesAndMevPool = GiantMevAndFeesPool(payable(address(factory.giantFeesAndMev())));
        giantSavETHPool = MockGiantSavETHVaultPool(payable(address(factory.giantSavETHPool())));
    }

    /*  In this test case, the first comer depositing into the giant pool can collect all the rewards already collected
     *  whatever the amount even if it has not contributed to generate them. Is it expected?
     *  Severity: Critical
     *
     *  Remediation:
     *    The calculation of the state, i.e., claimed AND accumulatedETHPerLPShare must happen after the token transfer instead of before.
     *
     */
    function testFirstComerSwipeRewards() public {
        // Set up users and ETH
        address rewarder = accountThree; vm.deal(rewarder, 10 ether);
        address hacker = accountTwo; vm.deal(hacker, 1 ether);
        uint256 rewards = 5 ether;

        // rewards the pool
        vm.prank(rewarder); address(giantFeesAndMevPool).call{value: rewards}("");

        vm.startPrank(hacker);
        giantFeesAndMevPool.depositETH{value: 0.001 ether}(0.001 ether);

        // Hacker can claim the 5 ether even if he did not contribute to receive it with old code
        // New code does not allow claiming rewards
        assertRewardsClaimed(hacker, 0);
    }

    // claimRewards claims the rewards with crafted inputs to passe some require statements.
    function claimRewards(address _recipient) private {
        address[] memory _stakingFundsVaults = new address[](1);
        bytes[][] memory _blsPublicKeysForKnots = new bytes[][](1);
        _stakingFundsVaults[0] = address(noopContract);
        vm.expectRevert(bytes4(keccak256("NoDerivativesMinted()"))); // new code - original test reverted
        giantFeesAndMevPool.claimRewards(_recipient, _stakingFundsVaults, _blsPublicKeysForKnots);
    }

    // assertRewardsClaimed claim rewards and check if it changed the balance of the account.
    function assertRewardsClaimed(address _recipient, uint256 expectedReward) public {
        uint256 beforeBalance = address(_recipient).balance;
        claimRewards(_recipient);
        uint256 afterBalance = address(_recipient).balance;
        // as you can see, nothing as been withdrawn...
        assertEq(afterBalance - beforeBalance, expectedReward);
    }
}