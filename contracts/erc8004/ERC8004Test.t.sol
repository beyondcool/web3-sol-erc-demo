// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SimpleIdentityRegistry} from "./SimpleIdentityRegistry.sol";
import {SimpleReputationRegistry} from "./SimpleReputationRegistry.sol";

/**
 * @title ERC8004Test
 * @notice ERC-8004 Trustless Agents 协议的教学测试
 *
 * ═══════════════════════════════════════════════════════════════
 *  测试目标：理解 ERC-8004 的核心流程
 * ═══════════════════════════════════════════════════════════════
 *
 *  场景设定：
 *    Alice 开发了一个 AI 翻译 Agent，她想把它注册到链上，
 *    让别人可以找到并使用它。Bob 和 Charlie 用了这个 Agent 后
 *    给它打分。Dave 想用这个 Agent，先查了一下它的声誉。
 *
 *  核心认知：
 *    ERC-8004 不定义 Agent 怎么工作（那是 MCP/A2A 的事），
 *    它定义 Agent 怎么**被发现和信任**——
 *    就像 LinkedIn 让人找到你，Trustpilot 让人信任你。
 *
 *  ═══════════════════════════════════════════════════════════════
 *
 *  📊 这个测试文件涵盖的场景：
 *    Test 1: ✅ 注册 Agent → IdentityRegistry 基础功能
 *    Test 2: ✅ 打分和查询 → ReputationRegistry 核心流程
 *    Test 3: ❌ Agent 所有者不能给自己打分 → 防刷分机制
 *    Test 4: ✅ 撤销评价 → 反悔机制
 *    Test 5: ✅ 更新 Agent 信息 → 修改 URI
 *    Test 6: ✅ 发现 Agent → 遍历所有已注册的 Agent
 */
contract ERC8004Test is Test {

    /* ─────────── 测试角色 ─────────── */

    address public alice;       // Agent 开发者/所有者
    address public bob;         // 用户1（用了 Agent 后打分）
    address public charlie;     // 用户2（也用了 Agent）
    address public dave;        // 潜在用户（查声誉决定是否使用）

    /* ─────────── 合约 ─────────── */

    SimpleIdentityRegistry      public identityRegistry;
    SimpleReputationRegistry    public reputationRegistry;

    /* ─────────── Agent 信息 ─────────── */

    string constant AGENT_URI = "ipfs://QmXyZExampleAgentURI";
    string constant AGENT_URI_V2 = "ipfs://QmUpdatedAgentURI";

    /* ═══════════════════════════════════════════════════════════
     *  测试准备
     * ═══════════════════════════════════════════════════════════ */

    function setUp() public {
        // ── 创建角色 ──
        alice   = makeAddr("alice");    // AI Agent 的开发者
        bob     = makeAddr("bob");      // 用户1
        charlie = makeAddr("charlie");  // 用户2
        dave    = makeAddr("dave");     // 潜在用户

        // ── 部署 ERC-8004 组件 ──
        // ① IdentityRegistry：Agent 注册表
        identityRegistry = new SimpleIdentityRegistry();

        // ② ReputationRegistry：声誉系统，需要关联身份注册表
        reputationRegistry = new SimpleReputationRegistry(address(identityRegistry));
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 1：注册 Agent
     *
     *  这是 ERC-8004 的起点——把 Agent "搬上链"。
     *
     *  发生什么：
     *    1. Alice 调用 register()
     *    2. 合约铸造一个 NFT，tokenId = 1
     *    3. Alice 成为这个 Agent 的所有者
     *    4. agentURI 指向一个描述 Agent 的 JSON 文件
     *
     *  理解重点：
     *    - Agent 是 NFT！可以转账、可以在 OpenSea 展示
     *    - agentURI 指向的是"注册信息文件"，不是元数据图片
     *    - 注册之后任何人都可以查询这个 Agent
     * ═══════════════════════════════════════════════════════════ */

    function test_RegisterAgent() public {
        // ── 步骤 ①：Alice 注册 Agent ──
        vm.prank(alice);
        uint256 agentId = identityRegistry.register(AGENT_URI);

        // ── 步骤 ②：验证注册结果 ──

        // ✅ agentId = 1（第一个注册的 Agent）
        assertEq(agentId, 1, "First agent should have ID 1");

        // ✅ Agent 的所有者是 Alice（NFT 在 Alice 手里）
        assertEq(identityRegistry.ownerOf(agentId), alice, "Owner should be Alice");

        // ✅ tokenURI 指向我们设置的注册信息
        assertEq(identityRegistry.tokenURI(agentId), AGENT_URI, "URI should match");

        // ✅ 注册总数 = 1
        assertEq(identityRegistry.totalAgents(), 1, "Total agents should be 1");

        // ✅ isRegistered 返回 true
        assertTrue(identityRegistry.isRegistered(agentId), "Agent should be registered");

        // ✅ getAgentProfile 返回完整信息
        (address owner, string memory uri, uint256 total) = identityRegistry.getAgentProfile(agentId);
        assertEq(owner, alice, "Profile owner should be Alice");
        assertEq(uri, AGENT_URI, "Profile URI should match");
        assertEq(total, 1, "Profile total should be 1");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 2：打分和查询声誉
     *
     *  注册只是第一步。关键在于——这个 Agent 到底好不好用？
     *
     *  场景：
     *    Bob 和 Charlie 都用了 Alice 的翻译 Agent。
     *    Bob 觉得不错（85分），Charlie 觉得非常好（92分）。
     *    他们各自在链上打了分。
     *    Dave 想用这个 Agent，先查一下大家的评价。
     *
     *  理解重点：
     *    - 打分是完全公开的
     *    - 任何人都可以打分（除了 Agent 所有者）
     *    - 标签（tag）让查询更有意义
     *    - 链上的聚合评分可以被其他合约直接调用
     * ═══════════════════════════════════════════════════════════ */

    function test_FeedbackAndReputation() public {
        // ── 先注册 Agent ──
        vm.prank(alice);
        uint256 agentId = identityRegistry.register(AGENT_URI);

        // ── 步骤 ①：Bob 打分（85 分，标签 "translation"） ──
        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 85, 0, "translation", "zh_en");

        // ── 步骤 ②：Charlie 打分（92 分，标签 "translation"） ──
        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 92, 0, "translation", "zh_en");

        // ── 步骤 ③：Dave 想用这个 Agent，先查声誉 ──
        (uint64 count, int128 avg, uint8 decimals) = reputationRegistry.getSummary(agentId);

        // ✅ 有 2 条评价
        assertEq(count, 2, "Should have 2 feedbacks");

        // ✅ 平均分 = (85 + 92) / 2 = 88（整数除法）
        assertEq(avg, 88, "Average should be 88");

        // ✅ 小数位数 = 0（因为 Bob 和 Charlie 都用了 decimals=0）
        assertEq(decimals, 0, "Decimals should be 0");

        // ── Dave 查完："嗯，88 分，不错，用这个 Agent" ──
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 3：Agent 所有者不能给自己打分
     *
     *  如果 Alice 可以给自己打 100 分，声誉系统就没有意义了。
     *  这是防刷分的第一道防线。
     * ═══════════════════════════════════════════════════════════ */

    function test_OwnerCannotRateOwnAgent() public {
        // ── Alice 注册 Agent ──
        vm.prank(alice);
        uint256 agentId = identityRegistry.register(AGENT_URI);

        // ── Alice 想给自己 Agent 打 100 分... ──
        vm.prank(alice);

        // ❌ 被拒绝！"Owner cannot rate own agent"
        vm.expectRevert("Owner cannot rate own agent");
        reputationRegistry.giveFeedback(agentId, 100, 0, "general", "");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 4：撤销评价
     *
     *  Bob 一开始给了 85 分，后来觉得这个 Agent 升级后更好了，
     *  想撤销之前的低分重新打。
     *
     *  理解重点：
     *    - 评价是"逻辑删除"（isRevoked = true），不是物理删除
     *    - 数据不可篡改，但可以被标记为无效
     *    - getSummary() 自动排除已撤销的评价
     * ═══════════════════════════════════════════════════════════ */

    function test_RevokeFeedback() public {
        // ── 注册 Agent ──
        vm.prank(alice);
        uint256 agentId = identityRegistry.register(AGENT_URI);

        // ── Bob 第一次打分：85 ──
        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 85, 0, "general", "");

        // ── 查一下：平均分 85 ──
        (, int128 avgBefore,) = reputationRegistry.getSummary(agentId);
        assertEq(avgBefore, 85, "Average should be 85 before revoke");

        // ── Bob 想撤销这个评价 ──
        vm.prank(bob);
        reputationRegistry.revokeFeedback(agentId, 1);  // feedbackIndex = 1

        // ── 再查：已撤销，不计入，评价条数为 0 ──
        (uint64 countAfter,,) = reputationRegistry.getSummary(agentId);
        assertEq(countAfter, 0, "Count should be 0 after revoke");

        // ── 但仍能读取到原始数据（审计轨迹） ──
        (int128 value,, , , bool isRevoked) = reputationRegistry.readFeedback(agentId, bob, 1);
        assertEq(value, 85, "Original value preserved");
        assertTrue(isRevoked, "Should be marked as revoked");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 5：更新 Agent 信息
     *
     *  Alice 的 Agent 升级了 API，从 v1 变到 v2。
     *  她只需要更新 URI 指向新的注册文件——不需要重新注册。
     *
     *  理解重点：
     *    - agentId 不变，身份不变，注册信息变
     *    - 声誉记录不会因为 URI 更新而消失
     *    - 只有 Agent 所有者才能更新
     * ═══════════════════════════════════════════════════════════ */

    function test_UpdateAgentURI() public {
        // ── 注册 Agent（v1） ──
        vm.prank(alice);
        uint256 agentId = identityRegistry.register(AGENT_URI);

        // ── 确认原始 URI ──
        assertEq(identityRegistry.tokenURI(agentId), AGENT_URI);

        // ── 升级到 v2 ──
        vm.prank(alice);
        identityRegistry.setAgentURI(agentId, AGENT_URI_V2);

        // ✅ URI 已更新
        assertEq(
            identityRegistry.tokenURI(agentId),
            AGENT_URI_V2,
            "URI should be updated to v2"
        );

        // ── 非所有者不能更新 ──
        vm.prank(bob);
        vm.expectRevert("Only agent owner can update");
        identityRegistry.setAgentURI(agentId, "ipfs://malicious");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 6：发现 Agent
     *
     *  ERC-8004 的一个重要功能：让用户发现可用的 Agent。
     *  任何人都可以遍历所有已注册的 Agent，查看它们的
     *  描述、服务和声誉。
     *
     *  想象一个"Agent 应用商店"——
     *  前端从合约读取所有 agentId，从 URI 获取注册信息，
     *  从 ReputationRegistry 获取评分——展示给用户。
     * ═══════════════════════════════════════════════════════════ */

    function test_DiscoverAgents() public {
        // ── 三个不同的开发者注册了自己的 Agent ──
        address translator = makeAddr("translator");
        address coder = makeAddr("coder");
        address artist = makeAddr("artist");

        vm.prank(translator);
        identityRegistry.register("ipfs://translator-agent");
        vm.prank(coder);
        identityRegistry.register("ipfs://code-review-agent");
        vm.prank(artist);
        identityRegistry.register("ipfs://art-generator");

        // ── 发现 Agent：遍历所有 ID ──
        uint256[] memory allIds = identityRegistry.getAllAgentIds();
        uint256 total = identityRegistry.totalAgents();

        assertEq(total, 3, "Should have 3 agents");
        assertEq(allIds.length, 3, "Should find 3 agent IDs");

        // ── 查询每个 Agent 的信息 ──
        for (uint256 i = 0; i < allIds.length; i++) {
            uint256 id = allIds[i];
            (address owner, string memory uri,) = identityRegistry.getAgentProfile(id);

            // 每个 Agent 都有所有者（不为零地址）
            assertTrue(owner != address(0), "Agent must have an owner");

            // URI 不为空
            assertTrue(bytes(uri).length > 0, "Agent must have a URI");

            // 打印信息（在 forge test -vv 中可见）
            emit log_named_address("Agent Owner", owner);
            emit log_named_string("Agent URI", uri);
        }
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 7（Bonus）：完整场景——注册 → 使用 → 打分 → 发现
     *
     *  把上面所有步骤串起来，模拟一个完整的"Agent 经济"流程。
     * ═══════════════════════════════════════════════════════════ */

    function test_FullScenario() public {
        // ── ① Alice 注册翻译 Agent ──
        vm.prank(alice);
        uint256 agentId = identityRegistry.register(AGENT_URI);
        assertEq(agentId, 1);

        // ── ② Bob 用了，觉得很不错，打 90 分 ──
        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 90, 0, "translation", "zh_en");

        // ── ③ Dave 在"Agent 商店"里发现了这个 Agent ──
        uint256[] memory ids = identityRegistry.getAllAgentIds();
        assertEq(ids.length, 1, "Found 1 agent in registry");

        // 查看 Agent 信息
        string memory uriFromProfile = identityRegistry.tokenURI(agentId);
        assertEq(uriFromProfile, AGENT_URI);

        // 查看声誉
        (, int128 avg,) = reputationRegistry.getSummary(agentId);

        // ── ④ Dave 看到 90 分：决定使用这个 Agent ✅ ──
        assertTrue(avg >= 80, "Score is above threshold, Dave uses the agent");

        // ── ⑤ Dave 用了之后也觉得不错，打 88 分 ──
        vm.prank(dave);
        reputationRegistry.giveFeedback(agentId, 88, 0, "translation", "en_jp");

        // ── ⑥ 声誉更新：平均分变成 (90 + 88) / 2 = 89 ──
        (, int128 newAvg,) = reputationRegistry.getSummary(agentId);
        assertEq(newAvg, 89, "Average should be 89 after Dave's feedback");
    }
}
