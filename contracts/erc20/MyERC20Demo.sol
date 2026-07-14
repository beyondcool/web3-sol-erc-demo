// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// 导入 OpenZeppelin 的 ERC20 合约和 Ownable 合约
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MyERC20Demo
 * @dev 一个简单的 ERC20 代币教学示例
 */
contract MyERC20Demo is ERC20, Ownable {

    /**
     * @dev 构造函数，在部署合约时执行一次
     * @param initialSupply 初始发行的代币总量
     */
    constructor(uint256 initialSupply) ERC20("MyERC20Demo", "MED") Ownable(msg.sender) {
        // 调用 ERC20 的 _mint 函数，将初始代币全部铸造给合约部署者
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }

    /**
     * @dev 允许合约所有者铸造新的代币
     * @param to 接收新铸造代币的地址
     * @param amount 铸造的数量
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev 允许合约所有者销毁代币
     * @param from 要销毁代币的地址
     * @param amount 销毁的数量
     */
    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }
}