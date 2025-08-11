// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract FailingERC20Mock is ERC20Mock {
    bool public shouldFailTransfer;
    bool public shouldFailTransferFrom;

    constructor() ERC20Mock() {}

    function setShouldFailTransfer(bool _shouldFail) external {
        shouldFailTransfer = _shouldFail;
    }

    function setShouldFailTransferFrom(bool _shouldFail) external {
        shouldFailTransferFrom = _shouldFail;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldFailTransfer) return false;
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldFailTransferFrom) return false;
        return super.transferFrom(from, to, amount);
    }
}
