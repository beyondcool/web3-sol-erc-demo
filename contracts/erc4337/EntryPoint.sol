// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UserOperation} from "./UserOperation.sol";
import {IAccount} from "./IAccount.sol";
import {IPaymaster} from "./IPaymaster.sol";

/**
 * @title EntryPoint
 * @notice ERC-4337 协调器（简化教学版）
 *
 * ═══════════════════════════════════════════════════════════════
 *  EntryPoint：ERC-4337 的中枢
 * ═══════════════════════════════════════════════════════════════
 *
 * 📌 EntryPoint 是什么？
 * ─────────────────────────
 *   EntryPoint 是 ERC-4337 架构中的"中央交换机"。
 *   所有 UserOperation 都经过它处理，它负责协调以下流程：
 *
 *   ┌──────────────────────────────────────────────────────────┐
 *   │  ① 验证阶段（Validation Phase）                          │
 *   │     ┌───────────┐     ┌────────────┐     ┌───────────┐    │
 *   │     │ EntryPoint│────▶│ Account    │────▶│(Paymaster)│   │
 *   │     │           │     │ 验签名      │     │ 确认代付   │   │
 *   │     └───────────┘     └────────────┘     └───────────┘    │
 *   │                                                          │
 *   │  ② 执行阶段（Execution Phase）                           │
 *   │     ┌───────────┐     ┌────────────┐     ┌──────────┐    │
 *   │     │ EntryPoint│────▶│ Account    │────▶│ 目标合约  │   │
 *   │     │           │     │ execute()  │     │ (如 DAI)  │   │
 *   │     └───────────┘     └────────────┘     └──────────┘    │
 *   │                                                          │
 *   │  ③ Gas 结算（Payment Phase）                             │
 *   │     从 Account 或 Paymaster 的存款中扣 gas 费              │
 *   └──────────────────────────────────────────────────────────┘
 *
 * 📌 核心设计思想
 * ─────────────────────────
 *   1️⃣ 两阶段处理
 *       先验证所有 UserOp（签名 + gas），再执行操作。
 *       这防止了"验证时没问题，执行时恶意操作"的攻击。
 *
 *   2️⃣ 统一的 gas 市场
 *       UserOp 中的 gas 字段（maxFeePerGas 等）与 EIP-1559 兼容，
 *       让 Account 也可以参与以太坊的 gas 市场。
 *
 *   3️⃣ 存款机制
 *       Account 和 Paymaster 在 EntryPoint 中预存 ETH，
 *       gas 费从存款中扣除。不直接持有 ETH 的 Account
 *       可以通过 Paymaster 代付。
 *
 * ═══════════════════════════════════════════════════════════════
 *  本合约：简化的 EntryPoint，聚焦核心流程
 *  ⚠️ 为教学目的做了大量简化，请勿用于生产
 * ═══════════════════════════════════════════════════════════════
 */
contract EntryPoint {

    /* ─────────────── 事件 ─────────────── */

    /// @notice 有新的 UserOp 被处理
    /// @param  userOpHash  UserOp 的唯一标识哈希
    /// @param  sender      钱包地址
    /// @param  paymaster   gas 代付者（0 地址表示用户自付）
    /// @param  gasFee      实际收取的 gas 费用（wei）
    event UserOperationExecuted(
        bytes32 indexed userOpHash,
        address indexed sender,
        address indexed paymaster,
        uint256 gasFee
    );

    /// @notice 账户或 Paymaster 存入 ETH
    event Deposit(address indexed account, uint256 amount);

    /// @notice 账户或 Paymaster 提取 ETH
    event Withdrawn(address indexed account, uint256 amount);

    /* ─────────────── 常量 ─────────────── */

    /// @dev EIP-712 类型哈希（用于计算 UserOp 哈希）
    bytes32 private constant USER_OPERATION_TYPEHASH =
        keccak256(
            "UserOperation("
            "address sender,"
            "uint256 nonce,"
            "bytes initCode,"
            "bytes callData,"
            "uint256 callGasLimit,"
            "uint256 verificationGasLimit,"
            "uint256 preVerificationGas,"
            "uint256 maxFeePerGas,"
            "uint256 maxPriorityFeePerGas,"
            "bytes paymasterAndData"
            ")"
        );

    /// @dev 模拟 gas 价格（wei/gas），教学用固定值
    ///      实际生产中使用区块的 basefee
    uint256 private constant MOCK_GAS_PRICE = 10 gwei;

    /* ─────────────── 状态 ─────────────── */

    /// @notice 各地址的 ETH 存款（Account 或 Paymaster 预存 gas 费）
    mapping(address => uint256) public deposits;

    /// @notice 各钱包的 nonce 计数器（防重放）
    mapping(address => uint256) public nonces;

    /* ─────────────── 存款管理 ─────────────── */

    /// @notice 向 EntryPoint 存入 ETH，作为未来的 gas 费
    /// @dev   无论是 Account 还是 Paymaster，都需要先存款才能使用
    function deposit() external payable {
        _depositFor(msg.sender);
    }

    /// @notice 为指定地址存入 ETH（他人代存）
    /// @param  target 要存入的目标地址（Account 或 Paymaster）
    function depositFor(address target) external payable {
        _depositFor(target);
    }

    function _depositFor(address target) internal {
        deposits[target] += msg.value;
        emit Deposit(target, msg.value);
    }

    /// @notice 提取存款
    /// @param  to      收款地址
    /// @param  amount  提取金额
    function withdraw(address payable to, uint256 amount) external {
        require(deposits[msg.sender] >= amount, "EP: insufficient deposit");
        deposits[msg.sender] -= amount;
        to.transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /* ─────────────── UserOp 哈希 ─────────────── */

    /// @notice 计算 UserOp 的全局唯一哈希（EIP-712 风格）
    /// @param  op  UserOperation
    /// @return userOpHash  用于签名的哈希值
    /// @dev   用户签名的是这个哈希。Account 需要验证它
    function getUserOpHash(UserOperation calldata op) external pure returns (bytes32) {
        return _getUserOpHash(op);
    }

    function _getUserOpHash(UserOperation calldata op) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                USER_OPERATION_TYPEHASH,
                op.sender,
                op.nonce,
                keccak256(op.initCode),
                keccak256(op.callData),
                op.callGasLimit,
                op.verificationGasLimit,
                op.preVerificationGas,
                op.maxFeePerGas,
                op.maxPriorityFeePerGas,
                keccak256(op.paymasterAndData)
            )
        );
    }

    /* ─────────────── 核心函数：处理 UserOp ─────────────── */

    /// @notice 处理一个 UserOperation
    /// @param  op  UserOperation
    /// @dev   流程：验证 → 执行 → 扣 gas
    function handleOp(UserOperation calldata op) external {
        // ── 前置检查 ──
        // 确保 nonce 正确（防重放）
        require(op.nonce == nonces[op.sender], "EP: invalid nonce");
        nonces[op.sender]++;

        // 计算 UserOp 哈希（这是用户签名的内容）
        bytes32 userOpHash = _getUserOpHash(op);

        // 解析 paymaster 地址（如果有的话）
        address paymaster = _getPaymaster(op);

        // 计算预估 gas 费（教学用简化版）
        uint256 gasFee = _calculateGasFee();

        // ═══════════════════════════════════════════
        // 阶段 ①：验证（Validation Phase）
        // ═══════════════════════════════════════════
        // 先调用 Account 验证：确认用户确实授权了这个操作
        // 如果有 Paymaster，还要验证 Paymaster 愿意付 gas
        //
        // 为什么先验证再执行？
        // 防止"恶意 UserOp"浪费执行 gas。如果签名不对，尽早 revert。

        // ①-a：Account 验证签名
        // 调用钱包的 validateUserOp：
        //   - 检查 userOp 的签名是否来自钱包 owner
        //   - 如果签名为无效，必须 revert（回滚整个操作）
        IAccount(op.sender).validateUserOp(op, userOpHash);

        // ①-b：Paymaster 验证（如果有）
        // Paymaster 可以决定是否为这个 UserOp 买单
        if (paymaster != address(0)) {
            IPaymaster(paymaster).validatePaymasterUserOp(op, userOpHash);
        }

        // ═══════════════════════════════════════════
        // 阶段 ②：执行（Execution Phase）
        // ═══════════════════════════════════════════
        // Account 执行 UserOp.callData 中指定的操作
        // EntryPoint 只是触发 Account，具体的操作由 Account 完成

        (bool execSuccess, bytes memory execResult) = op.sender.call{gas: op.callGasLimit}(op.callData);
        require(execSuccess, string(abi.encodePacked("EP: execution failed: ", execResult)));

        // ═══════════════════════════════════════════
        // 阶段 ③：Gas 结算（Payment Phase）
        // ═══════════════════════════════════════════
        // 从 Account 或 Paymaster 的存款中扣除 gas 费
        // 实际生产中还涉及复杂的 gas 计量和退款逻辑

        if (paymaster == address(0)) {
            // 用户自付：从 Account 存款中扣
            require(deposits[op.sender] >= gasFee, "EP: insufficient account deposit");
            deposits[op.sender] -= gasFee;
            // 实际中这里的 gas 费会转给 Beneficiary（Bundler 指定）
        } else {
            // Paymaster 代付：从 Paymaster 存款中扣
            require(deposits[paymaster] >= gasFee, "EP: insufficient paymaster deposit");
            deposits[paymaster] -= gasFee;
        }

        emit UserOperationExecuted(userOpHash, op.sender, paymaster, gasFee);
    }

    /* ─────────────── 内部工具函数 ─────────────── */

    /// @notice 从 paymasterAndData 字段中提取 paymaster 地址
    /// @param  op  UserOperation
    /// @return paymaster 地址，如果没有 paymaster 则返回 address(0)
    function _getPaymaster(UserOperation calldata op) internal pure returns (address paymaster) {
        if (op.paymasterAndData.length >= 20) {
            // paymasterAndData 的前 20 字节是 paymaster 地址
            paymaster = address(bytes20(op.paymasterAndData[:20]));
        }
    }

    /// @notice 计算 gas 费用（教学简化版）
    /// @return gasFee  预估 gas 费用（wei）
    /// @dev   实际实现中会计算实际 gas 消耗 × gas 价格
    function _calculateGasFee() internal pure returns (uint256) {
        // 教学中用固定 gas 量 × 固定 gas 价格
        // 实际实现中：
        //   gasUsed = gas consumed during execution
        //   effectiveGasPrice = min(maxFeePerGas, block.basefee + maxPriorityFeePerGas)
        return 100_000 * MOCK_GAS_PRICE;
    }
}
