// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EIP7702Demo} from "./EIP7702Demo.sol";
import {EIP7702Utils} from "@openzeppelin/contracts/account/utils/EIP7702Utils.sol";

/**
 * @title EIP7702DemoTest
 * @notice EIP-7702 教学测试 —— 通过测试理解协议特性
 *
 * ═══════════════════════════════════════════════════════════════
 *  测试目标
 * ═══════════════════════════════════════════════════════════════
 *
 *  本测试的核心教学目的是让学生理解 EIP-7702 的 3 个关键认知：
 *
 *  认知 1：EIP-7702 = EOA + 临时合约能力
 *    执行时 address(this) = EOA，msg.sender = 调用者。
 *    EOA 保持了身份（identity），但获得了执行逻辑的能力（capability）。
 *
 *  认知 2：委托可检测
 *    EIP-7702 会在 EOA 的 code 中留下标记 0xef0100 + 委托地址。
 *    任何人都可以读取这个标记来发现委托关系。
 *    使用 OpenZeppelin 的 EIP7702Utils.fetchDelegate() 即可检测。
 *
 *  认知 3：EIP-7702 能做什么
 *    - 批量操作（batchCall）：原子性多笔交易
 *    - 链上验证（verifySignature）：EOA 身份不变，可以验证签名
 *    - 表达能力（say/log）：EOA 现在可以 emit 事件了
 *
 * ═══════════════════════════════════════════════════════════════
 *  测试架构说明
 * ═══════════════════════════════════════════════════════════════
 *
 *  EIP-7702 是协议级别的特性（新的交易类型 0x04），Solidity 层面
 *  无法直接触发。因此本测试使用两种方式来模拟：
 *
 *  方式 A：直接调用（测试基本功能）
 *    直接调 EIP7702Demo.whoAmI()，address(this) = 合约地址
 *    这是理解 EIP-7702 的"对照组"。
 *
 *  方式 B：DELEGATECALL 代理（模拟委托上下文）
 *    通过代理合约 DELEGATECALL 到 EIP7702Demo
 *    address(this) = 代理合约地址（模拟 EOA）
 *    这是 EIP-7702 执行模型的近似模拟。
 *
 *  方式 C：vm.etch 模拟委托前缀（测试委托检测）
 *    使用 vm.etch 在任意地址上写入 0xef0100 + address
 *    然后使用 EIP7702Utils.fetchDelegate() 检测
 *    这直接测试了 EIP-7702 的"可检测性"特性。
 */
contract EIP7702DemoTest is Test {

    // ─── 测试角色 ──────────────────────────────────────────────

    /// @notice Alice —— 一个普通的 EOA
    address public alice;
    uint256 public aliceKey;

    /// @notice Bob —— 另一个 EOA
    address public bob;

    // ─── 测试合约 ──────────────────────────────────────────────

    /// @notice EIP-7702 实现合约
    EIP7702Demo public demo;

    /* ═══════════════════════════════════════════════════════════
     *  测试准备
     * ═══════════════════════════════════════════════════════════ */

    function setUp() public {
        // 确定性生成 EOA
        (alice, aliceKey) = makeAddrAndKey("alice");
        bob = makeAddr("bob");

        // 部署实现合约
        demo = new EIP7702Demo();

        // 给 Alice 一些 ETH（用于批量转账测试）
        vm.deal(alice, 10 ether);
    }

    /* ═══════════════════════════════════════════════════════════
     *  ╔══════════════════════════════════════════════════════╗
     *  ║  认知 1：执行上下文（最重要的教学点！）              ║
     *  ╚══════════════════════════════════════════════════════╝
     *
     *  这两个测试必须一起看：
     *    - test_WhoAmI_Direct:  直接调用时 address(this) = 合约
     *    - test_WhoAmI_Delegate: Delegatecall 时 address(this) = 调用者
     *
     *  EIP-7702 的关键认知就在这里：
     *  当 EOA 委托了实现合约，调用 EOA 时，
     *  代码在 EOA 的上下文中执行 —— 和 DELEGATECALL 行为相同。
     * ═══════════════════════════════════════════════════════════ */

    /**
     * @notice 方式 A —— 直接调用 whoAmI()
     *
     *  address(this) = 实现合约的地址
     *  msg.sender    = 测试合约（this）
     *
     *  "对照组"：让学生看到正常情况下的上下文
     */
    function test_WhoAmI_Direct() public view {
        (address self, address caller) = demo.whoAmI();

        // 直接调用时，address(this) 是合约部署地址
        assertEq(self, address(demo), "direct: self should be the demo contract");
        // msg.sender 是测试合约
        assertEq(caller, address(this), "direct: caller should be the test contract");
    }

    /**
     * @notice 方式 B —— 通过代理合约 DELEGATECALL 到 whoAmI()
     *
     *  address(this) = 代理合约地址（模拟 EOA）
     *  msg.sender    = 调用者（测试合约）
     *
     *  这正是 EIP-7702 的执行模型：
     *    EOA（模拟为 proxy）→ DELEGATECALL → 实现合约
     *    实现合约中 address(this) = EOA（即 proxy）
     *
     *  学生理解：
     *    "EOA 还是那个 EOA，但代码的执行逻辑来自实现合约。"
     */
    function test_WhoAmI_DelegateCall() public {
        // 创建一个代理合约来进行 delegatecall
        EIP7702Proxy proxy = new EIP7702Proxy(address(demo));

        // 通过代理合约获取上下文信息
        (address self, address caller) = proxy.getWhoAmI();

        // DELEGATECALL 后，address(this) == 代理合约地址（模拟 EOA）
        assertEq(self, address(proxy), "delegate: self should be the proxy (simulated EOA)");
        // msg.sender 仍然是原始的调用者
        assertEq(caller, address(this), "delegate: caller should be the test contract");

        // ── 教学说明 ──
        // 这个测试的核心结论：
        //   直接调用   → address(this) = 实现合约
        //   DELEGATECALL → address(this) = 代理/EOA
        //   EIP-7702 就是这么工作的！
        //
        //  区别：EIP-7702 在协议层面做这件事（自动的），
        //        而这个测试在合约层面模拟（手动的）。
        //        但核心原理是一样的——DELEGATECALL。
        //
        //  对 dApp 开发者意味着：
        //    你的合约可以假设 address(this) 就是用户地址，
        //    不需要额外的 msg.sender 判断或认证逻辑。
    }

    /* ═══════════════════════════════════════════════════════════
     *  ╔══════════════════════════════════════════════════════╗
     *  ║  认知 2：委托可检测                                 ║
     *  ╚══════════════════════════════════════════════════════╝
     *
     *  EIP-7702 会在 EOA 的 code 中写入 0xef0100 + delegate_addr。
     *  使用 OZ 的 EIP7702Utils.fetchDelegate() 可以读取。
     *
     *  这是一个"只读"标记——任何人都可以发现委托关系。
     * ═══════════════════════════════════════════════════════════ */

    /**
     * @notice 方式 C —— 使用 vm.etch 写入 EIP-7702 委托前缀
     *
     *  模拟场景：Alice（EOA）通过 EIP-7702 交易委托给了 demo 合约。
     *
     *  实际协议中，ETP-7702 交易会自动设置这个 code。
     *  这里用 vm.etch 手动模拟，以便展示检测方法。
     */
    function test_CheckDelegation() public {
        // ── 模拟前的状态 ──
        // Alice 是普通 EOA，没有委托
        address delegateBefore = demo.checkDelegation(alice);
        assertEq(delegateBefore, address(0), "alice has no delegation initially");

        // ── 模拟 EIP-7702 委托 ──
        // 实际协议中，EIP-7702 交易会设置 code = 0xef0100 || delegate
        // 这里用 vm.etch 手动模拟：
        bytes memory eip7702Code = abi.encodePacked(
            bytes3(0xef0100),   // EIP-7702 前缀
            address(demo)       // 委托的实现合约地址
        );
        vm.etch(alice, eip7702Code);

        // ── 模拟后的状态 ──
        // 现在 Alice 的 code 包含了 EIP-7702 委托标记
        address delegateAfter = demo.checkDelegation(alice);
        assertEq(delegateAfter, address(demo), "alice now delegates to demo contract");

        // ── Bob 没有委托 ──
        address bobDelegate = demo.checkDelegation(bob);
        assertEq(bobDelegate, address(0), "bob has no delegation");

        // ── 直接调用 EIP7702Utils ──
        // 当然也可以直接调用库（不需要经过 demo 合约）
        address delegateFromLib = EIP7702Utils.fetchDelegate(alice);
        assertEq(delegateFromLib, address(demo), "direct EIP7702Utils check matches");
    }

    /**
     * @notice EOA 没有委托时 accountInfo 返回 address(0)
     *
     *  补充测试：让同学理解 accountInfo() 在非委托上下文中的行为。
     */
    function test_AccountInfo_Direct() public view {
        (address self, uint256 balance, address delegate) = demo.accountInfo();

        assertEq(self, address(demo), "direct: self is the demo contract");
        // 合约部署时没有接收 ETH，余额为 0
        assertEq(balance, 0, "direct: no ETH on contract");
        // 合约地址本身没有 EIP-7702 委托前缀
        assertEq(delegate, address(0), "direct: no delegation on contract address");
    }

    /* ═══════════════════════════════════════════════════════════
     *  ╔══════════════════════════════════════════════════════╗
     *  ║  认知 3：EOA 能做什么了？                           ║
     *  ╚══════════════════════════════════════════════════════╝
     *
     *  以下测试展示 EIP-7702 为 EOA 带来的具体能力。
     * ═══════════════════════════════════════════════════════════ */

    /* ── 3-a: 批量操作 ──────────────────────────────────── */

    /**
     * @notice 批量调用 —— 原子性执行多个 ETH 转账
     *
     *  场景：Alice 在一笔交易中给 Bob 多次转账。
     *  没有 EIP-7702：需要发两笔交易。
     *  有 EIP-7702：一笔批量调用完成。
     *
     *  教学点：虽然这里直接调用了 demo.batchCall()，
     *  但在 EIP-7702 场景下，它会在 Alice 的上下文中执行，
     *  ETH 从 Alice 的余额中扣除。
     */
    function test_BatchCall_Transfer() public {
        // ── 准备批量调用参数：一次给 Bob 转两笔 ──
        address[] memory targets = new address[](2);
        targets[0] = bob;
        targets[1] = bob; // 也转给 Bob（展示同一目标可多次调用）

        uint256[] memory values = new uint256[](2);
        values[0] = 1 ether;
        values[1] = 2 ether;

        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = "";
        calldatas[1] = "";

        // ── 模拟 Alice 调用 batchCall ──
        // 注意：这里直接调用 demo 合约，ETH 来自测试合约
        // 在真实 EIP-7702 中，ETH 来自 Alice 自己的余额
        vm.deal(address(this), 10 ether);

        vm.prank(alice);
        demo.batchCall{value: 3 ether}(targets, values, calldatas);

        // ── 验证：Bob 收到了 1 + 2 = 3 ETH ──
        assertEq(bob.balance, 3 ether, "bob received total 3 ETH in one batch");
    }

    /**
     * @notice 批量调用参数长度不匹配时回滚
     */
    function test_BatchCall_LengthMismatch() public {
        address[] memory targets = new address[](1);
        targets[0] = bob;

        uint256[] memory values = new uint256[](2); // 和 targets 长度不一致
        values[0] = 1 ether;
        values[1] = 2 ether;

        bytes[] memory calldatas = new bytes[](1);

        vm.expectRevert();
        demo.batchCall(targets, values, calldatas);
    }

    /* ── 3-b: 签名验证 ──────────────────────────────────── */

    /**
     * @notice 验证签名来自当前上下文地址
     *
     *  教学点：在 EIP-7702 委托中，address(this) = EOA 地址。
     *  所以 verifySignature 验证的是"签名是否来自 EOA 自己"。
     *  这是 EIP-7702 和 ERC-4337 的区别之一：
     *  4337 需要 EntryPoint 做签名验证，7702 原生支持。
     */
    function test_VerifySignature() public {
        // Alice 签名一条消息
        bytes32 message = keccak256("EIP-7702 is cool!");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, message);

        // ── 直接验证 ──
        // 在直接调用时，address(this) = demo 合约地址
        // 所以 verifySignature 检查的是"签名者 == 合约地址？"
        // 这通常返回 false（合约地址没有私钥）
        bool validDirect = demo.verifySignature(message, v, r, s);
        assertFalse(validDirect, "direct: demo contract didn't sign this");

        // ── 模拟 EIP-7702 上下文 ──
        // 通过代理合约 delegatecall 调用 verifySignature
        EIP7702Proxy proxy = new EIP7702Proxy(address(demo));
        bool validDelegate = proxy.verifySig(message, v, r, s);

        // 在 DELEGATECALL 上下文中，address(this) = proxy 地址
        // 而 proxy 也没有私钥，所以也是 false
        // 但如果是 Alice 做了 EIP-7702 委托，address(this) = alice
        // 那么 ecrecover 恢复的 alice == address(this) → true
        //
        // 下面这个测试展示了关键逻辑：
        assertFalse(validDelegate, "delegate: proxy didn't sign this");

        // ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
        //  如果你理解了这个，EIP-7702 的核心就懂了：
        //
        //  EIP7702Demo.verifySignature 的逻辑是：
        //    ecrecover(hash, sig) == address(this)
        //
        //  直接调用时  → address(this) = 合约地址 → ❌
        //  EIP-7702 时 → address(this) = EOA 地址 → ✅
        //
        //  同样的代码，不同的上下文，结果不一样！
        //  这就是 EIP-7702 的魔法——EOA 保持了身份，所以可以验证自己的签名。
        // ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
    }

    /* ── 3-c: 表达能力 ──────────────────────────────────── */

    /**
     * @notice EOA 可以通过委托 emit 事件
     *
     *  普通 EOA 无法 emit 事件——它没有代码执行能力。
     *  EIP-7702 让 EOA 可以通过委托合约 emit 事件。
     *
     *  应用场景：交易历史追踪、链上通知等。
     */
    function test_Say_EmitsLog() public {
        // 演示：直接调用 say 函数
        vm.expectEmit(true, true, true, true, address(demo));
        emit EIP7702Demo.Log(address(demo), "hello eip-7702!"); // 注意这里是合约地址
        demo.say("hello eip-7702!");
    }

    /* ═══════════════════════════════════════════════════════════
     *  综合理解测验
     *
     *  以下测试检验学生是否真正理解了 EIP-7702 的核心。
     *
     *  问题：
     *    如果 Alice（EOA）通过 EIP-7702 委托到 EIP7702Demo，
     *    然后 Bob 调用 Alice 地址执行 batchCall。
     *    请问：
     *      a) address(this) 在 batchCall 中是谁？
     *      b) msg.sender 是谁？
     *      c) batchCall 转账的 ETH 来自谁的余额？
     *
     *  答案：
     *      a) Alice（EOA 地址）
     *      b) Bob（原始调用者）
     *      c) Alice（因为 address(this) = Alice, value 从 Alice 扣）
     * ═══════════════════════════════════════════════════════════ */

    /**
     * @notice 模拟 EIP-7702 全流程
     *
     *  这个测试用一个集成场景把前面所有知识点串起来：
     *
     *  场景：
     *    Alice 通过 EIP-7702 委托到 demo 合约。
     *    Alice 在一笔"委托交易"中执行 batchCall：
     *      - 转 1 ETH 给 Bob
     *      - 校验自己的身份
     *
     *  测试方法：
     *    使用 EIP7702Proxy 模拟 EIP-7702 的执行上下文。
     *    代理合约通过 DELEGATECALL 执行实现合约的代码，
     *    此时 address(this) = 代理合约地址（模拟 EOA 身份保持）。
     */
    function test_SimulatedEIP7702Flow() public {
        // ── Step 1: 部署"模拟 EOA"（实质是一个 DELEGATECALL 代理）──
        // 在真实 EIP-7702 中：Alice 用自己的私钥签署授权，EVM 自动 DELEGATECALL
        // 在这里：EIP7702Proxy 手动 DELEGATECALL 到实现合约
        // 结果一样：address(this) = 代理/EOA 地址
        EIP7702Proxy simulatedEOA = new EIP7702Proxy(address(demo));

        // 给模拟 EOA 一些 ETH（确保余额足够）
        // 在真实 EIP-7702 中，ETH 来自 EOA 的余额
        vm.deal(address(simulatedEOA), 5 ether);
        assertEq(address(simulatedEOA).balance, 5 ether, "deal should set balance");

        // ── Step 2: Bob 触发"模拟 EOA"的批量操作 ──
        // 在真实场景中：Bob call Alice 地址 → EVM 检测到 0xef0100 → DELEGATECALL
        // 在这里：Bob call 代理合约的 executeBatchCall → 内部 DELEGATECALL
        address[] memory targets = new address[](1);
        targets[0] = bob;

        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        assertEq(address(simulatedEOA).balance, 5 ether, "balance before call");

        vm.prank(bob);
        simulatedEOA.executeBatchCall{value: 0}(targets, values, calldatas);

        // ── Step 3: 验证 ──
        // Bob 收到了 1 ETH（来自模拟 EOA 的余额）
        assertEq(bob.balance, 1 ether, "bob received 1 ETH");
        // 模拟 EOA 扣除了 1 ETH
        assertEq(address(simulatedEOA).balance, 5 ether - 1 ether, "simulated EOA sent 1 ETH");
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  辅助合约：EIP-7702 代理
 *
 *  这个合约模拟了一个"加持了 EIP-7702 能力的 EOA"。
 *
 *  在真实 EIP-7702 中，当 EOA（地址 X）被调用时：
 *    ① EVM 检测到 X 的 code 前缀是 0xef0100
 *    ② 自动 DELEGATECALL 到实现合约
 *    ③ address(this) = X
 *
 *  这个代理合约手动做了同样的事：
 *    ① 我们故意让外部调用走这里
 *    ② 合约内部 DELEGATECALL 到实现合约
 *    ③ address(this) = 代理合约地址（模拟 EOA）
 *
 *  教学要点：
 *    这不是 EIP-7702 的实现，而是教学辅助工具。
 *    它让学生能在 Solidity 层面看到 DELEGATECALL 的行为，
 *    从而理解 EIP-7702 在协议层面做的事。
 * ═══════════════════════════════════════════════════════════════ */
contract EIP7702Proxy {
    address public immutable implementation;

    constructor(address _impl) {
        implementation = _impl;
    }

    /// @notice 通过 DELEGATECALL 调用实现合约的 whoAmI
    function getWhoAmI() external returns (address self, address caller) {
        (bool ok, bytes memory data) = implementation.delegatecall(
            abi.encodeCall(EIP7702Demo.whoAmI, ())
        );
        require(ok, "delegatecall failed");
        return abi.decode(data, (address, address));
    }

    /// @notice 通过 DELEGATECALL 调用实现合约的 verifySignature
    function verifySig(bytes32 hash, uint8 v, bytes32 r, bytes32 s) external returns (bool) {
        (bool ok, bytes memory data) = implementation.delegatecall(
            abi.encodeCall(EIP7702Demo.verifySignature, (hash, v, r, s))
        );
        require(ok, "delegatecall failed");
        return abi.decode(data, (bool));
    }

    /// @notice 通过 DELEGATECALL 调用实现合约的 batchCall
    function executeBatchCall(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external payable {
        (bool ok, ) = implementation.delegatecall(
            abi.encodeCall(EIP7702Demo.batchCall, (targets, values, calldatas))
        );
        require(ok, "batch delegatecall failed");
    }

    /// @notice 接收 ETH（确保 delegatecall 的 receive 能工作）
    receive() external payable {}
}
