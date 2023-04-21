// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OwnableSmartWallet} from "../../../../contracts/smart-wallet/OwnableSmartWallet.sol";
import {OwnableSmartWalletFactory} from "../../../../contracts/smart-wallet/OwnableSmartWalletFactory.sol";
import {IOwnableSmartWallet} from "../../../../contracts/smart-wallet/interfaces/IOwnableSmartWallet.sol";
import {IOwnableSmartWalletFactoryEvents} from "../../../../contracts/smart-wallet/interfaces/IOwnableSmartWalletFactory.sol";

import { TestUtils } from "../../../utils/TestUtils.sol";

import { LENDER, BORROWER, DUMB_ADDRESS} from "./constants.sol";
import {ExecutableMock} from "../../../../contracts/testing/ExecutableMock.sol";

contract OwnableSmartWalletFactoryTest is
    TestUtils,
    IOwnableSmartWalletFactoryEvents
{

    OwnableSmartWalletFactory walletFactory;
    address targetWallet;

    event TestEvent(address indexed addr);

    function setUp() public {
        walletFactory = new OwnableSmartWalletFactory();
    }

    /// @dev [OSWF-1]: createWallet creates new wallet correctly and emits events
    function test_OSWF_01_createWallet_correctly_clones_wallet_and_emits_event()
        public
    {
        vm.expectEmit(false, true, false, false);
        emit WalletCreated(address(0), LENDER);

        vm.prank(LENDER);
        address newWallet = walletFactory.createWallet();

        assertEq(
            IOwnableSmartWallet(newWallet).owner(),
            LENDER,
            "Owner is not correct"
        );

        vm.expectEmit(false, true, false, false);
        emit WalletCreated(address(0), BORROWER);

        newWallet = walletFactory.createWallet(BORROWER);

        assertEq(
            IOwnableSmartWallet(newWallet).owner(),
            BORROWER,
            "Owner is not correct"
        );
    }

    /// @dev [OSWF-2]: constructor creates correct contract and fires event
    function test_OSWF_02_constructor_is_correct() public {
        vm.expectEmit(false, false, false, false);
        emit WalletCreated(address(0), address(0));

        OwnableSmartWalletFactory newFactory = new OwnableSmartWalletFactory();

        assertEq(
            OwnableSmartWallet(payable(newFactory.masterWallet())).owner(),
            address(newFactory),
            "New factoty master wallet owner incorrect"
        );
    }
}
