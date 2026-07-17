// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgenticCommerce} from "./AgenticCommerce.sol";
import {MyERC20Demo} from "../erc20/MyERC20Demo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ERC8183Test
 * @notice ERC-8183 Agentic Commerce 协议的教学测试
 *
 * ═══════════════════════════════════════════════════════════════
 *  测试目标：理解 ERC-8183 的核心生命周期
 * ═══════════════════════════════════════════════════════════════
 *
 *  场景设定：
 *    Alice 有一个翻译任务需要外包。Bob 是一个翻译 AI Agent。
 *    Eva 是验收员（Evaluator），负责检查 Bob 的翻译质量。
 *
 *  核心认知：
 *    ERC-8183 不定义 AI Agent 怎么工作，它定义 Agent 之间
 *    怎么**安全交易**--用托管（escrow）+ 验收（evaluator）
 *    替代了"我先付钱"或"我先干活"的信任问题。
 *
 *  ═══════════════════════════════════════════════════════════════
 *
 *  📊 这个测试文件涵盖的场景：
 *    Test 1: [OK] 完整生命周期 → 创建 → 充值 → 提交 → 验收 → 放款
 *    Test 2: [OK] Evaluator 拒绝 → 退款给 Client
 *    Test 3: [OK] Client 在 Open 时取消
 *    Test 4: [OK] 过期自动退款
 *    Test 5: [OK] Provider 参与议价（setBudget 协商）
 *    Test 6: ❌ 权限校验 - Provider 不能调用 complete
 */
contract ERC8183Test is Test {

    /* ─────────── 测试角色 ─────────── */

    address public alice;       // Client - 发任务 + 出钱
    address public bob;         // Provider - 干活
    address public eva;         // Evaluator - 验收

    /* ─────────── 合约 ─────────── */

    MyERC20Demo      public token;
    AgenticCommerce  public commerce;

    /* ─────────── 常量 ─────────── */

    uint256 constant BUDGET     = 5_000 * 10 ** 18;  // 5000 个代币
    uint256 constant INITIAL    = 100_000 * 10 ** 18; // 初始分发
    uint256 constant ONE_DAY    = 1 days;
    uint256 constant SEVEN_DAYS = 7 days;

    string constant DESCRIPTION = "Translate the document from English to Chinese";

    /* ═══════════════════════════════════════════════════════════
     *  测试准备
     * ═══════════════════════════════════════════════════════════ */

    function setUp() public {
        // ── 创建角色 ──
        alice = makeAddr("alice");   // Client
        bob   = makeAddr("bob");     // Provider
        eva   = makeAddr("eva");     // Evaluator

        // ── 部署 ERC-20 代币 ──
        token = new MyERC20Demo(1_000_000);

        // ── 部署 AgenticCommerce ──
        commerce = new AgenticCommerce(IERC20(address(token)));

        // ── 给 Alice 转一些代币，让她有钱发任务 ──
        token.transfer(alice, INITIAL);
    }

    /* ═══════════════════════════════════════════════════════════
     *  辅助函数：创建一个基础 Job
     * ═══════════════════════════════════════════════════════════ */

    /// @dev Alice 创建一个 Job，Provider = Bob，Evaluator = Eva
    ///      过期时间 = 7 天后
    function _createJob() internal returns (uint256 jobId) {
        vm.prank(alice);
        jobId = commerce.createJob(
            bob,
            eva,
            block.timestamp + SEVEN_DAYS,
            DESCRIPTION,
            address(0)   // 不使用 Hook
        );
    }

    /// @dev Alice 设置预算 + 充值
    function _fundJob(uint256 jobId) internal {
        vm.prank(alice);
        commerce.setBudget(jobId, BUDGET, "");

        vm.prank(alice);
        token.approve(address(commerce), BUDGET);

        vm.prank(alice);
        commerce.fund(jobId, BUDGET, "");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 1：完整生命周期（Happy Path）
     *
     *  这是 ERC-8183 最核心的流程--一个 Job 从生到死的完整过程。
     *
     *  场景：
     *    Alice 需要翻译一份文档。她在链上创建一个 Job，
     *    充值 5000 个代币。Bob 翻译完，提交交付物（哈希）。
     *    Eva 检查后确认质量合格→资金释放给 Bob。
     *
     *  理解重点：
     *    - 资金全程在合约托管，任何一方都不能单方面卷款
     *    - Evaluator 是"仲裁者"，决定钱给谁
     *    - deliverable 是哈希，实际文件在链下
     * ═══════════════════════════════════════════════════════════ */

    function test_HappyPath_FullLifecycle() public {
        // ── 步骤 ①：Alice 创建 Job ──
        uint256 jobId = _createJob();
        assertEq(jobId, 1, "First job should have ID 1");

        // ── 验证初始状态 ──
        AgenticCommerce.Job memory job = commerce.getJob(jobId);
        assertEq(job.client,     alice);
        assertEq(job.provider,   bob);
        assertEq(job.evaluator,  eva);
        assertEq(uint256(job.status), uint256(AgenticCommerce.JobStatus.Open), "Should be Open");
        assertEq(job.budget,     0, "Budget not set yet");
        emit log_string("Job created - status: Open");

        // ── 步骤 ②：Alice 设置预算并充值 ──
        _fundJob(jobId);

        job = commerce.getJob(jobId);
        assertEq(uint256(job.status), uint256(AgenticCommerce.JobStatus.Funded), "Should be Funded");
        assertEq(job.budget, BUDGET, "Budget should match");
        emit log_string("Job funded - status: Funded");

        // 验证资金已托管（本合约余额增加）
        assertEq(token.balanceOf(address(commerce)), BUDGET, "Tokens should be in escrow");

        // ── 步骤 ③：Bob 提交交付物 ──
        bytes32 deliverable = keccak256("translation_output.json");
        vm.prank(bob);
        commerce.submit(jobId, deliverable, "");

        job = commerce.getJob(jobId);
        assertEq(uint256(job.status), uint256(AgenticCommerce.JobStatus.Submitted), "Should be Submitted");
        assertEq(job.deliverable, deliverable, "Deliverable hash should match");
        emit log_string("[OK] Deliverable submitted - status: Submitted");

        // ── 步骤 ④：Eva 验收通过 ──
        bytes32 reason = keccak256("quality_check_passed");
        vm.prank(eva);
        commerce.complete(jobId, reason, "");

        job = commerce.getJob(jobId);
        assertEq(uint256(job.status), uint256(AgenticCommerce.JobStatus.Completed), "Should be Completed");
        emit log_string("[OK] Job completed - status: Completed");

        // ── 步骤 ⑤：验证资金已释放给 Bob ──
        assertEq(token.balanceOf(address(commerce)), 0, "Escrow should be empty");
        assertEq(token.balanceOf(bob), BUDGET, "Bob should be paid");

        emit log_string(" Payment released to Bob!");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 2：Evaluator 拒绝（Submitted 时）
     *
     *  如果 Eva 检查发现 Bob 的翻译质量不合格，
     *  她可以调用 reject() → 资金退回给 Alice。
     *
     *  这展示了 Evaluator 的"否决权"--钱不会被骗走。
     *
     *  理解重点：
     *    - reject 将状态从 Submitted → Rejected
     *    - 已托管的资金全额退还给 Client
     *    - Provider 拿不到钱（活没干好）
     * ═══════════════════════════════════════════════════════════ */

    function test_EvaluatorRejectsSubmittedJob() public {
        uint256 jobId = _createJob();
        _fundJob(jobId);

        // ── Bob 提交 ──
        vm.prank(bob);
        commerce.submit(jobId, keccak256("bad_translation.json"), "");

        // ── Eva 拒绝（翻译不合格） ──
        vm.prank(eva);
        commerce.reject(jobId, keccak256("quality_too_low"), "");

        // ── 验证：状态为 Rejected ──
        AgenticCommerce.Job memory job = commerce.getJob(jobId);
        assertEq(uint256(job.status), uint256(AgenticCommerce.JobStatus.Rejected), "Should be Rejected");

        // ── 验证：资金退回给 Alice ──
        assertEq(token.balanceOf(address(commerce)), 0, "Escrow should be empty");
        assertEq(token.balanceOf(alice), INITIAL, "Alice should get refund");

        // Bob 没拿到钱
        assertEq(token.balanceOf(bob), 0, "Bob should not be paid");

        emit log_string("[OK] Evaluator rejected - Alice got refund, Bob got nothing");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 3：Client 在 Open 状态取消
     *
     *  Alice 如果改变主意了（在充值之前），可以直接取消。
     *  这时没有资金被托管，所以无需退款。
     *
     *  理解重点：
     *    - Open 状态只允许 Client 调用 reject
     *    - 没有资金托管，纯取消操作
     *    - 一旦 Funded，Client 就不能单方面取消了
     *      （必须由 Evaluator reject 或等到过期）
     * ═══════════════════════════════════════════════════════════ */

    function test_ClientCancelsOpenJob() public {
        uint256 jobId = _createJob();

        // ── Alice 取消（还没充值） ──
        vm.prank(alice);
        commerce.reject(jobId, keccak256("changed_my_mind"), "");

        // ── 验证 ──
        AgenticCommerce.Job memory job = commerce.getJob(jobId);
        assertEq(uint256(job.status), uint256(AgenticCommerce.JobStatus.Rejected), "Should be Rejected");

        // Alice 余额不变（没花过钱）
        assertEq(token.balanceOf(alice), INITIAL, "Alice balance unchanged");

        emit log_string("[OK] Client cancelled Open job - no funds lost");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 4：过期退款（claimRefund）
     *
     *  如果 Bob 提交了交付物但 Eva 一直不验收（或者掉线了），
     *  资金不能永远卡在合约里。ERC-8183 提供了"逃生舱"--
     *  claimRefund。
     *
     *  理解重点：
     *    - 任何人在 expiredAt 之后都可以调用（包括定时脚本）
     *    - 不需要 Client、Provider、Evaluator 任何一方配合
     *    - 这是 permissionless 的安全措施
     *    - 规范明确规定 claimRefund 不能被 Hook 拦截
     * ═══════════════════════════════════════════════════════════ */

    function test_ClaimRefundAfterExpiry() public {
        uint256 jobId = _createJob();
        _fundJob(jobId);

        // ── Bob 提交了 ──
        vm.prank(bob);
        commerce.submit(jobId, keccak256("work_done.json"), "");

        // ── 但 Eva 一直没验收... ──
        // 时间快进到过期之后
        vm.warp(block.timestamp + SEVEN_DAYS + 1 seconds);

        // ── 任何人都可以触发退款（这里 Bob 来调用，展示"任何人"） ──
        vm.prank(bob);  // 甚至是 Provider 自己！
        commerce.claimRefund(jobId);

        // ── 验证 ──
        AgenticCommerce.Job memory job = commerce.getJob(jobId);
        assertEq(uint256(job.status), uint256(AgenticCommerce.JobStatus.Expired), "Should be Expired");

        // 钱退给了 Alice（不是 Bob！）
        assertEq(token.balanceOf(alice), INITIAL, "Alice got refund");
        assertEq(token.balanceOf(bob), 0, "Bob didn't get paid");
        assertEq(token.balanceOf(address(commerce)), 0, "Escrow empty");

        emit log_string("[OK] Claim refund after expiry - Alice got money back");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 5：Provider 参与议价
     *
     *  ERC-8183 的一个灵活设计：Provider 也可以调用 setBudget。
     *  这让双方可以在链上"协商"价格。
     *
     *  场景：
     *    Alice 设了 3000 的预算。
     *    Bob 觉得太少，设成 5000。
     *    Alice 接受新价格，fund(5000)。
     *
     *  理解重点：
     *    - setBudget 可由 Client 或 Provider 调用
     *    - 双方都可以"出价"，最终由 Client 的 fund 决定是否接受
     *    - expectedBudget 参数防止 Provider 突然抬价
     * ═══════════════════════════════════════════════════════════ */

    function test_ProviderCanSetBudget() public {
        uint256 jobId = _createJob();
        uint256 lowerBudget = 3_000 * 10 ** 18;

        // ── Alice 设 3000 ──
        vm.prank(alice);
        commerce.setBudget(jobId, lowerBudget, "");

        // ── Bob 觉得太少，设成 5000 ──
        vm.prank(bob);
        commerce.setBudget(jobId, BUDGET, "");

        // ── Alice 接受 5000 ──
        vm.prank(alice);
        token.approve(address(commerce), BUDGET);

        vm.prank(alice);
        commerce.fund(jobId, BUDGET, "");  // 如果传 expectedBudget = 3000，会 revert！

        // ── 验证 ──
        AgenticCommerce.Job memory job = commerce.getJob(jobId);
        assertEq(uint256(job.status), uint256(AgenticCommerce.JobStatus.Funded), "Should be Funded");
        assertEq(job.budget, BUDGET, "Budget should be 5000");

        emit log_string("[OK] Provider negotiated price - budget changed from 3000 to 5000");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 6：权限校验 - Provider 不能 complete
     *
     *  只有 Evaluator 可以调用 complete/reject（在 Funded/Submitted 时）。
     *  Provider 和 Client 都不能绕过 Evaluator。
     *
     *  理解重点：
     *    - 职责分离是 ERC-8183 的核心安全模型
     *    - Provider 干完活但不能自己说"干完了，打钱"
     *    - Client 付了钱但不能自己说"活不行，退钱"
     *      （除非在 Open 状态取消）
     * ═══════════════════════════════════════════════════════════ */

    function test_ProviderCannotCompleteJob() public {
        uint256 jobId = _createJob();
        _fundJob(jobId);

        vm.prank(bob);
        commerce.submit(jobId, keccak256("work.json"), "");

        // ── Bob 想自己确认完成... 但不行！ ──
        vm.prank(bob);
        vm.expectRevert("Only evaluator");
        commerce.complete(jobId, keccak256("done"), "");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 7（Bonus）：Funded 时 Evaluator 直接拒绝
     *
     *  Evaluator 甚至可以在 Bob 提交之前就拒绝--
     *  如果 Alice 描述不清、或者 Bob 身份不对，
     *  Eva 可以直接退单。
     *
     *  这展示了 Evaluator 的另一个权力：把关。
     * ═══════════════════════════════════════════════════════════ */

    function test_EvaluatorRejectsBeforeSubmission() public {
        uint256 jobId = _createJob();
        _fundJob(jobId);

        // ── Eva 评估后发现这个任务不合适，直接拒绝 ──
        vm.prank(eva);
        commerce.reject(jobId, keccak256("requirements_unclear"), "");

        // ── 验证：资金退款给 Alice ──
        AgenticCommerce.Job memory job = commerce.getJob(jobId);
        assertEq(uint256(job.status), uint256(AgenticCommerce.JobStatus.Rejected));
        assertEq(token.balanceOf(alice), INITIAL, "Alice refunded");

        emit log_string("[OK] Evaluator rejected before submission - Alice refunded");
    }
}
