// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

/**
 * @title DecentralizedStablecoin
 * @author Anastasia Tymchak
 * @notice ERC20 stablecoin governed by DSCEngine, pegged to USD, and collateralized by exogenous  assets (ETH & BTC)
 * @dev This contract implements the stablecoin logic and is intended to be governed by DSCEngine
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Errors} from "./Errors.sol";

contract DecentralizedStablecoin is ERC20Burnable, Ownable, Errors {
    /**
     * @notice Initializes the DecentralizedStablecoin token with name and symbol, and sets the deployer as the owner
     */
    constructor() ERC20("DecentralizedStablecoin", "DSC") Ownable(msg.sender) {}

    /**
     * @notice Mints new DSC tokens to the specified address. Only callable by the owner
     * @param _to The address to receive the newly minted DSC tokens
     * @param _amount The amount of DSC tokens to mint
     * @return success Returns true if minting succeeds
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool success) {
        if (_to == address(0)) {
            revert DecentralizedStablecoin_NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStablecoin_MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    /**
     * @notice Burns DSC tokens from the owner's balance. Only callable by the owner
     * @param _amount The amount of DSC tokens to burn
     * @dev Reverts if the amount is zero or exceeds the owner's balance
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        // can't burn 0
        if (_amount <= 0) {
            revert DecentralizedStablecoin_MustBeMoreThanZero();
        }
        // can't burn more that balance
        if (_amount > balance) {
            revert DecentralizedStablecoin_AmountExceedsBalance();
        }
        super.burn(_amount);
    }
}
