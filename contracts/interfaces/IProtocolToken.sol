// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IFeeSharing.sol";

interface IProtocolToken is IERC20 {
    function lastEmissionTime() external view returns (uint256);

    function claimMasterRewards(uint256 amount) external returns (uint256 effectiveAmount);

    function masterEmissionRate() external view returns (uint256);

    function feeShareContract() external view returns (IFeeSharing);

    function feeShareTokenId() external view returns (uint256);
}
