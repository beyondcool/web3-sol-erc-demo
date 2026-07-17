// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title SimpleReputationRegistry
 * @notice ERC-8004 声誉注册表（Reputation Registry）教学示例
 * @dev
 *
 * ═══════════════════════════════════════════════════════════════════
 *  什么是 ERC-8004 Reputation Registry？
 * ═══════════════════════════════════════════════════════════════════
 *
 *  ▌ 我们为什么要它？
 *     Identity Registry 让 Agent 有了身份——但我们怎么知道它可不可信？
 *     "这个 Agent 说它能翻译，别人用过吗？效果怎么样？"
 *
 *     Reputation Registry 就是一个**链上的评价板**——
 *     任何用户都能给用过的 Agent 打分，分数全网公开。
 *
 *  ▌ 核心概念
 *     ┌───────────────┬───────────────────────────────────────┐
 *     │ 评价 (Feedback)│ 一个用户对某个 Agent 的评分 + 标签     │
 *     │ 评分值 (value) │ 0-100 的整数（如 85 = 85 分）         │
 *     │ 标签 (tag)     │ 分类维度（如 "翻译质量"、"响应速度"）  │
 *     │ 撤销 (Revoke)  │ 标记之前给的评价无效（不删除数据）     │
 *     └───────────────┴───────────────────────────────────────┘
 *
 *  ▌ 有了这个，你能做什么？
 *     ✅ 给 Agent 打分  → 分享你的使用体验
 *     ✅ 查询声誉      → 用之前先看别人的评价
 *     ✅ 合约集成      → 根据链上声誉决定是否调用某个 Agent
 *     ✅ 撤销评分      → 如果改主意了（保留审计轨迹，不真删除）
 *
 *  ▌ 链上 vs 链下
 *     - 链上存：评分、标签、是否撤销（轻量、快速）
 *     - 链下存：详细的评价文件（IPFS），链上存 hash 担保完整性
 *     - 本教学为了简洁只实现了链上部分
 *
 *  ⚠️ 防女巫攻击的重要说明
 *     本合约没有限制刷分——合约层面无法区分"100个真实用户"
 *     和"1个攻击者刷100条好评"。实际使用中，声誉系统应该：
 *       a) 只看特定白名单评价者的评分
 *       b) 在链下给不同评价者加权
 *       c) 要求评价者持有某种凭证
 *
 * ═══════════════════════════════════════════════════════════════════
 */

/**
 * @title IIdentityRegistry (简化接口)
 * @dev 只声明我们需要用到的函数
 */
interface IIdentityRegistry {
    function isRegistered(uint256 agentId) external view returns (bool);
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract SimpleReputationRegistry {

    // ═════════════════════════════════════════════════════════════
    //  数据结构定义
    // ═════════════════════════════════════════════════════════════

    /// @notice 一条评价记录
    /// @param value        评分（0-100，比如 85 分）
    /// @param valueDecimals 小数位数（0=整数，2=百分数精确到 0.01）
    /// @param tag1         分类标签（如 "quality"、"speed"）
    /// @param tag2         二级标签（可选，如 "zh_en" 表示中英翻译）
    /// @param isRevoked    是否已被评价者撤销
    struct Feedback {
        int128  value;
        uint8   valueDecimals;
        string  tag1;
        string  tag2;
        bool    isRevoked;
    }

    /// @notice 一个用户对某个 Agent 的所有评价
    /// @param count    评价总数（也是最新 feedbackIndex）
    /// @param feedbacks mapping 从 feedbackIndex 到 Feedback 记录
    struct UserFeedback {
        uint64 count;
        mapping(uint64 => Feedback) feedbacks;
    }

    // ═════════════════════════════════════════════════════════════
    //  状态变量
    // ═════════════════════════════════════════════════════════════

    /// @notice 关联的身份注册表合约地址（只读接口）
    IIdentityRegistry public identityRegistry;

    /// @notice 核心存储：agentId → 评价者地址 → 该评价者的所有评价
    mapping(uint256 => mapping(address => UserFeedback)) private _feedbacks;

    /// @notice 用于遍历：agentId → 所有给它评过分的用户列表
    mapping(uint256 => address[]) private _clients;

    /// @notice 辅助映射：快速判断某个用户是否已加入 _clients[agentId]
    mapping(uint256 => mapping(address => bool)) private _isClient;

    // ═════════════════════════════════════════════════════════════
    //  事件
    // ═════════════════════════════════════════════════════════════

    /// @notice 新评价提交时触发
    event NewFeedback(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64  feedbackIndex,
        int128  value,
        uint8   valueDecimals,
        string  tag1,
        string  tag2
    );

    /// @notice 评价被撤销时触发
    event FeedbackRevoked(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64  indexed feedbackIndex
    );

    // ═════════════════════════════════════════════════════════════
    //  构造函数
    // ═════════════════════════════════════════════════════════════

    /// @param identityRegistry_ 身份注册表合约地址
    /// @dev 构造时关联一个 IdentityRegistry，用于验证 agentId 是否合法。
    ///      真实部署时，IdentityRegistry 和 ReputationRegistry 是独立的两个合约，
    ///      通过这个引用关联起来。
    constructor(address identityRegistry_) {
        identityRegistry = IIdentityRegistry(identityRegistry_);
    }

    // ═════════════════════════════════════════════════════════════
    //  给 Agent 打分
    // ═════════════════════════════════════════════════════════════

    /**
     * @notice 提交对某个 Agent 的评价
     * @param agentId       被评价的 Agent ID（必须已注册）
     * @param value         评分值，如 85 表示 85/100
     * @param valueDecimals 小数位数（0 表示整数，2 表示 value 实际是 xx%）
     * @param tag1          主标签（例如 "quality", "speed", "uptime"）
     * @param tag2          次标签（可选，例如 "zh_en" 指定语种）
     *
     * @dev
     *  关键规则：
     *    ① Agent 所有者不能给自己的 Agent 打分（防止刷分）
     *    ② 同一个用户可以给同一个 Agent 多次打分
     *       （每次的 feedbackIndex 递增，可用于追踪变化）
     *    ③ valueDecimals 必须在 0-18 之间
     *
     *  数值示例：
     *    value=87,  decimals=0  → "87 分"
     *    value=9977, decimals=2 → "99.77%"
     *    value=560,  decimals=0 → "560ms"
     *    value=1,    decimals=0 → "可用/是"
     *
     *  标签示例：
     *    tag1="general"            → 总体评分
     *    tag1="translation", tag2="zh_en" → 中英翻译专项评分
     *    tag1="response_time"      → 响应速度评分
     */
    function giveFeedback(
        uint256 agentId,
        int128  value,
        uint8   valueDecimals,
        string  calldata tag1,
        string  calldata tag2
    ) external {
        // ── 前置检查 ────────────────────────────────────────
        require(identityRegistry.isRegistered(agentId), "Agent not registered");
        require(
            identityRegistry.ownerOf(agentId) != msg.sender,
            "Owner cannot rate own agent"
        );
        require(valueDecimals <= 18, "Decimals must be <= 18");

        // ── 存储评价 ────────────────────────────────────────
        UserFeedback storage userFeedbacks = _feedbacks[agentId][msg.sender];
        userFeedbacks.count++;
        uint64 feedbackIndex = userFeedbacks.count;

        userFeedbacks.feedbacks[feedbackIndex] = Feedback({
            value:         value,
            valueDecimals: valueDecimals,
            tag1:          tag1,
            tag2:          tag2,
            isRevoked:     false
        });

        // ── 首次评价时记录地址 ───────────────────────────────
        if (!_isClient[agentId][msg.sender]) {
            _isClient[agentId][msg.sender] = true;
            _clients[agentId].push(msg.sender);
        }

        emit NewFeedback(agentId, msg.sender, feedbackIndex, value, valueDecimals, tag1, tag2);
    }

    // ═════════════════════════════════════════════════════════════
    //  撤销评价
    // ═════════════════════════════════════════════════════════════

    /**
     * @notice 撤销自己之前提交的一条评价
     * @param agentId       Agent ID
     * @param feedbackIndex 要撤销的评价的索引（从 1 开始）
     *
     * @dev
     *  仅标记 isRevoked = true，**不删除数据**。
     *  这样做的好处：
     *    - 保留审计轨迹（不可抵赖）
     *    - 评价者可以反悔（改主意了可以撤销）
     *    - 查询时默认排除已撤销的评价
     */
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external {
        require(feedbackIndex > 0, "Invalid index");

        UserFeedback storage userFeedbacks = _feedbacks[agentId][msg.sender];
        require(feedbackIndex <= userFeedbacks.count, "Feedback does not exist");
        require(!userFeedbacks.feedbacks[feedbackIndex].isRevoked, "Already revoked");

        userFeedbacks.feedbacks[feedbackIndex].isRevoked = true;

        emit FeedbackRevoked(agentId, msg.sender, feedbackIndex);
    }

    // ═════════════════════════════════════════════════════════════
    //  查询函数
    // ═════════════════════════════════════════════════════════════

    /**
     * @notice 获取某个 Agent 的声誉摘要（平均分）
     * @param agentId     要查询的 Agent
     * @return count      有效评价条数（未撤销的）
     * @return avgValue   平均分（算术平均，整数）
     * @return avgDecimals 平均分的小数位数（取第一条记录的值）
     *
     * @dev
     *  这是最简单的链上聚合——取所有未撤销评价的算术平均。
     *
     *  ⚠️ 安全提示：
     *  链上聚合无法防女巫（1 个用户刷 100 条好评和 100 个真实用户
     *  各评 1 条，在这里看起来一样）。在生产系统中，应该：
     *  1. 在链下做加权聚合（给信誉好的评价者更高权重）
     *  2. 或通过 `getSummaryWithClients()` 只计算指定地址的评分
     */
    function getSummary(uint256 agentId)
        external
        view
        returns (uint64 count, int128 avgValue, uint8 avgDecimals)
    {
        address[] memory clients = _clients[agentId];
        int128 totalValue = 0;
        uint64 totalCount = 0;
        uint8 decimals = 0;

        for (uint256 i = 0; i < clients.length; i++) {
            UserFeedback storage userFeedbacks = _feedbacks[agentId][clients[i]];
            for (uint64 j = 1; j <= userFeedbacks.count; j++) {
                Feedback storage fb = userFeedbacks.feedbacks[j];
                if (!fb.isRevoked) {
                    totalValue += fb.value;
                    totalCount++;
                    // 取第一条记录的 decimals 作为参考
                    if (totalCount == 1) {
                        decimals = fb.valueDecimals;
                    }
                }
            }
        }

        if (totalCount > 0) {
            avgValue = totalValue / int128(uint128(totalCount));
        }

        return (totalCount, avgValue, decimals);
    }

    /**
     * @notice 读取一条具体的评价记录
     * @param agentId       Agent ID
     * @param client        评价者地址
     * @param feedbackIndex 评价索引（从 1 开始）
     */
    function readFeedback(uint256 agentId, address client, uint64 feedbackIndex)
        external
        view
        returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked)
    {
        Feedback storage fb = _feedbacks[agentId][client].feedbacks[feedbackIndex];
        return (fb.value, fb.valueDecimals, fb.tag1, fb.tag2, fb.isRevoked);
    }

    /// @notice 获取评价过指定 Agent 的所有用户地址列表
    function getClients(uint256 agentId) external view returns (address[] memory) {
        return _clients[agentId];
    }

    /// @notice 获取某个用户对指定 Agent 的评价总数
    /// @return 0 = 从未评价过
    function getLastIndex(uint256 agentId, address client) external view returns (uint64) {
        return _feedbacks[agentId][client].count;
    }

    // ═════════════════════════════════════════════════════════════
    //  进阶查询：按指定评价者列表过滤
    // ═════════════════════════════════════════════════════════════

    /**
     * @notice 只计算指定评价者的评分摘要（防女巫的实用方法）
     * @param agentId         要查询的 Agent
     * @param trustedClients  受信评价者地址列表
     * @return count          这些评价者的有效评价条数
     * @return avgValue       他们的平均分
     *
     * @dev
     *  这是"防女巫的实用打法"：调用者自己维护一份可信评价者名单
     *  （比如链下的 KYC 验证），只计算名单上的人的打分。
     *  这样女巫攻击者即使刷了 1000 条评分，只要不在名单里就不计入。
     */
    function getSummaryWithClients(
        uint256 agentId,
        address[] calldata trustedClients
    ) external view returns (uint64 count, int128 avgValue) {
        int128 totalValue = 0;
        uint64 totalCount = 0;

        for (uint256 i = 0; i < trustedClients.length; i++) {
            UserFeedback storage userFeedbacks = _feedbacks[agentId][trustedClients[i]];
            for (uint64 j = 1; j <= userFeedbacks.count; j++) {
                Feedback storage fb = userFeedbacks.feedbacks[j];
                if (!fb.isRevoked) {
                    totalValue += fb.value;
                    totalCount++;
                }
            }
        }

        if (totalCount > 0) {
            avgValue = totalValue / int128(uint128(totalCount));
        }

        return (totalCount, avgValue);
    }
}
