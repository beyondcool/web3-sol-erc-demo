// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title SimpleIdentityRegistry
 * @notice ERC-8004 身份注册表（Identity Registry）教学示例
 * @dev
 *
 * ═══════════════════════════════════════════════════════════════════
 *  什么是 ERC-8004 Identity Registry？
 * ═══════════════════════════════════════════════════════════════════
 *
 *  Identity Registry 是 ERC-8004 协议最核心的组件。
 *  它让 AI Agent（智能代理）在区块链上拥有一个独一无二的、可验证的
 *  链上身份。
 *
 *  ▌ 现实类比
 *     就像公司有营业执照号，AI Agent 在这里有唯一的 agentId。
 *     公司详情存在工商系统，Agent 详情存在 URI 指向的 JSON 文件。
 *     NFT 的所有者 = 该 Agent 的"法人"。
 *
 *  ▌ 为什么用 ERC-721（NFT）？
 *     ┌──────────────┬────────────────────────────────────┐
 *     │ 唯一性       │ 每个 agentId 全局唯一，不会撞车       │
 *     │ 所有权       │ 谁持有 NFT，谁控制 Agent            │
 *     │ 可转让       │ Agent 能像 NFT 一样转手             │
 *     │ 兼容性       │ OpenSea、钱包等都能展示 Agent       │
 *     └──────────────┴────────────────────────────────────┘
 *
 *  ▌ 有了这个，你能做什么？
 *     ✅ 注册 Agent    → 给它一个链上身份
 *     ✅ 更新信息      → 修改 URI（升级 API、改联系方式等）
 *     ✅ 发现 Agent    → 遍历所有已注册的 Agent
 *     ✅ 验证身份      → 任何合约都能查 "这个 agentId 真存在吗？"
 *     ✅ 转让控制权    → NFT 转给其他人
 *
 * ═══════════════════════════════════════════════════════════════════
 */

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

/**
 * @dev 本合约直接使用 ERC721URIStorage：
 *      - ERC721 提供 NFT 基础（铸造、转账、查询）
 *      - URIStorage 为每个 tokenId 存储独立的 URI（即 agentURI）
 *
 *      不需要 Ownable——因为"谁可以更新 Agent 信息"的权限
 *      由 ERC-721 的所有权机制（ownerOf）天然提供。
 */
contract SimpleIdentityRegistry is ERC721URIStorage {

    // ═════════════════════════════════════════════════════════════
    //  状态变量
    // ═════════════════════════════════════════════════════════════

    /// @dev _nextTokenId: 自增的 agentId，从 1 开始（0 通常代表"空"）
    uint256 private _nextTokenId;

    /// @dev _allAgentIds: 记录所有注册过的 agentId，用于枚举查询
    uint256[] private _allAgentIds;

    // ═════════════════════════════════════════════════════════════
    //  事件
    // ═════════════════════════════════════════════════════════════

    /// @notice 新 Agent 注册时触发
    /// @param agentId  新分配的 Agent ID
    /// @param agentURI 指向注册信息文件的 URI
    /// @param owner    初始所有者
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);

    /// @notice Agent 信息更新时触发
    /// @param agentId  更新的 Agent
    /// @param newURI   新的 URI
    /// @param updatedBy 操作者
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);

    // ═════════════════════════════════════════════════════════════
    //  构造函数
    // ═════════════════════════════════════════════════════════════

    constructor() ERC721("ERC8004 Agent Identity", "AGENT") {
        _nextTokenId = 1;   // agentId 从 1 开始
    }

    // ═════════════════════════════════════════════════════════════
    //  注册 —— 创建一个新 Agent
    // ═════════════════════════════════════════════════════════════

    /**
     * @notice 注册一个新的 AI Agent，获得唯一的链上身份
     * @param agentURI 指向 Agent 注册信息文件的 URI
     * @return agentId 新分配的 Agent ID
     *
     * @dev
     *  调用流程（三步）：
     *    ① _safeMint(msg.sender, agentId) → 铸造 NFT
     *    ② _setTokenURI(agentId, agentURI) → 设置注册信息
     *    ③ 记录到 _allAgentIds → 方便遍历查询
     *
     *  agentURI 可以指向任意格式的存储，ERC-8004 规范建议的结构：
     *
     *    ipfs://QmXyZ...              → 存在 IPFS（推荐）
     *    https://agent.example.com/   → 存在 Web 服务器
     *    data:application/json;base64,... → 全部塞进链上交易
     *
     *  ════════════════════════════════════════════════════
     *  注册文件的 JSON 结构（必须包含 type 和 name）：
     *  ════════════════════════════════════════════════════
     *  {
     *    "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
     *    "name": "MyAgent",
     *    "description": "我是做什么的",
     *    "image": "https://example.com/avatar.png",
     *    "services": [
     *      { "name": "MCP", "endpoint": "https://...", "version": "..." },
     *      { "name": "email", "endpoint": "hello&commat;agent.com" }
     *    ]
     *  }
     *
     *  这个文件描述了 Agent 是谁、怎么联系、提供什么服务。
     */
    function register(string calldata agentURI) external returns (uint256 agentId) {
        agentId = _nextTokenId;
        _nextTokenId++;

        // ① 铸造 NFT，调用者成为 Agent 所有者
        _safeMint(msg.sender, agentId);

        // ② 设置 agentURI（ERC721URIStorage 的功能）
        _setTokenURI(agentId, agentURI);

        // ③ 添加进列表，方便遍历
        _allAgentIds.push(agentId);

        emit Registered(agentId, agentURI, msg.sender);
    }

    // ═════════════════════════════════════════════════════════════
    //  更新 —— 修改 Agent 的注册信息
    // ═════════════════════════════════════════════════════════════

    /**
     * @notice 更新 Agent 的注册信息 URI
     * @param agentId 要更新的 Agent
     * @param newURI  新的 URI
     *
     * @dev
     *  只有 Agent 的所有者（ownerOf）可以更新。
     *  因为信息存在链下 JSON 文件里，更新 URI 相当于"换了一页简介"。
     *
     *  什么时候需要更新？
     *    - Agent 换了 API 地址（从 v1 升到 v2）
     *    - 更新了服务描述或定价
     *    - 添加新的联系方式
     */
    function setAgentURI(uint256 agentId, string calldata newURI) external {
        require(ownerOf(agentId) == msg.sender, "Only agent owner can update");
        _setTokenURI(agentId, newURI);
        emit URIUpdated(agentId, newURI, msg.sender);
    }

    // ═════════════════════════════════════════════════════════════
    //  查询函数
    // ═════════════════════════════════════════════════════════════

    /// @notice 查询已注册的 Agent 总数
    function totalAgents() external view returns (uint256) {
        return _allAgentIds.length;
    }

    /// @notice 获取所有已注册的 Agent ID 列表（用于"发现 Agent"）
    function getAllAgentIds() external view returns (uint256[] memory) {
        return _allAgentIds;
    }

    /// @notice 检查某个 agentId 是否已被注册
    /// @dev 使用内部的 _ownerOf（不 revert）来判断是否存在
    function isRegistered(uint256 agentId) external view returns (bool) {
        return _ownerOf(agentId) != address(0);
    }

    /// @notice 获取 Agent 的完整信息摘要（教学辅助函数，展示组合查询）
    /// @param agentId 要查询的 Agent
    /// @return owner  Agent 的所有者
    /// @return uri    Agent 的注册信息 URI
    /// @return totalSupply 当前注册总数
    function getAgentProfile(uint256 agentId)
        external
        view
        returns (address owner, string memory uri, uint256 totalSupply)
    {
        return (ownerOf(agentId), tokenURI(agentId), _allAgentIds.length);
    }

    // ═════════════════════════════════════════════════════════════
    //  重写（多重继承必须显式指定 override）
    // ═════════════════════════════════════════════════════════════

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
