pragma solidity ^0.8.13;

// SPDX-License-Identifier: MIT

import "forge-std/console.sol";
import { TestUtils } from "../../utils/TestUtils.sol";

import { GiantSavETHVaultPool } from "../../../contracts/liquid-staking/GiantSavETHVaultPool.sol";
import { GiantMevAndFeesPool } from "../../../contracts/liquid-staking/GiantMevAndFeesPool.sol";
import { LPToken } from "../../../contracts/liquid-staking/LPToken.sol";
import { GiantLP } from "../../../contracts/liquid-staking/GiantLP.sol";
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

// https://code4rena.com/reports/2022-11-stakehouse#h-02-rewards-of-giantmevandfeespool-can-be-locked-for-all-users
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

    /*  In this test case, a malicious user could cancel the rewards of all other users...
     *  Severity: Critical
     *
     *  lpTokenETH has some `before...` and `after...` hook functions that can be triggered with public methods of the ERC-20 token. Calling transfer on the token indirectly calls `_setClaimedToMax` which
     *  increases the claimed amount of the user that indirectly decreases the amount of rewards he is expected to receive...
     *
     *  NOTE: one can comment out the triggering line `giantFeesAndMevPool.lpTokenETH().transfer(payable(otherUser), 0)` to see how the contract should work without the malicious user interaction.
     *        Without it, otherUser should receive 2.5 ether, which is the equivalent of 5 ether of reward split in two between the two users who deposited.
     *
     */
    function testRewardsAreUnexpectedlyCanceledByMaliciousUser() public {
        // Set up users and ETH
        address rewarder = accountThree; vm.deal(rewarder, 10 ether);
        address hacker = address(accountTwo); vm.deal(hacker, 1 ether);
        address otherUser = accountOne; vm.deal(otherUser, 1 ether);
        uint256 rewards = 5 ether;

        // we contract needs to deposit the minimum amount in the pool
        vm.prank(otherUser); giantFeesAndMevPool.depositETH{value: 0.001 ether}(0.001 ether);
        vm.prank(hacker); giantFeesAndMevPool.depositETH{value: 0.001 ether}(0.001 ether);

        // Simulate deposit of ETH reward into giant pools
        vm.prank(rewarder); address(giantFeesAndMevPool).call{value: rewards}("");

        // And check that rewards are expected to be split in half between hacker and otherUser.
        assertPreviewAccumulatedETH(address(hacker), 0); // Rewards preview is zero because no derivatives minted
        assertPreviewAccumulatedETH(address(otherUser), 0); // Rewards preview is zero because no derivatives minted

        // At this point, the hack execute a transfer of 0 to the other user to indirectly call _setClaimedToMax
        // and make the claimed amount of otherUser raised which leads to decreasing his rewards.
        // NOTE: You can try to comment out this line if you want to see what should happen if everything went as expected without the malicious user interacting.
        //       In that case, otherUser should be rewarded 2.5 ether after the claim.
        vm.startPrank(hacker);
        GiantLP token = giantFeesAndMevPool.lpTokenETH();
        vm.expectRevert("Transfer Error"); // Revert because transfer of zero is illegal now
        token.transfer(payable(otherUser), 0);
        vm.stopPrank();

        // from now on, act as the impacted user
        vm.startPrank(otherUser);

        // The preview method shows that the expected rewards for otherUser has gone down to 0... but to make sure this is not only a bug
        // in the preview method, we'll try to claim the rewards right below.
        assertPreviewAccumulatedETH(address(otherUser), 0); // Rewards preview is zero because no derivatives minted
        assertPreviewAccumulatedETH(address(hacker), 0); // Rewards preview is zero because no derivatives minted

        assertRewardsClaimed(otherUser, 0 ether);
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

    function previewAccumulatedETH(address _user) public returns (uint256) {
        address[] memory _stakingFundsVaults = new address[](0);
        LPToken[][] memory _lpTokens = new LPToken[][](0);
        return giantFeesAndMevPool.previewAccumulatedETH(_user, _stakingFundsVaults, _lpTokens);
    }

    function assertPreviewAccumulatedETH(address _user, uint256 expectedAmount) public {
        uint256 am = previewAccumulatedETH(_user);
        assertEq(am, expectedAmount);
    }
}