// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

contract CourtRegistry is Ownable {

    uint256 public constant MAX_JURORS = 100;

    enum JurorStatus { Active, Warned, Removed }

    struct Juror {
        address wallet;
        uint256 totalVotes;
        uint256 majorityVotes;
        uint256 minorityVotes;
        uint256 totalEarnings;
        JurorStatus status;
        uint256 registeredAt;
    }

    uint256 public totalJurors;
    address[] public jurorList;

    mapping(address => Juror) public jurors;
    mapping(address => bool) public isRegistered;

    event JurorApproved(address indexed juror, uint256 timestamp);
    event JurorWarned(address indexed juror, uint256 timestamp);
    event JurorRemoved(address indexed juror, uint256 timestamp);
    event JurorStatsUpdated(address indexed juror, bool wasMajority, uint256 earnings, uint256 timestamp);

    modifier jurorExists(address _juror) {
        require(isRegistered[_juror], "Juror not registered");
        _;
    }

    constructor() Ownable(msg.sender) {}

    function approveJuror(address _juror) external onlyOwner {
        require(_juror != address(0), "Invalid address");
        require(!isRegistered[_juror], "Already registered");
        require(totalJurors < MAX_JURORS, "Maximum jurors reached");

        jurors[_juror] = Juror({
            wallet: _juror,
            totalVotes: 0,
            majorityVotes: 0,
            minorityVotes: 0,
            totalEarnings: 0,
            status: JurorStatus.Active,
            registeredAt: block.timestamp
        });

        isRegistered[_juror] = true;
        jurorList.push(_juror);
        totalJurors++;

        emit JurorApproved(_juror, block.timestamp);
    }

    function warnJuror(address _juror) external onlyOwner jurorExists(_juror) {
        require(jurors[_juror].status == JurorStatus.Active, "Juror not active");
        jurors[_juror].status = JurorStatus.Warned;
        emit JurorWarned(_juror, block.timestamp);
    }

    function removeJuror(address _juror) external onlyOwner jurorExists(_juror) {
        require(jurors[_juror].status != JurorStatus.Removed, "Already removed");
        jurors[_juror].status = JurorStatus.Removed;
        totalJurors--;
        emit JurorRemoved(_juror, block.timestamp);
    }

    function updateJurorStats(
        address _juror,
        bool _wasMajority,
        uint256 _earnings
    ) external onlyOwner jurorExists(_juror) {
        Juror storage juror = jurors[_juror];
        juror.totalVotes++;
        if (_wasMajority) {
            juror.majorityVotes++;
        } else {
            juror.minorityVotes++;
        }
        juror.totalEarnings += _earnings;
        emit JurorStatsUpdated(_juror, _wasMajority, _earnings, block.timestamp);
    }

    function isActiveJuror(address _juror) external view returns (bool) {
        return isRegistered[_juror] && jurors[_juror].status == JurorStatus.Active;
    }

    function getJuror(address _juror) external view jurorExists(_juror) returns (Juror memory) {
        return jurors[_juror];
    }

    function getAllJurors() external view returns (address[] memory) {
        return jurorList;
    }

    function getActiveJurors() external view returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < jurorList.length; i++) {
            if (jurors[jurorList[i]].status == JurorStatus.Active) {
                activeCount++;
            }
        }

        address[] memory activeJurors = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < jurorList.length; i++) {
            if (jurors[jurorList[i]].status == JurorStatus.Active) {
                activeJurors[index++] = jurorList[i];
            }
        }
        return activeJurors;
    }
}