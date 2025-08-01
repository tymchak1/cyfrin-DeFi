// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract Errors {
    error DecentralizedStablecoin_MustBeMoreThatZero();
    error DecentralizedStablecoin_AmountExceedsBalance();
    error DecentralizedStablecoin_NotZeroAddress();

    error DSCEngine_NotZeroAddress();
    error DSCEngine_MustBeMoreThatZero();
    error DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine_TokenIsNotAllowed();
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine_MintFailed();
}
