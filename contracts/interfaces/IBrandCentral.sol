// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IBrandCentral {
    /// @notice Address of the contract managing list of restricted tickers
    function claimAuction() external view returns (address);

    /// @notice Allow the brand manager to set the building type associated with the brand
    function registerBuildingTypeToBrand(uint256 _brandTokenId, uint256 _buildingTypeId) external;
}