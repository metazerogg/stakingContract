// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BasicToken is ERC20 {
    constructor() ERC20("BasicToken", "BasicTkn") {
        _mint(msg.sender, 100_000_000 * (10 ** uint256(decimals())));
    }
}
