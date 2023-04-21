// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import { MockStakingFundsVault } from "../../../../contracts/testing/liquid-staking/MockStakingFundsVault.sol";
import { Receiver } from "./Receiver.sol";

contract CertoraMockStakingFundsVault is MockStakingFundsVault {
    function _transferETH(address _recipient, uint256 _amount) internal override {
        (bool result) = Receiver(payable(_recipient)).sendTo{value:_amount}();
        require(result, "Transfer failed");
    }

    function getTotalSupplyOfLPAssociatedWithBLSPubKey(
        bytes calldata _blsPubKey
    ) external view returns (uint256) {
        if (address(lpTokenForKnot[_blsPubKey]) == address(0)) return 0;
        return lpTokenForKnot[_blsPubKey].totalSupply();
    }
}