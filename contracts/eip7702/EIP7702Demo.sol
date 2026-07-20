// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EIP7702Utils} from "@openzeppelin/contracts/account/utils/EIP7702Utils.sol";

/**
 * @title  EIP7702Demo
 * @author  OpenZeppelin
 * @notice  EIP-7702 教学示例 —— EOA 临时获得合约执行能力
 *
 * ═══════════════════════════════════════════════════════════════
 *  一句话理解 EIP-7702
 * ═══════════════════════════════════════════════════════════════
 *
 *  EOA 签名授权，把自己的 code 临时替换为 "0xef0100 + 实现合约地址"。
 *  当有人调用这个 EOA 时，EVM 识别到 0xef0100 前缀，自动 DELEGATECALL
 *  到实现合约。实现合约执行时，address(this) 仍然是 EOA 本身。
 *
 *  → EOA 保持了身份，但获得了合约的执行能力。
 *
 * ═══════════════════════════════════════════════════════════════
 *  为什么需要 EIP-7702？
 * ═══════════════════════════════════════════════════════════════
 *
 *  传统的 EOA 只能做一件事：用私钥签名交易。它不能：
 *    - 批量操作（原子性地执行多个调用）
 *    - 自定义验证逻辑（如多签、社交恢复）
 *    - 在链上执行任何代码逻辑
 *
 *  解决方法有两个方向：
 *
 *    ERC-4337（账户抽象）：
 *      让用户创建一个合约账户（CA），用 UserOperation 代替交易。
 *      优点：功能最强；缺点：EOA 不再是自己，dApp 需要适配。
 *
 *    EIP-7702（临时委托）：
 *      EOA 还是 EOA，只是临时借用合约的能力。
 *      优点：兼容性最好（dApp 无需修改）；缺点：能力是临时的。
 *
 * ═══════════════════════════════════════════════════════════════
 *  EIP-7702 执行流程
 * ═══════════════════════════════════════════════════════════════
 *
 *  ① EOA 签署授权消息（Authorization）
 *     内容: (chain_id, implementation_addr, nonce, signature)
 *
 *  ② 授权消息放入 EIP-7702 交易类型（type 0x04）
 *     EOA 的 code 被暂时设为: 0xef0100 || implementation_addr（共23字节）
 *
 *  ③ 后续调用（CALL）这个 EOA 时，EVM 识别到 0xef0100 前缀
 *     → 自动 DELEGATECALL 到 implementation_addr
 *     → 执行实现合约的代码，但上下文是 EOA:
 *         address(this) = EOA 地址
 *         msg.sender    = 原始调用者
 *         存储          = EOA 的状态存储
 *
 *  ⚠️ 持久化说明（EIP-7702 版本演进）
 *
 *  早期草稿版本 → 交易结束后 code 恢复为空（"临时委托"）
 *  最终纳入 Pectra 升级的版本 → code **持久保留**
 *
 *    交易结束后 code 不清空，永久留在 EOA 的账户状态中。
 *    直到下一次 EIP-7702 交易覆盖委托地址，或主动清除委托。
 *
 *  这意味着 EIP-7702 的委托是跨交易有效的：
 *    - 交易 A：Alice 委托给 demo → code 写入 0xef0100 + demo
 *    - 交易 B：CALL Alice → 仍然能触发 DELEGATECALL（不需要重新签名）
 *    - 交易 C：Alice 重新签名授权 → 覆盖为新的委托地址
 *    - 交易 D：Alice 签名授权 address(0) → 清除委托（恢复为普通 EOA）
 *
 * ═══════════════════════════════════════════════════════════════
 *  本合约演示的能力
 * ═══════════════════════════════════════════════════════════════
 *
 *  1️⃣ 上下文自省 (whoAmI)
 *     展示 EIP-7702 最核心的特性：address(this) 是 EOA 而非合约
 *
 *  2️⃣ 批量操作 (batchCall)
 *     EOA 通过委托，在一笔交易中原子性地执行多个调用
 *
 *  3️⃣ 委托检测 (checkDelegation)
 *     使用 OpenZeppelin 的 EIP7702Utils 读取任意地址的委托信息
 *
 *  4️⃣ 签名验证 (verifySignature)
 *     EOA 在链上验证一个 ECDSA 签名是否由自己签署
 */
contract EIP7702Demo {

    address public owner;


    /* ─────────────── Events ─────────────── */

    /// @notice 通用日志事件
    event Log(address indexed eoa, string message);

    /* ─────────────── Errors ─────────────── */

    /// @notice 批量调用中第 N 笔失败
    error BatchCallFailed(uint256 index);

    /* ──────────────────────────────────────────────────────────
     *  1️⃣  上下文自省
     *
     *  这是 EIP-7702 最核心的教学点！
     *
     *  直接调用合约:
     *    address(this) = 本合约部署地址（0x123...）
     *
     *  EIP-7702 委托后调用 EOA:
     *    address(this) = 发起委托的 EOA 地址（0xabc...）
     *    msg.sender    = 原始调用者
     *
     *  关键认知：
     *    合约的逻辑在 EOA 的上下文中执行。
     *    EOA 还是那个 EOA，但获得了执行逻辑的能力。
     * ────────────────────────────────────────────────────────── */

    /**
     * 只有合约部署者（owner）才能调用EOA code指向的合约（当前合约）中的函数。
     * 这是为了防止其他人滥用 EIP-7702 委托功能，确保只有授权的 EOA 可以执行批量操作和其他敏感操作。
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "EIP7702Demo: not owner");
        _;
    }

    constructor() {
        owner = msg.sender;  // 部署者初始为 owner
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /**
     * @notice 【测试用的】查询当前执行上下文
     * @return self   当前执行上下文地址
     *         直接调用 → 本合约地址
     *         EIP-7702 → 委托了的 EOA 地址
     * @return caller 调用者地址
     */
    function whoAmI() external view returns (address self, address caller) {
        self = address(this);
        caller = msg.sender;
    }

    /* ──────────────────────────────────────────────────────────
     *  2️⃣  批量操作
     *
     *  普通 EOA 一笔交易只能做一件事。
     *  EIP-7702 让 EOA 可以在一笔交易中原子性地做多件事。
     *
     *  场景示例：
     *    用户想同时给 10 个人转账，或者一次性授权多个 DeFi 协议。
     *    没有 EIP-7702：需要发 10 笔交易，每笔都要签名。
     *    有 EIP-7702：一笔交易，一个签名，全部完成。
     *
     *  原理：
     *    委托合约可以包含任意执行逻辑，包括循环调用其他合约。
     *    因为执行上下文是 EOA，这些调用"看起来"就像 EOA 自己发的。
     * ────────────────────────────────────────────────────────── */

    /**
     * @notice 批量执行多个调用（原子性）
     * @param targets   目标合约地址列表
     * @param values    随各调用发送的 ETH 列表
     * @param calldatas 各调用的 calldata 列表
     * @return results  各调用的返回数据
     *
     *  如果任一调用失败，整个交易回滚（原子性保证）。
     */
    function batchCall(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external payable onlyOwner returns (bytes[] memory results) {
        uint256 len = targets.length;
        require(len == values.length && len == calldatas.length, "EIP7702Demo: length mismatch");

        results = new bytes[](len);

        for (uint256 i = 0; i < len; i++) {
            (bool ok, bytes memory res) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!ok) revert BatchCallFailed(i);
            results[i] = res;
        }

        emit Log(address(this), "batch executed");
    }

    /* ──────────────────────────────────────────────────────────
     *  3️⃣  委托检测
     *
     *  如何知道一个地址是否有 EIP-7702 委托？
     *
     *  EIP-7702 将 EOA 的 code 设置为:
     *    0xef0100 || delegate_address
     *    └─────┘   └──────────────┘
     *     前缀       委托地址（20字节）
     *
     *  检测方法（由 OpenZeppelin 的 EIP7702Utils 实现）:
     *    1. 读取 address.code，取前 23 字节
     *    2. 检查前 3 字节是否是 0xef0100
     *    3. 如果是，后 20 字节即是委托地址
     *
     *  学生思考：
     *    如果 address.code.length == 0 → 普通 EOA
     *    如果前 3 字节 == 0xef0100    → EIP-7702 委托的 EOA
     *    其他情况                       → 普通合约（CA）
     * ────────────────────────────────────────────────────────── */

    /**
     * @notice 检查任意地址是否有 EIP-7702 委托
     * @param account 要检查的地址
     * @return delegate 委托的实现合约地址（没有则为 address(0)）
     *
     *  底层使用 OpenZeppelin 的 EIP7702Utils.fetchDelegate()
     */
    function checkDelegation(address account) external view returns (address delegate) {
        return EIP7702Utils.fetchDelegate(account);
    }

    /**
     * @notice 获取当前 EOA 的详细信息
     * @return self        当前执行上下文
     * @return balance     当前账户的 ETH 余额
     * @return delegate    如果当前是 EIP-7702 委托则返回委托地址
     *
     *  这展示了 EIP-7702 的另一个重要事实：
     *  即使在委托执行中，查询的是 EOA 自己的余额和信息。
     */
    function accountInfo() external view returns (
        address self,
        uint256 balance,
        address delegate
    ) {
        self = address(this);
        balance = self.balance;
        delegate = EIP7702Utils.fetchDelegate(self);
    }

    /* ──────────────────────────────────────────────────────────
     *  4️⃣  签名验证
     *
     *  EIP-7702 的一个重要特性：
     *  因为 address(this) 就是 EOA 的地址，合约代码可以直接
     *  用 ecrecover 验证一个签名是否由这个 EOA 签署。
     *
     *  这在 ERC-4337 中需要 EntryPoint 配合，而在 EIP-7702 中
     *  是原生的——因为 EOA 的身份直接就是执行上下文。
     *
     *  应用场景：链下消息授权（如 Permit、DAO 投票委托）
     * ────────────────────────────────────────────────────────── */

    /**
     * @notice 验证一个 ECDSA 签名是否由当前 EOA 签署
     * @param hash  消息哈希
     * @param v     签名 v 值
     * @param r     签名 r 值
     * @param s     签名 s 值
     * @return valid 如果签名者是当前 EOA 则返回 true
     *
     *  教学点：因为 address(this) === EOA，所以 ecrecover
     *  恢复的地址等于 address(this) 就是签名由 EOA 自己签署。
     */
    function verifySignature(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external view returns (bool valid) {
        address recovered = ecrecover(hash, v, r, s);
        // 注意：在非委托调用（直接调用本合约）时，这验证的是
        // "这个签名是不是合约地址签的"——这通常没意义。
        // 但在 EIP-7702 委托中，address(this) === EOA，
        // 所以这是在验证 "这个签名是不是 EOA 自己签的"。
        return recovered == address(this);
    }

    /* ──────────────────────────────────────────────────────────
     *  辅助函数
     * ────────────────────────────────────────────────────────── */

    /**
     * @notice 让 EOA 通过委托"说"一句话（记录一条日志）
     * @param message 要记录的消息
     *
     *  教学意义：展示 EOA 可以有了"表达能力"。
     *  普通 EOA 无法 emit 事件，但通过委托就可以。
     */
    function say(string calldata message) external {
        emit Log(address(this), message);
    }

    /**
     * @notice 接收 ETH
     *
     *  教学点：虽然 EOA 本来就能收 ETH，但通过委托可以实现
     *  自定义的接收逻辑（比如自动兑换、记录捐赠等）。
     */
    receive() external payable {
        emit Log(address(this), "ETH received via EIP-7702");
    }
}
