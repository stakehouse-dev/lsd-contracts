pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "forge-std/Test.sol";

import { StakingFundsVault } from "../../../contracts/liquid-staking/StakingFundsVault.sol";
import { Syndicate } from "../../../contracts/syndicate/Syndicate.sol";
import { SavETHVault } from "../../../contracts/liquid-staking/SavETHVault.sol";
import { LPToken } from "../../../contracts/liquid-staking/LPToken.sol";
import {
    TestUtils,
    MockLSDNFactory,
    MockLiquidStakingManager,
    MockAccountManager,
    IDataStructures
} from "../../utils/TestUtils.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract StakingFundsVaultFuzzTest is TestUtils {

    address operations = accountOne;

    MockLiquidStakingManager liquidStakingManager;
    StakingFundsVault vault;
    SavETHVault savETHPool;

    uint256 maxStakingAmountPerValidator;

    function maxETHDeposit(address _user, bytes[] memory _blsPubKeys) public {
        uint256[] memory amounts = new uint256[](_blsPubKeys.length);

        for (uint256 i; i < _blsPubKeys.length; ++i) {
            amounts[i] = maxStakingAmountPerValidator;
        }

        depositETH(_user, _blsPubKeys.length * maxStakingAmountPerValidator, amounts, _blsPubKeys);
    }

    function depositETH(address _user, uint256 _totalETH, uint256[] memory _amounts, bytes[] memory _blsPubKeys) public {
        require(_blsPubKeys.length > 0, "Empty array");

        // Give the user ETH
        vm.deal(_user, _totalETH);

        uint256 vaultBalanceBefore = address(vault).balance;

        // Impersonate the user and deposit ETH for all of the BLS keys
        vm.startPrank(_user);
        vault.batchDepositETHForStaking{value: _totalETH}(_blsPubKeys, _amounts);
        vm.stopPrank();

        // Check that the deposit worked
        assertEq(address(vault).balance - vaultBalanceBefore, _totalETH);
    }

    function setUp() public {
        factory = createMockLSDNFactory();
        liquidStakingManager = deployDefaultLiquidStakingNetwork(factory, admin);
        manager = liquidStakingManager;
        vault = liquidStakingManager.stakingFundsVault();
        savETHPool = liquidStakingManager.savETHVault();
        maxStakingAmountPerValidator = vault.maxStakingAmountPerValidator();

        // set up BLS keys required to initials registered
        MockAccountManager(factory.accountMan()).setLifecycleStatus(blsPubKeyOne, 1);
        MockAccountManager(factory.accountMan()).setLifecycleStatus(blsPubKeyTwo, 1);
        MockAccountManager(factory.accountMan()).setLifecycleStatus(blsPubKeyThree, 1);

        liquidStakingManager.setIsPartOfNetwork(blsPubKeyOne, true);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyTwo, true);
        liquidStakingManager.setIsPartOfNetwork(blsPubKeyThree, true);
    }

    function setSetupIsCorrect() public {
        assertEq(maxStakingAmountPerValidator, 4 ether);
    }

    // test for staking when user has sufficient funds
    function testFuzzDepositETHForStaking(
        address account,
        uint256 depositAmount
    ) public {
        uint256 revertReason;

        // setting max deposit limit to 20,000 ethers
        depositAmount = depositAmount% 20000 ether;

        if(revertReason == 0 && depositAmount < 0.001 ether) {
            revertReason = 2;
        }
        else if(revertReason == 0 && depositAmount % 0.001 ether != 0) {
            revertReason = 3;
        }
        else if(revertReason == 0 && depositAmount > 4 ether) {
            revertReason = 4;
        }

        vm.deal(account, depositAmount);
        vm.prank(account);

        if(revertReason == 0) {
            vault.depositETHForStaking{value: depositAmount}(blsPubKeyTwo, depositAmount);

            assertEq(account.balance, 0);

            LPToken token = vault.lpTokenForKnot(blsPubKeyTwo);
            assertEq(token.balanceOf(account), depositAmount);
            assertEq(vault.numberOfLPTokensIssued(), 1);
            assertEq(vault.KnotAssociatedWithLPToken(token), blsPubKeyTwo);
        }
        else if(revertReason == 2) {
            vm.expectRevert("Min amount not reached");
            vault.depositETHForStaking{value: depositAmount}(blsPubKeyTwo, depositAmount);
        }
        else if(revertReason == 3) {
            vm.expectRevert("Amount not multiple of min staking");
            vault.depositETHForStaking{value: depositAmount}(blsPubKeyTwo, depositAmount);
        }
        else {
            vm.expectRevert("Amount exceeds the staking limit for the validator");
            vault.depositETHForStaking{value: depositAmount}(blsPubKeyTwo, depositAmount);
        }
    }

    // test for batch staking when user has sufficient funds
    function testFuzzBatchDepositETHForStaking(
        address account,
        uint256[] memory depositAmounts
    ) public {
        uint256 length = depositAmounts.length;
        uint256 totalAmount;
        uint256 revertReason;

        bytes[] memory blsPublicKeys = new bytes[](length);

        vm.assume(account != address(0) && !Address.isContract(account));

        if(length == 0) {
            revertReason = 1;
        }

        for(uint256 i=0; i<length; ++i) {
            // setting max deposit limit to 20,000 ethers
            depositAmounts[i] = depositAmounts[i] % 20000 ether;
            totalAmount += depositAmounts[i];

            if(revertReason == 0 && depositAmounts[i] < 0.001 ether) {
                revertReason = 2;
            }
            else if (revertReason == 0 && depositAmounts[i] % 0.001 ether != 0) {
                revertReason = 3;
            } else if (revertReason == 0 && depositAmounts[i] > 4 ether) {
                revertReason = 4;
            }

            blsPublicKeys[i] = blsPubKeyTwo;
        }

        vm.deal(account, totalAmount);
        vm.prank(account);

        if(totalAmount > 4 ether && revertReason == 0 ) {
            revertReason = 4;
        }

        emit log_named_uint("totalAmount: ", totalAmount);

        if(revertReason == 0) {
            vault.batchDepositETHForStaking{value: 4 ether}(blsPublicKeys, depositAmounts);

            assertEq(account.balance, 0);

            LPToken token = vault.lpTokenForKnot(blsPubKeyTwo);
            assertEq(token.balanceOf(account), totalAmount);
            assertEq(vault.numberOfLPTokensIssued(), 1);
            assertEq(vault.KnotAssociatedWithLPToken(token), blsPubKeyTwo);
        }
        else if(revertReason == 1) {
            emit log_named_uint("revertReason: ", revertReason);
            vm.expectRevert("Empty arrays");
            vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
        }
        else if(revertReason == 2) {
            emit log_named_uint("revertReason: ", revertReason);
            vm.expectRevert("Min amount not reached");
            vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
        }
        else if(revertReason == 3) {
            emit log_named_uint("revertReason: ", revertReason);
            vm.expectRevert("Amount not multiple of min staking");
            vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
        }
        else if(revertReason == 4) {
            emit log_named_uint("revertReason: ", revertReason);
            vm.expectRevert("Amount exceeds the staking limit for the validator");
            vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
        }
        else {
            emit log_named_uint("revertReason: ", revertReason);
        }
    }

    // test for staking when user has insufficient funds
    function testFuzzDepositETHForStakingWithInsufficientFunds(
        address account,
        uint256 depositAmount
    ) public {
        if(account == address(0) || depositAmount == 0) return;

        // setting max deposit limit to 20,000 ethers
        depositAmount = 1 + depositAmount % 20000 ether;

        vm.deal(account, depositAmount - 1);
        vm.prank(account);

        vm.expectRevert();
        vault.depositETHForStaking{value: depositAmount}(blsPubKeyTwo, depositAmount);
    }

    // test for batch staking when user has insufficient funds
    function testFuzzBatchDepositETHForStakingWithInsufficientFunds(
        address account,
        uint256[] memory depositAmounts
    ) public {
        uint256 length = depositAmounts.length;
        uint256 totalAmount;
        uint256 revertReason;

        bytes[] memory blsPublicKeys = new bytes[](length);

        vm.assume(account != address(0) && !Address.isContract(account));

        if(length == 0) {
            revertReason = 1;
        }

        for(uint256 i=0; i<length; ++i) {
            // setting max deposit limit to 20,000 ethers
            depositAmounts[i] = depositAmounts[i] % 20000 ether;
            totalAmount += depositAmounts[i];

            if(revertReason == 0 && depositAmounts[i] < 0.001 ether) {
                revertReason = 2;
            }
            else if(revertReason == 0 && depositAmounts[i] % 0.001 ether != 0) {
                revertReason = 3;
            }
            else if(revertReason == 0 && totalAmount > 4 ether) {
                revertReason = 4;
            }

            blsPublicKeys[i] = blsPubKeyTwo;
        }

        vm.deal(account, totalAmount);
        vm.prank(account);

        if(revertReason == 0) {
            vault.batchDepositETHForStaking{value: totalAmount}(blsPublicKeys, depositAmounts);

            assertEq(account.balance, 0);

            LPToken token = vault.lpTokenForKnot(blsPubKeyTwo);
            assertEq(token.balanceOf(account), totalAmount);
            assertEq(vault.numberOfLPTokensIssued(), 1);
            assertEq(vault.KnotAssociatedWithLPToken(token), blsPubKeyTwo);
        }
        else if(revertReason == 1) {
            vm.expectRevert("Empty arrays");
            vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
        }
        else if(revertReason == 2) {
            vm.expectRevert("Min amount not reached");
            vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
        }
        else if(revertReason == 3) {
            vm.expectRevert("Amount not multiple of min staking");
            vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
        }
        else if(revertReason == 4) {
            vm.expectRevert("Amount exceeds the staking limit for the validator");
            vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
        }
    }

    // test for staking when user tries to deposit for BLS public key in different lifecycle statuses
    function testFuzzDepositETHForStakingWithBLSPublicKeysInDifferentStatuses(
        address account,
        uint256 depositAmount
    ) public {
        uint256 revertReason;

        // setting max deposit limit to 20,000 ethers
        depositAmount = depositAmount% 20000 ether;

        if(revertReason == 0 && depositAmount < 0.001 ether) {
            revertReason = 2;
        }
        else if(revertReason == 0 && depositAmount % 0.001 ether != 0) {
            revertReason = 3;
        } else if (revertReason == 0 && depositAmount > 4 ether) {
            revertReason = 4;
        }

        vm.deal(account, depositAmount);
        vm.prank(account);

        for(uint256 lifecycleStatus = 0; lifecycleStatus < 5; ++lifecycleStatus) {

            if(revertReason == 0) {
                vault.depositETHForStaking{value: depositAmount}(blsPubKeyTwo, depositAmount);

                assertEq(account.balance, 0);

                LPToken token = vault.lpTokenForKnot(blsPubKeyTwo);
                assertEq(token.balanceOf(account), depositAmount);
                assertEq(vault.numberOfLPTokensIssued(), 1);
                assertEq(vault.KnotAssociatedWithLPToken(token), blsPubKeyTwo);
            }
            else if(revertReason == 2) {
                vm.expectRevert("Min amount not reached");
                vault.depositETHForStaking{value: depositAmount}(blsPubKeyTwo, depositAmount);
            } else if (revertReason == 4) {
                vm.expectRevert("Amount exceeds the staking limit for the validator");
                vault.depositETHForStaking{value: depositAmount}(blsPubKeyTwo, depositAmount);
            }
            else {
                vm.expectRevert("Amount not multiple of min staking");
                vault.depositETHForStaking{value: depositAmount}(blsPubKeyTwo, depositAmount);
            }
        }
    }

    // test batch staking for BLS public keys which are in different stages of lifecycle
    function testFuzzBatchDepositETHForStakingWithBLSPublicKeysInDifferentStatuses(
        address account,
        uint256[] memory _depositAmounts
    ) public {
        uint256 length = _depositAmounts.length;
        uint256 totalAmount;
        uint256 count;
        uint256 MAX_DEPOSIT = 1 ether;

        bytes[] memory tempBlsPublicKeys = new bytes[](length);
        uint256[] memory tempDepositAmounts = new uint256[](length);

        LPToken token = vault.lpTokenForKnot(blsPubKeyTwo);
        if(address(token) == address(0)) {
            return;
        }
        uint256 totalTokensMinted = token.totalSupply();

        // test all cases with each of the lifecycle statuses
        for(uint256 lifecycleStatus=1; lifecycleStatus<5; ++lifecycleStatus) {
            emit log_named_uint("Lifecycle status", lifecycleStatus);

            MockAccountManager(factory.accountMan()).setLifecycleStatus(blsPubKeyTwo, lifecycleStatus);

            for(uint256 i=0; i<length; ++i) {

                // setting max deposit limit to MAX_DEPOSIT
                _depositAmounts[i] = _depositAmounts[i]  % MAX_DEPOSIT;

                if(_depositAmounts[i] < 0.001 ether) {
                    continue;
                }

                uint256 newAmount = (_depositAmounts[i] * 0.001 ether) % MAX_DEPOSIT;
                emit log_named_uint("newAmount", newAmount);

                // this condition makes sure that only eligible deposit amounts are pushed into the array
                // and hence batch deposit function is tested for case where all deposit values are correct
                // BLS public key array should be of same length as the accepted deposit amounts array
                // if(_depositAmounts[i] > 0.001 ether && _depositAmounts[i] % 0.001 ether == 0) {
                tempDepositAmounts[count] = newAmount;
                emit log_named_uint("tempDepositAmount", tempDepositAmounts[count]);
                tempBlsPublicKeys[count] = blsPubKeyTwo;
                totalAmount += tempDepositAmounts[i];
                ++count;
            }

            bytes[] memory blsPublicKeys = new bytes[](count);
            uint256[] memory depositAmounts = new uint256[](count);

            for(uint256 i=0; i<count; ++i) {
                // emit log_named_uint("deposit", depositAmounts[i]);
                blsPublicKeys[i] = tempBlsPublicKeys[i];
                depositAmounts[i] = tempDepositAmounts[i];
            }

            vm.deal(account, totalAmount);
            vm.prank(account);

            if(_depositAmounts.length < 1) {
                vm.expectRevert("Empty arrays");
                vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
            }
            if(blsPublicKeys.length < 1) {
                vm.expectRevert("Empty arrays");
                vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
            }
            else {
                if(lifecycleStatus != 1) {
                    emit log("Lifecycle status not 1");
                    vm.expectRevert("Lifecycle status must be one");
                    vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
                }
                else {
                    if(totalAmount + totalTokensMinted > 24 ether) {
                        emit log_named_uint("Total amount", totalAmount);
                        vm.expectRevert("Amount exceeds the staking limit for the validator");
                        vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
                    }
                    else if(totalAmount + totalTokensMinted > 0 ether) {
                        emit log_named_uint("Total amount", totalAmount);
                        vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);

                        assertEq(account.balance, 0);

                        assertEq(token.balanceOf(account), totalAmount);
                        assertEq(vault.numberOfLPTokensIssued(), 1);
                        assertEq(vault.KnotAssociatedWithLPToken(token), blsPubKeyTwo);

                    }
                    else {
                        emit log_named_uint("Total amount", totalAmount);
                        vm.expectRevert("Min amount not reached");
                        vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
                    }
                    if(account == address(0)) {
                        vm.expectRevert("ERC20: mint to the zero address");
                        vault.batchDepositETHForStaking(blsPublicKeys, depositAmounts);
                    }
                }
            }
        }
    }

    // Burn random amounts of LP tokens for BLS public keys
    function testFuzzBurnLPTokensForETHByBLS(uint256[] memory _amounts) public {
        address account = accountOne;
        uint256 revertReason;
        uint256 totalAmount;
        uint256 depositAmount = 4 ether;
        // uint256 exitLoop = 1;
        // uint256 newLength;

        if(account == address(0)) return;

        if(_amounts.length < 1 || (_amounts.length == 1 && _amounts[0] < 0.001 ether)) {
            return;
        }

        vm.deal(account, 4 ether);

        LPToken token = vault.lpTokenForKnot(blsPubKeyTwo);
        assertEq(address(token), address(0));

        vm.prank(account);
        vault.depositETHForStaking{value: depositAmount}(blsPubKeyTwo, depositAmount);
        assertEq(account.balance, 0);

        token = vault.lpTokenForKnot(blsPubKeyTwo);
        assertEq(token.balanceOf(account), depositAmount);
        assertEq(vault.numberOfLPTokensIssued(), 1);
        assertEq(vault.KnotAssociatedWithLPToken(token), blsPubKeyTwo);

        vm.warp(block.timestamp + 2 hours);

        uint256 value = 0.001 ether;
        uint256 len = 4 ether / value;
        
        // len = minimum(len, amounts.length)
        emit log_named_uint("initial len", len);
        if(_amounts.length < len) {
            len = _amounts.length;
        }
        emit log_named_uint("array length", _amounts.length);
        emit log_named_uint("final len", len);

        uint256[] memory amounts = new uint256[](len);
        bytes[] memory blsPublicKeys = new bytes[](len);

        for(uint256 i=0; i<len; ++i) {
            amounts[i] = value;
            blsPublicKeys[i] = blsPubKeyTwo;
            totalAmount += value;
        }

        vm.startPrank(account);

        if(len == 0) {
            vm.expectRevert("Empty arrays");
            vault.burnLPTokensForETHByBLS(blsPublicKeys, amounts);
            revertReason = 1;
        }

        if(revertReason == 0) {
            if(len > 1) {
                vm.expectRevert("Too new");
                vault.burnLPTokensForETHByBLS(blsPublicKeys, amounts);
            }
            else {
                vault.burnLPTokensForETHByBLS(blsPublicKeys, amounts);

                assertEq(token.balanceOf(account), 4 ether - totalAmount);
                assertEq(vault.numberOfLPTokensIssued(), 1);
                assertEq(vault.KnotAssociatedWithLPToken(token), blsPubKeyTwo);
            }
        }

        if(len == 1 && amounts[0] == 0) {
            vm.expectRevert("Not enough balance");
            vault.burnLPTokensForETHByBLS(blsPublicKeys, amounts);
        }
        vm.stopPrank();
    }

    function testFuzzClaimRewards(address account, uint256 arrayLength) public {
        // address account = accountOne;
        uint256 revertReason;
        uint256 totalAmount;
        uint256 depositAmount = 4 ether;

        vm.assume(arrayLength >= 1 && arrayLength <= 256 && account != address(0));
        vm.deal(address(vault), 75 ether);

        // if(account == address(0) || arrayLength < 1) return;

        vm.deal(account, 4 ether);

        LPToken token = vault.lpTokenForKnot(blsPubKeyTwo);
        assertEq(address(token), address(0));

        vm.prank(account);
        vault.depositETHForStaking{value: depositAmount}(blsPubKeyTwo, depositAmount);

        token = vault.lpTokenForKnot(blsPubKeyTwo);
        assertEq(token.balanceOf(account), depositAmount);
        assertEq(vault.numberOfLPTokensIssued(), 1);
        assertEq(vault.KnotAssociatedWithLPToken(token), blsPubKeyTwo);

        bytes[] memory blsPublicKeys = new bytes[](arrayLength);

        for(uint256 i=0; i<arrayLength; ++i) {
            blsPublicKeys[i] = blsPubKeyTwo;
            totalAmount = 0.2 ether * arrayLength;
        }

        vm.startPrank(account);

        if(arrayLength > 1) {
            if(liquidStakingManager.syndicate() == address(0)) {
                vm.expectRevert("Invalid configuration");
                vault.claimRewards(account, blsPublicKeys);
            }
            else {
                vm.expectRevert();
                vault.claimRewards(account, blsPublicKeys);
            }
        }
        else {
            if(liquidStakingManager.syndicate() == address(0)) {
                vm.expectRevert("Invalid configuration");
                vault.claimRewards(account, blsPublicKeys);
            }
            else {
                vault.claimRewards(account, blsPublicKeys);
                assertEq(account.balance, totalAmount);
                assertEq(token.balanceOf(account), depositAmount);
            }
        }

        vm.stopPrank();
    }

    function testFuzzClaimRewardsForMintedBLSPublicKey(address account, uint256 arrayLength) public {

        uint256 revertReason;
        uint256 totalAmount;
        uint256 depositAmount = 4 ether;

        vm.assume(
            arrayLength >= 1 && 
            arrayLength <= 256 && 
            account != address(0)&& 
            Address.isContract(account) == false
        );
        vm.deal(address(vault), 75 ether);

        // if(account == address(0) || arrayLength < 1) return;

        bytes[] memory blsPublicKeys = new bytes[](arrayLength);

        for(uint256 i=0; i<arrayLength; ++i) {
            vm.deal(account, 32 ether);
            blsPublicKeys[i] = blsPubKeyFour;
            // totalAmount = 0.2 ether * arrayLength;
        }

        depositStakeAndMintDerivativesForCustomAccountAndCustomNetwork(
            account, // node runner
            account, // fees and mev LP user
            account, // savETH LP user
            account, // user
            blsPubKeyFour, // bls public key
            liquidStakingManager, // LSM
            vault, // staking funds vault
            savETHPool
        );

        vm.startPrank(account);

        LPToken token = vault.lpTokenForKnot(blsPubKeyFour);
        assertEq(token.balanceOf(account), depositAmount);
        assertEq(vault.numberOfLPTokensIssued(), 1);
        assertEq(vault.KnotAssociatedWithLPToken(token), blsPubKeyFour);

        LPToken savETHToken = savETHPool.lpTokenForKnot(blsPubKeyFour);
        assertEq(savETHToken.balanceOf(account), 24 ether);
        assertEq(savETHPool.numberOfLPTokensIssued(), 1);
        assertEq(savETHPool.KnotAssociatedWithLPToken(savETHToken), blsPubKeyFour);

        uint256 lifecycleStatus = MockAccountManager(factory.accountMan()).blsPublicKeyToLifecycleStatus(blsPubKeyFour);
        assertEq(lifecycleStatus, 3);

        if(arrayLength > 1) {
            if(liquidStakingManager.syndicate() == address(0)) {
                vm.expectRevert("Invalid configuration");
                vault.claimRewards(account, blsPublicKeys);
            }
            else {
                vm.expectRevert(bytes4(keccak256("InactiveKnot()")));
                vault.claimRewards(account, blsPublicKeys);
            }
        }
        else {
            if(liquidStakingManager.syndicate() == address(0)) {
                vm.expectRevert("Invalid configuration");
                vault.claimRewards(account, blsPublicKeys);
            }
            else {
                vm.expectRevert(bytes4(keccak256("InactiveKnot()")));
                vault.claimRewards(account, blsPublicKeys);
                assertEq(account.balance, totalAmount);
                assertEq(token.balanceOf(account), 4 ether);
                assertEq(savETHToken.balanceOf(account), 24 ether);
            }
        }

        vm.stopPrank();
    }

    function testFuzzWithdrawETHAsRandomAccount(address account, address wallet, uint256 amount) public {

        vm.assume(account != address(0));
        vm.deal(address(vault), amount);
        
        // try withdrawing ETH from the pool as a random account
        vm.startPrank(account);

        uint256 poolBalance = address(vault).balance;

        if(account != address(liquidStakingManager)) {
            vm.expectRevert("Only network manager");
            vault.withdrawETH(wallet, amount);
        }
        else {
            if(amount < 4 ether) {
                vm.expectRevert("Amount cannot be less than 4 ether");
                vault.withdrawETH(wallet, amount);
            }
            else if(poolBalance < amount) {
                vm.expectRevert("Not enough ETH to withdraw");
                vault.withdrawETH(wallet, amount);
            }
            else if(wallet == address(0)) {
                vm.expectRevert("Zero address");
                vault.withdrawETH(wallet, amount);
            }
            else {
                // vm.expectRevert("Only network manager");
                uint256 ethFromLPsBefore = vault.totalETHFromLPs();
                uint256 walletBalanceBefore = wallet.balance;
                vault.withdrawETH(wallet, amount);
                uint256 ethFromLPsAfter = vault.totalETHFromLPs();
                uint256 walletBalanceAfter = wallet.balance;
                
                assertEq(ethFromLPsBefore - amount, ethFromLPsAfter);
                assertEq(walletBalanceBefore + amount, walletBalanceAfter);
            }
        }

        vm.stopPrank();
    }

    function testFuzzWithdrawETHAsLSM(address account, address wallet, uint256 amount) public {

        vm.deal(address(vault), amount);
        vm.assume(account != address(0) && amount <= 4 ether && !Address.isContract(account));
        
        // try withdrawing ETH from the pool as the LSM
        vm.startPrank(address(liquidStakingManager));

        uint256 poolBalance = address(vault).balance;
        emit log_named_uint("Pool balance: ", poolBalance);

        if(amount < 4 ether) {
            vm.expectRevert("Amount cannot be less than 4 ether");
            vault.withdrawETH(wallet, amount);
        }
        else if(poolBalance < amount) {
            vm.expectRevert("Not enough ETH to withdraw");
            vault.withdrawETH(wallet, amount);
        }
        else if(wallet == address(0)) {
            vm.expectRevert("Zero address");
            vault.withdrawETH(wallet, amount);
        }
        else {
            // checks for underflow
            uint256 ethFromLPsBefore = vault.totalETHFromLPs();
            emit log_named_uint("ethFromLPsBefore: ", ethFromLPsBefore);

            uint256 walletBalanceBefore = wallet.balance;
            emit log_named_uint("walletBalanceBefore: ", walletBalanceBefore);
            
            vm.expectRevert(stdError.arithmeticError);
            vault.withdrawETH(wallet, amount);

            uint256 ethFromLPsAfter = vault.totalETHFromLPs();
            uint256 walletBalanceAfter = wallet.balance;
            
            assertEq(ethFromLPsBefore, ethFromLPsAfter);
            assertEq(walletBalanceBefore, walletBalanceAfter);
        }

        vm.stopPrank();
        
        vm.deal(account, 5 ether);
        
        vm.prank(account);
        vault.depositETHForStaking{value: 4 ether}(blsPubKeyTwo, 4 ether);

        // assertEq(account.balance, 1 ether);

        LPToken token = vault.lpTokenForKnot(blsPubKeyTwo);
        assertEq(token.balanceOf(account), 4 ether);
        assertEq(vault.numberOfLPTokensIssued(), 1);
        assertEq(vault.KnotAssociatedWithLPToken(token), blsPubKeyTwo);

        // try withdrawing ETH from the pool as the LSM
        vm.startPrank(address(liquidStakingManager));

        poolBalance = address(vault).balance;
        emit log_named_uint("Pool balance: ", poolBalance);

        if(amount < 4 ether) {
            vm.expectRevert("Amount cannot be less than 4 ether");
            vault.withdrawETH(wallet, amount);
        }
        else if(poolBalance < amount) {
            vm.expectRevert("Not enough ETH to withdraw");
            vault.withdrawETH(wallet, amount);
        }
        else if(wallet == address(0)) {
            vm.expectRevert("Zero address");
            vault.withdrawETH(wallet, amount);
        }
        else {
            // checks for underflow
            uint256 ethFromLPsBefore = vault.totalETHFromLPs();
            emit log_named_uint("ethFromLPsBefore: ", ethFromLPsBefore);

            uint256 walletBalanceBefore = wallet.balance;
            emit log_named_uint("walletBalanceBefore: ", walletBalanceBefore);
            
            vault.withdrawETH(wallet, amount);

            uint256 ethFromLPsAfter = vault.totalETHFromLPs();
            uint256 walletBalanceAfter = wallet.balance;
            
            assertEq(ethFromLPsBefore - amount, ethFromLPsAfter);
            assertEq(walletBalanceBefore + amount, walletBalanceAfter);
        }

        vm.stopPrank();
    }

    function testFuzzUnstakeSyndicateSETHByBurningLP(address account, uint256 length, uint256 amount) public {

        uint256 revertReason;

        vm.assume(
            length >= 1 && 
            length <= 256 && 
            account != address(0) && 
            amount <= 4 ether &&
            !Address.isContract(account)
        );

        vm.deal(account, 32 ether);

        bytes[] memory blsPublicKeys = new bytes[](length);

        for(uint256 i=0; i<length; ++i) {
            blsPublicKeys[i] = blsPubKeyFour;
        }

        depositStakeAndMintDerivativesForCustomAccountAndCustomNetwork(
            account, // node runner
            account, // fees and mev LP user
            account, // savETH LP user
            account, // user
            blsPubKeyFour, // bls public key
            liquidStakingManager, // LSM
            vault, // staking funds vault
            savETHPool
        );

        // It takes 128 blocks to activate KNOT
        vm.roll(block.number + 500);

        vm.startPrank(account);

        LPToken token = vault.lpTokenForKnot(blsPubKeyFour);
        assertEq(token.balanceOf(account), 4 ether);
        assertEq(vault.numberOfLPTokensIssued(), 1);
        assertEq(vault.KnotAssociatedWithLPToken(token), blsPubKeyFour);

        uint256 lifecycleStatus = MockAccountManager(factory.accountMan()).blsPublicKeyToLifecycleStatus(blsPubKeyFour);
        assertEq(lifecycleStatus, 3);

        if(length > 1) {
            revertReason = 1;
        }
        else if(amount <= 0) {
            revertReason = 2;
        }
        else if(token.balanceOf(account) < amount) {
            revertReason = 3;
        }
        else if(amount < 0.001 ether) {
            revertReason = 4;
        }

        // write test conditions
        if(revertReason == 1) {
            vm.expectRevert("One unstake at a time");
            vault.unstakeSyndicateSETHByBurningLP(blsPublicKeys, amount);
        }
        else if(revertReason == 2) {
            vm.expectRevert("No amount specified");
            vault.unstakeSyndicateSETHByBurningLP(blsPublicKeys, amount);
        }
        else if(revertReason == 3) {
            vm.expectRevert("Not enough LP");
            vault.unstakeSyndicateSETHByBurningLP(blsPublicKeys, amount);
        }
        else if(revertReason == 4) {
            vm.expectRevert("Min transfer amount");
            vault.unstakeSyndicateSETHByBurningLP(blsPublicKeys, amount);
        }
        else {
            uint256 totalSharesBeforeBurning = vault.totalShares();

            address payable syndicate = payable(liquidStakingManager.syndicate());
            uint256 sETHStakedBalanceBeforeBurning = Syndicate(syndicate).sETHStakedBalanceForKnot(blsPubKeyFour, address(vault));
            uint256 sETHTotalStakeBeforeBurning = Syndicate(syndicate).sETHTotalStakeForKnot(blsPubKeyFour);
            
            vault.unstakeSyndicateSETHByBurningLP(blsPublicKeys, amount);

            assertEq(token.balanceOf(account), 4 ether - amount);
            assertEq(totalSharesBeforeBurning - vault.totalShares(), amount);

            uint256 sETHStakedBalanceAfterBurning = Syndicate(syndicate).sETHStakedBalanceForKnot(blsPubKeyFour, address(vault));
            uint256 sETHTotalStakeAfterBurning = Syndicate(syndicate).sETHTotalStakeForKnot(blsPubKeyFour);
            emit log_named_uint("sETHStakedBalanceBeforeBurning: ", sETHStakedBalanceBeforeBurning);
            emit log_named_uint("sETHStakedBalanceAfterBurning: ", sETHStakedBalanceAfterBurning);

            emit log_named_uint("sETHTotalStakeBeforeBurning: ", sETHTotalStakeBeforeBurning);
            emit log_named_uint("sETHTotalStakeAfterBurning: ", sETHTotalStakeAfterBurning);
            
            assertEq(sETHStakedBalanceBeforeBurning - sETHStakedBalanceAfterBurning, amount*3);
            assertEq(sETHTotalStakeBeforeBurning - sETHTotalStakeAfterBurning, amount*3);
        }

        vm.stopPrank();
    }

}