pragma solidity ^0.8.13;

contract Sender {
    function sendETH(address _recipient, uint256 _amount) external {
        payable(_recipient).transfer(_amount);
    }

    function getBalance(address _account) public view returns (uint256) {
        return _account.balance;
    }
}