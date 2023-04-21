// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import { TestUtils } from "../../../utils/TestUtils.sol";

uint256 constant INTEREST_RATE = RAY / (100 * 3600 * 24 * 365);

address constant DUMB_ADDRESS = 0xC4375B7De8af5a38a93548eb8453a498222C4fF2;
address constant DUMB_ADDRESS2 = 0x93548eB8453a498222C4FF2C4375b7De8af5A38a;
address constant DUMB_ADDRESS3 = 0x822293548EB8453A49c4fF2c4375B7DE8AF5a38A;

address constant LENDER = 0x498222C4Ff2C4393548eb8453a75B7dE8AF5A38a;
address constant BORROWER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
address constant DEPLOYER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

uint256 constant EXPECTED_ETH2_DEPOSIT_DURATION = 72 * 60 * 60;
uint256 constant RAY = 1e27;
uint256 constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60;

uint256 constant TIME_UNTIL_STUCK = 30 * 24 * 60 * 60;

uint256 constant DEPOSIT_AMOUNT = 32 ether;
uint256 constant DETH_MINTED_AMOUNT = 24 ether;

contract Roles is TestUtils {

    constructor() {
        vm.label(LENDER, "LENDER");
        vm.label(BORROWER, "BORROWER");
        vm.label(DEPLOYER, "DEPLOYER");

        vm.label(DUMB_ADDRESS, "DUMB_ADDRESS");
    }
}
