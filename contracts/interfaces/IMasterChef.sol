// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IMasterChef {
    function wethToken() external view returns (address);

    function protocolToken() external view returns (address);

    function yieldBooster() external view returns (address);

    function emergencyUnlock() external view returns (bool);

    function isUnlockOperator(address) external view returns (bool);

    function getPoolInfo(
        address _poolAddress
    )
        external
        view
        returns (
            address poolAddress,
            uint256 allocPoint,
            uint256 allocPointsWETH,
            uint256 lastRewardTime,
            uint256 reserve,
            uint256 reserveWETH,
            uint256 poolEmissionRate,
            uint256 poolEmissionRateWETH
        );

    function claimRewards() external returns (uint256 rewardAmount, uint256 amountWETH);
}
