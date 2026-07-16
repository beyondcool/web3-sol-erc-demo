// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title MyToken
 * @notice 一个带 ERC-2612 permit 功能的简单代币
 */
contract MyToken is ERC20Permit {
    constructor(uint256 initialSupply) ERC20("MyToken", "MTK") ERC20Permit("MyToken") {
        _mint(msg.sender, initialSupply);
    }
}