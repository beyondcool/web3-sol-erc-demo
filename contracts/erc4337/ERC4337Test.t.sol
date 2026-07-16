// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {UserOperation} from "./UserOperation.sol";
import {EntryPoint} from "./EntryPoint.sol";
import {SimpleAccount} from "./SimpleAccount.sol";
import {SimplePaymaster} from "./SimplePaymaster.sol";

/**
 * @title ERC4337Test
 * @notice ERC-4337 账户抽象协议的教学测试
 *
 * ═══════════════════════════════════════════════════════════════
 *  测试目标：理解 ERC-4337 的核心流程
 * ═══════════════════════════════════════════════════════════════
 *
 *  场景设定：
 *    Alice 有一个智能钱包（SimpleAccount 合约）。
 *    她想用这个钱包给 Bob 转账 0.5 ETH。
 *    但她的钱包是一个合约——传统上合约不能主动发起交易。
 *    通过 ERC-4337，她可以：
 *      1️⃣ 构造一个 UserOp（描述她想要的操作）
 *      2️⃣ 用她的 EOA 私钥签名
 *      3️⃣ 提交给 EntryPoint
 *      4️⃣ EntryPoint 协调处理整个流程
 *
 *  核心认知：
 *    ERC-4337 的关键创新不是"智能钱包"本身，
 *    而是它定义了一套**标准化流程**让智能钱包可以像 EOA 一样操作。
 *
 *    就像 ERC-20 标准化了代币接口一样，
 *    ERC-4337 标准化了智能钱包的操作流程！
 *
 *  ═══════════════════════════════════════════════════════════════
 *
 *  📊 这个测试文件涵盖的场景：
 *    Test 1: ✅ 基本 UserOp 流程（自付 gas）
 *    Test 2: ✅ Paymaster 代付 gas
 *    Test 3: ❌ 拒绝无效签名
 *    Test 4: ✅ 防重放——Nonce 保护
 */
contract ERC4337Test is Test {

    /* ─────────── 测试角色 ─────────── */

    address public alice;        // 钱包 owner（EOA，持有私钥）
    uint256 public aliceKey;     // Alice 的私钥（用于签名）
    address public bob;          // 接收转账的人
    address payable public recipient; // 收款地址

    /* ─────────── 合约 ─────────── */

    EntryPoint public ep;        // EntryPoint 协调器
    SimpleAccount public wallet; // Alice 的智能钱包
    SimplePaymaster public pm;   // Paymaster（代付者）

    /* ─────────── 常量 ─────────── */

    uint256 constant TRANSFER_AMOUNT = 0.5 ether;

    /* ═══════════════════════════════════════════════════════════
     *  测试准备
     * ═══════════════════════════════════════════════════════════ */

    function setUp() public {
        // ── 创建角色 ──
        (alice, aliceKey) = makeAddrAndKey("alice");
        bob = makeAddr("bob");
        recipient = payable(makeAddr("recipient"));

        // ── 部署 ERC-4337 核心组件 ──
        // 1. EntryPoint：唯一的协调器
        ep = new EntryPoint();

        // 2. 智能钱包：Alice 的合约钱包，所有者是 Alice
        wallet = new SimpleAccount(alice, address(ep));

        // 3. Paymaster：由 Alice 赞助的代付合约
        pm = new SimplePaymaster(address(ep), alice);

        // ── 给钱包充值 ETH ──
        // Alice 的智能钱包有 10 ETH
        vm.deal(address(wallet), 10 ether);

        // ── 向 EntryPoint 存款用于 gas ──
        // Alice（作为钱包 owner）向 EntryPoint 存入 1 ETH 作为 gas 费
        // 实际生产中这可以由 Bundler 或任何人为钱包存入
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        ep.depositFor{value: 1 ether}(address(wallet));

        // Paymaster 也存入 ETH，用于代付场景
        vm.prank(alice);
        ep.depositFor{value: 10 ether}(address(pm));
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 1：基本 UserOp 流程——智能钱包给 Bob 转账
     *
     *  这是 ERC-4337 最核心的使用场景：
     *    1. Alice 构造一个 UserOp，描述"从我的钱包给 Bob 转 0.5 ETH"
     *    2. Alice 用她的 EOA 私钥签名
     *    3. Bundler（测试中由 test 合约扮演）提交给 EntryPoint
     *    4. EntryPoint 验证签名 → 执行转账 → 扣 gas
     *
     *  重点理解：
     *    - UserOp 就像一笔"代理交易"
     *    - 验证阶段：EntryPoint 问钱包"这个签名对吗？"
     *    - 执行阶段：EntryPoint 说"好的，执行吧"
     *    - Gas 阶段：从钱包的存款中扣除费用
     * ═══════════════════════════════════════════════════════════ */

    function test_BasicUserOpTransfer() public {
        // ── 记录初始余额 ──
        uint256 balanceBefore = address(wallet).balance;
        uint256 recipientBefore = recipient.balance;

        // ── 步骤 ①：Alice 构造 UserOp ──
        UserOperation memory op;
        op.sender = address(wallet);
        op.nonce = ep.nonces(address(wallet)); // 当前 nonce = 0
        op.callData = abi.encodeCall(SimpleAccount.execute, (bob, TRANSFER_AMOUNT, ""));
        op.callGasLimit = 100_000;
        op.verificationGasLimit = 50_000;
        op.preVerificationGas = 10_000;
        op.maxFeePerGas = 10 gwei;
        op.maxPriorityFeePerGas = 1 gwei;
        // paymasterAndData 为空 → Alice 自己付 gas

        // ── 步骤 ②：Alice 签名 ──
        bytes32 userOpHash = ep.getUserOpHash(op);
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, ethSignedHash);
        op.signature = abi.encodePacked(r, s, v);

        // ── 步骤 ③：提交给 EntryPoint ──
        // 测试中的 msg.sender 是 test 合约（模拟 Bundler）
        ep.handleOp(op);

        // ── 步骤 ④：验证结果 ──
        // ✅ Bob 收到了 0.5 ETH
        assertEq(
            bob.balance - recipientBefore,
            TRANSFER_AMOUNT,
            "Bob should receive 0.5 ETH"
        );

        // ✅ 钱包余额减少了 = 0.5 ETH + gas（约 0.001 ETH）
        // 注意：wallet 的 ETH 余额不变！gas 从 EntryPoint 的 deposit 扣
        // 钱包只需要在 EntryPoint 有存款即可
        assertEq(
            address(wallet).balance,
            balanceBefore - TRANSFER_AMOUNT,
            "Wallet balance should decrease by transfer amount"
        );

        // ✅ Alice 在 EntryPoint 的存款减少了（gas 费被扣除）
        assertLt(ep.deposits(address(wallet)), 1 ether, "Gas deposit should decrease");

        // ✅ Nonce 递增了（防重放）
        assertEq(ep.nonces(address(wallet)), 1, "Nonce should increment");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 2：Paymaster 代付 gas
     *
     *  这个场景展示 ERC-4337 的杀手级功能——gas 抽象！
     *    Alice 的智能钱包在 EntryPoint 中没有任何存款
     *    但她通过指定 Paymaster，让 Paymaster 替她付 gas
     *
     *  不用 ETH 也能付 gas，这对新用户 onboarding 非常重要！
     * ═══════════════════════════════════════════════════════════ */

    function test_PaymasterSponsoredTransfer() public {
        // ── 新钱包，没有 gas 存款 ──
        SimpleAccount freshWallet = new SimpleAccount(alice, address(ep));
        vm.deal(address(freshWallet), 5 ether);
        // 注意：没有调用 ep.depositFor(freshWallet)！
        // 如果 Alice 自付 gas，会因为存款不足而失败

        // ── 构造 UserOp，带上 Paymaster ──
        UserOperation memory op;
        op.sender = address(freshWallet);
        op.nonce = ep.nonces(address(freshWallet));
        op.callData = abi.encodeCall(SimpleAccount.execute, (recipient, 1 ether, ""));
        op.callGasLimit = 100_000;
        op.verificationGasLimit = 50_000;
        op.preVerificationGas = 10_000;
        op.maxFeePerGas = 10 gwei;
        op.maxPriorityFeePerGas = 1 gwei;

        // ⭐ 关键区别：指定 Paymaster！
        // paymasterAndData = paymaster地址(20B) + 附加数据(0B)
        op.paymasterAndData = abi.encodePacked(address(pm));

        // ── Alice 签名（签名包含了 paymasterAndData 字段） ──
        bytes32 userOpHash = ep.getUserOpHash(op);
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, ethSignedHash);
        op.signature = abi.encodePacked(r, s, v);

        // ── 提交 ──
        uint256 pmDepositBefore = ep.deposits(address(pm));
        ep.handleOp(op);

        // ── 验证 ──
        // ✅ 转账成功
        assertEq(recipient.balance, 1 ether, "Recipient should receive 1 ETH");

        // ✅ Gas 从 Paymaster 的存款中扣除，不是从钱包扣！
        assertEq(
            ep.deposits(address(freshWallet)),
            0,
            "Fresh wallet deposit should remain 0"
        );
        assertLt(
            ep.deposits(address(pm)),
            pmDepositBefore,
            "Paymaster deposit should decrease"
        );

        // ✅ 钱包的 ETH 余额减少了 1 ETH（转账），但没付额外 gas
        assertEq(
            address(freshWallet).balance,
            5 ether - 1 ether,
            "Wallet loses only the transfer amount"
        );
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 3：拒绝无效签名
     *
     *  确保安全的测试：
     *    如果签名不是来自钱包 owner，EntryPoint 会拒绝 UserOp。
     *    这是钱包安全的基础。
     * ═══════════════════════════════════════════════════════════ */

    function test_RejectInvalidSignature() public {
        // ── Bob 冒充 Alice 构造 UserOp ──
        UserOperation memory op;
        op.sender = address(wallet);
        op.nonce = ep.nonces(address(wallet));
        op.callData = abi.encodeCall(SimpleAccount.execute, (bob, TRANSFER_AMOUNT, ""));
        op.callGasLimit = 100_000;
        op.verificationGasLimit = 50_000;
        op.preVerificationGas = 10_000;
        op.maxFeePerGas = 10 gwei;
        op.maxPriorityFeePerGas = 1 gwei;

        // Bob 用自己的私钥签名（不是 Alice 的！）
        bytes32 userOpHash = ep.getUserOpHash(op);
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256("bob's private key")), // Bob 的私钥
            ethSignedHash
        );
        op.signature = abi.encodePacked(r, s, v);

        // ── 预期：验证失败，revert ──
        vm.expectRevert("SA: signature not from owner");
        ep.handleOp(op);

        // ❌ 钱包的 ETH 没有被转走（安全！）
        assertEq(address(wallet).balance, 10 ether, "No ETH should be transferred");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 4：防重放——Nonce 保护
     *
     *  ERC-4337 的核心安全特性：nonce（计数器）。
     *
     *   每个 UserOp 都有 nonce 字段，类似于以太坊交易的 nonce。
     *   它确保：
     *     1. 每个 UserOp 只能被执行一次（防重放攻击）
     *     2. 执行顺序是确定的（先提交的先执行）
     *
     *   这个测试展示：
     *     - 同一个 UserOp 执行两次 → 第二次因为 nonce 不匹配而失败
     * ═══════════════════════════════════════════════════════════ */

    function test_ReplayProtection() public {
        // ── 构造一个正常的 UserOp ──
        UserOperation memory op;
        op.sender = address(wallet);
        op.nonce = ep.nonces(address(wallet)); // nonce = 0
        op.callData = abi.encodeCall(SimpleAccount.execute, (recipient, 1 ether, ""));
        op.callGasLimit = 100_000;
        op.verificationGasLimit = 50_000;
        op.preVerificationGas = 10_000;
        op.maxFeePerGas = 10 gwei;
        op.maxPriorityFeePerGas = 1 gwei;

        // ── 签名 ──
        bytes32 userOpHash = ep.getUserOpHash(op);
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, ethSignedHash);
        op.signature = abi.encodePacked(r, s, v);

        // ── 第一次执行：成功 ✅ ──
        ep.handleOp(op);
        assertEq(recipient.balance, 1 ether, "First execution succeeds");
        assertEq(ep.nonces(address(wallet)), 1, "Nonce incremented to 1");

        // ── 第二次执行相同 UserOp：失败 ❌ ──
        // 因为 nonce 已经变成 1 了，而 UserOp 使用的是 nonce = 0
        vm.expectRevert("EP: invalid nonce");
        ep.handleOp(op);

        // ✅ 收款人的余额没有变化（第二次没有执行）
        assertEq(recipient.balance, 1 ether, "No double execution");
    }
}
