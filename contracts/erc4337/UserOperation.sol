// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title UserOperation
 * @notice ERC-4337 的核心数据结构
 *
 * ═══════════════════════════════════════════════════════════════
 *  ERC-4337：账户抽象（Account Abstraction）
 * ═══════════════════════════════════════════════════════════════
 *
 * 📌 传统以太坊的问题
 * ─────────────────────────
 *   在以太坊上，有两种账户：
 *     EOA（外部账户） — 有私钥，可以发起交易，支付 gas
 *     CA（合约账户）   — 有代码，不能主动发起交易，不能付 gas
 *
 *   问题：如果你想用合约作为"钱包"，它无法自己发起交易。
 *   合约为"被动"的，只能响应 EOA 发起的交易。
 *
 *   ERC-4337 要解决的核心问题就是：
 *   「让合约也能像 EOA 一样发起交易，同时不改变以太坊共识层」
 *
 * 📌 什么是 UserOperation（用户操作）？
 * ─────────────────────────
 *   UserOperation（简称 UserOp）是 ERC-4337 引入的"伪交易"。
 *   它描述了用户想让自己的智能钱包做什么——就像一笔交易描述了
 *   EOA 想做什么一样。
 *
 *   UserOp 与普通交易的对应关系：
 *     ┌──────────────────┬──────────────────────────────┐
 *     │   普通交易字段    │     UserOp 对应字段           │
 *     ├──────────────────┼──────────────────────────────┤
 *     │ from             │ sender（你的智能钱包地址）      │
 *     │ to               │ 编码在 callData 中            │
 *     │ data             │ callData                     │
 *     │ value            │ 编码在 callData 中            │
 *     │ gasLimit         │ callGasLimit                 │
 *     │ maxFeePerGas     │ maxFeePerGas                 │
 *     │ nonce            │ nonce                        │
 *     │ v, r, s (签名)   │ signature                    │
 *     └──────────────────┴──────────────────────────────┘
 *
 * 📌 ERC-4337 的四个核心角色
 * ─────────────────────────
 *   1️⃣ 用户（User）
 *      构造并签名 UserOp，提交给 Bundler
 *
 *   2️⃣ Bundler（打包者，链下）
 *      收集多个 UserOp，打包成一笔交易提交给 EntryPoint
 *      （可以理解为"矿工/验证者的替身"）
 *
 *   3️⃣ EntryPoint（入口点，链上合约）
 *      统一的协调合约。所有 UserOp 都经过它处理。
 *      它负责：
 *        a. 调用 Account 验证 UserOp 的签名
 *        b. 调用 Account 执行 UserOp 的操作
 *        c. 处理 gas 支付
 *
 *   4️⃣ Account（账户合约）
 *      用户的智能钱包。它定义了自己的验证逻辑和操作逻辑。
 *
 *   （还有可选角色 Paymaster — 见 IPaymaster.sol）
 *
 * ═══════════════════════════════════════════════════════════════
 *  本文件：定义 UserOperation 结构体，供其他合约引用
 * ═══════════════════════════════════════════════════════════════
 *
 * 📚 参考：https://github.com/ethereum/ERCs/blob/master/ERCS/erc-4337.md
 *          https://eips.ethereum.org/EIPS/eip-4337
 */

/// @notice UserOperation 结构体 — ERC-4337 的"伪交易"
/// @dev 每个字段的详细含义见下方注释
struct UserOperation {
    /// @notice 智能钱包地址（你部署的 SimpleAccount 合约地址）
    address sender;

    /// @notice 防重放计数器
    /// @dev  每个 sender 的 nonce 必须严格递增，防止 UserOp 被重复执行
    uint256 nonce;

    /// @notice 如果 sender 还没部署，用 initCode 创建它
    /// @dev  如果 sender 已存在，此字段应为空。为简化教学，本示例假设 sender 已部署
    bytes initCode;

    /// @notice 要执行的操作数据（编码了你想调用的函数和参数）
    /// @dev  通常编码为：abi.encodeCall(SimpleAccount.execute, (to, value, data))
    ///       例如：想向 0xABC 转 1 ETH，就是
    ///       abi.encodeCall(account.execute, (0xABC, 1 ether, ""))
    bytes callData;

    /// @notice 执行阶段分配的 gas 量
    uint256 callGasLimit;

    /// @notice 验证阶段分配的 gas 量
    uint256 verificationGasLimit;

    /// @notice Bundler 打包交易的 gas 补偿
    uint256 preVerificationGas;

    /// @notice 用户愿意支付的最大优先费（给验证者的 tip）
    uint256 maxFeePerGas;

    /// @notice 最大 gas 价格（单位：wei）
    uint256 maxPriorityFeePerGas;

    /// @notice Paymaster（代付者）地址和附加数据
    /// @dev  为空表示用户自己付 gas
    ///       非空表示由 Paymaster 代付，编码为 address(20B) + data(可变)
    bytes paymasterAndData;

    /// @notice 用户对 UserOp 的签名
    /// @dev  签名内容 = userOpHash（EntryPoint 计算，包含整个操作的哈希）
    bytes signature;
}
