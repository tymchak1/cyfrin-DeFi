// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract Errors {
    error DecentralizedStablecoin_MustBeMoreThanZero();
    error DecentralizedStablecoin_AmountExceedsBalance();
    error DecentralizedStablecoin_NotZeroAddress();

    error DSCEngine_NotZeroAddress();
    error DSCEngine_MustBeMoreThanZero();
    error DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine_TokenIsNotAllowed();
    error DSCEngine_TransferFailed();
    error DSCEngine_BreaksHealthFactor();
    error DSCEngine_MintFailed();
    error DSCEngine_UserHealthFactorIsNotBroken();
    error DSCEngine_HealthFactorNotImproved();
    error DSCEngine_InsufficientCollateralBalance();
    error DSCEngine_RedeemValueGreaterThanCollateral();
    error DSCEngine_CollateralValueOverflow();
}
