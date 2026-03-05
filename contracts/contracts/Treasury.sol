// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Treasury is Ownable {
    IERC20 public usdc;

    uint256 public totalRevenue;

    event FundsReceived(uint256 amount, uint256 timestamp);
    event FundsWithdrawn(address indexed to, uint256 amount, uint256 timestamp);

    constructor(address _usdc) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
    }

    function receiveFunds(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than zero");
        require(usdc.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        totalRevenue += _amount;
        emit FundsReceived(_amount, block.timestamp);
    }

    function withdraw(address _to, uint256 _amount) external onlyOwner {
        require(_amount > 0, "Amount must be greater than zero");
        require(usdc.balanceOf(address(this)) >= _amount, "Insufficient balance");
        require(usdc.transfer(_to, _amount), "Transfer failed");
        emit FundsWithdrawn(_to, _amount, block.timestamp);
    }

    function getBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}