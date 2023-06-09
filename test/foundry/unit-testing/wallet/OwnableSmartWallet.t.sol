// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {OwnableSmartWallet} from "../../../../contracts/smart-wallet/OwnableSmartWallet.sol";
import {IOwnableSmartWalletEvents} from "../../../../contracts/smart-wallet/interfaces/IOwnableSmartWallet.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { TestUtils } from "../../../utils/TestUtils.sol";

import {LENDER, BORROWER, DUMB_ADDRESS} from "./constants.sol";
import {ExecutableMock} from "../../../../contracts/testing/ExecutableMock.sol";

contract OwnableSmartWalletTest is TestUtils, IOwnableSmartWalletEvents {

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    OwnableSmartWallet wallet;
    ExecutableMock callableContract;

    function setUp() public {
        address implementation = address(new OwnableSmartWallet());

        ERC1967Proxy proxy = new ERC1967Proxy(
            implementation,
            abi.encodeCall(
                OwnableSmartWallet(payable(address(implementation))).initialize,
                (LENDER)
            )
        );

        wallet = OwnableSmartWallet(payable(address(proxy)));

        callableContract = new ExecutableMock();
    }

    /// @dev [OSW-1]: Initializer sets correct owner and can't be called twice
    function test_OSW_01_initializer_sets_correct_value_and_can_be_called_once()
        public
    {
        assertEq(wallet.owner(), LENDER, "Wallet owner incorrect");

        vm.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        wallet.initialize(DUMB_ADDRESS);
    }

    /// @dev [OSW-2]: setApproval sets value correctly, emits event and reverts on non-owner
    function test_OSW_02_setApproval_has_access_control_and_sets_value_correctly()
        public
    {
        vm.expectEmit(true, true, false, true);
        emit TransferApprovalChanged(LENDER, BORROWER, true);

        vm.prank(LENDER);
        wallet.setApproval(BORROWER, true);

        assertTrue(
            wallet.isTransferApproved(LENDER, BORROWER),
            "Value was not set"
        );

        vm.expectEmit(true, true, false, true);
        emit TransferApprovalChanged(LENDER, BORROWER, false);

        vm.prank(LENDER);
        wallet.setApproval(BORROWER, false);

        assertTrue(
            !wallet.isTransferApproved(LENDER, BORROWER),
            "Value was not set"
        );
    }

    /// @dev [OSW-2A]: setApproval reverts on zero-address
    function test_OSW_02A_setApproval_reverts_on_zero_to_address() public {
        vm.expectRevert(
            bytes("OwnableSmartWallet: Approval cannot be set for zero address")
        );
        vm.prank(LENDER);
        wallet.setApproval(address(0), true);
    }

    /// @dev [OSW-3]: isTransferApproved returns true for same address
    function test_OSW_03_isTransferApproved_returns_true_for_same_address()
        public
    {
        assertTrue(
            wallet.isTransferApproved(LENDER, LENDER),
            "Transfer not approved from address to itself"
        );
    }

    /// @dev [OSW-4]: transferOwnership reverts unless owner or approved address calls
    function test_OSW_04_transferOwnership_reverts_unless_authorized() public {
        vm.expectRevert(bytes("OwnableSmartWallet: Transfer is not allowed"));
        vm.prank(BORROWER);
        wallet.transferOwnership(BORROWER);
    }

    /// @dev [OSW-5]: transferOwnership works for owner/approvedAddress, sets correct value and emits event
    function test_OSW_05_transferOwnership_is_correct() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(LENDER, BORROWER);

        vm.prank(LENDER);
        wallet.transferOwnership(BORROWER);

        assertEq(wallet.owner(), BORROWER, "Owner was not set correctly");

        vm.prank(BORROWER);
        wallet.setApproval(LENDER, true);

        vm.expectEmit(true, true, false, true);
        emit TransferApprovalChanged(BORROWER, LENDER, false);

        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(BORROWER, DUMB_ADDRESS);

        vm.prank(LENDER);
        wallet.transferOwnership(DUMB_ADDRESS);

        assertEq(wallet.owner(), DUMB_ADDRESS, "Owner was not set correctly");

        assertTrue(
            !wallet.isTransferApproved(BORROWER, LENDER),
            "Approval was not removed"
        );
    }

    /// @dev [OSW-6]: execute passes correct data to correct contract
    function test_OSW_06_execute_is_correct() public {
        vm.deal(LENDER, 2000);

        vm.expectCall(address(callableContract), "foo");

        vm.prank(LENDER);
        wallet.execute{value: 1000}(address(callableContract), "foo");

        assertEq(
            string(callableContract.getCallData()),
            "foo",
            "Incorrect calldata was passed"
        );

        assertEq(
            callableContract.getValue(),
            1000,
            "Incorrect value was passed"
        );

        vm.prank(LENDER);
        wallet.execute{value: 1000}(address(callableContract), "foobar", 250);

        assertEq(
            string(callableContract.getCallData()),
            "foobar",
            "Incorrect calldata was passed"
        );

        assertEq(
            callableContract.getValue(),
            250,
            "Incorrect value was passed"
        );

        vm.prank(LENDER);
        wallet.execute(address(callableContract), "foobar");

        assertEq(callableContract.getValue(), 0, "Incorrect value was passed");
    }

    /// @dev [OSW-6A]: execute reverts for non-owner
    function test_OSW_06A_execute_reverts_for_non_owner() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(BORROWER);
        wallet.execute(address(callableContract), "foo");

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(BORROWER);
        wallet.execute(address(callableContract), "foo", 1000);
    }
}
