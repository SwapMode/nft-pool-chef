// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IProtocolToken.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/INFTPool.sol";
import "./interfaces/IYieldBooster.sol";

contract MasterChef is Ownable, IMasterChef {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Info of each NFT pool
    struct PoolInfo {
        uint256 allocPoints; // How many allocation points assigned to this NFT pool
        uint256 allocPointsWETH;
        uint256 lastRewardTime; // Last time that distribution to this NFT pool occurs
        uint256 reserve; // Pending rewards to distribute to the NFT pool
        uint256 reserveWETH;
    }

    // Used by pools to release all their locks at once in case of emergency
    bool public override emergencyUnlock;

    address public treasury;

    IProtocolToken private immutable _protocolToken;

    IERC20 public immutable WETH;

    // Contract address handling yield boosts
    IYieldBooster private _yieldBooster;

    // Total allocation points. Must be the sum of all allocation points in all pools
    uint256 public totalAllocPoints;
    uint256 public totalAllocPointsWETH;

    // The time at which farming starts
    uint256 public immutable startTime;

    // WETH overall reward rate
    uint256 public wethPerSecond;

    // Pools' information
    mapping(address => PoolInfo) private _poolInfo;

    // All existing pool addresses
    EnumerableSet.AddressSet private _pools;

    // Only contains pool addresses w/ allocPoints > 0
    EnumerableSet.AddressSet private _activePools;

    // Addresses allowed to forcibly unlock locked spNFTs
    EnumerableSet.AddressSet private _unlockOperators;

    // ============================================= //
    // =================== EVENTS ================== //
    // ============================================= //

    event ClaimRewards(address indexed poolAddress, uint256 amount, uint256 amountWETH);
    event PoolAdded(address indexed poolAddress, uint256 allocPoint);
    event PoolSet(address indexed poolAddress, uint256 allocPoint, uint256 allocPointsWETH);
    event SetYieldBooster(address previousYieldBooster, address newYieldBooster);
    event PoolUpdated(
        address indexed poolAddress,
        uint256 reserve,
        uint256 reserveWETH,
        uint256 lastRewardTime
    );
    event SetEmergencyUnlock(bool emergencyUnlock);
    event WethRateUpdated(uint256 rate);

    error ZeroAddress();
    error PoolNotExists();
    error PoolAlreadyExists();
    error InvalidStartTime();

    // ================================================ //
    // =================== MODIFIERS ================== //
    // ================================================ //

    /*
     * @dev Check if a pool exists
     */
    modifier validatePool(address poolAddress) {
        if (!_pools.contains(poolAddress)) revert PoolNotExists();
        _;
    }

    constructor(
        IProtocolToken _mainToken,
        address _treasury,
        address _weth,
        uint256 _wethPerSecond,
        uint256 _startTime,
        IYieldBooster _boost
    ) {
        // yield boost can be unset
        if (address(_mainToken) == address(0) || _treasury == address(0) || _weth == address(0)) {
            revert ZeroAddress();
        }

        if (block.timestamp < _startTime && _startTime >= _mainToken.lastEmissionTime()) {
            revert InvalidStartTime();
        }

        _protocolToken = _mainToken;
        WETH = IERC20(_weth);
        treasury = _treasury;
        wethPerSecond = _wethPerSecond;
        startTime = _startTime;
        _yieldBooster = _boost;

        _unlockOperators.add(_treasury);
        _unlockOperators.add(msg.sender);

        // Register under the same SFS NFT
        _mainToken.feeShareContract().assign(_mainToken.feeShareTokenId());
    }

    // ================================================== //
    // =================== PUBLIC VIEW ================== //
    // ================================================== //

    function protocolToken() external view override returns (address) {
        return address(_protocolToken);
    }

    function wethToken() external view override returns (address) {
        return address(WETH);
    }

    /**
     * @dev Returns main token emission rate from main chef (allocated to this contract)
     */
    function emissionRates() public view returns (uint256 mainRate, uint256 wethRate) {
        mainRate = _protocolToken.masterEmissionRate();
        wethRate = wethPerSecond;
    }

    function yieldBooster() external view override returns (address) {
        return address(_yieldBooster);
    }

    /**
     * @dev Returns the number of available pools
     */
    function poolsLength() external view returns (uint256) {
        return _pools.length();
    }

    /**
     * @dev Returns a pool from its "index"
     */
    function getPoolAddressByIndex(uint256 index) external view returns (address) {
        if (index >= _pools.length()) return address(0);
        return _pools.at(index);
    }

    /**
     * @dev Returns the number of active pools
     */
    function activePoolsLength() external view returns (uint256) {
        return _activePools.length();
    }

    /**
     * @dev Returns an active pool from its "index"
     */
    function getActivePoolAddressByIndex(uint256 index) external view returns (address) {
        if (index >= _activePools.length()) return address(0);
        return _activePools.at(index);
    }

    /**
     * @dev Returns data of a given pool
     */
    function getPoolInfo(
        address _poolAddress
    )
        external
        view
        override
        returns (
            address poolAddress,
            uint256 allocPoints,
            uint256 allocPointsWETH,
            uint256 lastRewardTime,
            uint256 reserve,
            uint256 reserveWETH,
            uint256 poolEmissionRate,
            uint256 poolEmissionRateWETH
        )
    {
        PoolInfo memory pool = _poolInfo[_poolAddress];

        poolAddress = _poolAddress;
        allocPoints = pool.allocPoints;
        allocPointsWETH = pool.allocPointsWETH;
        lastRewardTime = pool.lastRewardTime;
        reserve = pool.reserve;
        reserveWETH = pool.reserveWETH;

        if (totalAllocPoints == 0 && totalAllocPointsWETH == 0) {
            poolEmissionRate = 0;
            poolEmissionRateWETH = 0;
        } else {
            (uint256 mainRate, uint256 wethRate) = emissionRates();

            poolEmissionRate = (mainRate * allocPoints) / totalAllocPoints;
            poolEmissionRateWETH = (wethRate * allocPointsWETH) / totalAllocPointsWETH;
        }
    }

    function isUnlockOperator(address account) external view override returns (bool) {
        return account == owner() || _unlockOperators.contains(account);
    }

    // ================================================================= //
    // =================== EXTERNAL PUBLIC FUNCTIONS  ================== //
    // ================================================================= //

    /**
     * @dev Updates rewards states of the given pool to be up-to-date
     */
    function updatePool(address nftPool) external validatePool(nftPool) {
        _updatePool(nftPool);
    }

    /**
     * @dev Updates rewards states for all pools
     *
     * Be careful of gas spending
     */
    function massUpdatePools() external {
        _massUpdatePools();
    }

    /**
     * @dev Transfer to a pool its pending rewards in reserve, can only be called by the NFT pool contract itself
     */
    function claimRewards() external override returns (uint256 rewardAmount, uint256 amountWETH) {
        // Check if caller is a listed pool
        if (!_pools.contains(msg.sender)) {
            return (0, 0);
        }

        _updatePool(msg.sender);

        // Updates caller's reserve
        PoolInfo storage pool = _poolInfo[msg.sender];
        rewardAmount = pool.reserve;
        amountWETH = pool.reserveWETH;

        if (rewardAmount == 0 && amountWETH == 0) {
            return (0, 0);
        }

        pool.reserve = 0;
        pool.reserveWETH = 0;

        emit ClaimRewards(msg.sender, rewardAmount, amountWETH);

        _safeRewardsTransfer(_protocolToken, msg.sender, rewardAmount);
        _safeRewardsTransfer(WETH, msg.sender, amountWETH);
    }

    // =============================================== //
    // =================== INTERNAL ================== //
    // =============================================== //

    /**
     * @dev Safe token transfer function, in case rounding error causes pool to not have enough tokens
     */
    function _safeRewardsTransfer(
        IERC20 token,
        address to,
        uint256 amount
    ) internal returns (uint256 effectiveAmount) {
        uint256 tokenBalance = token.balanceOf(address(this));

        if (amount > tokenBalance) {
            amount = tokenBalance;
        }

        token.safeTransfer(to, amount);

        return amount;
    }

    /**
     * @dev Updates rewards states of the given pool to be up-to-date
     *
     * Pool should be validated prior to calling this
     */
    function _updatePool(address poolAddress) internal {
        PoolInfo storage pool = _poolInfo[poolAddress];

        uint256 currentBlockTimestamp = block.timestamp;
        uint256 lastRewardTime = pool.lastRewardTime; // gas saving

        if (currentBlockTimestamp <= lastRewardTime) {
            return;
        }

        uint256 allocPoints = pool.allocPoints; // gas saving
        uint256 allocPointsWETH = pool.allocPointsWETH;

        // Do not allocate rewards if pool is not active
        if ((allocPoints > 0 || allocPointsWETH > 0) && INFTPool(poolAddress).hasDeposits()) {
            // calculate how much rewards are expected to be received for this pool
            (uint256 mainRate, uint256 wethRate) = emissionRates();
            uint256 duration = currentBlockTimestamp - lastRewardTime;
            uint256 mainRewards = (duration * mainRate * allocPoints) / totalAllocPoints;
            uint256 wethRewards = (duration * wethRate * allocPointsWETH) / totalAllocPointsWETH;

            // Claim expected rewards from the token
            // Use returned effective minted amount instead of expected amount
            (mainRewards) = _protocolToken.claimMasterRewards(mainRewards);

            pool.reserve += mainRewards;
            pool.reserveWETH += wethRewards;
        }

        pool.lastRewardTime = currentBlockTimestamp;

        emit PoolUpdated(poolAddress, pool.reserve, pool.reserveWETH, currentBlockTimestamp);
    }

    /**
     * @dev Updates rewards states for all pools
     *
     * Be careful of gas spending
     */
    function _massUpdatePools() internal {
        uint256 length = _activePools.length();
        for (uint256 index = 0; index < length; ++index) {
            _updatePool(_activePools.at(index));
        }
    }

    // ============================================ //
    // =================== ADMIN ================== //
    // ============================================ //

    function setWethRewardRate(uint256 wethRate) external onlyOwner {
        wethPerSecond = wethRate;
        emit WethRateUpdated(wethRate);
    }

    /**
     * @dev Set YieldBooster contract's address
     *
     * Must only be called by the owner
     */
    function setYieldBooster(IYieldBooster yieldBooster_) external onlyOwner {
        require(
            address(yieldBooster_) != address(0),
            "setYieldBooster: cannot be set to zero address"
        );
        emit SetYieldBooster(address(_yieldBooster), address(yieldBooster_));
        _yieldBooster = yieldBooster_;
    }

    /**
     * @dev Set emergency unlock status for all pools
     *
     * Must only be called by the owner
     */
    function setEmergencyUnlock(bool emergencyUnlock_) external onlyOwner {
        emergencyUnlock = emergencyUnlock_;
        emit SetEmergencyUnlock(emergencyUnlock);
    }

    /**
     * @dev Adds a new pool
     * param withUpdate should be set to true every time it's possible
     *
     * Must only be called by the owner
     */
    function add(
        INFTPool nftPool,
        uint256 allocPoints,
        uint256 allocPointsWETH,
        bool withUpdate
    ) external onlyOwner {
        address poolAddress = address(nftPool);
        if (_pools.contains(poolAddress)) revert PoolAlreadyExists();

        if (allocPoints > 0 || allocPointsWETH > 0) {
            if (withUpdate) {
                // Update all pools if new pool allocPoint > 0
                _massUpdatePools();
            }
            _activePools.add(poolAddress);
        }

        // Update lastRewardTime if startTime has already been passed
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;

        // Update totalAllocPoint with the new pool's points
        totalAllocPoints += allocPoints;
        totalAllocPointsWETH += allocPointsWETH;

        _pools.add(poolAddress);

        _poolInfo[poolAddress] = PoolInfo({
            allocPoints: allocPoints,
            allocPointsWETH: allocPointsWETH,
            lastRewardTime: lastRewardTime,
            reserve: 0,
            reserveWETH: 0
        });

        emit PoolAdded(poolAddress, allocPoints);
    }

    /**
     * @dev Updates configuration on existing pool
     * param withUpdate should be set to true every time it's possible
     *
     * Must only be called by the owner
     */
    function set(
        address poolAddress,
        uint256 allocPoints,
        uint256 allocPointsWETH,
        bool withUpdate
    ) external validatePool(poolAddress) onlyOwner {
        PoolInfo storage pool = _poolInfo[poolAddress];

        uint256 prevAllocPoints = pool.allocPoints;
        uint256 prevAllocPointsWETH = pool.allocPointsWETH;

        if (withUpdate) {
            _massUpdatePools();
        }

        _updatePool(poolAddress);

        // Update (pool's and total) allocPoints
        pool.allocPoints = allocPoints;
        pool.allocPointsWETH = allocPointsWETH;

        totalAllocPoints = (totalAllocPoints - prevAllocPoints) + allocPoints;
        totalAllocPointsWETH = (totalAllocPointsWETH - prevAllocPointsWETH) + allocPointsWETH;

        // If request is activating the pool
        if (
            (prevAllocPoints == 0 && allocPoints > 0) ||
            (prevAllocPointsWETH == 0 && allocPointsWETH > 0)
        ) {
            _activePools.add(poolAddress);
        } else if (
            prevAllocPoints > 0 &&
            allocPoints == 0 &&
            (prevAllocPointsWETH > 0 && allocPointsWETH == 0)
        ) {
            // Request is deactivating pool
            _activePools.remove(poolAddress);
        }

        emit PoolSet(poolAddress, allocPoints, allocPointsWETH);
    }

    function addUnlockOperator(address account) external onlyOwner {
        _unlockOperators.add(account);
    }

    function removeUnlockOperator(address account) external onlyOwner {
        _unlockOperators.remove(account);
    }
}
