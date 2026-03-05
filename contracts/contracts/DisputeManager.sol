// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICourtRegistry {
    function getActiveJurors() external view returns (address[] memory);
    function isActiveJuror(address _juror) external view returns (bool);
    function updateJurorStats(address _juror, bool _wasMajority, uint256 _earnings) external;
}

interface IPredictionMarket {
    function resolveMarket(uint256 _marketId) external;
    function proposeResult(uint256 _marketId, bool _result) external;
}

contract DisputeManager is Ownable, ReentrancyGuard {

    IERC20 public usdc;
    ICourtRegistry public courtRegistry;
    IPredictionMarket public predictionMarket;
    address public treasury;

    uint256 public constant PROPOSAL_BOND = 1000 * 1e6;
    uint256 public constant DISPUTE_BOND = 1000 * 1e6;
    uint256 public constant SPORTS_DISPUTE_WINDOW = 2 hours;
    uint256 public constant POLITICS_DISPUTE_WINDOW = 72 hours;
    uint256 public constant VOTING_WINDOW = 24 hours;
    uint256 public constant VOTING_EXTENSION = 12 hours;
    uint256 public constant MIN_VOTES_REQUIRED = 30;
    uint256 public constant JURORS_PER_CASE = 50;
    uint256 public constant MAJORITY_VOTER_REWARD_PERCENT = 40;
    uint256 public constant TREASURY_PERCENT = 50;
    uint256 public constant WINNING_SIDE_PERCENT = 10;

    enum DisputeState { PROPOSED, DISPUTED, VOTING, RESOLVED }
    enum MarketCategory { SPORTS, POLITICS, CRYPTO, WEATHER }

    struct Proposal {
        uint256 marketId;
        address proposer;
        bool proposedResult;
        uint256 proposalTime;
        uint256 disputeWindowEnd;
        uint256 bond;
        DisputeState state;
        MarketCategory category;
    }

    struct Dispute {
        uint256 proposalId;
        address disputer;
        uint256 disputeTime;
        uint256 votingWindowEnd;
        uint256 bond;
        uint256 yesVotes;
        uint256 noVotes;
        bool finalResult;
        bool resolved;
    }

    struct Vote {
        bytes32 commitHash;
        bool revealed;
        bool vote;
        bool committed;
    }

    uint256 public proposalCount;
    uint256 public disputeCount;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => address[]) public selectedJurors;
    mapping(uint256 => mapping(address => Vote)) public votes;
    mapping(uint256 => mapping(address => bool)) public isSelectedJuror;
    mapping(uint256 => uint256) public marketProposal;

    event ResultProposed(uint256 indexed proposalId, uint256 indexed marketId, bool result, address proposer, uint256 timestamp);
    event ResultDisputed(uint256 indexed disputeId, uint256 indexed proposalId, address disputer, uint256 timestamp);
    event JurorsSelected(uint256 indexed disputeId, uint256 jurorCount, uint256 timestamp);
    event VoteCommitted(uint256 indexed disputeId, address indexed juror, uint256 timestamp);
    event VoteRevealed(uint256 indexed disputeId, address indexed juror, bool vote, uint256 timestamp);
    event DisputeResolved(uint256 indexed disputeId, bool finalResult, uint256 timestamp);
    event ProposalAccepted(uint256 indexed proposalId, bool result, uint256 timestamp);
    event RewardDistributed(address indexed juror, uint256 amount, uint256 timestamp);

    constructor(
        address _usdc,
        address _courtRegistry,
        address _predictionMarket,
        address _treasury
    ) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        courtRegistry = ICourtRegistry(_courtRegistry);
        predictionMarket = IPredictionMarket(_predictionMarket);
        treasury = _treasury;
    }

    function proposeResult(
        uint256 _marketId,
        bool _result,
        MarketCategory _category
    ) external nonReentrant {
        require(usdc.transferFrom(msg.sender, address(this), PROPOSAL_BOND), "Bond transfer failed");

        uint256 disputeWindow = _category == MarketCategory.POLITICS
            ? POLITICS_DISPUTE_WINDOW
            : SPORTS_DISPUTE_WINDOW;

        uint256 proposalId = proposalCount++;
        proposals[proposalId] = Proposal({
            marketId: _marketId,
            proposer: msg.sender,
            proposedResult: _result,
            proposalTime: block.timestamp,
            disputeWindowEnd: block.timestamp + disputeWindow,
            bond: PROPOSAL_BOND,
            state: DisputeState.PROPOSED,
            category: _category
        });

        marketProposal[_marketId] = proposalId;
        emit ResultProposed(proposalId, _marketId, _result, msg.sender, block.timestamp);
    }

    function disputeResult(uint256 _proposalId) external nonReentrant {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.state == DisputeState.PROPOSED, "Not in proposed state");
        require(block.timestamp <= proposal.disputeWindowEnd, "Dispute window closed");
        require(usdc.transferFrom(msg.sender, address(this), DISPUTE_BOND), "Bond transfer failed");

        uint256 disputeId = disputeCount++;
        disputes[disputeId] = Dispute({
            proposalId: _proposalId,
            disputer: msg.sender,
            disputeTime: block.timestamp,
            votingWindowEnd: block.timestamp + VOTING_WINDOW,
            bond: DISPUTE_BOND,
            yesVotes: 0,
            noVotes: 0,
            finalResult: false,
            resolved: false
        });

        proposal.state = DisputeState.DISPUTED;
        _selectJurors(disputeId);

        emit ResultDisputed(disputeId, _proposalId, msg.sender, block.timestamp);
    }

    function _selectJurors(uint256 _disputeId) internal {
        address[] memory activeJurors = courtRegistry.getActiveJurors();
        require(activeJurors.length >= MIN_VOTES_REQUIRED, "Not enough active jurors");

        uint256 count = activeJurors.length < JURORS_PER_CASE
            ? activeJurors.length
            : JURORS_PER_CASE;

        for (uint256 i = 0; i < count; i++) {
            uint256 randomIndex = uint256(keccak256(abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                i,
                _disputeId
            ))) % activeJurors.length;

            address selected = activeJurors[randomIndex];
            if (!isSelectedJuror[_disputeId][selected]) {
                selectedJurors[_disputeId].push(selected);
                isSelectedJuror[_disputeId][selected] = true;
            }
        }

        emit JurorsSelected(_disputeId, selectedJurors[_disputeId].length, block.timestamp);
    }

    function commitVote(uint256 _disputeId, bytes32 _commitHash) external {
        require(isSelectedJuror[_disputeId][msg.sender], "Not a selected juror");
        require(!votes[_disputeId][msg.sender].committed, "Already committed");
        require(block.timestamp <= disputes[_disputeId].votingWindowEnd, "Voting window closed");

        votes[_disputeId][msg.sender].commitHash = _commitHash;
        votes[_disputeId][msg.sender].committed = true;

        emit VoteCommitted(_disputeId, msg.sender, block.timestamp);
    }

    function revealVote(uint256 _disputeId, bool _vote, bytes32 _secret) external {
        require(isSelectedJuror[_disputeId][msg.sender], "Not a selected juror");
        require(votes[_disputeId][msg.sender].committed, "Vote not committed");
        require(!votes[_disputeId][msg.sender].revealed, "Already revealed");
        require(block.timestamp > disputes[_disputeId].votingWindowEnd, "Voting still open");

        bytes32 expectedHash = keccak256(abi.encodePacked(_vote, _secret, msg.sender));
        require(votes[_disputeId][msg.sender].commitHash == expectedHash, "Invalid reveal");

        votes[_disputeId][msg.sender].revealed = true;
        votes[_disputeId][msg.sender].vote = _vote;

        if (_vote) {
            disputes[_disputeId].yesVotes++;
        } else {
            disputes[_disputeId].noVotes++;
        }

        emit VoteRevealed(_disputeId, msg.sender, _vote, block.timestamp);
    }

    function resolveDispute(uint256 _disputeId) external onlyOwner nonReentrant {
        Dispute storage dispute = disputes[_disputeId];
        require(!dispute.resolved, "Already resolved");
        require(block.timestamp > dispute.votingWindowEnd, "Voting still open");

        uint256 totalVotes = dispute.yesVotes + dispute.noVotes;
        require(totalVotes >= MIN_VOTES_REQUIRED, "Not enough votes");

        Proposal storage proposal = proposals[dispute.proposalId];
        bool majorityVotedYes = dispute.yesVotes > dispute.noVotes;
        dispute.finalResult = majorityVotedYes;
        dispute.resolved = true;
        proposal.state = DisputeState.RESOLVED;

        bool proposerWon = majorityVotedYes == proposal.proposedResult;
        uint256 losingBond = DISPUTE_BOND;

        uint256 treasuryAmount = (losingBond * TREASURY_PERCENT) / 100;
        uint256 voterRewardPool = (losingBond * MAJORITY_VOTER_REWARD_PERCENT) / 100;
        uint256 winningSideReward = (losingBond * WINNING_SIDE_PERCENT) / 100;

        require(usdc.transfer(treasury, treasuryAmount), "Treasury transfer failed");

        if (proposerWon) {
            require(usdc.transfer(proposal.proposer, PROPOSAL_BOND + winningSideReward), "Proposer reward failed");
        } else {
            require(usdc.transfer(dispute.disputer, DISPUTE_BOND + winningSideReward), "Disputer reward failed");
        }

        _distributeVoterRewards(_disputeId, majorityVotedYes, voterRewardPool);

        predictionMarket.resolveMarket(proposal.marketId);

        emit DisputeResolved(_disputeId, majorityVotedYes, block.timestamp);
    }

    function _distributeVoterRewards(
        uint256 _disputeId,
        bool _majorityVote,
        uint256 _rewardPool
    ) internal {
        address[] memory jurors = selectedJurors[_disputeId];
        uint256 majorityCount = 0;

        for (uint256 i = 0; i < jurors.length; i++) {
            Vote storage v = votes[_disputeId][jurors[i]];
            if (v.revealed && v.vote == _majorityVote) {
                majorityCount++;
            }
        }

        if (majorityCount == 0) return;

        uint256 rewardPerJuror = _rewardPool / majorityCount;

        for (uint256 i = 0; i < jurors.length; i++) {
            Vote storage v = votes[_disputeId][jurors[i]];
            bool wasMajority = v.revealed && v.vote == _majorityVote;
            courtRegistry.updateJurorStats(jurors[i], wasMajority, wasMajority ? rewardPerJuror : 0);

            if (wasMajority) {
                require(usdc.transfer(jurors[i], rewardPerJuror), "Juror reward failed");
                emit RewardDistributed(jurors[i], rewardPerJuror, block.timestamp);
            }
        }
    }

    function acceptProposal(uint256 _proposalId) external onlyOwner nonReentrant {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.state == DisputeState.PROPOSED, "Not in proposed state");
        require(block.timestamp > proposal.disputeWindowEnd, "Dispute window still open");

        proposal.state = DisputeState.RESOLVED;

        require(usdc.transfer(proposal.proposer, PROPOSAL_BOND), "Bond return failed");
        predictionMarket.resolveMarket(proposal.marketId);

        emit ProposalAccepted(_proposalId, proposal.proposedResult, block.timestamp);
    }

    function extendVotingWindow(uint256 _disputeId) external onlyOwner {
        Dispute storage dispute = disputes[_disputeId];
        require(!dispute.resolved, "Already resolved");
        uint256 totalVotes = dispute.yesVotes + dispute.noVotes;
        require(totalVotes < MIN_VOTES_REQUIRED, "Enough votes already");
        dispute.votingWindowEnd += VOTING_EXTENSION;
    }

    function getSelectedJurors(uint256 _disputeId) external view returns (address[] memory) {
        return selectedJurors[_disputeId];
    }

    function getVote(uint256 _disputeId, address _juror) external view returns (Vote memory) {
        return votes[_disputeId][_juror];
    }

    function generateCommitHash(
        bool _vote,
        bytes32 _secret,
        address _juror
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(_vote, _secret, _juror));
    }
}