// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20Burnable, ERC20} from "openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

/**
 * @title Decentralized Stable coin
 * @author Han
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 *
 * This contract is the ERC20 implementation of stablecoin system. It is governed by the DSCEngine.
 */
contract NewStableCoin is ERC20Burnable, Ownable {
    error NewStableCoin__MustBeMoreThanZero();
    error NewStableCoin__BurnAmountExceedsBalance();
    error NewStableCoin__NotZeroAddress();

    constructor() ERC20("NewStableCoin", "NSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        // Can't burn 0 tokens
        if (_amount <= 0) {
            revert NewStableCoin__MustBeMoreThanZero();
        }
        // Can't burn more than they own
        if (balance < _amount) {
            revert NewStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        // Can't mint to zero address
        if (_to == address(0)) {
            revert NewStableCoin__NotZeroAddress();
        }
        // Can't mint if given amount is less than zero
        if (_amount <= 0) {
            revert NewStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
