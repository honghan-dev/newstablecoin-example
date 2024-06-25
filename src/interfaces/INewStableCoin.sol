// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface INewStableCoin {
    /**
     * @notice Burns a specific amount of tokens.
     * @param amount The amount of tokens to be burned.
     * @dev Only the owner can call this function.
     */
    function burn(uint256 amount) external;

    /**
     * @notice Mints a specific amount of tokens to a specified address.
     * @param to The address to mint the tokens to.
     * @param amount The amount of tokens to be minted.
     * @return Returns true if the minting was successful.
     * @dev Only the owner can call this function.
     */
    function mint(address to, uint256 amount) external returns (bool);

    /**
     * @notice Transfers tokens from one address to another.
     * @param from The address from which to transfer tokens.
     * @param to The address to which the tokens will be transferred.
     * @param amount The amount of tokens to be transferred.
     * @return Returns true if the transfer was successful.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
