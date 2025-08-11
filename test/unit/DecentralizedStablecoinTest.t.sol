// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {Errors} from "../../src/Errors.sol";

contract DecentralizedStablecoinTest is Test, Errors {
    DecentralizedStablecoin dsc;
    address owner = address(1);
    address user = address(2);

    function setUp() public {
        vm.prank(owner);
        dsc = new DecentralizedStablecoin();
    }

    // mint tests
    function testMint_Success() public {
        vm.prank(owner);
        bool result = dsc.mint(user, 100 ether);
        assertTrue(result);
        assertEq(dsc.balanceOf(user), 100 ether);
    }

    function testMint_RevertIfZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DecentralizedStablecoin_NotZeroAddress.selector));
        dsc.mint(address(0), 100 ether);
    }

    function testMint_RevertIfAmountZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DecentralizedStablecoin_MustBeMoreThanZero.selector));
        dsc.mint(user, 0);
    }

    function testMint_RevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        dsc.mint(user, 100 ether);
    }

    // burn tests
    function testBurn_Success() public {
        vm.prank(owner);
        dsc.mint(owner, 100 ether);

        vm.prank(owner);
        dsc.burn(50 ether);

        assertEq(dsc.balanceOf(owner), 50 ether);
    }

    function testBurn_RevertIfAmountZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DecentralizedStablecoin_MustBeMoreThanZero.selector));
        dsc.burn(0);
    }

    function testBurn_RevertIfAmountExceedsBalance() public {
        vm.prank(owner);
        dsc.mint(owner, 100 ether);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DecentralizedStablecoin_AmountExceedsBalance.selector));
        dsc.burn(200 ether);
    }

    function testBurn_RevertIfNotOwner() public {
        vm.prank(owner);
        dsc.mint(owner, 100 ether);

        vm.prank(user);
        vm.expectRevert();
        dsc.burn(50 ether);
    }
}
