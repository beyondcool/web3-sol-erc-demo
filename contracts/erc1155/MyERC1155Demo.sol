// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============================================================
// 📖 ERC-1155 教学示例 —— 游戏道具系统
// ============================================================
// 本合约演示 ERC-1155 多代币标准（Multi Token Standard）的核心用法。
//
// 🤔 什么是 ERC-1155？
//    ERC-20   = 同质化代币（你的一枚 USDT == 我的一枚 USDT）
//    ERC-721  = 非同质化代币（每个 tokenId 独一无二，总量 = 1）
//    ERC-1155 = 以上两者的结合 —— 一个合约管理多种代币类型！
//
// 🎮 本合约场景：游戏道具系统
//    我们用 ERC-1155 表示一个游戏中的所有道具，每种道具是一个 token 类型：
//
//    代币 ID | 名称       | 类型    | 特性
//    --------|------------|---------|-----------------------
//     1      | 金币       | 同质化  | 谁都可以有很多个
//     2      | 银币       | 同质化  | 同上
//     3      | 传说之剑   | 非同质化 | 全服仅此一把 (supply = 1)
//     4      | 传说之盾   | 非同质化 | 全服仅此一面 (supply = 1)
//
// ✨ ERC-1155 关键特点：
//    1. 批量操作 —— 一次交易转移/查询多种代币，大幅节省 Gas
//    2. 统一管理 —— 同质化与非同质化代币共存于同一合约
//    3. 安全回调 —— 转入合约时触发 onERC1155Received 回调，防止锁死
//    4. ApprovalForAll —— 全局授权模式（不是按额度，而是按操作者）
// ============================================================

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MyERC1155Demo
 * @dev ERC-1155 多代币教学示例 —— 游戏道具系统
 *
 * 本合约继承自 OpenZeppelin 的 ERC1155 和 Ownable：
 * - ERC1155 提供标准实现（余额、转账、授权、批量操作）
 * - Ownable 提供 onlyOwner 权限控制（铸造、销毁等管理功能）
 */
contract MyERC1155Demo is ERC1155, Ownable {

    // ============================================================
    // 🆔 代币类型 ID 常量
    // ============================================================
    // 🔑 关键概念：在 ERC-1155 中，每种代币由一个 uint256 id 标识
    //
    // 同质化代币（Fungible Token）：
    //   - 很多用户可以有相同的 id，各自持有不同数量
    //   - 类似于 ERC-20：每个用户有一个 balance
    //
    // 非同质化代币（Non-Fungible Token, NFT）：
    //   - 一个 id 总供应量为 1，只属于一个用户
    //   - 类似于 ERC-721：每个 id 独一无二
    //   - 当某个 id 的 supply = 1 时，它就变成了 NFT！
    // ============================================================

    // 这里的 id 常量可以去掉，使用动态生成的 id（如 _nextNFTId）也是可以的。
    // 如果mint数量大于1，则为同质化代币；如果mint数量为1，则为非同质化代币（NFT）。
    uint256 public constant GOLD    = 1; // 🪙 金币（同质化）
    uint256 public constant SILVER  = 2; // 🥈 银币（同质化）
    uint256 public constant SWORD   = 3; // ⚔️ 传说之剑（非同质化，总量 1）
    uint256 public constant SHIELD  = 4; // 🛡️ 传说之盾（非同质化，总量 1）

    // ============================================================
    // 📊 状态变量
    // ============================================================

    /// @dev 记录每种代币的总供应量（用于区分同质化与非同质化）
    mapping(uint256 id => uint256 amount) private _totalSupply;

    /// @dev 下一个可用的 NFT id（自动递增，用于铸造新 NFT）
    uint256 private _nextNFTId;

    // ============================================================
    // 🏗️ 构造函数
    // ============================================================

    /**
     * @dev 部署合约时设置：
     *       1. URI 元数据基础地址（ERC-1155 用 uri(id) 获取元数据，而非 tokenURI）
     *       2. 合约所有者（Ownable）
     *       3. 初始化 NFT id 计数器
     *
     * @param uri_ 元数据基础 URI（格式参考 https://example.com/metadata/{id}.json）
     * 
     *      ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️ 
     *      这里设置的 uri_ 是uri模板，实际使用时 需要替换里面的 {id} 为具体的【代币类型 id】。
     *      但openzeppelin的ERC1155实现中，uri(uint256)函数会返回这个【模板字符串】，
     *      前端或调用方需要自己替换 {id}。或者可以在合约中重写 uri(uint256) 函数来返回最终的 URI。
     *      ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️
     */
    constructor(string memory uri_) ERC1155(uri_) Ownable(msg.sender) {
        _nextNFTId = 10; // 从 10 开始，与基础道具 ID (1-4) 分开
    }

    // ============================================================
    // 👀 查询函数
    // ============================================================

    /**
     * @notice 查询某地址持有某种代币的数量
     * @dev 这与 ERC-20 的 balanceOf(address) 不同 —— 需要指定 token id！
     *
     * 例如：balanceOf(player, GOLD) → 玩家有多少金币
     *       balanceOf(player, SWORD) → 玩家有传说之剑吗？（返回 0 或 1）
     *
     * @param account 要查询的用户地址
     * @param id      代币类型 ID
     * @return 该地址持有的该代币数量
     */
    function balanceOf(address account, uint256 id)
        public
        view
        override
        returns (uint256)
    {
        return super.balanceOf(account, id);
    }

    /**
     * @notice 批量查询多个地址的多种代币余额 ✅ ERC-1155 独有功能！
     * @dev 这是 ERC-1155 相比 ERC-20/ERC-721 的核心优势之一。
     *      一次 RPC 调用查多个数据，比多次调用 balanceOf 节省大量 Gas。
     *
     * ⚠️ 参数要求：accounts 和 ids 数组长度必须相等
     *       每个 accounts[i] 对应查询 ids[i] 的余额
     *
     * @param accounts 要查询的用户地址列表
     * @param ids      要查询的代币 ID 列表
     * @return 每个 (account, id) 对的余额
     */
    function balanceOfBatch(
        address[] memory accounts,
        uint256[] memory ids
    ) public view override returns (uint256[] memory) {
        return super.balanceOfBatch(accounts, ids);
    }

    /**
     * @notice 查询某种代币的总供应量
     * @param id 代币类型 ID
     * @return 总供应量
     */
    function totalSupply(uint256 id) public view returns (uint256) {
        return _totalSupply[id];
    }

    /**
     * @notice 判断某种代币是否为非同质化代币（NFT）
     * @dev 教学辅助函数：当某种代币的最大供应量为 1 时，它就是一个 NFT
     * @param id 代币类型 ID
     * @return 如果是 NFT 返回 true
     */
    function isNonFungible(uint256 id) public view returns (bool) {
        return _totalSupply[id] <= 1; // 总供应量为 0 或 1 视作 NFT
    }

    // ============================================================
    // ✨ 元数据 URI
    // ============================================================

    /**
     * @notice 获取某个代币类型的元数据 URI
     * @dev
     *   与 ERC-721 不同（每个 tokenId 可以有独立 URI），
     *   ERC-1155 的 URI 是对应整个代币类型的。
     *
     *   格式惯例：{baseURI}{id}.json
     *   其中 {id} 是十六进制编码（不带 0x 前缀，小写）
     *    
     *   Openzeppelin 的 ERC1155 实现中，uri(uint256) 统一返回模板字符串，需自行替换 {id}。
     *
     *   例如：https://game.example.com/api/item/{id}.json
     *        → https://game.example.com/api/item/1.json（金币元数据）
     *        → https://game.example.com/api/item/3.json（传说之剑元数据）
     *
     * @param id 代币类型 ID
     * @return 该代币类型的元数据 URI
     */
    function uri(uint256 id) public view override returns (string memory) {
        return super.uri(id);
    }

    /**
     * @notice 设置新的基础 URI（仅所有者）
     * @param newUri 新的基础 URI
     */
    function setURI(string memory newUri) public onlyOwner {
        _setURI(newUri);
    }

    // ============================================================
    // 🎯 铸造（Mint）
    // ============================================================

    /**
     * @notice 铸造一定数量的某种代币给指定地址
     * @dev 调用内部 _mint 函数，该函数会发送 TransferSingle 事件
     *
     * ⚠️ 安全提示：如果 to 是合约地址，它会收到 onERC1155Received 回调
     *    如果该合约没有实现 IERC1155Receiver，交易会 revert！
     *    这是为了防止代币被永远锁在合约中。
     *
     * @param to     接收代币的地址
     * @param id     代币类型 ID
     * @param amount 铸造数量
     * @param data   附加数据（传给回调函数），这是onERC1155Received回调方法的最后一个参数
     */
    function mint(address to, uint256 id, uint256 amount, bytes memory data)
        public onlyOwner
    {
        _totalSupply[id] += amount;
        _mint(to, id, amount, data);
    }

    /**
     * @notice 批量铸造多种代币 ✅ ERC-1155 核心优势
     * @dev 一次交易铸造多种代币，所有代币发给同一个地址
     *    内部调用 _mintBatch，会发送 TransferBatch 事件（而非 TransferSingle × N）
     *
     * 🔑 教学要点：使用批量操作比循环单独调用 mint 更省 Gas，
     *    因为只要做一次状态根更新、一次事件发射。
     *
     * @param to      接收代币的地址
     * @param ids     代币类型 ID 列表
     * @param amounts 对应每种代币的铸造数量
     * @param data    附加数据
     */
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public onlyOwner {
        for (uint256 i = 0; i < ids.length; i++) {
            _totalSupply[ids[i]] += amounts[i];
        }
        _mintBatch(to, ids, amounts, data);
    }

    /**
     * @notice 铸造一个全新的非同质化代币（NFT）
     * @dev 教学辅助函数：每次调用创建一个新的 token id，初始供应量 = 1
     *
     * 这是一个典型的"半同质化"用法：
     * - 每种 NFT 是一个独立的 id
     * - 每个 id 的总供应量 = 1（因此它是 NFT）
     *
     * @param to   接收 NFT 的地址
     * @param data 附加数据
     * @return 新铸造的 NFT id
     */
    function mintNFT(address to, bytes memory data)
        public onlyOwner returns (uint256)
    {
        uint256 nftId = _nextNFTId;
        _nextNFTId++;

        _totalSupply[nftId] = 1; // ✅ 供应量为 1 → 这是一个 NFT
        _mint(to, nftId, 1, data);

        return nftId;
    }

    // ============================================================
    // 🔥 销毁（Burn）
    // ============================================================

    /**
     * @notice 销毁指定地址的某种代币
     * @param from   要销毁代币的地址
     * @param id     代币类型 ID
     * @param amount 销毁数量
     */
    function burn(address from, uint256 id, uint256 amount) public onlyOwner {
        _totalSupply[id] -= amount;
        _burn(from, id, amount);
    }

    /**
     * @notice 批量销毁多种代币
     * @param from    要销毁代币的地址
     * @param ids     代币类型 ID 列表
     * @param amounts 对应销毁数量
     */
    function burnBatch(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) public onlyOwner {
        for (uint256 i = 0; i < ids.length; i++) {
            _totalSupply[ids[i]] -= amounts[i];
        }
        _burnBatch(from, ids, amounts);
    }

    // ============================================================
    // 📤 转账（Transfer）
    // ============================================================

    /**
     * @notice 安全转账 —— 单种代币
     * @dev
     * 与 ERC-20 不同：
     *   - ERC-20: transfer(to, amount) → 转账的是 msg.sender 的余额
     *   - ERC-1155: safeTransferFrom(from, to, id, amount, data) → 需指定转出方
     *
     * 转账者必须满足以下条件之一：
     *   1. 是代币的发送方（from == msg.sender）
     *   2. 已被 from 授权（isApprovedForAll(from, msg.sender) == true）✅
     *
     * @param from   代币转出方
     * @param to     代币接收方
     * @param id     代币类型 ID
     * @param amount 转账数量
     * @param data   附加数据（传给接收合约的 onERC1155Received）
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        super.safeTransferFrom(from, to, id, amount, data);
    }

    /**
     * @notice 批量安全转账 ✅ ERC-1155 独有
     * @dev 一次交易转账多种代币，大幅节省 Gas
     *
     * 🔑 教学要点：
     *   批量操作是 ERC-1155 被设计出来的核心动因。
     *   在游戏中，你可能需要：
     *     - 从玩家背包中取走：金币、银币、药水（3 种同质化代币）
     *     - 放入任务奖励：经验书、装备（2 种代币）
     *   用 ERC-20/ERC-721 需要 5 次独立交易；用 ERC-1155 只需 1 次！
     *
     * @param from   代币转出方
     * @param to     代币接收方
     * @param ids    代币类型 ID 列表
     * @param amounts 对应转账数量
     * @param data   附加数据（传给接收合约的 onERC1155BatchReceived）
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    // ============================================================
    // ✅ 授权（Approval）
    // ============================================================

    /**
     * @notice 授权或撤销某个操作者管理你所有代币的权限
     * @dev
     * ERC-1155 的授权模型不同于 ERC-20：
     *   - ERC-20: approve(spender, amount) → 按额度授权
     *   - ERC-1155: setApprovalForAll(operator, approved) → 按操作者授权 ✅
     *
     * 🔑 教学要点：
     *   为什么 ERC-1155 不用 approve(amount) 模型？
     *   因为批量操作时你不知道每种代币需要多少额度。
     *   "全权委托"更适合批量场景 —— 你信任某个合约（如市场、游戏引擎）
     *   可以操作你所有类型的代币。
     *
     *   如果你想限制额度，可以在自己的合约中实现类似 ERC-20 的授权逻辑。
     *
     * @param operator 被授权/撤销的操作者地址
     * @param approved true = 授权，false = 撤销授权
     */
    function setApprovalForAll(address operator, bool approved)
        public override
    {
        super.setApprovalForAll(operator, approved);
    }

    /**
     * @notice 查询某个地址是否授权了某个操作者
     * @param account 授权人
     * @param operator 操作者
     * @return 是否已授权
     */
    function isApprovedForAll(address account, address operator)
        public view override returns (bool)
    {
        return super.isApprovedForAll(account, operator);
    }

    // ============================================================
    // 🔌 接口检测（supportsInterface）
    // ============================================================

    /**
     * @dev ERC-165 接口检测
     * ERC-1155 标准定义了三个接口 ID：
     *   - IERC1155: 0xd9b67a26
     *   - IERC1155MetadataURI: 0x0e89341c
     *   - IERC165: 0x01ffc9a7
     */
    function supportsInterface(bytes4 interfaceId)
        public view override returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
