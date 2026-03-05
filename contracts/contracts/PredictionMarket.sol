// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PredictionMarket is Ownable, ReentrancyGuard {

    IERC20 public usdc;
    address public treasury;
    address public factory;

    enum MarketState { OPEN, LOCKED, PENDING, DISPUTED, RESOLVED, CANCELLED }

    struct Market {
        string question;
        string category;
        string competition;
        uint256 eventStartTime;
        uint256 resolutionDeadline;
        uint256 initialLiquidity;
        uint256 yesPool;
        uint256 noPool;
        uint256 totalShares;
        bool result;
        MarketState state;
    }

    struct Position {
        uint256 yesShares;
        uint256 noShares;
        uint256 yesAmountPaid;
        uint256 noAmountPaid;
    }

    uint256 public marketCount;
    uint256 public constant MINIMUM_POOL = 500 * 1e6;
    uint256 public constant OVERROUND = 103;
    uint256 public constant CASHOUT_FEE = 10;
    uint256 public constant MAX_CASHOUT_PERCENT = 70;
    uint256 public constant CASHOUT_CLOSE_BEFORE = 30 minutes;
    uint256 public constant RESOLUTION_TIMEOUT = 7 days;
    uint256 public constant PROTOCOL_FEE_PERCENT = 3;

    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => Position)) public positions;
    mapping(uint256 => uint256) public totalCashedOutYes;
    mapping(uint256 => uint256) public totalCashedOutNo;

    event MarketCreated(uint256 indexed marketId, string question, uint256 initialLiquidity, uint256 timestamp);
    event SharesPurchased(uint256 indexed marketId, address indexed user, bool isYes, uint256 amount, uint256 shares, uint256 timestamp);
    event CashoutProcessed(uint256 indexed marketId, address indexed user, bool isYes, uint256 payout, uint256 timestamp);
    event ResultProposed(uint256 indexed marketId, bool result, uint256 timestamp);
    event MarketResolved(uint256 indexed marketId, bool result, uint256 timestamp);
    event MarketCancelled(uint256 indexed marketId, uint256 timestamp);
    event WinningsClaimed(uint256 indexed marketId, address indexed user, uint256 amount, uint256 timestamp);
    event RefundClaimed(uint256 indexed marketId, address indexed user, uint256 amount, uint256 timestamp);
    event MarketPaused(uint256 indexed marketId, uint256 timestamp);
    event MarketUnpaused(uint256 indexed marketId, uint256 timestamp);

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    modifier marketExists(uint256 _marketId) {
        require(_marketId < marketCount, "Market does not exist");
        _;
    }

    modifier inState(uint256 _marketId, MarketState _state) {
        require(markets[_marketId].state == _state, "Invalid market state");
        _;
    }

    constructor(address _usdc, address _treasury, address _factory) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        treasury = _treasury;
        factory = _factory;
    }

    function createMarket(
        string calldata _question,
        string calldata _category,
        string calldata _competition,
        uint256 _eventStartTime,
        uint256 _resolutionDeadline,
        uint256 _initialLiquidity
    ) external onlyOwner nonReentrant {
        require(_eventStartTime > block.timestamp, "Event must be in the future");
        require(_resolutionDeadline > _eventStartTime, "Resolution must be after event start");
        require(_initialLiquidity > 0, "Initial liquidity required");
        require(usdc.transferFrom(msg.sender, address(this), _initialLiquidity), "Liquidity transfer failed");

        uint256 marketId = marketCount++;
        markets[marketId] = Market({
            question: _question,
            category: _category,
            competition: _competition,
            eventStartTime: _eventStartTime,
            resolutionDeadline: _resolutionDeadline,
            initialLiquidity: _initialLiquidity,
            yesPool: _initialLiquidity / 2,
            noPool: _initialLiquidity / 2,
            totalShares: 0,
            result: false,
            state: MarketState.OPEN
        });

        emit MarketCreated(marketId, _question, _initialLiquidity, block.timestamp);
    }

    function buyShares(uint256 _marketId, bool _isYes, uint256 _amount) 
        external 
        nonReentrant 
        marketExists(_marketId) 
        inState(_marketId, MarketState.OPEN) 
    {
        Market storage market = markets[_marketId];
        require(block.timestamp < market.eventStartTime, "Event already started");
        require(_amount > 0, "Amount must be greater than zero");
        require(usdc.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        uint256 totalPool = market.yesPool + market.noPool;
        uint256 shares;

        if (_isYes) {
            shares = (_amount * totalPool * 100) / (market.yesPool * OVERROUND);
            market.yesPool += _amount;
            positions[_marketId][msg.sender].yesShares += shares;
            positions[_marketId][msg.sender].yesAmountPaid += _amount;
        } else {
            shares = (_amount * totalPool * 100) / (market.noPool * OVERROUND);
            market.noPool += _amount;
            positions[_marketId][msg.sender].noShares += shares;
            positions[_marketId][msg.sender].noAmountPaid += _amount;
        }

        market.totalShares += shares;
        emit SharesPurchased(_marketId, msg.sender, _isYes, _amount, shares, block.timestamp);
    }

    function calculatePayout(uint256 _marketId, bool _isYes, uint256 _amount) 
        external 
        view 
        marketExists(_marketId) 
        returns (uint256 shares, uint256 potentialPayout) 
    {
        Market storage market = markets[_marketId];
        uint256 totalPool = market.yesPool + market.noPool;

        if (_isYes) {
            shares = (_amount * totalPool * 100) / (market.yesPool * OVERROUND);
            potentialPayout = (shares * market.noPool) / market.totalShares + _amount;
        } else {
            shares = (_amount * totalPool * 100) / (market.noPool * OVERROUND);
            potentialPayout = (shares * market.yesPool) / market.totalShares + _amount;
        }
    }

    function cashout(uint256 _marketId, bool _isYes) 
        external 
        nonReentrant 
        marketExists(_marketId) 
        inState(_marketId, MarketState.OPEN) 
    {
        Market storage market = markets[_marketId];
        require(block.timestamp < market.eventStartTime - CASHOUT_CLOSE_BEFORE, "Cashout window closed");

        Position storage position = positions[_marketId][msg.sender];
        uint256 shares;
        uint256 amountPaid;

        if (_isYes) {
            require(position.yesShares > 0, "No YES shares to cashout");
            shares = position.yesShares;
            amountPaid = position.yesAmountPaid;
            uint256 newCashedOut = totalCashedOutYes[_marketId] + amountPaid;
            require(newCashedOut <= (market.yesPool * MAX_CASHOUT_PERCENT) / 100, "Cashout limit reached");
            totalCashedOutYes[_marketId] = newCashedOut;
            position.yesShares = 0;
            position.yesAmountPaid = 0;
            market.yesPool -= amountPaid;
            market.totalShares -= shares;
        } else {
            require(position.noShares > 0, "No NO shares to cashout");
            shares = position.noShares;
            amountPaid = position.noAmountPaid;
            uint256 newCashedOut = totalCashedOutNo[_marketId] + amountPaid;
            require(newCashedOut <= (market.noPool * MAX_CASHOUT_PERCENT) / 100, "Cashout limit reached");
            totalCashedOutNo[_marketId] = newCashedOut;
            position.noShares = 0;
            position.noAmountPaid = 0;
            market.noPool -= amountPaid;
            market.totalShares -= shares;
        }

        uint256 payout = (amountPaid * (100 - CASHOUT_FEE)) / 100;
        require(usdc.transfer(msg.sender, payout), "Cashout transfer failed");
        emit CashoutProcessed(_marketId, msg.sender, _isYes, payout, block.timestamp);
    }

    function lockMarket(uint256 _marketId) 
        external 
        onlyOwner 
        marketExists(_marketId) 
        inState(_marketId, MarketState.OPEN) 
    {
        Market storage market = markets[_marketId];
        require(block.timestamp >= market.eventStartTime, "Event not started yet");
        uint256 userFunds = (market.yesPool + market.noPool) - market.initialLiquidity;
        require(userFunds >= MINIMUM_POOL, "Minimum pool not reached");
        markets[_marketId].state = MarketState.LOCKED;
    }

    function proposeResult(uint256 _marketId, bool _result) 
        external 
        onlyOwner 
        marketExists(_marketId) 
        inState(_marketId, MarketState.LOCKED) 
    {
        markets[_marketId].result = _result;
        markets[_marketId].state = MarketState.PENDING;
        emit ResultProposed(_marketId, _result, block.timestamp);
    }

    function resolveMarket(uint256 _marketId) 
        external 
        onlyOwner 
        marketExists(_marketId) 
        inState(_marketId, MarketState.PENDING) 
    {
        markets[_marketId].state = MarketState.RESOLVED;
        emit MarketResolved(_marketId, markets[_marketId].result, block.timestamp);
    }

    function claimWinnings(uint256 _marketId) 
        external 
        nonReentrant 
        marketExists(_marketId) 
        inState(_marketId, MarketState.RESOLVED) 
    {
        Market storage market = markets[_marketId];
        Position storage position = positions[_marketId][msg.sender];

        uint256 userShares;
        uint256 losingPool;
        uint256 winningPool;
        uint256 amountPaid;

        if (market.result) {
            userShares = position.yesShares;
            amountPaid = position.yesAmountPaid;
            losingPool = market.noPool;
            winningPool = market.yesPool;
            position.yesShares = 0;
            position.yesAmountPaid = 0;
        } else {
            userShares = position.noShares;
            amountPaid = position.noAmountPaid;
            losingPool = market.yesPool;
            winningPool = market.noPool;
            position.noShares = 0;
            position.noAmountPaid = 0;
        }

        require(userShares > 0, "No winning shares");

        uint256 totalWinningShares = market.totalShares;
        uint256 profitFromLosingPool = (userShares * losingPool) / totalWinningShares;
        uint256 protocolFee = (profitFromLosingPool * PROTOCOL_FEE_PERCENT) / 100;
        uint256 userProfit = profitFromLosingPool - protocolFee;
        uint256 totalPayout = amountPaid + userProfit;

        require(usdc.transfer(msg.sender, totalPayout), "Payout transfer failed");
        require(usdc.transfer(treasury, protocolFee), "Fee transfer failed");

        emit WinningsClaimed(_marketId, msg.sender, totalPayout, block.timestamp);
    }

    function claimRefund(uint256 _marketId) 
        external 
        nonReentrant 
        marketExists(_marketId) 
        inState(_marketId, MarketState.CANCELLED) 
    {
        Position storage position = positions[_marketId][msg.sender];
        uint256 refundAmount = position.yesAmountPaid + position.noAmountPaid;
        require(refundAmount > 0, "Nothing to refund");

        position.yesShares = 0;
        position.noShares = 0;
        position.yesAmountPaid = 0;
        position.noAmountPaid = 0;

        require(usdc.transfer(msg.sender, refundAmount), "Refund transfer failed");
        emit RefundClaimed(_marketId, msg.sender, refundAmount, block.timestamp);
    }

    function cancelMarket(uint256 _marketId) 
        external 
        onlyOwner 
        marketExists(_marketId) 
    {
        MarketState state = markets[_marketId].state;
        require(
            state == MarketState.OPEN || 
            state == MarketState.LOCKED || 
            state == MarketState.PENDING,
            "Cannot cancel resolved market"
        );
        markets[_marketId].state = MarketState.CANCELLED;
        uint256 liquidity = markets[_marketId].initialLiquidity;
        require(usdc.transfer(owner(), liquidity), "Liquidity return failed");
        emit MarketCancelled(_marketId, block.timestamp);
    }

    function pauseMarket(uint256 _marketId) 
        external 
        onlyOwner 
        marketExists(_marketId) 
        inState(_marketId, MarketState.OPEN) 
    {
        markets[_marketId].state = MarketState.LOCKED;
        emit MarketPaused(_marketId, block.timestamp);
    }

    function unpauseMarket(uint256 _marketId) 
        external 
        onlyOwner 
        marketExists(_marketId) 
        inState(_marketId, MarketState.LOCKED) 
    {
        markets[_marketId].state = MarketState.OPEN;
        emit MarketUnpaused(_marketId, block.timestamp);
    }

    function getMarket(uint256 _marketId) 
        external 
        view 
        marketExists(_marketId) 
        returns (Market memory) 
    {
        return markets[_marketId];
    }

    function getPosition(uint256 _marketId, address _user) 
        external 
        view 
        marketExists(_marketId) 
        returns (Position memory) 
    {
        return positions[_marketId][_user];
    }

    function getYesPrice(uint256 _marketId) 
        external 
        view 
        marketExists(_marketId) 
        returns (uint256) 
    {
        Market storage market = markets[_marketId];
        uint256 totalPool = market.yesPool + market.noPool;
        return (market.yesPool * OVERROUND) / totalPool;
    }

    function getNoPrice(uint256 _marketId) 
        external 
        view 
        marketExists(_marketId) 
        returns (uint256) 
    {
        Market storage market = markets[_marketId];
        uint256 totalPool = market.yesPool + market.noPool;
        return (market.noPool * OVERROUND) / totalPool;
    }
}