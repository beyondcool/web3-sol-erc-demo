// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title GaslessTransfer
 * @notice 演示利用 permit 实现“无需用户持有 ETH 即可授权转账”
 *
 * 典型场景：
 * 1. Alice 持有 MTK，但她的地址没有 ETH 支付 gas。
 * 2. Alice 对一条授权消息进行签名，表示允许 Bob 提取一定数额的 MTK。
 * 3. Alice 将签名（v, r, s）发给 Bob（或任何中继者）。
 * 4. Bob 调用本合约的 `permitAndTransferFrom`，一次性完成授权和转账，
 *    交易的 gas 由 Bob 支付。
 */
contract GaslessTransfer {
    /**
     * @dev Permit模式必须这样一个方法，让用户可以在链下签名授权，然后在链上执行转账。
     * 
     * @notice 使用链下签名执行授权并转移代币
     * @param token   代币合约地址（ERC20Permit），也可以写成 MyToken 类型，但改后就只能支持这个MyToken代币啦。
     * @param owner   代币持有人（签名者）
     * @param to      接收者
     * @param value   转移数量
     * @param deadline 签名有效截止时间（Unix 时间戳）
     * @param v, r, s 签名数据
     */
    function permitAndTransferFrom(
        ERC20Permit token,
        address owner,
        address to,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // 第一步：调用代币合约的 permit，链上验证签名并为 spender 授权
        token.permit(owner, address(this), value, deadline, v, r, s);

        // 第二步：本合约已获得授权，直接从 owner 转给 to
        token.transferFrom(owner, to, value);
    }
}