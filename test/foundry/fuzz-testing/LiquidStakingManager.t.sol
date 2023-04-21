pragma solidity ^0.8.13;

// SPDX-License-Identifier: MIT

import "forge-std/console.sol";

import {TestUtils} from "../../utils/TestUtils.sol";

import {NodeRunner} from "../../../contracts/testing/liquid-staking/NodeRunner.sol";
import {IDataStructures} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IDataStructures.sol";
import { IERC20 } from "@blockswaplab/stakehouse-solidity-api/contracts/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {MockSlotRegistry} from "../../../contracts/testing/stakehouse/MockSlotRegistry.sol";
import {MockSavETHRegistry} from "../../../contracts/testing/stakehouse/MockSavETHRegistry.sol";
import {LPToken} from "../../../contracts/liquid-staking/LPToken.sol";
import {Syndicate} from "../../../contracts/syndicate/Syndicate.sol";
import {MockStakeHouseUniverse} from "../../../contracts/testing/stakehouse/MockStakeHouseUniverse.sol";
import {MockBrandNFT} from "../../../contracts/testing/stakehouse/MockBrandNFT.sol";
import {MockAccountManager} from "../../../contracts/testing/stakehouse/MockAccountManager.sol";
import "../../../contracts/testing/liquid-staking/NonEOARepresentative.sol";

contract LiquidStakingManagerFuzzTests is TestUtils {
    function setUp() public {
        vm.startPrank(accountFive); // this will mean it gets dETH initial supply
        factory = createMockLSDNFactory();
        vm.stopPrank();

        // Deploy 1 network and get default dependencies
        manager = deployNewLiquidStakingNetwork(factory, admin, false, "LSDN");

        savETHVault = getSavETHVaultFromManager(manager);
        stakingFundsVault = getStakingFundsVaultFromManager(manager);

        // make 'admin' the 'DAO'
        vm.prank(address(factory));
        manager.updateDAOAddress(admin);
    }

    // claimRewardsAsNodeRunner with different recipient and bls public keys
    function testFuzzClaimRewardsAsNodeRunner(
        address recipient,
        uint256 blsPubKeysCount
    ) public {
        vm.assume(!Address.isContract(recipient));

        vm.assume(blsPubKeysCount < 4);

        bytes[] memory blsPubKeys = new bytes[](blsPubKeysCount);
        for (uint256 i = 0; i < blsPubKeysCount; ++i) {
            if (i == 0) {
                blsPubKeys[i] = blsPubKeyOne;
            }
            if (i == 1) {
                blsPubKeys[i] = blsPubKeyTwo;
            }
            if (i == 2) {
                blsPubKeys[i] = blsPubKeyThree;
            }
            if (i == 3) {
                blsPubKeys[i] = blsPubKeyFour;
            }
        }

        if (blsPubKeysCount == 0) {
            vm.expectRevert(bytes4(keccak256("EmptyArray()")));
            manager.claimRewardsAsNodeRunner(recipient, blsPubKeys);
        } else {
            for (uint256 i = 0; i < blsPubKeysCount; ++i) {
                vm.deal(accountOne, 100 ether);
                vm.deal(accountTwo, 100 ether);
                vm.deal(accountThree, 100 ether);
                depositStakeAndMintDerivativesForDefaultNetwork(
                    accountOne,
                    accountTwo,
                    accountThree,
                    blsPubKeys[i]
                );
            }

            vm.roll(block.number + 1 + (5 * 32));

            // Send syndicate some EIP1559 rewards
            uint256 eip1559Tips = 0.6743 ether;
            sendEIP1559RewardsToSyndicateAtAddress(
                eip1559Tips,
                manager.syndicate()
            );

            if (recipient == address(0)) {
                vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
                manager.claimRewardsAsNodeRunner(recipient, blsPubKeys);
            } else {
                vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
                manager.claimRewardsAsNodeRunner(recipient, blsPubKeys);

                vm.prank(accountOne);
                manager.claimRewardsAsNodeRunner(recipient, blsPubKeys);
            }
        }
    }

    function testFuzzRegisterBLSpublicKeys(
        uint256 blsPubKeysCount,
        address eoaRepresentative
    ) public {
        vm.assume(blsPubKeysCount < 4);

        bytes[] memory blsPubKeys = new bytes[](blsPubKeysCount);
        for (uint256 i = 0; i < blsPubKeysCount; ++i) {
            if (i == 0) {
                blsPubKeys[i] = blsPubKeyOne;
            }
            if (i == 1) {
                blsPubKeys[i] = blsPubKeyTwo;
            }
            if (i == 2) {
                blsPubKeys[i] = blsPubKeyThree;
            }
            if (i == 3) {
                blsPubKeys[i] = blsPubKeyFour;
            }
        }

        if (blsPubKeysCount == 0) {
            vm.expectRevert(bytes4(keccak256("EmptyArray()")));
            manager.registerBLSPublicKeys(
                blsPubKeys,
                blsPubKeys,
                eoaRepresentative
            );
        } else {
            vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
            manager.registerBLSPublicKeys(
                blsPubKeys,
                new bytes[](0),
                eoaRepresentative
            );

            vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
            manager.registerBLSPublicKeys(
                blsPubKeys,
                blsPubKeys,
                eoaRepresentative
            );

            vm.deal(accountOne, blsPubKeysCount * 4 ether);

            vm.expectRevert(bytes4(keccak256("OnlyEOA()")));
            vm.prank(accountOne);
            manager.registerBLSPublicKeys{value: blsPubKeysCount * 4 ether}(
                blsPubKeys,
                blsPubKeys,
                address(factory)
            );

            if (Address.isContract(eoaRepresentative)) {
                vm.expectRevert(bytes4(keccak256("OnlyEOA()")));
                vm.prank(accountOne);
                manager.registerBLSPublicKeys{value: blsPubKeysCount * 4 ether}(
                    blsPubKeys,
                    blsPubKeys,
                    eoaRepresentative
                );
            } else {
                manager.registerBLSPublicKeys{value: blsPubKeysCount * 4 ether}(
                    blsPubKeys,
                    blsPubKeys,
                    eoaRepresentative
                );
            }
        }
    }

    // anyone can stake different count of validators
    function testFuzzStakeValidators(address user, uint256 blsPubKeysCount)
        public
    {
        vm.assume(blsPubKeysCount < 4);

        // prepare parameters
        bytes[] memory blsPubKeys = new bytes[](blsPubKeysCount);
        for (uint256 i = 0; i < blsPubKeysCount; ++i) {
            if (i == 0) {
                blsPubKeys[i] = blsPubKeyOne;
            }
            if (i == 1) {
                blsPubKeys[i] = blsPubKeyTwo;
            }
            if (i == 2) {
                blsPubKeys[i] = blsPubKeyThree;
            }
            if (i == 3) {
                blsPubKeys[i] = blsPubKeyFour;
            }
        }
        IDataStructures.EIP712Signature[]
            memory sigs = new IDataStructures.EIP712Signature[](
                blsPubKeysCount
            );
        bytes32[] memory dataRoots = new bytes32[](blsPubKeysCount);

        // check stake
        if (blsPubKeysCount == 0) {
            vm.expectRevert(bytes4(keccak256("EmptyArray()")));
            vm.prank(user);
            manager.stake(blsPubKeys, blsPubKeys, blsPubKeys, sigs, dataRoots);
        } else {
            vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
            vm.prank(user);
            manager.stake(
                blsPubKeys,
                new bytes[](0),
                blsPubKeys,
                sigs,
                dataRoots
            );

            vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
            vm.prank(user);
            manager.stake(
                blsPubKeys,
                blsPubKeys,
                new bytes[](0),
                sigs,
                dataRoots
            );

            vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
            vm.prank(user);
            manager.stake(
                blsPubKeys,
                blsPubKeys,
                blsPubKeys,
                new IDataStructures.EIP712Signature[](0),
                dataRoots
            );

            vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
            manager.stake(
                blsPubKeys,
                blsPubKeys,
                blsPubKeys,
                sigs,
                new bytes32[](0)
            );

            vm.expectRevert(bytes4(keccak256("BLSPubKeyBanned()")));
            vm.prank(user);
            manager.stake(blsPubKeys, blsPubKeys, blsPubKeys, sigs, dataRoots);

            for (uint256 i = 0; i < blsPubKeysCount; ++i) {
                bytes memory _blsKey = blsPubKeys[i];
                address nodeRunner = accountTwo;
                vm.deal(nodeRunner, 100 ether);

                IERC20 dETHToken = savETHVault.dETHToken();
                vm.startPrank(accountFive);
                dETHToken.transfer(
                    address(savETHVault.saveETHRegistry()),
                    96 ether
                );
                vm.stopPrank();

                registerSingleBLSPubKey(nodeRunner, _blsKey, accountFour);

                vm.deal(accountOne, 32 ether);
                vm.startPrank(accountOne);
                savETHVault.depositETHForStaking{value: 24 ether}(
                    _blsKey,
                    24 ether
                );
                stakingFundsVault.depositETHForStaking{value: 4 ether}(
                    _blsKey,
                    4 ether
                );
                vm.stopPrank();
            }

            vm.prank(user);
            manager.stake(blsPubKeys, blsPubKeys, blsPubKeys, sigs, dataRoots);

            address smartWallet = manager.smartWalletOfKnot(blsPubKeys[0]);
            assertEq(
                manager.stakedKnotsOfSmartWallet(smartWallet),
                blsPubKeysCount
            );
        }
    }

    // anyone can mint derivatives of different count of validators
    function testFuzzMintDerivatives(address user, uint256 blsPubKeysCount)
        public
    {
        vm.assume(blsPubKeysCount < 3);

        // stakehouse create
        vm.deal(accountOne, 100 ether);
        vm.deal(accountTwo, 100 ether);
        vm.deal(accountThree, 100 ether);
        depositStakeAndMintDerivativesForDefaultNetwork(
            accountOne,
            accountTwo,
            accountThree,
            blsPubKeyFour
        );

        // prepare parameters
        bytes[] memory blsPubKeys = new bytes[](blsPubKeysCount);
        for (uint256 i = 0; i < blsPubKeysCount; ++i) {
            if (i == 0) {
                blsPubKeys[i] = blsPubKeyOne;
            }
            if (i == 1) {
                blsPubKeys[i] = blsPubKeyTwo;
            }
            if (i == 2) {
                blsPubKeys[i] = blsPubKeyThree;
            }
        }
        IDataStructures.ETH2DataReport[]
            memory reports = new IDataStructures.ETH2DataReport[](
                blsPubKeysCount
            );
        IDataStructures.EIP712Signature[]
            memory sigs = new IDataStructures.EIP712Signature[](
                blsPubKeysCount
            );

        // check mintDerivatives
        if (blsPubKeysCount == 0) {
            vm.expectRevert(bytes4(keccak256("EmptyArray()")));
            vm.prank(user);
            manager.mintDerivatives(blsPubKeys, reports, sigs);
        } else {
            vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
            vm.prank(user);
            manager.mintDerivatives(
                blsPubKeys,
                reports,
                new IDataStructures.EIP712Signature[](0)
            );

            vm.expectRevert(bytes4(keccak256("InconsistentArrayLength()")));
            vm.prank(user);
            manager.mintDerivatives(
                blsPubKeys,
                new IDataStructures.ETH2DataReport[](0),
                sigs
            );

            vm.expectRevert(bytes4(keccak256("BLSPubKeyBanned()")));
            vm.prank(user);
            manager.mintDerivatives(blsPubKeys, reports, sigs);

            for (uint256 i = 0; i < blsPubKeysCount; ++i) {
                bytes memory _blsKey = blsPubKeys[i];
                vm.deal(accountTwo, 100 ether);
                vm.deal(accountThree, 100 ether);
                registerSingleBLSPubKey(accountOne, _blsKey, accountFour);
                depositIntoDefaultSavETHVault(accountThree, _blsKey, 24 ether);
                depositIntoDefaultStakingFundsVault(
                    accountTwo,
                    _blsKey,
                    4 ether
                );
                stakeSingleBlsPubKey(_blsKey);
            }

            vm.expectRevert(bytes4(keccak256("DepositNotCompleted()")));
            vm.prank(user);
            manager.mintDerivatives(blsPubKeys, reports, sigs);

            for (uint256 i = 0; i < blsPubKeysCount; ++i) {
                bytes memory _blsKey = blsPubKeys[i];
                MockAccountManager(factory.accountMan()).setLifecycleStatus(
                    _blsKey,
                    2
                );
                MockStakeHouseUniverse(factory.uni()).setAssociatedHouseForKnot(
                        _blsKey,
                        manager.stakehouse()
                    );
            }

            address smartWallet = manager.smartWalletOfKnot(blsPubKeys[0]);
            assertEq(
                manager.stakedKnotsOfSmartWallet(smartWallet),
                blsPubKeysCount
            );

            vm.prank(user);
            manager.mintDerivatives(blsPubKeys, reports, sigs);

            assertEq(manager.stakedKnotsOfSmartWallet(smartWallet), 0);
        }
    }
}
