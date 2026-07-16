// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UserOperation} from "./UserOperation.sol";

/**
 * @title IAccount
 * @notice 账户合约（智能钱包）必须实现的接口
 *
 * ═══════════════════════════════════════════════════════════════
 *  账户合约（Smart Account / Smart Wallet）
 * ═══════════════════════════════════════════════════════════════
 *
 * 📌 什么是 Account？
 * ─────────────────────────
 *   在 ERC-4337 中，Account 就是你部署的一个合约，它就是你的"钱包"。
 *   它做两件事：
 *
 *   1️⃣ 验证（validateUserOp）
 *      当有人声称"替我执行这个操作"时，Account 要检查：
 *      "这是我本人的意愿吗？签名对吗？"
 *
 *   2️⃣ 执行（通过 callData 触发）
 *      验证通过后，EntryPoint 会调用 Account 上的某个函数
 *      （通常是一个 execute 函数），Account 再转发这个调用到目标
 *
 * 📌 Account 能做到传统 EOA 做不到的事
 * ─────────────────────────
 *   ✅ 多签验证 — 需要多个 key 共同签名才能执行操作
 *   ✅ 社交恢复 — 弄丢 key 可以通过朋友恢复控制权
 *   ✅  限额控制 — 每天只能转出一定金额
 *   ✅ 自定义 gas 支付 — 用 USDC 付 gas，或让别人代付
 *   ✅ 批量操作 — 一个 UserOp 里可以包含多笔转账、交换等
 *   ✅ Session Key — 授权某个应用在有限范围内代为操作
 *
 * ═══════════════════════════════════════════════════════════════
 *  本接口：定义 validateUserOp 函数签名
 * ═══════════════════════════════════════════════════════════════
 */
interface IAccount {

    /// @notice 验证 UserOperation 是否由钱包所有者授权
    /// @param  userOp     需要验证的 UserOperation
    /// @param  userOpHash UserOp 的哈希（EIP-712 格式，见 EntryPoint）
    /// @dev   验证失败时必须 revert（回滚）
    /// @dev   这个函数只会被 EntryPoint 调用
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) external;
}
