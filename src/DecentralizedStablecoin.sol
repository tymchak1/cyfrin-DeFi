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

/*
 * @title DecentralizedStablecoin
 * @author Anastasia Tymchak
 * Collateral: Exogenous (ETH & BTC)
 * Relative Stability: Pegged to USD
 * 
 * This is the contract meant to be governed by DSCEngine. This contract is just an ERC20
 implementation of our stablecoin system.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Errors} from "./Errors.sol";

contract DecentralizedStablecoin is ERC20, ERC20Burnable, Ownable, Errors {
    constructor(
        address initialOwner
    ) ERC20("DecentralizedStablecoin", "DSC") Ownable(initialOwner) {}

    function mint(
        address _to,
        uint256 _amount
    ) public onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStablecoin_NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStablecoin_MustBeMoreThatZero();
        }
        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        // can't burn 0
        if (_amount <= 0) {
            revert DecentralizedStablecoin_MustBeMoreThatZero();
        }
        // can't burn more that balance
        if (_amount > balance) {
            revert DecentralizedStablecoin_AmountExceedsBalance();
        }
        super.burn(_amount);
    }
}
