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
import { UpgradeableBeacon } from "../../../contracts/proxy/UpgradeableBeacon.sol";

import { TestUtils } from "../../utils/TestUtils.sol";

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
        uint256 balanceBefore = address(syndicate).balance;
        (bool success, ) = address(syndicate).call{value: eip1559Reward}("");
        assertEq(success, true);
        uint256 balanceAfter = address(syndicate).balance;
        assertEq(balanceAfter - balanceBefore, eip1559Reward);
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

        vm.prank(admin);
        syndicate.updatePriorityStakingBlock(1);

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

    function testSupply() public {
        assertEq(sETH.totalSupply(), 125_000 * 10 ** 18);
        assertEq(sETH.balanceOf(accountOne), 125_000 * 10 ** 18);
    }

    function testWhenKnotSlashedContractBucketAccruesETHThatCanBeClaimedFromTopUp() public {
        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        uint256 eip1559Reward = 0.165 ether;
        sendEIP1559RewardsToSyndicate(eip1559Reward);

        uint256 collateralizedIndex = 0;
        uint256[] memory collateralizedIndexes = new uint256[](1);
        collateralizedIndexes[0] = collateralizedIndex;

        assertEq(accountTwo.balance, 0);

        // slash the first collateralised owner
        MockSlotRegistry(syndicate.slotReg()).setUserCollateralisedSLOTBalanceForKnot(houseOne, accountTwo, blsPubKeyOne, 2 ether);
        MockSlotRegistry(syndicate.slotReg()).setSlashedAmountOfSLOTForKnot(blsPubKeyOne, 2 ether);

        // let them claim
        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(accountTwo, blsPubKeyOneAsArray());

        // instead of first collateralised owner (accountTwo) getting eip1559Reward / 2, they get eip1559Reward / 4 because they were slashed half of their slot
        assertEq(accountTwo.balance, eip1559Reward / 4);

        // contract has additional ETH that should have gone to collateralised owner
        assertEq(address(syndicate).balance, eip1559Reward / 2 + (eip1559Reward / 4));
        assertEq(syndicate.accruedEarningPerCollateralizedSlotOwnerOfKnot(blsPubKeyOne, address(syndicate)), (eip1559Reward / 4));

        // Let account four top up the slot and be the second collateralised SLOT owner
        MockSlotRegistry(syndicate.slotReg()).setUserCollateralisedSLOTBalanceForKnot(houseOne, accountFour, blsPubKeyOne, 2 ether);
        MockSlotRegistry(syndicate.slotReg()).setSlashedAmountOfSLOTForKnot(blsPubKeyOne, 0 ether);
        MockSlotRegistry(syndicate.slotReg()).setNumberOfCollateralisedSlotOwnersForKnot(blsPubKeyOne, 2);
        MockSlotRegistry(syndicate.slotReg()).setCollateralisedOwnerAtIndex(blsPubKeyOne, 1, accountFour);

        vm.prank(accountFour);
        syndicate.claimAsCollateralizedSLOTOwner(accountFour, blsPubKeyOneAsArray());
        assertEq(syndicate.accruedEarningPerCollateralizedSlotOwnerOfKnot(blsPubKeyOne, address(syndicate)), 0);
        assertEq(accountFour.balance, eip1559Reward / 4);
        assertEq(address(syndicate).balance, eip1559Reward / 2);
    }

    function testWhenKnotSlashedContractBucketAccruesETHThatCanBeClaimedFromTopUpByOriginalCollateralisedSlotOwner() public {
        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        uint256 eip1559Reward = 0.165 ether;
        sendEIP1559RewardsToSyndicate(eip1559Reward);

        uint256 collateralizedIndex = 0;
        uint256[] memory collateralizedIndexes = new uint256[](1);
        collateralizedIndexes[0] = collateralizedIndex;

        assertEq(accountTwo.balance, 0);

        // slash the first collateralised owner
        MockSlotRegistry(syndicate.slotReg()).setUserCollateralisedSLOTBalanceForKnot(houseOne, accountTwo, blsPubKeyOne, 2 ether);
        MockSlotRegistry(syndicate.slotReg()).setSlashedAmountOfSLOTForKnot(blsPubKeyOne, 2 ether);

        // let them claim
        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(accountTwo, blsPubKeyOneAsArray());

        // instead of first collateralised owner (accountTwo) getting eip1559Reward / 2, they get eip1559Reward / 4 because they were slashed half of their slot
        assertEq(accountTwo.balance, eip1559Reward / 4);

        // contract has additional ETH that should have gone to collateralised owner
        assertEq(address(syndicate).balance, eip1559Reward / 2 + (eip1559Reward / 4));
        assertEq(syndicate.accruedEarningPerCollateralizedSlotOwnerOfKnot(blsPubKeyOne, address(syndicate)), (eip1559Reward / 4));

        // Original owner tops up
        MockSlotRegistry(syndicate.slotReg()).setUserCollateralisedSLOTBalanceForKnot(houseOne, accountTwo, blsPubKeyOne, 4 ether);
        MockSlotRegistry(syndicate.slotReg()).setSlashedAmountOfSLOTForKnot(blsPubKeyOne, 0 ether);

        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(accountTwo, blsPubKeyOneAsArray());
        assertEq(syndicate.accruedEarningPerCollateralizedSlotOwnerOfKnot(blsPubKeyOne, address(syndicate)), 0);
        assertEq(accountTwo.balance, eip1559Reward / 2);
        assertEq(address(syndicate).balance, eip1559Reward / 2);
    }

    function testCanReportSlashingToSyndicate() public {
        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        // for bls pub key one we will have 2 stakers staking 50% each
        uint256 stakingAmount = 12 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakingAmount;

        vm.startPrank(accountOne);
        sETH.approve(address(syndicate), stakingAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);
        vm.stopPrank();
        assertEq(syndicate.totalFreeFloatingShares(), stakingAmount);

        assertEq(syndicate.numberOfActiveKnots(), 1);
        assertEq(syndicate.numberOfRegisteredKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 0);
        assertEq(syndicate.isNoLongerPartOfSyndicate(blsPubKeyOne), false);

        // Now simulate beacon chain slashing
        MockAccountManager accountManager = MockAccountManager(syndicateFactory.accountMan());
        accountManager.markSlashedIsTrue(blsPubKeyOne);

        syndicate.informSyndicateKnotsAreKickedFromBeaconChain(blsPubKeyOneAsArray());

        assertEq(syndicate.totalFreeFloatingShares(), 0);
        assertEq(syndicate.isNoLongerPartOfSyndicate(blsPubKeyOne), true);
    }

    function testAddPriorityStakers() public {
        vm.prank(admin);
        vm.expectRevert(bytes4(keccak256("EmptyArray()")));
        syndicate.addPriorityStakers(new address[](0));

        vm.prank(admin);
        vm.expectRevert(bytes4(keccak256("DuplicateArrayElements()")));
        syndicate.addPriorityStakers(getAddressArrayFromValues(accountOne, accountOne));

        assertEq(syndicate.isPriorityStaker(accountOne), false);
        assertEq(syndicate.isPriorityStaker(accountTwo), false);

        vm.prank(admin);
        syndicate.addPriorityStakers(getAddressArrayFromValues(accountOne, accountTwo));

        assertEq(syndicate.isPriorityStaker(accountOne), true);
        assertEq(syndicate.isPriorityStaker(accountTwo), true);
    }

    function testPriorityStakingEndBlock() public {
        assertEq(syndicate.priorityStakingEndBlock(), 1);

        uint256 priorityEndBlock = block.number + 500;
        vm.prank(admin);
        syndicate.updatePriorityStakingBlock(priorityEndBlock);

        assertEq(syndicate.priorityStakingEndBlock(), priorityEndBlock);

        vm.prank(admin);
        syndicate.addPriorityStakers(getAddressArrayFromValues(accountOne, accountTwo));

        uint256 stakingAmount = 12 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakingAmount;

        vm.startPrank(accountOne);
        sETH.transfer(accountThree, stakingAmount);
        vm.stopPrank();

        vm.startPrank(accountThree);
        sETH.approve(address(syndicate), stakingAmount);
        vm.expectRevert(bytes4(keccak256("NotPriorityStaker()")));
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountThree);
        vm.stopPrank();

        vm.roll(block.number + 500);

        vm.startPrank(accountOne);
        sETH.approve(address(syndicate), stakingAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);
        vm.stopPrank();

        assertEq(syndicate.totalFreeFloatingShares(), stakingAmount);
    }

    function testCanAdjustActivationDistance() public {
        vm.startPrank(accountOne);
        sETH.transfer(accountThree, 500 ether);
        sETH.transfer(accountFive, 500 ether);
        vm.stopPrank();

        uint256 stakingAmount = 12 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakingAmount;

        vm.startPrank(accountOne);
        sETH.approve(address(syndicate), stakingAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);
        vm.stopPrank();

        // Send rewards to vault but show nothing can be claimed
        uint256 eip1559Reward = 0.6547 ether;
        sendEIP1559RewardsToSyndicate(eip1559Reward);
        assertEq(syndicate.totalETHReceived(), eip1559Reward);
        assertEq(syndicate.previewActivateableProposers(), 0);
        assertEq(syndicate.previewTotalFreeFloatingSharesToActivate(), 0);
        assertEq(syndicate.batchPreviewUnclaimedETHAsFreeFloatingStaker(accountOne, blsPubKeyOneAsArray()), 0);
        assertEq(syndicate.batchPreviewUnclaimedETHAsFreeFloatingStaker(accountTwo, blsPubKeyOneAsArray()), 0);

        vm.prank(accountOne);
        vm.expectRevert(bytes4(keccak256("InactiveKnot()")));
        syndicate.claimAsStaker(
            accountOne,
            blsPubKeyOneAsArray()
        );

        vm.prank(accountTwo);
        vm.expectRevert(bytes4(keccak256("InactiveKnot()")));
        syndicate.claimAsCollateralizedSLOTOwner(
            accountTwo,
            blsPubKeyOneAsArray()
        );

        // Move blocks forward to activate first guy
        vm.roll(block.number + 500);

        assertEq(syndicate.totalETHReceived(), eip1559Reward);
        assertEq(syndicate.previewActivateableProposers(), 1);

        vm.prank(accountOne);
        syndicate.claimAsStaker(
            accountOne,
            blsPubKeyOneAsArray()
        );
        assertEq(accountOne.balance, eip1559Reward / 2 - 1);

        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(
            accountTwo,
            blsPubKeyOneAsArray()
        );
        assertEq(accountTwo.balance, eip1559Reward / 2);

        // Make activation distance longer
        vm.prank(admin);
        syndicate.updateActivationDistanceInBlocks(500);

        // Set up test - register additional knot to syndicate
        vm.prank(admin);
        syndicate.registerKnotsToSyndicate(getBytesArrayFromBytes(blsPubKeyTwo));

        assertEq(syndicate.previewActivateableProposers(), 0);

        // Move forward 200 blocks but show it cannot be activated
        vm.roll(block.number + 200);
        assertEq(syndicate.previewActivateableProposers(), 0);

        // After enough blocks activation comes
        vm.roll(block.number + 400);
        assertEq(syndicate.previewActivateableProposers(), 1);
    }

    function testCannotClaimFromSyndicateIfProposerHasNotYetActivated() public {
        // Check basic properties making sure knot is not ready for activation
        assertEq(syndicate.numberOfActiveKnots(), 0);
        assertEq(syndicate.numberOfRegisteredKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 1);
        assertGt(syndicate.activationBlock(blsPubKeyOne), block.number);

        vm.startPrank(accountOne);
        sETH.transfer(accountThree, 500 ether);
        sETH.transfer(accountFive, 500 ether);
        vm.stopPrank();

        uint256 stakingAmount = 12 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakingAmount;

        vm.startPrank(accountOne);
        sETH.approve(address(syndicate), stakingAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);
        vm.stopPrank();

        // Send rewards to vault but show nothing can be claimed
        uint256 eip1559Reward = 0.6547 ether;
        sendEIP1559RewardsToSyndicate(eip1559Reward);
        assertEq(syndicate.totalETHReceived(), eip1559Reward);
        assertEq(syndicate.previewActivateableProposers(), 0);
        assertEq(syndicate.previewTotalFreeFloatingSharesToActivate(), 0);
        assertEq(syndicate.previewUnclaimedETHAsFreeFloatingStaker(accountOne, blsPubKeyOne), 0);
        assertEq(syndicate.previewUnclaimedETHAsCollateralizedSlotOwner(accountTwo, blsPubKeyOne), 0);

        vm.prank(accountOne);
        vm.expectRevert(bytes4(keccak256("InactiveKnot()")));
        syndicate.claimAsStaker(
            accountOne,
            blsPubKeyOneAsArray()
        );

        vm.prank(accountTwo);
        vm.expectRevert(bytes4(keccak256("InactiveKnot()")));
        syndicate.claimAsCollateralizedSLOTOwner(
            accountTwo,
            blsPubKeyOneAsArray()
        );

        // Move blocks forward to activate
        vm.roll(block.number + 200);

        assertEq(syndicate.totalETHReceived(), eip1559Reward);
        assertEq(syndicate.previewActivateableProposers(), 1);
        assertEq(syndicate.previewTotalFreeFloatingSharesToActivate(), stakingAmount);
        assertEq(syndicate.batchPreviewUnclaimedETHAsFreeFloatingStaker(accountOne, blsPubKeyOneAsArray()), eip1559Reward / 2 - 1);
        assertEq(syndicate.previewUnclaimedETHAsCollateralizedSlotOwner(accountTwo, blsPubKeyOne), eip1559Reward / 2);

        vm.prank(accountOne);
        syndicate.claimAsStaker(
            accountOne,
            blsPubKeyOneAsArray()
        );
        assertEq(accountOne.balance, eip1559Reward / 2 - 1);

        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(
            accountTwo,
            blsPubKeyOneAsArray()
        );
        assertEq(accountTwo.balance, eip1559Reward / 2);

        sendEIP1559RewardsToSyndicate(eip1559Reward);

        // Set up test - register additional knot to syndicate
        vm.prank(admin);
        syndicate.registerKnotsToSyndicate(getBytesArrayFromBytes(blsPubKeyTwo));

        vm.startPrank(accountOne);
        sETH.approve(address(syndicate), stakingAmount);
        syndicate.stake(getBytesArrayFromBytes(blsPubKeyTwo), sETHAmounts, accountOne);
        vm.stopPrank();

        vm.prank(accountOne);
        syndicate.claimAsStaker(
            accountOne,
            blsPubKeyOneAsArray()
        );
        assertEq(accountOne.balance, eip1559Reward - 1);

        // Move forward to activate second key but make sure that those shares cannot claim historical rewards
        vm.roll(block.number + 200);

        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(
            accountTwo,
            blsPubKeyOneAsArray()
        );
        assertEq(accountTwo.balance, eip1559Reward);

        // Now rewards after this point are split correctly against all new participants
        sendEIP1559RewardsToSyndicate(eip1559Reward);

        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(
            accountTwo,
            blsPubKeyOneAsArray()
        );
        assertEq(accountTwo.balance, eip1559Reward + (eip1559Reward / 4));

        vm.prank(accountFour);
        syndicate.claimAsCollateralizedSLOTOwner(
            accountFour,
            getBytesArrayFromBytes(blsPubKeyTwo)
        );
        assertEq(accountFour.balance, eip1559Reward / 4);

        vm.prank(accountOne);
        syndicate.claimAsStaker(
            accountOne,
            getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo)
        );
        assertEq(accountOne.balance, eip1559Reward + (eip1559Reward / 2) - 1);
    }

    function testDeRegisterKnotAfterUnstake() public {
        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        vm.startPrank(accountOne);
        sETH.transfer(accountThree, 500 ether);
        sETH.transfer(accountFive, 500 ether);
        vm.stopPrank();

        // for bls pub key one we will have 2 stakers staking 50% each
        uint256 stakingAmount = 12 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakingAmount;

        vm.startPrank(accountOne);
        sETH.approve(address(syndicate), stakingAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);
        vm.stopPrank();

        assertEq(syndicate.totalFreeFloatingShares(), stakingAmount);

        vm.startPrank(accountOne);
        syndicate.unstake(accountOne, accountOne, blsPubKeyOneAsArray(), sETHAmounts);
        vm.stopPrank();

        assertEq(syndicate.totalFreeFloatingShares(), 0);

        vm.prank(admin);
        syndicate.deRegisterKnots(blsPubKeyOneAsArray());

        assertEq(syndicate.totalFreeFloatingShares(), 0);
    }

    function testDeRegisterKnotBeforeUnstake() public {
        // push forward for activation
        vm.roll(block.number + 1 + (6*32));

        vm.startPrank(accountOne);
        sETH.transfer(accountThree, 500 ether);
        sETH.transfer(accountFive, 500 ether);
        vm.stopPrank();

        // for bls pub key one we will have 2 stakers staking 50% each
        uint256 stakingAmount = 12 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakingAmount;

        assertEq(syndicate.numberOfActiveKnots(), 0);
        assertEq(syndicate.numberOfRegisteredKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 1);

        syndicate.activateProposers();

        assertEq(syndicate.numberOfActiveKnots(), 1);
        assertEq(syndicate.numberOfRegisteredKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 0);

        vm.startPrank(accountOne);
        sETH.approve(address(syndicate), stakingAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);
        vm.stopPrank();

        assertEq(syndicate.numberOfActiveKnots(), 1);
        assertEq(syndicate.numberOfRegisteredKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 0);

        assertEq(syndicate.totalFreeFloatingShares(), stakingAmount);

        vm.prank(admin);
        syndicate.deRegisterKnots(blsPubKeyOneAsArray());

        assertEq(syndicate.numberOfActiveKnots(), 0);
        assertEq(syndicate.numberOfRegisteredKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 0);

        assertEq(syndicate.totalFreeFloatingShares(), 0);

        vm.startPrank(accountOne);
        syndicate.unstake(accountOne, accountOne, blsPubKeyOneAsArray(), sETHAmounts);
        vm.stopPrank();

        assertEq(syndicate.totalFreeFloatingShares(), 0);
    }

    // https://github.com/koolexcrypto/2023-01-blockswap-fv-private/issues/1
    function testDeRegisterInactiveKnot() public {
        // push forward for activation
        vm.roll(block.number + 1 + (6*32));

        vm.startPrank(accountOne);
        sETH.transfer(accountThree, 500 ether);
        sETH.transfer(accountFive, 500 ether);
        vm.stopPrank();

        // for bls pub key one we will have 2 stakers staking 50% each
        uint256 stakingAmount = 12 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakingAmount;

        assertEq(syndicate.numberOfActiveKnots(), 0);
        assertEq(syndicate.numberOfRegisteredKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 1);

        syndicate.activateProposers();

        assertEq(syndicate.numberOfActiveKnots(), 1);
        assertEq(syndicate.numberOfRegisteredKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 0);

        vm.startPrank(accountOne);
        sETH.approve(address(syndicate), stakingAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);
        vm.stopPrank();

        assertEq(syndicate.numberOfActiveKnots(), 1);
        assertEq(syndicate.numberOfRegisteredKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 0);

        assertEq(syndicate.totalFreeFloatingShares(), stakingAmount);

        // Make knot inactive with stakehouse
        MockStakeHouseUniverse(syndicateFactory.uni()).setIsActive(blsPubKeyOne, false);
        (,,,,,bool isActive) = MockStakeHouseUniverse(syndicateFactory.uni()).stakeHouseKnotInfo(blsPubKeyOne);
        assertEq(isActive, false);

        vm.prank(admin);
        syndicate.deRegisterKnots(blsPubKeyOneAsArray());

        assertEq(syndicate.totalFreeFloatingShares(), 0);
        assertEq(syndicate.isNoLongerPartOfSyndicate(blsPubKeyOne), true);
    }

    function testThreeKnotsMultipleStakers() public {
        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        assertEq(syndicate.numberOfActiveKnots(), 0);
        assertEq(syndicate.numberOfRegisteredKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 1);
        assertLt(syndicate.activationBlock(blsPubKeyOne), block.number);

        // Set up test - distribute sETH and register additional knot to syndicate
        vm.prank(admin);
        syndicate.registerKnotsToSyndicate(getBytesArrayFromBytes(blsPubKeyTwo));

        // Number of active knots increases but total number of proposers to activate stays at 1 because previous knot was activated
        assertEq(syndicate.numberOfActiveKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 1);

        // push forward for activation of knot 2
        vm.roll(block.number + 1 + (5*32));

        vm.startPrank(accountOne);
        sETH.transfer(accountThree, 500 ether);
        sETH.transfer(accountFive, 500 ether);
        vm.stopPrank();

        // for bls pub key one we will have 2 stakers staking 50% each
        uint256 stakingAmount = 6 ether;
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

        sETHAmounts[0] = 12 ether;
        vm.startPrank(accountFive);
        sETH.approve(address(syndicate), sETHAmounts[0]);
        syndicate.stake(getBytesArrayFromBytes(blsPubKeyTwo), sETHAmounts, accountFive);
        vm.stopPrank();

        // send some rewards
        uint256 eipRewards = 0.0943 ether;
        sendEIP1559RewardsToSyndicate(eipRewards);

        vm.prank(accountOne);
        vm.expectRevert(KnotIsFullyStakedWithFreeFloatingSlotTokens.selector);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);

        // Check syndicate state
        assertEq(syndicate.totalETHReceived(), eipRewards);

        // claim
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 0;

        assertEq(accountTwo.balance, 0);
        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(accountTwo, getBytesArrayFromBytes(blsPubKeyOne));
        assertEq(accountTwo.balance, eipRewards / 4);

        assertEq(accountFour.balance, 0);
        vm.prank(accountFour);
        syndicate.claimAsCollateralizedSLOTOwner(accountFour, getBytesArrayFromBytes(blsPubKeyTwo));
        assertEq(accountFour.balance, eipRewards / 4);

        assertEq(accountFive.balance, 0);
        vm.prank(accountFive);
        syndicate.claimAsStaker(accountFive, getBytesArrayFromBytes(blsPubKeyTwo));
        assertEq(accountFive.balance, (eipRewards / 4) - 1);

        assertEq(accountOne.balance, 0);
        vm.prank(accountOne);
        syndicate.claimAsStaker(accountOne, getBytesArrayFromBytes(blsPubKeyOne));
        assertEq(accountOne.balance, (eipRewards / 8) - 1);

        assertEq(accountThree.balance, 0);
        vm.prank(accountThree);
        syndicate.claimAsStaker(accountThree, getBytesArrayFromBytes(blsPubKeyOne));
        assertEq(accountThree.balance, (eipRewards / 8) - 1);

        // Check syndicate state
        assertEq(syndicate.totalETHReceived(), eipRewards);
        assertEq(address(syndicate).balance, 3); // Dust is left behind due to Solidity calc issues

        vm.prank(admin);
        vm.expectRevert(KnotIsAlreadyRegistered.selector);
        syndicate.registerKnotsToSyndicate(getBytesArrayFromBytes(blsPubKeyOne));

        vm.prank(admin);
        syndicate.registerKnotsToSyndicate(getBytesArrayFromBytes(blsPubKeyThree));
    }

    function testOneKnotWithMultipleFreeFloatingStakers() public {
        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        // account two is the collateralized owner for bls pub key one. Everyone else can be free floating staker but they need sETH
        vm.startPrank(accountOne);
        sETH.transfer(accountThree, 500 ether);
        sETH.transfer(accountFour, 500 ether);
        vm.stopPrank();

        // Stake free floating slot
        uint256 stakeAmount = 4 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakeAmount;

        vm.startPrank(accountOne);
        sETH.approve(address(syndicate), stakeAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);
        vm.stopPrank();

        vm.startPrank(accountThree);
        sETH.approve(address(syndicate), stakeAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountThree);
        vm.stopPrank();

        vm.startPrank(accountFour);
        sETH.approve(address(syndicate), stakeAmount);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountFour);
        vm.stopPrank();

        // send some eip rewards to syndicate
        uint256 eipRewards = 0.54 ether;
        sendEIP1559RewardsToSyndicate(eipRewards);

        // Claim as free floating
        assertEq(accountOne.balance, 0);
        vm.prank(accountOne);
        syndicate.claimAsStaker(accountOne, blsPubKeyOneAsArray());
        assertEq(accountOne.balance, 0.09 ether);

        assertEq(accountThree.balance, 0);
        vm.prank(accountThree);
        syndicate.claimAsStaker(accountThree, blsPubKeyOneAsArray());
        assertEq(accountThree.balance, 0.09 ether);

        assertEq(accountFour.balance, 0);
        vm.prank(accountFour);
        syndicate.claimAsStaker(accountFour, blsPubKeyOneAsArray());
        assertEq(accountFour.balance, 0.09 ether);

        // Now as the collateralized SLOT owner has not claimed, 0.27 out of 0.54 should still be with syndicate
        assertEq(address(syndicate).balance, 0.27 ether);

        // Collateralized owner claims
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 0;
        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(accountTwo, blsPubKeyOneAsArray());
        assertEq(address(syndicate).balance, 0);
        assertEq(accountTwo.balance, 0.27 ether);

        // nothing should happen by claiming again
        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(accountTwo, blsPubKeyOneAsArray());
        assertEq(address(syndicate).balance, 0);
        assertEq(accountTwo.balance, 0.27 ether);

        assertEq(accountOne.balance, 0.09 ether);
        vm.prank(accountOne);
        syndicate.claimAsStaker(accountOne, blsPubKeyOneAsArray());
        assertEq(accountOne.balance, 0.09 ether);

        assertEq(accountThree.balance, 0.09 ether);
        vm.prank(accountThree);
        syndicate.claimAsStaker(accountThree, blsPubKeyOneAsArray());
        assertEq(accountThree.balance, 0.09 ether);

        assertEq(accountFour.balance, 0.09 ether);
        vm.prank(accountFour);
        syndicate.claimAsStaker(accountFour, blsPubKeyOneAsArray());
        assertEq(accountFour.balance, 0.09 ether);
    }

    function testExpansionOfKnotSet() public {
        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        // Testing scenario where:
        // - syn is deployed
        // - it accrues ETH
        // - no one claims
        // - new knots are added to syn
        // - old ones claim successfully
        // - new ones have nothing to claim
        // - when ETH comes in again, then the full set can claim that additional ETH

        // Start test
        // Check that one knot is to be activated
        assertEq(syndicate.numberOfActiveKnots(), 0);
        assertEq(syndicate.totalProposersToActivate(), 1);
        assertEq(syndicate.isKnotRegistered(blsPubKeyOne), true);

        // Distribute some rewards, stake, no one claims and check claim amounts
        uint256 eip1559Reward = 0.165 ether;
        sendEIP1559RewardsToSyndicate(eip1559Reward);

        uint256 collateralizedIndex = 0;
        uint256[] memory collateralizedIndexes = new uint256[](1);
        collateralizedIndexes[0] = collateralizedIndex;

        uint256 stakeAmount = 12 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakeAmount;

        vm.startPrank(accountOne);
        sETH.approve(address(syndicate), 12 ether);
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);
        vm.stopPrank();

        // Without claiming ensure free floating staker and collateralized owners can claim correct amount of rewards
        assertEq(
            syndicate.previewUnclaimedETHAsFreeFloatingStaker(accountOne, blsPubKeyOne),
            eip1559Reward / 2
        );

        assertEq(
            syndicate.batchPreviewUnclaimedETHAsCollateralizedSlotOwner(accountTwo, blsPubKeyOneAsArray()),
            eip1559Reward / 2
        );

        assertEq(syndicate.totalETHReceived(), eip1559Reward);

        // Expand KNOT set
        vm.prank(admin);
        syndicate.registerKnotsToSyndicate(getBytesArrayFromBytes(blsPubKeyTwo));

        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        assertEq(syndicate.numberOfActiveKnots(), 1);
        assertEq(syndicate.totalProposersToActivate(), 1);
        assertEq(syndicate.isKnotRegistered(blsPubKeyOne), true);
        assertEq(syndicate.isKnotRegistered(blsPubKeyTwo), true);

        // Check claim amount for previous stakers is still correct
        assertEq(syndicate.totalClaimed(), 0);
        assertEq(address(syndicate).balance, eip1559Reward);
        assertEq(syndicate.totalETHReceived(), eip1559Reward);
        assertEq(syndicate.accumulatedETHPerFreeFloatingShare(), 6875000000000000000000);
        assertEq(syndicate.calculateNewAccumulatedETHPerFreeFloatingShare(), 0);
        assertEq(syndicate.sETHTotalStakeForKnot(blsPubKeyOne), stakeAmount);
        assertEq(syndicate.sETHStakedBalanceForKnot(blsPubKeyOne, accountOne), stakeAmount);
        assertEq(
            syndicate.previewUnclaimedETHAsFreeFloatingStaker(accountOne, blsPubKeyOne),
            eip1559Reward / 2
        );

        assertEq(
            syndicate.previewUnclaimedETHAsCollateralizedSlotOwner(accountTwo, blsPubKeyOne),
            eip1559Reward / 2
        );

        vm.prank(accountOne);
        syndicate.claimAsStaker(accountOne, blsPubKeyOneAsArray());
        assertEq(accountOne.balance, eip1559Reward / 2);
        assertEq(syndicate.previewUnclaimedETHAsFreeFloatingStaker(accountOne, blsPubKeyOne), 0);
        assertEq(
            syndicate.previewUnclaimedETHAsCollateralizedSlotOwner(accountTwo, blsPubKeyOne),
            eip1559Reward / 2
        );

        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(accountTwo, blsPubKeyOneAsArray());
        assertEq(syndicate.previewUnclaimedETHAsCollateralizedSlotOwner(accountTwo, blsPubKeyOne), 0);
        assertEq(accountTwo.balance, eip1559Reward / 2);
        assertEq(address(syndicate).balance, 0);

        // introduce a third staker for free floating
        vm.prank(accountOne);
        sETH.transfer(accountThree, stakeAmount);

        vm.startPrank(accountThree);
        sETHAmounts[0] = stakeAmount;
        sETH.approve(address(syndicate), stakeAmount);
        syndicate.stake(
            getBytesArrayFromBytes(blsPubKeyTwo),
            sETHAmounts,
            accountThree
        );
        vm.stopPrank();

        // send some more rewards again
        sendEIP1559RewardsToSyndicate(eip1559Reward);

        assertEq(syndicate.totalClaimed(), eip1559Reward);
        assertEq(syndicate.totalFreeFloatingShares(), stakeAmount * 2);
        assertEq(sETH.balanceOf(address(syndicate)), stakeAmount * 2);

        uint256 ethPerKnot = eip1559Reward / 2;
        uint256 ethPerFreeFloatingOrCollateralized = ethPerKnot;
        uint256 unclaimedFreeFloatingAccountOne = syndicate.previewUnclaimedETHAsFreeFloatingStaker(accountOne, blsPubKeyOne);
        uint256 unclaimedFreeFloatingAccountThree = syndicate.previewUnclaimedETHAsFreeFloatingStaker(accountThree, blsPubKeyTwo);
        assertEq(
            unclaimedFreeFloatingAccountOne + unclaimedFreeFloatingAccountThree,
            ethPerFreeFloatingOrCollateralized
        );

        uint256 accountOneBalBeforeClaim = accountOne.balance;
        vm.prank(accountOne);
        syndicate.claimAsStaker(accountOne, blsPubKeyOneAsArray());
        assertEq(accountOne.balance - accountOneBalBeforeClaim, unclaimedFreeFloatingAccountOne);

        uint256 accountThreeBalBeforeClaim = accountThree.balance;
        vm.prank(accountThree);
        syndicate.claimAsStaker(accountThree, getBytesArrayFromBytes(blsPubKeyTwo));
        assertEq(accountThree.balance - accountThreeBalBeforeClaim, unclaimedFreeFloatingAccountThree);

        assertEq(syndicate.getUnprocessedETHForAllCollateralizedSlot(), 0);
        assertEq(syndicate.getUnprocessedETHForAllFreeFloatingSlot(), 0);

        uint256 unclaimedCollateralizedAccountTwo = syndicate.previewUnclaimedETHAsCollateralizedSlotOwner(accountTwo, blsPubKeyOne);
        uint256 unclaimedCollateralizedAccountFour = syndicate.previewUnclaimedETHAsCollateralizedSlotOwner(accountFour, blsPubKeyTwo);
        assertEq(
            unclaimedCollateralizedAccountTwo + unclaimedCollateralizedAccountFour,
            ethPerFreeFloatingOrCollateralized
        );

        uint256 accountTwoBalBefore = accountTwo.balance;
        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(accountTwo, blsPubKeyOneAsArray());
        assertEq(accountTwo.balance - accountTwoBalBefore, unclaimedCollateralizedAccountTwo);

        vm.prank(accountFour);
        syndicate.claimAsCollateralizedSLOTOwner(accountFour, getBytesArrayFromBytes(blsPubKeyTwo));
        assertEq(accountFour.balance, unclaimedCollateralizedAccountFour);

        assertEq(address(syndicate).balance, 0);
    }

    function testClaimAsCollateralizedSlotOwner() public {
        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        uint256 eip1559Reward = 0.165 ether;
        sendEIP1559RewardsToSyndicate(eip1559Reward);

        uint256 collateralizedIndex = 0;
        uint256[] memory collateralizedIndexes = new uint256[](1);
        collateralizedIndexes[0] = collateralizedIndex;

        assertEq(accountTwo.balance, 0);

        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(accountTwo, blsPubKeyOneAsArray());

        assertEq(accountTwo.balance, eip1559Reward / 2);
        assertEq(address(syndicate).balance, eip1559Reward / 2);
    }

    function testStakeFreeFloatingReceiveETHAndThenClaim() public {
        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        uint256 stakeAmount = 12 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakeAmount;

        // Assume account one as message sender
        vm.startPrank(accountOne);

        // issue allowance to stake
        sETH.approve(address(syndicate), sETHAmounts[0]);

        // stake
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);

        // End impersonation
        vm.stopPrank();

        assertEq(sETH.balanceOf(address(syndicate)), stakeAmount);
        assertEq(syndicate.totalFreeFloatingShares(), stakeAmount);
        assertEq(syndicate.sETHTotalStakeForKnot(blsPubKeyOne), stakeAmount);
        assertEq(syndicate.sETHStakedBalanceForKnot(blsPubKeyOne, accountOne), stakeAmount);
        assertEq(syndicate.sETHUserClaimForKnot(blsPubKeyOne, accountOne), 0);
        assertEq(syndicate.accumulatedETHPerFreeFloatingShare(), 0);
        assertEq(syndicate.lastSeenETHPerFreeFloating(), 0);
        //assertEq(syndicate.lastSeenETHPerCollateralizedSlot(), 0);

        uint256 eip1559Reward = 0.04 ether;
        sendEIP1559RewardsToSyndicate(eip1559Reward);

        // Preview amount of unclaimed ETH before updating contract state
        assertEq(
            syndicate.previewUnclaimedETHAsFreeFloatingStaker(accountOne, blsPubKeyOne),
            0.02 ether - 1
        );

        syndicate.updateAccruedETHPerShares();

        assertEq(syndicate.lastSeenETHPerFreeFloating(), eip1559Reward / 2);
        //assertEq(syndicate.lastSeenETHPerCollateralizedSlot(), eip1559Reward / 2);
        assertEq(syndicate.totalETHReceived(), eip1559Reward);
        assertEq(syndicate.calculateETHForFreeFloatingOrCollateralizedHolders(), eip1559Reward / 2);
        assertEq(syndicate.accumulatedETHPerFreeFloatingShare(), ((eip1559Reward / 2) * 1e24) / stakeAmount);
        assertEq(syndicate.sETHUserClaimForKnot(blsPubKeyOne, accountOne), 0);

        assertEq(address(syndicate).balance, 0.04 ether);

        // Preview amount of unclaimed ETH post updating contract state
        assertEq(
            syndicate.previewUnclaimedETHAsFreeFloatingStaker(accountOne, blsPubKeyOne),
                0.02 ether - 1
        );

        vm.prank(accountOne);
        syndicate.claimAsStaker(accountOne, blsPubKeyOneAsArray());

        // Contract balance should have reduced
        // Solidity precision loss of 1 wei
        assertEq(address(syndicate).balance, 0.02 ether + 1);

        // Unclaimed ETH amount should now be zero
        assertEq(
            syndicate.previewUnclaimedETHAsFreeFloatingStaker(accountOne, blsPubKeyOne),
            0
        );

        // user ETH balance should now be 0.02 ether minus 1 due to precision loss
        assertEq(accountOne.balance, 0.02 ether - 1);

        // try to claim again and fail
        vm.prank(accountOne);
        syndicate.claimAsStaker(accountOne, blsPubKeyOneAsArray());
        assertEq(address(syndicate).balance, 0.02 ether + 1);

        vm.prank(accountOne);
        syndicate.unstake(accountOne, accountOne, blsPubKeyOneAsArray(), sETHAmounts);
        assertEq(address(syndicate).balance, 0.02 ether + 1);

        vm.startPrank(accountOne);

        // issue allowance to stake
        sETH.approve(address(syndicate), sETHAmounts[0]);

        uint256 expectedDebt = (syndicate.accumulatedETHPerFreeFloatingShare() * stakeAmount) / syndicate.PRECISION();

        // stake
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);

        // Check user was assigned the correct debt on re-staking so they cannot double claim
        assertEq(syndicate.sETHUserClaimForKnot(blsPubKeyOne, accountOne), expectedDebt);

        // try to claim again and fail
        syndicate.claimAsStaker(accountOne, blsPubKeyOneAsArray());

        // End impersonation
        vm.stopPrank();

        assertEq(address(syndicate).balance, 0.02 ether + 1);
    }

    function testBothCollateralizedAndSlotClaim() public {
        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        uint256 eip1559Reward = 0.165 ether;
        sendEIP1559RewardsToSyndicate(eip1559Reward);

        uint256 collateralizedIndex = 0;
        uint256[] memory collateralizedIndexes = new uint256[](1);
        collateralizedIndexes[0] = collateralizedIndex;

        // set up collateralized knot
        MockSlotRegistry(syndicate.slotReg()).setCollateralisedOwnerAtIndex(blsPubKeyOne, collateralizedIndex, accountTwo);
        MockSlotRegistry(syndicate.slotReg()).setUserCollateralisedSLOTBalanceForKnot(houseOne, accountTwo, blsPubKeyOne, 4 ether);

        assertEq(accountTwo.balance, 0);
        assertEq(
            syndicate.previewUnclaimedETHAsCollateralizedSlotOwner(
                accountTwo,
                blsPubKeyOne
            ),
            eip1559Reward / 2
        );

        syndicate.batchUpdateCollateralizedSlotOwnersAccruedETH(blsPubKeyOneAsArray());

        vm.prank(accountTwo);
        syndicate.claimAsCollateralizedSLOTOwner(accountTwo, blsPubKeyOneAsArray());

        assertEq(accountTwo.balance, eip1559Reward / 2);
        assertEq(address(syndicate).balance, eip1559Reward / 2);

        // now let free floating guy come in and stake sETH
        vm.startPrank(accountOne);

        uint256 stakeAmount = 12 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakeAmount;

        sETH.approve(address(syndicate), stakeAmount);

        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);

        assertEq(accountOne.balance, 0);
        assertEq(address(syndicate).balance, eip1559Reward / 2);

        syndicate.claimAsStaker(accountOne, blsPubKeyOneAsArray());

        vm.stopPrank();

        assertEq(syndicate.sETHStakedBalanceForKnot(blsPubKeyOne, accountOne), 12 ether);
        assertEq(syndicate.sETHUserClaimForKnot(blsPubKeyOne, accountOne), eip1559Reward / 2);

        assertEq(accountOne.balance, (eip1559Reward / 2));
        assertEq(address(syndicate).balance, 0);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#h-04-unstaking-does-not-update-the-mapping-sethuserclaimforknot
    function testUnstakeUpdatesSETHUserClaimForKnot() public {
        // push forward for activation
        vm.roll(block.number + 1 + (5*32));

        uint256 stakeAmount = 12 ether;
        uint256[] memory sETHAmounts = new uint256[](1);
        sETHAmounts[0] = stakeAmount;

        // Assume account one as message sender
        vm.startPrank(accountOne);
        // issue allowance to stake
        sETH.approve(address(syndicate), sETHAmounts[0]);
        // stake
        syndicate.stake(blsPubKeyOneAsArray(), sETHAmounts, accountOne);
        // End impersonation
        vm.stopPrank();

        assertEq(
            syndicate.sETHTotalStakeForKnot(blsPubKeyOne),
            stakeAmount
        );
        assertEq(
            syndicate.sETHStakedBalanceForKnot(blsPubKeyOne, accountOne),
            stakeAmount
        );
        assertEq(
            syndicate.sETHUserClaimForKnot(blsPubKeyOne, accountOne),
            stakeAmount * syndicate.accumulatedETHPerFreeFloatingShare() / 1e24
        );

        uint256 eip1559Reward = 0.04 ether;
        sendEIP1559RewardsToSyndicate(eip1559Reward);

        assertEq(
            syndicate.sETHTotalStakeForKnot(blsPubKeyOne),
            stakeAmount
        );
        assertEq(
            syndicate.sETHStakedBalanceForKnot(blsPubKeyOne, accountOne),
            stakeAmount
        );
        assertEq(
            syndicate.sETHUserClaimForKnot(blsPubKeyOne, accountOne),
            stakeAmount * syndicate.accumulatedETHPerFreeFloatingShare() / 1e24
        );

        // unstake half
        uint256 unstakeAmount = stakeAmount / 2;
        sETHAmounts[0] = unstakeAmount;
        vm.prank(accountOne);
        syndicate.unstake(accountOne, accountOne, blsPubKeyOneAsArray(), sETHAmounts);

        assertEq(
            syndicate.sETHTotalStakeForKnot(blsPubKeyOne),
            stakeAmount - unstakeAmount
        );
        assertEq(
            syndicate.sETHStakedBalanceForKnot(blsPubKeyOne, accountOne),
            stakeAmount - unstakeAmount
        );
        assertEq(
            syndicate.sETHUserClaimForKnot(blsPubKeyOne, accountOne),
            (stakeAmount - unstakeAmount) * syndicate.accumulatedETHPerFreeFloatingShare() / 1e24
        );
    }

    function testBeaconUpgradeableFromOnlyOwner() public {
        address upgradeManager = address(this);
        UpgradeableBeacon beacon = UpgradeableBeacon(syndicateFactory.beacon());
        address newImplementation = address(new SyndicateMock());

        vm.startPrank(accountOne);
        vm.expectRevert("Ownable: caller is not the owner");
        beacon.updateImplementation(newImplementation);
        vm.stopPrank();

        vm.startPrank(upgradeManager);
        beacon.updateImplementation(newImplementation);
        vm.stopPrank();
        
        assertEq(beacon.implementation(), newImplementation);
    }

    function testBeaconUpgradeableAfterOwnershipTransfer() public {
        address upgradeManager = address(this);
        UpgradeableBeacon beacon = UpgradeableBeacon(syndicateFactory.beacon());
        address newImplementation = address(new SyndicateMock());

        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(accountOne);
        beacon.transferOwnership(accountOne);
        vm.stopPrank();

        vm.startPrank(upgradeManager);
        beacon.transferOwnership(accountOne);
        vm.stopPrank();

        vm.startPrank(upgradeManager);
        vm.expectRevert("Ownable: caller is not the owner");
        beacon.updateImplementation(newImplementation);
        vm.stopPrank();

        vm.startPrank(accountOne);
        beacon.updateImplementation(newImplementation);
        vm.stopPrank();

        assertEq(beacon.implementation(), newImplementation);
    }
}
