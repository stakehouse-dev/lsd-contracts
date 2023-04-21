pragma solidity ^0.8.13;

// SPDX-License-Identifier: MIT

import "forge-std/console.sol";

import {GiantPoolTests} from "./GiantPools.t.sol";

contract TakeFromGiantPools2 is GiantPoolTests {
    // https://code4rena.com/reports/2022-11-stakehouse/#h-08-function-withdraweth-from-giantmevandfeespool-can-steal-most-of-eth-because-of-idleeth-is-reduced-before-burning-token
    function testDWUpdateRate2() public {
        address feesAndMevUserOne = accountOne; vm.deal(feesAndMevUserOne, 4 ether);
        address feesAndMevUserTwo = accountTwo; vm.deal(feesAndMevUserTwo, 4 ether);
        // Deposit ETH into giant fees and mev
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();
        vm.startPrank(feesAndMevUserTwo);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.warp(block.timestamp + 46 minutes);
        giantFeesAndMevPool.withdrawETH(4 ether);
        vm.stopPrank();
        console.log("user one:", getBalance(feesAndMevUserOne));
        console.log("user two(attacker):", getBalance(feesAndMevUserTwo));
        console.log("giantFeesAndMevPool:", getBalance(address(giantFeesAndMevPool)));
        assertEq(getBalance(feesAndMevUserTwo), 4 ether);
        assertEq(getBalance(address(giantFeesAndMevPool)), 4 ether);
    }
    function getBalance(address addr) internal returns (uint){
        // just ETH
        return addr.balance;  // + giantFeesAndMevPool.lpTokenETH().balanceOf(addr);
    }
}