pragma solidity ^0.8.13;

// SPDX-License-Identifier: MIT

import "forge-std/console.sol";

import {TestUtils} from "../../utils/TestUtils.sol";

import {GiantMevAndFeesPool} from "../../../contracts/liquid-staking/GiantMevAndFeesPool.sol";

contract TakeFromGiantPools3 is TestUtils {
    GiantMevAndFeesPool public giantFeesAndMevPool;
    uint256 public idleETHBefore;
    uint256 public withdrawalAmount;

    function setUp() public {
        vm.startPrank(accountFive); // this will mean it gets dETH initial supply
        factory = createMockLSDNFactory();
        vm.stopPrank();

        // Deploy 1 network
        manager = deployNewLiquidStakingNetwork(factory, admin, false, "LSDN");

        giantFeesAndMevPool = GiantMevAndFeesPool(
            payable(address(factory.giantFeesAndMev()))
        );
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#h-16-reentrancy-vulnerability-in-giantmevandfeespoolwithdraweth
    function testReentrancyVulnerabilityFromWithdrawETHOfGiantMevAndFeesPool()
        public
    {
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, 8 ether);
        vm.deal(address(this), 8 ether);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        giantFeesAndMevPool.depositETH{value: 8 ether}(8 ether);

        // try to withdraw half
        vm.warp(block.timestamp + 60 minutes);
        idleETHBefore = 8 ether;
        withdrawalAmount = 4 ether;
        assertEq(giantFeesAndMevPool.idleETH(), idleETHBefore);
        giantFeesAndMevPool.withdrawETH(withdrawalAmount);

        // try to withdraw another half (withdraw all)
        vm.warp(block.timestamp + 60 minutes);
        idleETHBefore = 4 ether;
        withdrawalAmount = 4 ether;
        assertEq(giantFeesAndMevPool.idleETH(), idleETHBefore);
        giantFeesAndMevPool.withdrawETH(4 ether);

        assertEq(giantFeesAndMevPool.idleETH(), 0);
    }

    fallback() external payable {
        // check idleETH in fallback function
        assertEq(giantFeesAndMevPool.idleETH(), idleETHBefore - withdrawalAmount);
    }
}
