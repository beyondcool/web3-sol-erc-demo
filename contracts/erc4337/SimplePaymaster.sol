// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UserOperation} from "./UserOperation.sol";
import {IPaymaster} from "./IPaymaster.sol";

/**
 * @title SimplePaymaster
 * @notice 最简单的 gas 代付合约（教学版）
 *
 * ═══════════════════════════════════════════════════════════════
 *  SimplePaymaster：不用 ETH 也能付 gas
 * ═══════════════════════════════════════════════════════════════
 *
 * 📌 场景：新用户没有 ETH，怎么用 dApp？
 * ─────────────────────────
 *   想象你做了一个游戏 DApp，用户 Alice 刚创建钱包，
 *   她钱包里没有任何 ETH——只有一些 USDC。
 *
 *   她想玩游戏，但连第一笔 gas 都付不起。怎么办？
 *
 *   方案 A：让她先去交易所买 ETH → 体验差
 *   方案 B：你（项目方）替她付 gas → Paymaster 做的事 ✅
 *
 * 📌 Paymaster 的三种典型模式
 * ─────────────────────────
 *   1️⃣ 免费赞助（Free Sponsorship）
 *       项目方无条件替用户付 gas（如：领取空投）
 *       实现：Paymaster 验证通过后直接付 gas，不向用户收费
 *
 *   2️⃣ 代币兑换（ERC-20 Swap）
 *       用户付 USDC，Paymaster 替用户付 ETH gas
 *       实现：Paymaster 内部用 Uniswap 把 USDC 换成 ETH
 *
 *   3️⃣ 条件赞助（Conditional Sponsorship）
 *       只赞助特定操作（如：只赞助在你的 DApp 内部的交易）
 *       实现：检查 UserOp.callData 是否调用你的合约
 *
 * ═══════════════════════════════════════════════════════════════
 *  本合约：最简单的免费赞助 Paymaster
 *   - 任何人都可以通过这个 Paymaster 代付 gas
 *   - 赞助方（部署者）预先存入 ETH 到 EntryPoint
 *   - 教学需要，不设任何条件（实际项目应该加条件！）
 * ═══════════════════════════════════════════════════════════════
 */
contract SimplePaymaster is IPaymaster {

    /// @notice 关联的 EntryPoint 地址
    address public immutable entryPoint;

    /// @notice 赞助方地址（向 EntryPoint 存入 ETH 的人）
    address public immutable sponsor;

    /* ─────────────── 事件 ─────────────── */

    /// @notice Paymaster 为某个 UserOp 代付了 gas
    event GasSponsored(
        address indexed sender,
        bytes32 indexed userOpHash,
        address indexed sponsor
    );

    /* ─────────────── 构造函数 ─────────────── */

    /// @param  _entryPoint  EntryPoint 合约地址
    /// @param  _sponsor     赞助方地址
    constructor(address _entryPoint, address _sponsor) {
        require(_entryPoint != address(0), "PM: entryPoint cannot be zero");
        require(_sponsor != address(0), "PM: sponsor cannot be zero");
        entryPoint = _entryPoint;
        sponsor = _sponsor;
    }

    /* ─────────────── 核心函数 ─────────────── */

    /// @notice 验证 Paymaster 是否愿意为这个 UserOp 付 gas
    /// @param  userOp      需要代付的 UserOperation
    /// @param  userOpHash  UserOp 的哈希
    /// @dev   只有 EntryPoint 可以调用
    ///
    /// 教学版：无条件代付
    /// 实际项目中你应该在这里加各种检查条件，例如：
    ///
    ///   🟢 白名单检查：只给白名单里的用户代付
    ///      require(allowedUsers[userOp.sender], "user not allowed");
    ///
    ///   🟢 操作检查：只给特定合约的特定函数调用代付
    ///      解析 userOp.callData，检查调用的合约和函数
    ///
    ///   🟢 预算检查：每个用户每天代付不超过 N 笔
    ///      require(dailyCount[userOp.sender] < MAX_PER_DAY, "rate limit");
    ///
    ///   🟢 签名检查：用户需要在链下获得项目方的签名后才能使用
    ///      防止 Paymaster 被滥用
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) external {
        // 安全检查：只有 EntryPoint 可以调用
        require(msg.sender == entryPoint, "PM: only EntryPoint");

        // 教学版：无条件通过 ✅
        // 意味着"Sponsor 愿意为任何 UserOp 付 gas"
        //
        // ⚠️ 在实际项目中，这里必须有条件检查！！
        //    否则谁都可以用你的 Paymaster 免费发交易，
        //    你的 ETH 会被耗尽！
        //
        // 下面的条件检查示例见上面的 NatSpec 注释

        emit GasSponsored(userOp.sender, userOpHash, sponsor);
    }
}
