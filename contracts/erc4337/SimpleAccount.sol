// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UserOperation} from "./UserOperation.sol";
import {IAccount} from "./IAccount.sol";
import {EntryPoint} from "./EntryPoint.sol";

/**
 * @title SimpleAccount
 * @notice 最简单的 ERC-4337 智能钱包（教学版）
 *
 * ═══════════════════════════════════════════════════════════════
 *  SimpleAccount：你的智能钱包
 * ═══════════════════════════════════════════════════════════════
 *
 * 📌 什么是智能钱包（Smart Account）？
 * ─────────────────────────
 *   传统 EOA 钱包（如 MetaMask 生成的地址）：
 *     - 控制权 = 私钥持有者
 *     - 逻辑固定：只能用 ECDSA 签名
 *     - 无法升级、无法恢复
 *
 *   智能钱包（本合约）：
 *     - 控制权 = 你编写的验证逻辑（可以是任何方式！）
 *     - 可以升级、可以恢复、可以批量操作
 *     - 可以用任何方式付 gas
 *
 * 📌 谁"拥有"这个钱包？
 * ─────────────────────────
 *   在这个教学示例中，钱包由一个 EOA 地址（owner）控制。
 *   owner 持有私钥，用私钥签名 UserOp。
 *
 *   但！这只是最基本的验证方式。你可以改成：
 *   ✅ 多签：需要 2/3 的人签名才能操作
 *   ✅ Passkey：用 WebAuthn 签名
 *   ✅ 社交恢复：
 *      - owner 丢了 → 找 3 个朋友认证 → 重置 owner
 *   ✅ Session Key：
 *      - 给某个 DApp 授权：每天最多花 100 USDC
 *
 * 📌 钱包能做什么？
 * ─────────────────────────
 *   1️⃣ execute(to, value, data)
 *      通过 EntryPoint 调用 → 向任意地址转账或调用合约
 *
 *   2️⃣ 接收 ETH
 *      receive() → 别人可以向你转账
 *
 * ═══════════════════════════════════════════════════════════════
 *  本合约：最简单的 ERC-4337 Account 实现
 *  ⚠️ 为教学目的做了大量简化，请勿用于生产
 * ═══════════════════════════════════════════════════════════════
 */
contract SimpleAccount is IAccount {

    /* ─────────────── 状态变量 ─────────────── */

    /// @notice 钱包的所有者（一个 EOA 地址的私钥持有者）
    /// @dev   可以改成任何验证逻辑：多签地址、Passkey、甚至 AI agent 地址
    address public owner;

    /// @notice 关联的 EntryPoint 地址（不可更改）
    /// @dev   这里写死 EntryPoint 地址，防止重放攻击
    ///       （一个 UserOp 只能在指定的 EntryPoint 上执行）
    address public immutable entryPoint;

    /* ─────────────── 事件 ─────────────── */

    /// @notice 钱包执行了一笔操作
    event Executed(address indexed target, uint256 value, bytes data);

    /// @notice 钱包所有者变更（仅用于演示，本合约未实现）
    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);

    /* ─────────────── 修饰符 ─────────────── */

    /// @notice 只允许 EntryPoint 调用
    /// @dev   这是关键的安全检查！只有 EntryPoint 可以调用验证和执行函数
    modifier onlyEntryPoint() {
        require(msg.sender == address(entryPoint), "SA: only EntryPoint");
        _;
    }

    /* ─────────────── 构造函数 ─────────────── */

    /// @notice 部署智能钱包
    /// @param  _owner       钱包所有者地址（你的 EOA）
    /// @param  _entryPoint  EntryPoint 合约地址
    constructor(address _owner, address _entryPoint) {
        require(_owner != address(0), "SA: owner cannot be zero");
        require(_entryPoint != address(0), "SA: entryPoint cannot be zero");
        owner = _owner;
        entryPoint = _entryPoint;
    }

    /* ─────────────── 接收 ETH ─────────────── */

    /// @notice 钱包可以接收 ETH
    /// @dev   别人可以像给 EOA 转账一样给你转 ETH
    receive() external payable {}

    /// @notice 钱包的 ETH 余额
    /// @return 钱包中持有的 ETH 数量
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /* ─────────────── ERC-4337 核心函数 ─────────────── */

    /// @notice 验证 UserOp 是否由 owner 授权（IAccount 接口实现）
    /// @param  userOp      需要验证的 UserOperation
    /// @param  userOpHash  需要验证的哈希（用户签名的内容）
    /// @dev   只有 EntryPoint 可以调用此函数
    ///
    /// ═══════════════════════════════════════════════════
    ///  验证逻辑详解
    /// ═══════════════════════════════════════════════════
    ///
    ///  第 1 步：恢复签名者
    ///    签名 = userOp.signature
    ///    哈希 = userOpHash
    ///    签名者 = ecrecover(hash, signature)
    ///    （ecrecover 是以太坊的内置函数，可以从签名恢复出签名者地址）
    ///
    ///  第 2 步：检查签名者是否 == owner
    ///    签名者 == 钱包 owner → 有效 ✅
    ///    签名者 != 钱包 owner → 无效 ❌ → revert
    ///
    ///  这就是最简单的 ECDSA 验证逻辑。
    ///  ⚡ 你可以把这里的验证换成任意逻辑：
    ///    - 多签验证
    ///    - ERC-1271 合约签名验证
    ///    - Scrypt/ZK 证明验证
    ///    - ...什么都可以！
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) external view onlyEntryPoint {
        // ── 第 1 步：通过 ecrecover 恢复签名者地址 ──
        // 将 userOpHash 转换为以太坊签名消息格式：
        //   ethSignedMessageHash = keccak256("\x19Ethereum Signed Message:\n32" ++ userOpHash)
        // 这是 MetaMask/ethers 签名前的标准处理方式
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash)
        );

        // 从签名中解析出 v, r, s
        // 签名格式：65 字节 = r(32B) + s(32B) + v(1B)
        require(userOp.signature.length == 65, "SA: invalid signature length");
        bytes32 r = bytes32(userOp.signature[0:32]);
        bytes32 s = bytes32(userOp.signature[32:64]);
        uint8 v = uint8(userOp.signature[64]);

        // 恢复签名者地址
        address recovered = ecrecover(ethSignedHash, v, r, s);

        // ── 第 2 步：检查签名者是否是钱包所有者 ──
        require(recovered == owner, "SA: signature not from owner");
        // 如果签名不是来自 owner，整个交易回滚
        // 验证通过，函数正常返回
    }

    /// @notice 执行操作（由 EntryPoint 在验证后调用）
    /// @param  to     目标合约地址
    /// @param  value  转账金额（wei）
    /// @param  data   调用数据
    /// @return result 执行结果
    /// @dev   只有 EntryPoint 可以通过 callData 触发此函数
    ///
    /// UserOp.callData 的编码方式：
    ///   abi.encodeCall(SimpleAccount.execute, (to, value, data))
    ///
    /// 实际使用示例：
    ///   向 0xVitalik 转 0.1 ETH：
    ///     callData = abi.encodeCall(
    ///         this.execute,
    ///         (0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045, 0.1 ether, "")
    ///     )
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external onlyEntryPoint returns (bytes memory result) {
        require(to != address(0), "SA: cannot execute to zero address");

        // 日志：记录这笔操作
        emit Executed(to, value, data);

        // 执行目标调用
        // 这里没有使用 .call{gas: ...} 限制 gas，简化教学
        (bool success, bytes memory ret) = to.call{value: value}(data);
        require(success, string(abi.encodePacked("SA: execution failed: ", ret)));

        return ret;
    }
}
