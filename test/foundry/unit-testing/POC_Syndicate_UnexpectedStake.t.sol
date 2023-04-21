// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import { console } from "forge-std/console.sol";

import { MockERC20 } from "../../../contracts/testing/MockERC20.sol";
import { SyndicateMock } from "../../../contracts/testing/syndicate/SyndicateMock.sol";

import { MockAccountManager } from "../../../contracts/testing/stakehouse/MockAccountManager.sol";
import { MockTransactionRouter } from "../../../contracts/testing/stakehouse/MockTransactionRouter.sol";
import { MockSlotRegistry } from "../../../contracts/testing/stakehouse/MockSlotRegistry.sol";
import { MockStakeHouseUniverse } from "../../../contracts/testing/stakehouse/MockStakeHouseUniverse.sol";

import { SyndicateFactoryMock } from "../../../contracts/testing/syndicate/SyndicateFactoryMock.sol";
import {
    KnotIsFullyStakedWithFreeFloatingSlotTokens,
    KnotIsAlreadyRegistered
} from "../../../contracts/syndicate/SyndicateErrors.sol";

import { TestUtils } from "../../utils/TestUtils.sol";

// [H-03] THEFT OF ETH OF FREE FLOATING SLOT HOLDERS
// https://code4rena.com/reports/2022-11-stakehouse/#h-03-theft-of-eth-of-free-floating-slot-holders
contract SyndicateTest is TestUtils {

    MockERC20 public sETH;

    SyndicateFactoryMock public syndicateFactory;

    SyndicateMock public syndicate;

    function blsPubKeyOneAsArray() public view returns (bytes[] memory) {
        bytes[] memory keys = new bytes[](1);
        keys[0] = blsPubKeyOne;
        return keys;
    }

    function sendEIP1559RewardsToSyndicate(uint256 eip1559Reward) public {
        (bool success, ) = address(syndicate).call{value: eip1559Reward}("");
        assertEq(success, true);
    }

    function setUp() public {
        // Deploy an sETH token for an arbitrary stakehouse
        sETH = new MockERC20("sETH", "sETH", accountOne);

        // Deploy the syndicate but no priority stakers are required
        address[] memory priorityStakers = new address[](0);

        // Create and inject mock stakehouse dependencies
        address accountMan = address(new MockAccountManager());
        address txRouter = address(new MockTransactionRouter());
        address uni = address(new MockStakeHouseUniverse());
        address slot = address(new MockSlotRegistry());
        syndicateFactory = new SyndicateFactoryMock(
            accountMan,
            txRouter,
            uni,
            slot
        );

        address payable _syndicate = payable(syndicateFactory.deployMockSyndicate(
                admin,
                0, // No priority staking block
                priorityStakers,
                blsPubKeyOneAsArray()
            ));

        syndicate = SyndicateMock(_syndicate);

        // Config mock stakehouse contracts
        MockSlotRegistry(syndicate.slotReg()).setShareTokenForHouse(houseOne, address(sETH));

        MockStakeHouseUniverse(syndicate.uni()).setAssociatedHouseForKnot(blsPubKeyOne, houseOne);
        MockStakeHouseUniverse(syndicate.uni()).setAssociatedHouseForKnot(blsPubKeyTwo, houseOne);
        MockStakeHouseUniverse(syndicate.uni()).setAssociatedHouseForKnot(blsPubKeyThree, houseOne);

        MockSlotRegistry(syndicate.slotReg()).setNumberOfCollateralisedSlotOwnersForKnot(blsPubKeyOne, 1);
        MockSlotRegistry(syndicate.slotReg()).setNumberOfCollateralisedSlotOwnersForKnot(blsPubKeyTwo, 1);
        MockSlotRegistry(syndicate.slotReg()).setNumberOfCollateralisedSlotOwnersForKnot(blsPubKeyThree, 1);

        MockSlotRegistry(syndicate.slotReg()).setCollateralisedOwnerAtIndex(blsPubKeyOne, 0, accountTwo);
        MockSlotRegistry(syndicate.slotReg()).setCollateralisedOwnerAtIndex(blsPubKeyTwo, 0, accountFour);
        MockSlotRegistry(syndicate.slotReg()).setCollateralisedOwnerAtIndex(blsPubKeyThree, 0, accountFive);

        MockSlotRegistry(syndicate.slotReg()).setUserCollateralisedSLOTBalanceForKnot(houseOne, accountTwo, blsPubKeyOne, 4 ether);
        MockSlotRegistry(syndicate.slotReg()).setUserCollateralisedSLOTBalanceForKnot(houseOne, accountFour, blsPubKeyTwo, 4 ether);
        MockSlotRegistry(syndicate.slotReg()).setUserCollateralisedSLOTBalanceForKnot(houseOne, accountFive, blsPubKeyThree, 4 ether);
    }

    function testUnexpectedClaimAsStaker() public {
        // Set up test - distribute sETH and register additional knot to syndicate
        vm.startPrank(admin);
        syndicate.registerKnotsToSyndicate(getBytesArrayFromBytes(blsPubKeyTwo));
        vm.stopPrank();

        // Push forward to activate
        vm.roll(block.number + 500);

        vm.startPrank(accountOne);
        sETH.transfer(accountThree, 500 ether);
        sETH.transfer(accountFive, 500 ether);
        vm.stopPrank();

        // for bls pub key one we will have 2 stakers staking 50% each
        uint256 stakingAmount = 4 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakingAmount;

        vm.startPrank(accountOne);
        sETH.approve(address(syndicate), stakingAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);
        vm.stopPrank();

        vm.startPrank(accountThree);
        sETH.approve(address(syndicate), stakingAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountThree);
        vm.stopPrank();

        // send some rewards
        uint256 eipRewards = 1 ether;
        sendEIP1559RewardsToSyndicate(eipRewards);

        // The attack starts at this stage
        vm.startPrank(accountThree);

        assertEq(accountThree.balance, 0);
        syndicate.claimAsStaker(accountThree, getBytesArrayFromBytes(blsPubKeyOne));

        // at this stage the rewards are expected but let see if we can grab some more...
        assertEq(accountThree.balance, eipRewards / 4);

        // By sending the minimum amount of gwei, I can diminish `sETHUserClaimForKnot` which is used in the calculation in `calculateUnclaimedFreeFloatingETHShare`
        // that eventually drives the staker claims.
        sETHAmounts[0] = 1 gwei;

        // we record the balance of sETH to check eventually that we have not lost anything the invested amount to perform the attack.
        uint256 sETHBalanceBefore = sETH.balanceOf(accountThree);
        sETH.approve(address(syndicate), sETHAmounts[0]);
        // and stake the minimum amount to manipulate `sETHUserClaimForKnot`.
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountThree);

        // claim again and check if we collected more. We do not any more
        syndicate.claimAsStaker(accountThree, getBytesArrayFromBytes(blsPubKeyOne));
        assertEq(accountThree.balance, eipRewards / 4);

        // now we can unstake the invested amount
        syndicate.unstake(accountThree, accountThree, blsPubKeyOneAsArray(), sETHAmounts);
        assertEq(accountThree.balance, eipRewards / 4);
        uint256 sETHBalanceAfter = sETH.balanceOf(accountThree);

        // let see if we can do some more.
        sETH.approve(address(syndicate), sETHAmounts[0]);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountThree);
        syndicate.claimAsStaker(accountThree, getBytesArrayFromBytes(blsPubKeyOne));
        assertEq(accountThree.balance, (eipRewards / 4));

        // check that the balance of sETH is as before the attack, we have not lost anything during the attack.
        assertEq(sETHBalanceAfter, sETHBalanceBefore);
    }
}