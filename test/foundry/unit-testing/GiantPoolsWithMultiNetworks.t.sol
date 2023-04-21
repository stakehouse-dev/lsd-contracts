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

contract GiantPoolsWithMultiNetworksTests is TestUtils {
    struct LSDNNetwork {
        MockLiquidStakingManager manager;
        MockSavETHVault savETHVault;
        MockStakingFundsVault stakingFundsVault;
    }

    LSDNNetwork[2] networks;
    MockGiantSavETHVaultPool giantSavETHPool;
    GiantMevAndFeesPool giantFeesAndMevPool;

    function setUp() public {
        vm.startPrank(accountFive); // this will mean it gets dETH initial supply
        factory = createMockLSDNFactory();
        vm.stopPrank();

        string[] memory names = new string[](2);
        names[0] = "LSDN";
        names[1] = "NLSDN";

        for (uint256 i = 0; i < 2; i++) {
            // Deploy 1 network
            networks[i].manager = deployNewLiquidStakingNetwork(
                factory,
                admin,
                false,
                names[i]
            );
            networks[i].savETHVault = MockSavETHVault(
                address(networks[i].manager.savETHVault())
            );
            networks[i].stakingFundsVault = MockStakingFundsVault(
                payable(address(networks[i].manager.stakingFundsVault()))
            );
        }

        giantFeesAndMevPool = GiantMevAndFeesPool(
            payable(address(factory.giantFeesAndMev()))
        );
        giantSavETHPool = MockGiantSavETHVaultPool(
            payable(address(factory.giantSavETHPool()))
        );
    }

    function testRevertWhenRegisterSameBLSPubKey() public {
        address nodeRunner = accountOne;
        address eoaRepresentative = accountFour;

        registerSingleBLSPubKey(
            nodeRunner,
            blsPubKeyOne,
            eoaRepresentative,
            networks[0].manager
        );

        vm.deal(nodeRunner, 4 ether);
        vm.startPrank(nodeRunner);
        vm.expectRevert(bytes4(keccak256("BLSKeyAlreadyRegistered()")));
        networks[1].manager.registerBLSPublicKeys{value: 4 ether}(
            getBytesArrayFromBytes(blsPubKeyOne),
            getBytesArrayFromBytes(blsPubKeyOne),
            eoaRepresentative
        );
        vm.stopPrank();
    }

    function testCanRegisterDifferentBLSPubKey() public {
        address nodeRunner = accountOne;
        address eoaRepresentative = accountFour;

        registerSingleBLSPubKey(
            nodeRunner,
            blsPubKeyOne,
            eoaRepresentative,
            networks[0].manager
        );

        registerSingleBLSPubKey(
            nodeRunner,
            blsPubKeyTwo,
            eoaRepresentative,
            networks[1].manager
        );
    }

    function testDepositToMultipleNetworks() public {
        bytes[] memory blsPubKeys = new bytes[](2);
        blsPubKeys[0] = blsPubKeyOne;
        blsPubKeys[1] = blsPubKeyTwo;
        for (uint256 i = 0; i < 2; i++) {
            address nodeRunner = accountOne;
            vm.deal(nodeRunner, 100 ether);
            address eoaRepresentative = accountFour;
            address feesAndMevUser = accountTwo;
            vm.deal(feesAndMevUser, 100 ether);
            address savETHUser = accountThree;
            vm.deal(savETHUser, 100 ether);
            registerSingleBLSPubKey(
                nodeRunner,
                blsPubKeys[i],
                eoaRepresentative,
                networks[i].manager
            );

            vm.prank(savETHUser);
            giantSavETHPool.depositETH{value: 48 ether}(48 ether);

            vm.prank(feesAndMevUser);
            giantFeesAndMevPool.depositETH{value: 48 ether}(48 ether);

            bytes[][] memory blsKeysForVaults = new bytes[][](1);
            blsKeysForVaults[0] = getBytesArrayFromBytes(blsPubKeys[i]);
            uint256[][] memory stakeAmountsForVaults = new uint256[][](1);
            stakeAmountsForVaults[0] = getUint256ArrayFromValues(24 ether);
            giantSavETHPool.batchDepositETHForStaking(
                getAddressArrayFromValues(address(networks[i].savETHVault)),
                getUint256ArrayFromValues(24 ether),
                blsKeysForVaults,
                stakeAmountsForVaults
            );
            assertEq(
                address(networks[i].manager.savETHVault()).balance,
                24 ether
            );

            stakeAmountsForVaults[0] = getUint256ArrayFromValues(4 ether);
            giantFeesAndMevPool.batchDepositETHForStaking(
                getAddressArrayFromValues(
                    address(networks[i].stakingFundsVault)
                ),
                getUint256ArrayFromValues(4 ether),
                blsKeysForVaults,
                stakeAmountsForVaults
            );
            assertEq(address(networks[i].stakingFundsVault).balance, 4 ether);
        }
    }

    function testStakeMintDerivativesFromMultipleNetworks() public {
        bytes[] memory blsPubKeys = new bytes[](2);
        blsPubKeys[0] = blsPubKeyOne;
        blsPubKeys[1] = blsPubKeyTwo;

        testDepositToMultipleNetworks();

        for (uint256 i = 0; i < 2; i++) {
            address feesAndMevUser = accountTwo;

            stakeAndMintDerivativesSingleKey(
                blsPubKeys[i],
                networks[i].manager
            );

            vm.roll(block.number + 500);

            uint256 associatedWithdrawalBatch = giantFeesAndMevPool
                .allocatedWithdrawalBatchForBlsPubKey(blsPubKeys[i]);
            uint256 totalETHFundedForBatch = giantFeesAndMevPool
                .totalETHFundedPerBatch(
                    feesAndMevUser,
                    associatedWithdrawalBatch
                );
            assertEq(totalETHFundedForBatch, 4 ether);
            assertEq(
                giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUser),
                96 ether
            );
        }
    }

    function testWithdrawLPFromMultipleNetworks() public {
        bytes[] memory blsPubKeys = new bytes[](2);
        blsPubKeys[0] = blsPubKeyOne;
        blsPubKeys[1] = blsPubKeyTwo;

        testStakeMintDerivativesFromMultipleNetworks();

        for (uint256 i = 0; i < 2; i++) {
            address feesAndMevUser = accountTwo;

            LPToken blsPubKeyLP = networks[i].stakingFundsVault.lpTokenForKnot(
                blsPubKeys[i]
            );
            uint256 associatedWithdrawalBatchForKeyOne = giantFeesAndMevPool
                .allocatedWithdrawalBatchForBlsPubKey(blsPubKeys[i]);

            assertEq(blsPubKeyLP.balanceOf(feesAndMevUser), 0 ether);

            uint256 totalLiquidityInActiveRangeForUser = giantFeesAndMevPool
                .getTotalLiquidityInActiveRangeForUser(feesAndMevUser);
            uint256 lpTokenETHBalancer = giantFeesAndMevPool
                .lpTokenETH()
                .balanceOf(feesAndMevUser);

            // withdraw 2 ether
            vm.startPrank(feesAndMevUser);
            giantFeesAndMevPool.withdrawLP(blsPubKeyLP, 2 ether);
            vm.stopPrank();

            assertEq(blsPubKeyLP.balanceOf(feesAndMevUser), 2 ether);
            assertEq(
                giantFeesAndMevPool.lpTokenETH().balanceOf(feesAndMevUser),
                lpTokenETHBalancer - 2 ether
            );
            assertEq(
                giantFeesAndMevPool.totalETHFundedPerBatch(
                    feesAndMevUser,
                    associatedWithdrawalBatchForKeyOne
                ),
                2 ether
            );
            assertEq(
                giantFeesAndMevPool.getTotalLiquidityInActiveRangeForUser(
                    feesAndMevUser
                ),
                totalLiquidityInActiveRangeForUser - 2 ether
            );
        }
    }
}
