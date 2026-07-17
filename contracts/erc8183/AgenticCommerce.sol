// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ═══════════════════════════════════════════════════════════════════════
//  ERC-8183 标准接口
// ═══════════════════════════════════════════════════════════════════════
//
//  这个接口定义了 ERC-8183 协议的外部 API。任何兼容的合约都必须实现
//  这些函数和事件。对于教学，我们先把接口亮出来——让你看到"协议长什么样"，
//  再看实现怎么 work。
//
// ═══════════════════════════════════════════════════════════════════════

interface IERC8183 {

    // ── 事件 ──────────────────────────────────────────────────────

    /// @notice 新 Job 创建时触发
    event JobCreated(uint256 indexed jobId, address indexed client, address indexed provider, address evaluator, uint256 expiredAt, address hook);

    /// @notice 设置 Provider 时触发
    event ProviderSet(uint256 indexed jobId, address indexed provider);

    /// @notice 设置预算时触发
    event BudgetSet(uint256 indexed jobId, uint256 amount);

    /// @notice Job 资金到账时触发
    event JobFunded(uint256 indexed jobId, address indexed client, uint256 amount);

    /// @notice Provider 提交交付物时触发
    event JobSubmitted(uint256 indexed jobId, address indexed provider, bytes32 deliverable);

    /// @notice Evaluator 确认完成时触发
    event JobCompleted(uint256 indexed jobId, address indexed evaluator, bytes32 reason);

    /// @notice Evaluator 或 Client 拒绝 Job 时触发
    event JobRejected(uint256 indexed jobId, address indexed rejector, bytes32 reason);

    /// @notice Job 过期时触发（claimRefund 时）
    event JobExpired(uint256 indexed jobId);

    /// @notice 向 Provider 释放付款时触发
    event PaymentReleased(uint256 indexed jobId, address indexed provider, uint256 amount);

    /// @notice 向 Client 退款时触发
    event Refunded(uint256 indexed jobId, address indexed client, uint256 amount);

    // ── 核心生命周期函数 ────────────────────────────────────────────

    /// @notice 创建一个新的 Job（状态 = Open）
    /// @param provider   Provider 地址（可传 address(0) 后续用 setProvider 设置）
    /// @param evaluator  Evaluator 地址（不可为 address(0)）
    /// @param expiredAt  过期时间戳（unix 秒），此后可触发 claimRefund
    /// @param description Job 描述
    /// @param hook       Hook 合约地址（不使用时传 address(0)）
    /// @return jobId     新 Job 的 ID
    function createJob(
        address provider,
        address evaluator,
        uint256 expiredAt,
        string calldata description,
        address hook
    ) external returns (uint256 jobId);

    /// @notice 为没有 Provider 的 Job 设置 Provider（仅当 status = Open）
    function setProvider(uint256 jobId, address provider, bytes calldata optParams) external;

    /// @notice 设置 Job 预算（Client 或 Provider 都可调用，仅当 status = Open）
    function setBudget(uint256 jobId, uint256 amount, bytes calldata optParams) external;

    /// @notice Client 将预算转入托管（status: Open → Funded）
    /// @param expectedBudget 前端运行保护：必须等于当前 job.budget
    function fund(uint256 jobId, uint256 expectedBudget, bytes calldata optParams) external;

    /// @notice Provider 提交交付物（仅当 status = Funded）
    function submit(uint256 jobId, bytes32 deliverable, bytes calldata optParams) external;

    /// @notice Evaluator 确认完成 → 释放资金给 Provider（仅当 status = Submitted）
    function complete(uint256 jobId, bytes32 reason, bytes calldata optParams) external;

    /// @notice 拒绝 Job（调用者/状态/效果见下方详细注释）
    function reject(uint256 jobId, bytes32 reason, bytes calldata optParams) external;

    /// @notice 过期后任何人均可调用，将资金退还给 Client（仅当 Funded 或 Submitted）
    function claimRefund(uint256 jobId) external;
}


// ═══════════════════════════════════════════════════════════════════════
//  AgenticCommerce — ERC-8183 核心实现（教学简化版）
// ═══════════════════════════════════════════════════════════════════════
//
//  这是 ERC-8183 的核心合约，实现了以下核心机制：
//
//  ┌─────────────────────────────────────────────────────────────────┐
//  │                     Job 生命周期（状态机）                        │
//  │                                                                 │
//  │   Open ──(fund)──▶ Funded ──(submit)──▶ Submitted ──(complete)──▶ Completed  │
//  │    │                                    │                        │
//  │    ├──(client reject)──▶ Rejected       ├──(evaluator reject)──▶ Rejected   │
//  │    │                                    │                        │
//  │    └────────────────────────────────────┴──(expired)──▶ Expired            │
//  │                                                                 │
//  └─────────────────────────────────────────────────────────────────┘
//
//  三个角色：
//    • Client   — 发布任务 + 出钱       → 可 reject（Open 时）
//    • Provider — 干活 + 提交交付物      → 可 setBudget（协商价格）
//    • Evaluator— 验收工作              → 可 complete / reject（Funded/Submitted 时）
//
//  本版本为教学简化，省略了平台费（fee）和 Hook 系统的实现。
//
// ═══════════════════════════════════════════════════════════════════════

contract AgenticCommerce is IERC8183, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═════════════════════════════════════════════════════════════════
    //  枚举 & 结构体
    // ═════════════════════════════════════════════════════════════════

    /// @notice Job 的六种状态
    /// @dev Solidity 枚举从 0 开始自动编号
    enum JobStatus {
        Open,       // 0 — 已创建，尚未充值
        Funded,     // 1 — 资金已托管
        Submitted,  // 2 — 已提交交付物
        Completed,  // 3 — 已完成（终态）
        Rejected,   // 4 — 已拒绝（终态）
        Expired     // 5 — 已过期（终态）
    }

    /// @notice Job 的数据结构
    struct Job {
        address     client;         // 任务发布者
        address     provider;       // 任务执行者
        address     evaluator;      // 验收者（唯一有权 complete/reject 的人）
        string      description;    // 任务描述（自由文本）
        uint256     budget;         // 预算金额（ERC-20 代币数量）
        uint256     expiredAt;      // 过期时间戳（unix 秒）
        JobStatus   status;         // 当前状态
        address     hook;           // Hook 合约地址（本教学版未实现）
        bytes32     deliverable;    // 交付物哈希（由 Provider 提交）
    }

    // ═════════════════════════════════════════════════════════════════
    //  状态变量
    // ═════════════════════════════════════════════════════════════════

    /// @dev _nextJobId: 自增 Job ID，从 1 开始（0 代表"空"）
    uint256 private _nextJobId;

    /// @dev _jobs: jobId → Job 的映射
    mapping(uint256 => Job) private _jobs;

    /// @dev paymentToken: 本合约使用的 ERC-20 代币地址（不可更改）
    ///      所有 Job 共用同一种代币，保持简单。
    IERC20 public immutable paymentToken;

    // ═════════════════════════════════════════════════════════════════
    //  自定义错误（Gas 更省，信息更丰富）
    // ═════════════════════════════════════════════════════════════════

    error Unauthorized(address caller);
    error InvalidStatus(JobStatus current, string expected);
    error AlreadySet();
    error ZeroAddress();
    error ZeroBudget();
    error ExpiredDeadline();
    error BudgetMismatch(uint256 expected, uint256 actual);
    error ProviderNotSet();

    // ═════════════════════════════════════════════════════════════════
    //  构造函数
    // ═════════════════════════════════════════════════════════════════

    /// @param _paymentToken 本合约使用的 ERC-20 代币地址
    constructor(IERC20 _paymentToken) {
        require(address(_paymentToken) != address(0), "Invalid token");
        paymentToken = _paymentToken;
        _nextJobId = 1;
    }

    // ═════════════════════════════════════════════════════════════════
    //  创建 —— createJob
    // ═════════════════════════════════════════════════════════════════

    /**
     * @notice 创建一个新的 Job，调用者自动成为 Client
     * @param provider   执行者地址（可传 address(0) → 后续用 setProvider 设置）
     * @param evaluator  验收者地址（不可为 address(0) — 否则没人能 complete/reject）
     * @param expiredAt  过期时间戳（必须在未来）
     * @param description 任务描述
     * @param hook       Hook 合约（本教学版传 address(0)）
     * @return jobId     新 Job 的 ID
     *
     * @dev
     *  创建后 Job 处于 Open 状态，尚未涉及资金。
     *  此时 Client 可以：① setBudget + fund → 充值；② reject → 取消。
     */
    function createJob(
        address provider,
        address evaluator,
        uint256 expiredAt,
        string calldata description,
        address hook
    ) external returns (uint256 jobId) {
        // ── 校验 ──
        require(evaluator != address(0), "Evaluator cannot be zero");
        require(expiredAt > block.timestamp, "expiredAt must be in the future");

        // ── 分配 ID ──
        jobId = _nextJobId;
        _nextJobId++;

        // ── 存储 Job ──
        Job storage job = _jobs[jobId];
        job.client      = msg.sender;
        job.provider    = provider;
        job.evaluator   = evaluator;
        job.description = description;
        job.expiredAt   = expiredAt;
        job.status      = JobStatus.Open;
        job.hook        = hook;
        // budget = 0（默认）, deliverable = 0（默认）

        emit JobCreated(jobId, msg.sender, provider, evaluator, expiredAt, hook);
    }

    // ═════════════════════════════════════════════════════════════════
    //  设置 Provider —— setProvider
    // ═════════════════════════════════════════════════════════════════

    /**
     * @notice 为没有 Provider 的 Job 设置 Provider
     * @dev 仅 Client 可调用，仅当 status = Open 且 provider 尚未设置
     */
    function setProvider(
        uint256 jobId,
        address provider,
        bytes calldata /*optParams*/
    ) external {
        Job storage job = _jobs[jobId];

        require(job.client == msg.sender, "Only client");
        require(job.status == JobStatus.Open, "Not Open");
        require(job.provider == address(0), "Provider already set");
        require(provider != address(0), "Provider cannot be zero");

        job.provider = provider;

        emit ProviderSet(jobId, provider);
    }

    // ═════════════════════════════════════════════════════════════════
    //  设置预算 —— setBudget
    // ═════════════════════════════════════════════════════════════════

    /**
     * @notice 设置 Job 的预算金额
     * @dev Client 或 Provider 都可调用。这允许双方"协商"价格：
     *      - Client 说："我出 100 个代币"
     *      - Provider 说："我要 200" → setBudget(200)
     *      - Client 可以接受（fund 200）或拒绝（reject 重来）
     *
     *      仅当 status = Open 时可用。
     *      fund 时还会通过 expectedBudget 做第二道保护。
     */
    function setBudget(
        uint256 jobId,
        uint256 amount,
        bytes calldata /*optParams*/
    ) external {
        Job storage job = _jobs[jobId];

        // ── 谁可以调用：Client 或 Provider ──
        require(
            msg.sender == job.client || msg.sender == job.provider,
            "Only client or provider"
        );
        require(job.status == JobStatus.Open, "Not Open");
        require(amount > 0, "Budget must be > 0");

        job.budget = amount;

        emit BudgetSet(jobId, amount);
    }

    // ═════════════════════════════════════════════════════════════════
    //  充值 —— fund
    // ═════════════════════════════════════════════════════════════════

    /**
     * @notice Client 将预算金额转入托管合约（状态: Open → Funded）
     * @param expectedBudget 预期金额。如果其他人（如 Provider）用 setBudget
     *                       改了金额，fund 会因为 expectedBudget != job.budget
     *                       而 revert——这就是"前端运行保护"。
     *
     * @dev
     *  核心逻辑：
     *    ① 各种校验（状态、调用者、Provider 已设置、金额匹配）
     *    ② 将 budget 从 Client 转账到本合约（托管）
     *    ③ 状态更新为 Funded
     *
     *  使用 ReentrancyGuard 防止重入攻击。
     */
    function fund(
        uint256 jobId,
        uint256 expectedBudget,
        bytes calldata /*optParams*/
    ) external nonReentrant {
        Job storage job = _jobs[jobId];

        // ── 校验 ──
        require(job.client == msg.sender, "Only client");
        require(job.status == JobStatus.Open, "Not Open");
        require(job.provider != address(0), "Provider not set");
        require(job.budget > 0, "Budget not set");
        require(job.budget == expectedBudget, "Budget mismatch");
        require(block.timestamp <= job.expiredAt, "Job expired");

        // ── 更新状态 ──
        job.status = JobStatus.Funded;

        // ── 转账：Client → 本合约 ──
        //  使用 SafeERC20 确保转账成功（否则 revert 回滚状态）
        paymentToken.safeTransferFrom(msg.sender, address(this), job.budget);

        emit JobFunded(jobId, msg.sender, job.budget);
    }

    // ═════════════════════════════════════════════════════════════════
    //  提交 —— submit
    // ═════════════════════════════════════════════════════════════════

    /**
     * @notice Provider 提交交付物（状态: Funded → Submitted）
     * @param deliverable 交付物的哈希值（bytes32）
     *
     * @dev
     *  deliverable 是链下文件的哈希（如 IPFS CID 的 hash）。
     *  Evaluator 根据这个哈希拿到链下文件，检查是否满足要求。
     *  ┌──────────────────────────────────────────────────────────┐
     *  │  为什么是哈希？                                           │
     *  │  链上存不了大文件，所以存"指纹"（哈希）。                    │
     *  │  Evaluator 在链下打开文件，自己算一遍哈希，                  │
     *  │  对上 → 文件没被篡改。                                     │
     *  └──────────────────────────────────────────────────────────┘
     */
    function submit(
        uint256 jobId,
        bytes32 deliverable,
        bytes calldata /*optParams*/
    ) external {
        Job storage job = _jobs[jobId];

        require(msg.sender == job.provider, "Only provider");
        require(job.status == JobStatus.Funded, "Not Funded");
        require(deliverable != bytes32(0), "Deliverable cannot be empty");

        job.status = JobStatus.Submitted;
        job.deliverable = deliverable;

        emit JobSubmitted(jobId, msg.sender, deliverable);
    }

    // ═════════════════════════════════════════════════════════════════
    //  完成 —— complete
    // ═════════════════════════════════════════════════════════════════

    /**
     * @notice Evaluator 确认工作完成（状态: Submitted → Completed）
     * @param reason 完成原因或备注（如 "交付物质量合格"）
     *
     * @dev
     *  这一步触发资金释放：
     *    本合约 → Provider（扣除平台费，但本教学版没有平台费）
     *
     *  只有 Evaluator 可以调用。Evaluator 可以是：
     *    • 另一个 AI Agent（自动检查交付物质量）
     *    • 一个 ZK 验证合约（自动验证计算结果）
     *    • 一个多签钱包（人工仲裁）
     *    协议不关心 Evaluator 是什么，只关心谁调用 complete/reject。
     */
    function complete(
        uint256 jobId,
        bytes32 reason,
        bytes calldata /*optParams*/
    ) external {
        Job storage job = _jobs[jobId];

        require(msg.sender == job.evaluator, "Only evaluator");
        require(job.status == JobStatus.Submitted, "Not Submitted");
        require(block.timestamp <= job.expiredAt, "Job expired");

        // ── 更新状态 ──
        job.status = JobStatus.Completed;

        // ── 释放资金：合约 → Provider ──
        uint256 amount = job.budget;
        paymentToken.safeTransfer(job.provider, amount);

        emit JobCompleted(jobId, msg.sender, reason);
        emit PaymentReleased(jobId, job.provider, amount);
    }

    // ═════════════════════════════════════════════════════════════════
    //  拒绝 —— reject
    // ═════════════════════════════════════════════════════════════════

    /**
     * @notice 拒绝 Job，根据状态和调用者不同行为不同：
     *
     *  ┌──────────┬──────────────────┬──────────────────────────┐
     *  │ 状态      │ 谁可以调用        │ 效果                     │
     *  ├──────────┼──────────────────┼──────────────────────────┤
     *  │ Open     │ Client           │ 取消 Job（无资金退回）     │
     *  │ Funded   │ Evaluator        │ 拒绝 + 退款给 Client      │
     *  │ Submitted│ Evaluator        │ 拒绝 + 退款给 Client      │
     *  └──────────┴──────────────────┴──────────────────────────┘
     *
     *  注意：
     *    - 过期后（block.timestamp > expiredAt）不能 reject，
     *      只能用 claimRefund。
     *    - 退款金额 = job.budget（全额退还）。
     */
    function reject(
        uint256 jobId,
        bytes32 reason,
        bytes calldata /*optParams*/
    ) external {
        Job storage job = _jobs[jobId];

        if (job.status == JobStatus.Open) {
            // ── Client 取消未充值的 Job ──
            require(msg.sender == job.client, "Only client can reject Open job");
            job.status = JobStatus.Rejected;

            emit JobRejected(jobId, msg.sender, reason);

        } else if (job.status == JobStatus.Funded || job.status == JobStatus.Submitted) {
            // ── Evaluator 拒绝已充值的 Job ──
            require(msg.sender == job.evaluator, "Only evaluator can reject");
            require(block.timestamp <= job.expiredAt, "Job expired, use claimRefund");

            job.status = JobStatus.Rejected;

            // 退款给 Client
            uint256 amount = job.budget;
            paymentToken.safeTransfer(job.client, amount);

            emit JobRejected(jobId, msg.sender, reason);
            emit Refunded(jobId, job.client, amount);

        } else {
            revert("Cannot reject in current status");
        }
    }

    // ═════════════════════════════════════════════════════════════════
    //  申请退款 —— claimRefund
    // ═════════════════════════════════════════════════════════════════

    /**
     * @notice 过期后任何人均可调用，将托管资金退还给 Client
     *
     * @dev
     *  这是 ERC-8183 的一个重要安全机制：即使 Client、Provider、Evaluator
     *  全部掉线，资金也不会卡在合约里。任何人（包括一个定时脚本）都可以
     *  在 expiredAt 之后调用此函数，触发退款。
     *
     *  适用状态：Funded 或 Submitted。
     *  不适用状态：Open（无资金）、Completed/Rejected（已是终态）。
     *
     *  ⚠️ 本函数不可被 Hook 拦截（规范明确禁止），保证永远可调用。
     */
    function claimRefund(uint256 jobId) external nonReentrant {
        Job storage job = _jobs[jobId];

        require(
            job.status == JobStatus.Funded || job.status == JobStatus.Submitted,
            "Not refundable"
        );
        require(block.timestamp > job.expiredAt, "Not expired yet");

        job.status = JobStatus.Expired;

        uint256 amount = job.budget;
        paymentToken.safeTransfer(job.client, amount);

        emit JobExpired(jobId);
        emit Refunded(jobId, job.client, amount);
    }

    // ═════════════════════════════════════════════════════════════════
    //  查询函数
    // ═════════════════════════════════════════════════════════════════

    /// @notice 获取 Job 的完整信息
    /// @return 包含 Job 所有字段的结构体
    /// @dev 教学辅助函数——方便学生检查每个字段的值
    function getJob(uint256 jobId) external view returns (Job memory) {
        require(jobId > 0 && jobId < _nextJobId, "Job does not exist");
        return _jobs[jobId];
    }

    /// @notice 获取当前 Job ID 计数器（下一个 Job 的 ID）
    /// @dev 可用于计算已创建的 Job 总数：currentJobId - 1
    function currentJobId() external view returns (uint256) {
        return _nextJobId;
    }

    /// @notice 将 JobStatus 枚举转为人类可读的字符串（教学辅助）
    function statusToString(JobStatus status) external pure returns (string memory) {
        if (status == JobStatus.Open)       return "Open";
        if (status == JobStatus.Funded)     return "Funded";
        if (status == JobStatus.Submitted)  return "Submitted";
        if (status == JobStatus.Completed)  return "Completed";
        if (status == JobStatus.Rejected)   return "Rejected";
        if (status == JobStatus.Expired)    return "Expired";
        return "Unknown";
    }
}
