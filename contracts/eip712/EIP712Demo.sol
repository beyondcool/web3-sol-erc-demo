// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * ┌─────────────────────────────────────────────────────────────────────┐
 * │                                                                     │
 * │   EIP-712: Typed Structured Data Signing                            │
 * │   ==============================================                    │
 * │                                                                     │
 * │   教学演示 —— 基于 OpenZeppelin 的简洁实现                           │
 * │                                                                     │
 * └─────────────────────────────────────────────────────────────────────┘
 *
 *
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║                                                                      ║
 * ║   🤔 什么是 EIP-712？                                                ║
 * ║   ═══════════════════                                              ║
 * ║                                                                    ║
 * ║   让用户签署「结构化的、人类可读的数据」，而不是黑箱式的哈希。               ║
 * ║   钱包可以展示签名内容给用户确认。                                      ║
 * ║                                                                     ║
 * ║   签的不是这个:                     而是签这个（钱包会展示）:              ║
 * ║     0x1902839184...                  ┌────────────────────────────┐  ║
 * ║                                      │ Domain: EIP712Demo        │  ║
 * ║                                      │ Chain: Ethereum Mainnet   │  ║
 * ║                                      │                            │  ║
 * ║                                      │ Note:                      │  ║
 * ║                                      │   content: "Hello!"       │  ║
 * ║                                      │   nonce:   1              │  ║
 * ║                                      └────────────────────────────┘  ║
 * ║                                                                      ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 *
 *
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║                                                                      ║
 * ║   📐 EIP-712 核心公式（4 步）                                        ║
 * ║   ═══════════════════════                                          ║
 * ║                                                                      ║
 * ║   第 1 步：域分离器 — 签名绑到「唯一的 dApp × 链 × 合约」              ║
 * ║     domainSeparator = keccak256(abi.encode(                         ║
 * ║       keccak256("EIP712Domain(string name,string version,            ║
 * ║                  uint256 chainId,address verifyingContract)"),       ║
 * ║       keccak256("EIP712Demo"),  keccak256("1"),                     ║
 * ║       block.chainid,  address(this)                                  ║
 * ║     ))                                                               ║
 * ║     ══ 这一步由 OZ 自动完成 ══                                      ║
 * ║                                                                      ║
 * ║   第 2 步：类型哈希 — 签名绑到「唯一的数据结构」                       ║
 * ║     NOTE_TYPEHASH = keccak256("Note(string content,uint256 nonce)") ║
 * ║                                                                      ║
 * ║   第 3 步：hashStruct — 把结构体编码成哈希                            ║
 * ║     structHash = keccak256(abi.encode(                              ║
 * ║       NOTE_TYPEHASH, keccak256(content), nonce                       ║
 * ║     ))                                                               ║
 * ║                                                                      ║
 * ║   第 4 步：最终摘要 — 这就是实际被签名的数据                          ║
 * ║     digest = keccak256(0x1901 || domainSeparator || structHash)     ║
 * ║     → ecrecover(digest, v, r, s) → 签名者地址                        ║
 * ║     ══ 这一步由 OZ 的 _hashTypedDataV4() 完成 ══                   ║
 * ║                                                                      ║
 * ║   ═══════════════════════════════════════════════                    ║
 * ║   OZ 替你做了第 1、4 步。你只需要关心第 2 步（定义 struct）            ║
 * ║   和第 3 步（实现 hashStruct）——这才是你应用独有的逻辑。              ║
 * ║                                                                      ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 *
 *
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║                                                                      ║
 * ║   🛡️ EIP-712 的安全价值                                             ║
 * ║   ════════════════════                                            ║
 * ║                                                                      ║
 * ║   Domain Separator 像签名上的「公章」：                                ║
 * ║     • 钓鱼防御：钱包展示结构化数据，用户看清后再签                      ║
 * ║     • 跨合约防御：签名绑到合约地址，A 的签名不能在 B 上用               ║
 * ║     • 跨链防御：签名绑到 chainId，主网签名不能在 Sepolia 用            ║
 * ║     • 类型混淆防御：Type Hash 唯一标识结构体形状                       ║
 * ║     • 重放防御（同合约内）：由 nonce 机制提供，每个签名只能用一次        ║
 * ║                                                                      ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 */

contract EIP712Demo is EIP712("EIP712Demo", "1") {
    // ═══════════════════════════════════════════════════════════════════
    //  📦 数据结构
    // ═══════════════════════════════════════════════════════════════════

    /// @notice 用户签名的「笔记」结构体
    struct Note {
        string  content;
        uint256 nonce;    // 防重放计数器
    }

    /// @notice Note 类型哈希：唯一标识这个数据结构
    bytes32 public constant NOTE_TYPEHASH = keccak256(
        "Note(string content,uint256 nonce)"
    );

    mapping(address => mapping(uint256 => bool)) public usedNonces;
    Note[] public notes;
    mapping(uint256 => address) public noteSigners;

    event NoteSigned(
        address indexed signer,
        uint256 indexed noteIndex,
        string content,
        uint256 nonce
    );

    // ═══════════════════════════════════════════════════════════════════
    //  ⚡ 第 3 步：hashStruct
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @notice 编码并哈希 Note 结构体
     * @dev    hashStruct(s) = keccak256(typeHash || encodeData(s))
     *
     *         EIP-712 编码规则：
     *         - 值类型（uint256, address...）：直接 abi.encode
     *         - 动态类型（string, bytes...）：abi.encode(keccak256(内容))
     *
     *         OZ 不替你编码 struct ——它不知道你的 struct 长什么样。
     *         你需要自己写 hashStruct。
     */
    function hashNote(Note calldata note) public pure returns (bytes32) {
        return keccak256(abi.encode(
            NOTE_TYPEHASH,
            keccak256(bytes(note.content)),  // 动态类型 → 先哈希
            note.nonce                         // 值类型 → 直接编码
        ));
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ✅ 签名验证
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @notice 链上验签并存储笔记
     * @dev    完整流程：
     *
     *   用户（钱包）                      合约
     *   ─────────────────────────────    ─────────────────
     *   1. 组装 Note + Domain            6. _hashTypedDataV4(hashNote(note)) → digest
     *   2. 钱包展示内容给用户确认             ↑ OZ 内部完成了：
     *   3. 用户签名得到 (v, r, s)              keccak256(0x1901 || domainSep || structHash)
     *   4. 调用 signNote(note, v, r, s)  7. ecrecover(digest, v, r, s) → signer
     *   5. 等待交易上链                   8. require(signer == msg.sender)
     *                                    9. 存储 Note
     */
    function signNote(
        Note calldata note,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(!usedNonces[msg.sender][note.nonce], "Nonce already used");

        bytes32 digest = _hashTypedDataV4(hashNote(note));
        // _hashTypedDataV4 等价于：
        //   keccak256(abi.encodePacked(
        //     hex"1901", _domainSeparatorV4(), structHash
        //   ))
        //
        // _domainSeparatorV4() 自动缓存了当前 chainId，硬分叉后重算。

        address recovered = ecrecover(digest, v, r, s);
        require(recovered == msg.sender, "Invalid signature");

        usedNonces[msg.sender][note.nonce] = true;
        notes.push(note);
        noteSigners[notes.length - 1] = msg.sender;

        emit NoteSigned(msg.sender, notes.length - 1, note.content, note.nonce);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  🔍 纯验签
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @notice 仅验证签名（不改状态），供中继器、后端服务使用
     */
    function verify(
        Note calldata note,
        address expectedSigner,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external view returns (bool) {
        bytes32 digest = _hashTypedDataV4(hashNote(note));
        return ecrecover(digest, v, r, s) == expectedSigner;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  👀 查询
    // ═══════════════════════════════════════════════════════════════════

    /// @notice 暴露 OZ 的 _domainSeparatorV4() 供测试和链下查询
    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function notesCount() external view returns (uint256) {
        return notes.length;
    }
}
