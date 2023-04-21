pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {MockLiquidStakingManager} from "../../../contracts/testing/liquid-staking/MockLiquidStakingManager.sol";
import {MockSavETHVault} from "../../../contracts/testing/liquid-staking/MockSavETHVault.sol";
import {LPTokenFactory} from "../../../contracts/liquid-staking/LPTokenFactory.sol";
import {LPToken} from "../../../contracts/liquid-staking/LPToken.sol";
import { IERC20 } from "@blockswaplab/stakehouse-solidity-api/contracts/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SyndicateMock} from "../../../contracts/testing/syndicate/SyndicateMock.sol";
import {MockBrandNFT} from "../../../contracts/testing/stakehouse/MockBrandNFT.sol";
import {MockLSDNFactory} from "../../../contracts/testing/liquid-staking/MockLSDNFactory.sol";
import {OwnableSmartWalletFactory} from "../../../contracts/smart-wallet/OwnableSmartWalletFactory.sol";
import {SavETHVaultDeployer} from "../../../contracts/liquid-staking/SavETHVaultDeployer.sol";
import {StakingFundsVaultDeployer} from "../../../contracts/liquid-staking/StakingFundsVaultDeployer.sol";
import {OptionalGatekeeperFactory} from "../../../contracts/liquid-staking/OptionalGatekeeperFactory.sol";
import {MockSavETHRegistry} from "../../../contracts/testing/stakehouse/MockSavETHRegistry.sol";
import {TestUtils} from "../../utils/TestUtils.sol";

contract SavETHVaultFuzzTest is TestUtils {
    LPTokenFactory tokenFactory;
    MockLiquidStakingManager liquidStakingManager;

    function setUp() public {
        vm.startPrank(accountFive); // this will mean it gets dETH initial supply
        factory = createMockLSDNFactory();
        vm.stopPrank();

        liquidStakingManager = deployDefaultLiquidStakingNetwork(
            factory,
            admin
        );

        savETHVault = MockSavETHVault(
            address(liquidStakingManager.savETHVault())
        );
        assertEq(savETHVault.dETHToken().balanceOf(accountFive), 125_000 ether);
    }

    // should deposit ETH for staking with different account, different amount
    // https://code4rena.com/reports/2022-11-stakehouse/#m-31-vaults-can-be-griefed-to-not-be-able-to-be-used-for-deposits
    function testFuzzDepositETHForStaking(
        address account,
        uint256 depositAmount
    ) public {
        vm.assume(account != address(0) && !Address.isContract(account));

        vm.deal(account, depositAmount);
        savETHVault.accountMan().setLifecycleStatus(blsPubKeyOne, 1);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);

        if (depositAmount >= 0.001 ether && depositAmount % 0.001 ether == 0) {
            if (depositAmount > 24 ether) {
                vm.prank(account);
                vm.expectRevert(
                    "Amount exceeds the staking limit for the validator"
                );
                savETHVault.depositETHForStaking{value: depositAmount}(
                    blsPubKeyOne,
                    depositAmount
                );
            } else {
                vm.prank(account);
                savETHVault.depositETHForStaking{value: depositAmount}(
                    blsPubKeyOne,
                    depositAmount
                );

                LPToken token = savETHVault.lpTokenForKnot(blsPubKeyOne);
                assertEq(token.balanceOf(account), depositAmount);
                assertEq(account.balance, 0);
                assertEq(
                    savETHVault.KnotAssociatedWithLPToken(token),
                    blsPubKeyOne
                );
                assertEq(savETHVault.numberOfLPTokensIssued(), 1);
            }
        } else if (depositAmount < 0.001 ether) {
            vm.prank(account);
            vm.expectRevert("Min amount not reached");
            savETHVault.depositETHForStaking{value: depositAmount}(
                blsPubKeyOne,
                depositAmount
            );
        } else {
            vm.prank(account);
            vm.expectRevert("Amount not multiple of min staking");
            savETHVault.depositETHForStaking{value: depositAmount}(
                blsPubKeyOne,
                depositAmount
            );
        }
    }

    // should deposit ETH for staking with multiple users
    function testFuzzDepositETHForStakingWithMultipleUsers(
        address[] memory accounts,
        uint256[] memory depositAmounts,
        bytes1[48][] memory blsPubKeys
    ) public {
        uint256 length = accounts.length;
        if (
            length > 4 ||
            blsPubKeys.length < length ||
            depositAmounts.length < length
        ) return;

        for (uint256 i = 0; i < length; ++i) {
            address account = accounts[i];
            vm.assume(account != address(0) && !Address.isContract(account));

            uint256 depositAmount = depositAmounts[i];
            bytes memory blsPubKey = new bytes(48);
            for (uint256 j = 0; j < 48; j++) blsPubKey[j] = blsPubKeys[i][j];

            vm.deal(account, depositAmount);
            savETHVault.accountMan().setLifecycleStatus(blsPubKey, 1);
            liquidStakingManager.setIsPartOfNetwork(blsPubKey, true);

            if (
                depositAmount >= 0.001 ether && depositAmount % 0.001 ether == 0
            ) {
                if (depositAmount > 24 ether) {
                    vm.prank(account);
                    vm.expectRevert(
                        "Amount exceeds the staking limit for the validator"
                    );
                    savETHVault.depositETHForStaking{value: depositAmount}(
                        blsPubKey,
                        depositAmount
                    );
                } else {
                    vm.prank(account);
                    savETHVault.depositETHForStaking{value: depositAmount}(
                        blsPubKey,
                        depositAmount
                    );

                    LPToken token = savETHVault.lpTokenForKnot(blsPubKey);
                    assertEq(token.balanceOf(account), depositAmount);
                    assertEq(account.balance, 0);
                    assertEq(
                        savETHVault.KnotAssociatedWithLPToken(token),
                        blsPubKey
                    );
                    assertEq(savETHVault.numberOfLPTokensIssued(), 1);
                }
            } else if (depositAmount < 0.001 ether) {
                vm.prank(account);
                vm.expectRevert("Min amount not reached");
                savETHVault.depositETHForStaking{value: depositAmount}(
                    blsPubKey,
                    depositAmount
                );
            } else {
                vm.prank(account);
                vm.expectRevert("Amount not multiple of min staking");
                savETHVault.depositETHForStaking{value: depositAmount}(
                    blsPubKey,
                    depositAmount
                );
            }
        }
    }

    // should deposit ETH for staking after withdraw with multiple rounds
    function testFuzzDepositETHForStakingAfterWithdrawWithMultipleRounds(
        uint8 rounds,
        address[] memory accounts,
        bytes1[48][] memory blsPubKeys
    ) public {
        uint256 length = accounts.length;
        if (rounds > 4 || length > 4 || blsPubKeys.length < length) return;

        uint256 depositAmount = 12 ether;
        uint256 withdrawAmount = 24 ether;

        for (uint256 round = 0; round < rounds; ++round) {
            for (uint256 i = 0; i < length; ++i) {
                address account = accounts[i];
                vm.assume(
                    account != address(0) && !Address.isContract(account)
                );

                bytes memory blsPubKey = new bytes(48);
                for (uint256 j = 0; j < 48; j++)
                    blsPubKey[j] = blsPubKeys[i][j];

                savETHVault.accountMan().setLifecycleStatus(blsPubKey, 1);
                liquidStakingManager.setIsPartOfNetwork(blsPubKey, true);

                uint256 balanceBefore;
                uint256 totalSupply;
                if (round != 0) {
                    LPToken token = savETHVault.lpTokenForKnot(blsPubKey);
                    balanceBefore = token.balanceOf(account);
                    totalSupply = token.totalSupply();
                }

                if (depositAmount + totalSupply > 24 ether) {
                    vm.prank(account);
                    vm.expectRevert(
                        "Amount exceeds the staking limit for the validator"
                    );
                    savETHVault.depositETHForStaking{value: depositAmount}(
                        blsPubKey,
                        depositAmount
                    );
                    continue;
                }

                vm.deal(account, depositAmount);

                vm.prank(account);
                savETHVault.depositETHForStaking{value: depositAmount}(
                    blsPubKey,
                    depositAmount
                );

                LPToken token = savETHVault.lpTokenForKnot(blsPubKey);
                assertEq(
                    token.balanceOf(account),
                    balanceBefore + depositAmount
                );

                uint256 totalBalanceBefore = address(savETHVault).balance;
                if (totalBalanceBefore >= withdrawAmount) {
                    vm.prank(address(liquidStakingManager));
                    savETHVault.withdrawETHForStaking(account, withdrawAmount);

                    assertEq(
                        address(savETHVault).balance,
                        totalBalanceBefore - withdrawAmount
                    );
                } else {
                    vm.prank(address(liquidStakingManager));
                    vm.expectRevert("Insufficient withdrawal amount");
                    savETHVault.withdrawETHForStaking(account, withdrawAmount);
                }
            }
        }
    }

    function testFuzzDepositETHForStakingWithNotEnoughBalance(
        address account,
        uint256 depositAmount
    ) public {
        vm.assume(account != address(0) && !Address.isContract(account));

        if (depositAmount < 1) {
            return;
        }
        vm.deal(account, depositAmount - 1);
        savETHVault.accountMan().setLifecycleStatus(blsPubKeyOne, 1);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);

        vm.prank(account);
        vm.expectRevert();
        savETHVault.depositETHForStaking{value: depositAmount}(
            blsPubKeyOne,
            depositAmount
        );

        vm.prank(account);
        vm.expectRevert("Must provide correct amount of ETH");
        savETHVault.depositETHForStaking{value: depositAmount - 1}(
            blsPubKeyOne,
            depositAmount
        );
    }

    // should batch deposit ETH for staking with different account, different amounts
    function testFuzzBatchDepositETHForStaking(
        address account,
        uint256[] memory depositAmounts
    ) public {
        vm.assume(account != address(0) && !Address.isContract(account));

        uint256 length = depositAmounts.length;
        if (length > 4) return;

        uint256 totalAmount;
        uint256 revertReason;
        bytes[] memory pubKeys = new bytes[](length);
        if (length == 0) {
            revertReason = 3;
        }
        for (uint256 i = 0; i < length; ++i) {
            depositAmounts[i] = depositAmounts[i] % 10000 ether;
            totalAmount += depositAmounts[i];
            if (revertReason == 0 && depositAmounts[i] < 0.001 ether) {
                revertReason = 1;
            } else if (
                revertReason == 0 && depositAmounts[i] % 0.001 ether != 0
            ) {
                revertReason = 2;
            }
            pubKeys[i] = blsPubKeyOne;
        }
        vm.deal(account, totalAmount);

        savETHVault.accountMan().setLifecycleStatus(blsPubKeyOne, 1);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);

        if (revertReason == 0) {
            vm.prank(account);
            savETHVault.batchDepositETHForStaking{value: totalAmount}(
                pubKeys,
                depositAmounts
            );

            LPToken token = savETHVault.lpTokenForKnot(blsPubKeyOne);
            assertEq(token.balanceOf(account), totalAmount);
            assertEq(account.balance, 0);
            assertEq(
                savETHVault.KnotAssociatedWithLPToken(token),
                blsPubKeyOne
            );
            assertEq(savETHVault.numberOfLPTokensIssued(), 1);
        } else if (revertReason == 1) {
            vm.prank(account);
            vm.expectRevert("Min amount not reached");
            savETHVault.batchDepositETHForStaking{value: totalAmount}(
                pubKeys,
                depositAmounts
            );
        } else if (revertReason == 2) {
            vm.prank(account);
            vm.expectRevert("Amount not multiple of min staking");
            savETHVault.batchDepositETHForStaking{value: totalAmount}(
                pubKeys,
                depositAmounts
            );
        } else {
            vm.prank(account);
            vm.expectRevert("Empty arrays");
            savETHVault.batchDepositETHForStaking{value: totalAmount}(
                pubKeys,
                depositAmounts
            );
        }
    }

    // should batch deposit ETH for staking with multiple users
    function testFuzzBatchDepositETHForStakingWithMultipleUsers(
        address[] memory accounts,
        uint256[][] memory depositAmountsArray,
        bytes1[48][] memory blsPubKeys
    ) public {
        uint256 userLength = accounts.length;
        if (
            userLength > 4 ||
            blsPubKeys.length < userLength ||
            depositAmountsArray.length < userLength
        ) return;

        for (uint256 i = 0; i < userLength; ++i) {
            address account = accounts[i];
            vm.assume(account != address(0) && !Address.isContract(account));
            if (depositAmountsArray[i].length > 4) continue;

            uint256[] memory depositAmounts = depositAmountsArray[i];
            bytes memory blsPubKey = new bytes(48);
            for (uint256 j = 0; j < 48; j++) blsPubKey[j] = blsPubKeys[i][j];

            uint256 length = depositAmounts.length;
            uint256 totalAmount;
            uint256 revertReason;
            bytes[] memory pubKeys = new bytes[](length);
            if (length == 0) {
                revertReason = 3;
            }
            for (uint256 i = 0; i < length; ++i) {
                depositAmounts[i] = depositAmounts[i] % 10000 ether;
                totalAmount += depositAmounts[i];
                if (revertReason == 0 && depositAmounts[i] < 0.001 ether) {
                    revertReason = 1;
                } else if (
                    revertReason == 0 && depositAmounts[i] % 0.001 ether != 0
                ) {
                    revertReason = 2;
                }
                pubKeys[i] = blsPubKey;
            }
            vm.deal(account, totalAmount);

            savETHVault.accountMan().setLifecycleStatus(blsPubKey, 1);
            liquidStakingManager.setIsPartOfNetwork(blsPubKey, true);

            if (revertReason == 0) {
                vm.prank(account);
                savETHVault.batchDepositETHForStaking{value: totalAmount}(
                    pubKeys,
                    depositAmounts
                );

                LPToken token = savETHVault.lpTokenForKnot(blsPubKey);
                assertEq(token.balanceOf(account), totalAmount);
                assertEq(account.balance, 0);
                assertEq(
                    savETHVault.KnotAssociatedWithLPToken(token),
                    blsPubKey
                );
                assertEq(savETHVault.numberOfLPTokensIssued(), 1);
            } else if (revertReason == 1) {
                vm.prank(account);
                vm.expectRevert("Min amount not reached");
                savETHVault.batchDepositETHForStaking{value: totalAmount}(
                    pubKeys,
                    depositAmounts
                );
            } else if (revertReason == 2) {
                vm.prank(account);
                vm.expectRevert("Amount not multiple of min staking");
                savETHVault.batchDepositETHForStaking{value: totalAmount}(
                    pubKeys,
                    depositAmounts
                );
            } else {
                vm.prank(account);
                vm.expectRevert("Empty arrays");
                savETHVault.batchDepositETHForStaking{value: totalAmount}(
                    pubKeys,
                    depositAmounts
                );
            }
        }
    }

    // test burn LP in different lifecycle status
    function testFuzzBurnLPInDifferentLifecycleStatus(
        address account,
        uint256 burnAmount,
        uint256 lifecycleStatus
    ) public {
        vm.assume(account != address(0) && !Address.isContract(account));

        // Adjust parameters
        burnAmount = burnAmount % 50 ether;
        lifecycleStatus = lifecycleStatus % 5;
        vm.assume(account != address(0));

        savETHVault.accountMan().setLifecycleStatus(blsPubKeyOne, 1);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);

        vm.deal(account, 24 ether);
        vm.prank(account);
        savETHVault.depositETHForStaking{value: 24 ether}(
            blsPubKeyOne,
            24 ether
        );

        LPToken token = savETHVault.lpTokenForKnot(blsPubKeyOne);

        // Fast forward time 3 hours ahead to allow for ETH withrawal
        vm.warp(block.timestamp + 3 hours);

        savETHVault.accountMan().setLifecycleStatus(
            blsPubKeyOne,
            lifecycleStatus
        );

        if (burnAmount < 0.001 ether) {
            vm.expectRevert("Amount cannot be zero");
            vm.prank(account);
            savETHVault.burnLPToken(token, burnAmount);
        } else if (burnAmount > token.balanceOf(account)) {
            vm.expectRevert("Not enough balance");
            vm.prank(account);
            savETHVault.burnLPToken(token, burnAmount);
        } else if (lifecycleStatus == 1) {
            vm.startPrank(account);
            savETHVault.burnLPToken(token, burnAmount);
            vm.stopPrank();

            assertEq(account.balance, burnAmount);
        } else if (lifecycleStatus == 3) {
            // send dETH to the vault as if the vault has withdrawn
            IERC20 dETHToken = savETHVault.dETHToken();
            vm.startPrank(accountFive);
            dETHToken.transfer(
                address(savETHVault.saveETHRegistry()),
                24 ether
            );
            vm.stopPrank();

            assertEq(dETHToken.balanceOf(account), 0);

            vm.prank(account);
            savETHVault.burnLPToken(token, burnAmount);
            vm.stopPrank();

            assertEq(dETHToken.balanceOf(account), burnAmount);
        } else {
            vm.expectRevert("Cannot burn LP tokens");
            vm.prank(account);
            savETHVault.burnLPToken(token, burnAmount);
        }
    }

    // test depositDETHForStaking with different amount
    function testFuzzDepositDETHForStaking(
        address account,
        uint128 dETHAmountToDeposit,
        uint256 lifecycleStatus
    ) public {
        vm.assume(account != address(0) && !Address.isContract(account));

        // 1. Adjust parameters
        dETHAmountToDeposit = dETHAmountToDeposit % 50 ether;
        lifecycleStatus = lifecycleStatus % 5;

        // 2. Prepare dETH for testing
        // First supply ETH when validator is at initials registered phase
        savETHVault.accountMan().setLifecycleStatus(blsPubKeyOne, 1);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);

        uint256 stakeAmount = 24 ether;
        vm.deal(account, stakeAmount);

        vm.prank(account);
        savETHVault.depositETHForStaking{value: stakeAmount}(
            blsPubKeyOne,
            stakeAmount
        );

        LPToken lp = savETHVault.lpTokenForKnot(blsPubKeyOne);

        // Move lifecycle straight to tokens minted i.e. knot has been created and savETH added to vault
        savETHVault.accountMan().setLifecycleStatus(blsPubKeyOne, 3);

        // send dETH to the vault as if the vault has withdrawn
        IERC20 dETHToken = savETHVault.dETHToken();
        vm.startPrank(accountFive);
        dETHToken.transfer(address(savETHVault.saveETHRegistry()), stakeAmount);
        vm.stopPrank();

        savETHVault.saveETHRegistry().setBalInIndex(
            1,
            blsPubKeyOne,
            stakeAmount
        );

        // burn LP token and get dETH
        uint256 balanceBefore = dETHToken.balanceOf(account);
        vm.prank(account);
        savETHVault.burnLPToken(lp, stakeAmount);
        assertEq(dETHToken.balanceOf(account), balanceBefore + stakeAmount);

        vm.startPrank(accountFive);
        dETHToken.approve(address(savETHVault), dETHAmountToDeposit);

        // 3. Start testing
        uint128 dETHRequired = savETHVault.dETHRequiredToIsolateWithdrawnKnot(
            blsPubKeyOne
        );

        if (dETHAmountToDeposit < 0.001 ether) {
            vm.expectRevert("Amount must be at least 0.001 ether");
            savETHVault.depositDETHForStaking(
                blsPubKeyOne,
                dETHAmountToDeposit
            );
        } else if (lifecycleStatus != 3) {
            savETHVault.accountMan().setLifecycleStatus(
                blsPubKeyOne,
                lifecycleStatus
            );
            vm.expectRevert("Lifecycle status must be three");
            savETHVault.depositDETHForStaking(
                blsPubKeyOne,
                dETHAmountToDeposit
            );
        } else if (dETHAmountToDeposit != dETHRequired) {
            // Move lifecycle straight to tokens minted
            savETHVault.accountMan().setLifecycleStatus(
                blsPubKeyOne,
                lifecycleStatus
            );
            vm.expectRevert("Amount must be equal to dETH required to isolate");
            savETHVault.depositDETHForStaking(
                blsPubKeyOne,
                dETHAmountToDeposit
            );
        } else {
            uint256 lpTotalSupplyBefore = lp.totalSupply();
            savETHVault.depositDETHForStaking(
                blsPubKeyOne,
                dETHAmountToDeposit
            );
            assertEq(
                lp.totalSupply(),
                lpTotalSupplyBefore + dETHAmountToDeposit
            );
        }
        vm.stopPrank();
    }

    // test depositDETHForStaking with multiple users
    function testFuzzDepositDETHForStakingWithMultipleUsers(
        address[] memory accounts,
        uint128[] memory dETHAmountToDeposits,
        uint256[] memory lifecycleStatusArray
    ) public {
        uint256 length = accounts.length;
        if (
            length > 4 ||
            dETHAmountToDeposits.length < length ||
            lifecycleStatusArray.length < length
        ) return;

        for (uint256 i = 0; i < length; ++i) {
            address account = accounts[i];
            vm.assume(account != address(0) && !Address.isContract(account));

            uint128 dETHAmountToDeposit = dETHAmountToDeposits[i];
            uint256 lifecycleStatus = lifecycleStatusArray[i];

            // 1. Adjust parameters
            dETHAmountToDeposit = dETHAmountToDeposit % 50 ether;
            lifecycleStatus = lifecycleStatus % 5;

            // 2. Prepare dETH for testing
            // First supply ETH when validator is at initials registered phase
            savETHVault.accountMan().setLifecycleStatus(blsPubKeyOne, 1);
            liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);

            uint256 stakeAmount = 24 ether;
            vm.deal(account, stakeAmount);

            vm.prank(account);
            savETHVault.depositETHForStaking{value: stakeAmount}(
                blsPubKeyOne,
                stakeAmount
            );

            LPToken lp = savETHVault.lpTokenForKnot(blsPubKeyOne);

            // Move lifecycle straight to tokens minted i.e. knot has been created and savETH added to vault
            savETHVault.accountMan().setLifecycleStatus(blsPubKeyOne, 3);

            // send dETH to the vault as if the vault has withdrawn
            IERC20 dETHToken = savETHVault.dETHToken();
            vm.startPrank(accountFive);
            dETHToken.transfer(
                address(savETHVault.saveETHRegistry()),
                stakeAmount
            );
            vm.stopPrank();

            savETHVault.saveETHRegistry().setBalInIndex(
                1,
                blsPubKeyOne,
                stakeAmount
            );

            // burn LP token and get dETH
            uint256 balanceBefore = dETHToken.balanceOf(account);
            vm.prank(account);
            savETHVault.burnLPToken(lp, stakeAmount);
            assertEq(dETHToken.balanceOf(account), balanceBefore + stakeAmount);

            vm.startPrank(accountFive);
            dETHToken.approve(address(savETHVault), dETHAmountToDeposit);

            // 3. Start testing
            uint128 dETHRequired = savETHVault
                .dETHRequiredToIsolateWithdrawnKnot(blsPubKeyOne);

            if (dETHAmountToDeposit < 0.001 ether) {
                vm.expectRevert("Amount must be at least 0.001 ether");
                savETHVault.depositDETHForStaking(
                    blsPubKeyOne,
                    dETHAmountToDeposit
                );
            } else if (lifecycleStatus != 3) {
                savETHVault.accountMan().setLifecycleStatus(
                    blsPubKeyOne,
                    lifecycleStatus
                );
                vm.expectRevert("Lifecycle status must be three");
                savETHVault.depositDETHForStaking(
                    blsPubKeyOne,
                    dETHAmountToDeposit
                );
            } else if (dETHAmountToDeposit != dETHRequired) {
                // Move lifecycle straight to tokens minted
                savETHVault.accountMan().setLifecycleStatus(
                    blsPubKeyOne,
                    lifecycleStatus
                );
                vm.expectRevert(
                    "Amount must be equal to dETH required to isolate"
                );
                savETHVault.depositDETHForStaking(
                    blsPubKeyOne,
                    dETHAmountToDeposit
                );
            } else {
                uint256 lpTotalSupplyBefore = lp.totalSupply();
                savETHVault.depositDETHForStaking(
                    blsPubKeyOne,
                    dETHAmountToDeposit
                );
                assertEq(
                    lp.totalSupply(),
                    lpTotalSupplyBefore + dETHAmountToDeposit
                );
            }
            vm.stopPrank();
        }
    }

    // test depositDETHForStaking with insufficient balance
    function testFuzzDepositDETHForStakingWithInsufficientBalance(
        address account,
        uint128 dETHAmountToDeposit,
        uint256 lifecycleStatus
    ) public {
        vm.assume(account != address(0) && !Address.isContract(account));

        // 1. Adjust parameters
        dETHAmountToDeposit = dETHAmountToDeposit % 50 ether;
        lifecycleStatus = lifecycleStatus % 5;

        // 2. Prepare dETH for testing
        // First supply ETH when validator is at initials registered phase
        savETHVault.accountMan().setLifecycleStatus(blsPubKeyOne, 1);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);

        uint256 stakeAmount = 24 ether;
        vm.deal(account, stakeAmount);

        vm.prank(account);
        savETHVault.depositETHForStaking{value: stakeAmount}(
            blsPubKeyOne,
            stakeAmount
        );

        LPToken lp = savETHVault.lpTokenForKnot(blsPubKeyOne);

        // Move lifecycle straight to tokens minted i.e. knot has been created and savETH added to vault
        savETHVault.accountMan().setLifecycleStatus(blsPubKeyOne, 3);

        // send dETH to the vault as if the vault has withdrawn
        IERC20 dETHToken = savETHVault.dETHToken();
        vm.startPrank(accountFive);
        dETHToken.transfer(address(savETHVault.saveETHRegistry()), stakeAmount);
        vm.stopPrank();

        savETHVault.saveETHRegistry().setBalInIndex(
            1,
            blsPubKeyOne,
            stakeAmount
        );

        // burn LP token and get dETH
        uint256 balanceOfBefore = dETHToken.balanceOf(account);
        vm.prank(account);
        savETHVault.burnLPToken(lp, stakeAmount);
        assertEq(dETHToken.balanceOf(account) - balanceOfBefore, stakeAmount);

        vm.startPrank(accountFive);
        dETHToken.approve(address(savETHVault), dETHAmountToDeposit);

        // 3. Start testing
        // transfer dETH to make insufficient balance condition
        dETHToken.transfer(accountFive, stakeAmount);

        uint128 dETHRequired = savETHVault.dETHRequiredToIsolateWithdrawnKnot(
            blsPubKeyOne
        );

        if (dETHAmountToDeposit < 0.001 ether) {
            vm.expectRevert("Amount must be at least 0.001 ether");
            savETHVault.depositDETHForStaking(
                blsPubKeyOne,
                dETHAmountToDeposit
            );
        } else if (lifecycleStatus != 3) {
            savETHVault.accountMan().setLifecycleStatus(
                blsPubKeyOne,
                lifecycleStatus
            );
            vm.expectRevert("Lifecycle status must be three");
            savETHVault.depositDETHForStaking(
                blsPubKeyOne,
                dETHAmountToDeposit
            );
        } else if (dETHAmountToDeposit != dETHRequired) {
            savETHVault.accountMan().setLifecycleStatus(
                blsPubKeyOne,
                lifecycleStatus
            );
            vm.expectRevert("Amount must be equal to dETH required to isolate");
            savETHVault.depositDETHForStaking(
                blsPubKeyOne,
                dETHAmountToDeposit
            );
        } else {
            vm.expectRevert("Insufficient dETH balance");
            savETHVault.depositDETHForStaking(
                blsPubKeyOne,
                dETHAmountToDeposit
            );
        }
    }

    // test rotateLPTokens with different amount / different lifecycle status
    function testFuzzRotateLPTokens(
        uint256 rotateAmount,
        uint256 oldLifecycleStatus,
        uint256 newLifecycleStatus
    ) public {
        // 1. Adjust parameters
        rotateAmount =
            ((rotateAmount % 24 ether) / 0.001 ether) *
            0.001 ether +
            (rotateAmount % 2) *
            0.0001 ether;
        oldLifecycleStatus = oldLifecycleStatus % 5;
        newLifecycleStatus = newLifecycleStatus % 5;

        // 2. Prepare LP tokens
        savETHVault.accountMan().setLifecycleStatus(blsPubKeyOne, 1);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);
        savETHVault.accountMan().setLifecycleStatus(blsPubKeyTwo, 1);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyTwo, true);

        uint256 oldLPAmount = 16 ether;
        uint256 newLPAmount = 12 ether;
        vm.deal(accountOne, oldLPAmount + newLPAmount);

        vm.startPrank(accountOne);
        savETHVault.depositETHForStaking{value: oldLPAmount}(
            blsPubKeyOne,
            oldLPAmount
        );
        savETHVault.depositETHForStaking{value: newLPAmount}(
            blsPubKeyTwo,
            newLPAmount
        );
        vm.stopPrank();

        // 3. Start testing

        LPToken previousLP = savETHVault.lpTokenForKnot(blsPubKeyOne);
        LPToken newLP = savETHVault.lpTokenForKnot(blsPubKeyTwo);

        assertEq(previousLP.balanceOf(accountOne), oldLPAmount);
        assertEq(newLP.balanceOf(accountOne), newLPAmount);

        vm.warp(block.timestamp + 1 days);

        savETHVault.accountMan().setLifecycleStatus(
            blsPubKeyOne,
            oldLifecycleStatus
        );
        savETHVault.accountMan().setLifecycleStatus(
            blsPubKeyTwo,
            newLifecycleStatus
        );

        vm.startPrank(accountOne);
        if (rotateAmount < 0.001 ether) {
            vm.expectRevert("Amount cannot be zero");
            savETHVault.rotateLPTokens(previousLP, newLP, rotateAmount);
        } else if (rotateAmount % 0.001 ether != 0) {
            vm.expectRevert("Amount not multiple of min staking");
            savETHVault.rotateLPTokens(previousLP, newLP, rotateAmount);
        } else if (rotateAmount > oldLPAmount) {
            vm.expectRevert("Not enough balance");
            savETHVault.rotateLPTokens(previousLP, newLP, rotateAmount);
        } else if (rotateAmount > 24 ether - newLPAmount) {
            vm.expectRevert("Not enough mintable tokens");
            savETHVault.rotateLPTokens(previousLP, newLP, rotateAmount);
        } else if (oldLifecycleStatus != 1 || newLifecycleStatus != 1) {
            vm.expectRevert("Lifecycle status must be one");
            savETHVault.rotateLPTokens(previousLP, newLP, rotateAmount);
        } else {
            savETHVault.rotateLPTokens(previousLP, newLP, rotateAmount);

            assertEq(
                previousLP.balanceOf(accountOne),
                oldLPAmount - rotateAmount
            );
            assertEq(newLP.balanceOf(accountOne), newLPAmount + rotateAmount);
        }
        vm.stopPrank();
    }
}
