// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UserOperation} from "./UserOperation.sol";

/**
 * @title IPaymaster
 * @notice Paymaster（代付者）接口 — ERC-4337 的可选角色
 *
 * ═══════════════════════════════════════════════════════════════
 *  Paymaster：让用户不需要 ETH 也能付 gas
 * ═══════════════════════════════════════════════════════════════
 *
 * 📌 为什么需要 Paymaster？
 * ─────────────────────────
 *   传统上，发起交易必须用 ETH 付 gas。但在很多场景中，这不方便：
 *     - 新用户还没有 ETH（想先用 USDC 付 gas）
 *     - 项目方想为用户代付 gas（提升用户体验）
 *     - DApp 希望用户用应用代币付 gas
 *
 *   Paymaster 就是来解决这些问题的！
 *
 *   一个 Paymaster 可以：
 *   🟢 代付 gas — 由项目方承担用户的 gas 费用
 *   🟢 接受 ERC-20 — 用户用 USDC/DAI 等代币"支付"gas
 *   🟢 条件代付 — 只有特定操作才代付（如：只在你的 DApp 里免 gas）
 *
 * 📌 Paymaster 的工作流程
 * ─────────────────────────
 *   1. 用户在 UserOp 的 paymasterAndData 中指定 Paymaster 地址
 *   2. EntryPoint 验证阶段调用 Paymaster 的 validatePaymasterUserOp
 *   3. Paymaster 检查是否愿意为此 UserOp 付 gas
 *   4. 如果通过，执行后 gas 从 Paymaster 的存款中扣除
 *
 * ═══════════════════════════════════════════════════════════════
 *  本接口：定义 Paymaster 必须实现的函数
 * ═══════════════════════════════════════════════════════════════
 */
interface IPaymaster {

    /// @notice 验证 Paymaster 是否愿意为这个 UserOp 代付 gas
    /// @param  userOp     需要验证的 UserOperation
    /// @param  userOpHash UserOp 的哈希
    /// @dev   验证失败时必须 revert
    /// @dev   这个函数只会被 EntryPoint 调用
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) external;
}
