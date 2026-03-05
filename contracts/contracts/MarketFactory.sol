// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MarketFactory is Ownable {
    
    address public treasury;
    address public usdc;

    address[] public allMarkets;
    
    mapping(address => bool) public approvedCreators;
    mapping(address => address[]) public creatorMarkets;

    event MarketCreated(address indexed market, address indexed creator, string question, uint256 timestamp);
    event CreatorApproved(address indexed creator, uint256 timestamp);
    event CreatorRemoved(address indexed creator, uint256 timestamp);

    modifier onlyApprovedCreator() {
        require(approvedCreators[msg.sender] || msg.sender == owner(), "Not an approved creator");
        _;
    }

    constructor(address _usdc, address _treasury) Ownable(msg.sender) {
        usdc = _usdc;
        treasury = _treasury;
    }

    function approveCreator(address _creator) external onlyOwner {
        require(_creator != address(0), "Invalid address");
        require(!approvedCreators[_creator], "Already approved");
        approvedCreators[_creator] = true;
        emit CreatorApproved(_creator, block.timestamp);
    }

    function removeCreator(address _creator) external onlyOwner {
        require(approvedCreators[_creator], "Not an approved creator");
        approvedCreators[_creator] = false;
        emit CreatorRemoved(_creator, block.timestamp);
    }

    function registerMarket(address _market, string calldata _question) external onlyApprovedCreator {
        require(_market != address(0), "Invalid market address");
        allMarkets.push(_market);
        creatorMarkets[msg.sender].push(_market);
        emit MarketCreated(_market, msg.sender, _question, block.timestamp);
    }

    function getAllMarkets() external view returns (address[] memory) {
        return allMarkets;
    }

    function getCreatorMarkets(address _creator) external view returns (address[] memory) {
        return creatorMarkets[_creator];
    }

    function getTotalMarkets() external view returns (uint256) {
        return allMarkets.length;
    }
}
