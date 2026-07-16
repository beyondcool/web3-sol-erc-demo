// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/**
 * @title ERC1271Wallet
 * @author OpenZeppelin
 * @notice ERC-1271 标准签名验证的教学示例
 *
 * ═══════════════════════════════════════════════════════════════
 *  ERC-1271：合约的标准签名验证接口
 * ═══════════════════════════════════════════════════════════════
 *
 * 📌 为什么需要 ERC-1271？
 * ─────────────────────────
 *   EOA（外部账户）可以用私钥签名，任何人在链上都可以通过 ecrecover
 *   恢复签名者地址来验证签名。
 *
 *   但是！合约账户（Contract Account）没有私钥——它是一段代码，
 *   无法像 EOA 那样"签名"。如果合约想对外证明"我认可这个签名"，
 *   就需要自己定义验证逻辑。
 *
 *   ERC-1271 标准化了这个验证接口，让所有合约都用同一种方式
 *   回答同一个问题："这个签名对我来说有效吗？"
 *
 * 📌 协议核心
 * ─────────────────────────
 *   接口定义（只有 1 个函数！）：
 *
 *   function isValidSignature(
 *       bytes32 hash,         // 被签名的消息哈希
 *       bytes calldata signature  // 签名数据
 *   ) external view returns (bytes4 magicValue);
 *
 *   ✅ 有效 → 返回 0x1626ba7e（即 bytes4(keccak256("isValidSignature(bytes32,bytes)")））
 *   ❌ 无效 → 返回 0xffffffff（任何其他值）
 *
 *   0x1626ba7e 被称为"魔法值"（Magic Value），其实就是函数选择器本身。
 *   返回自己的函数选择器 = "我担保这个签名有效"。
 *
 * 📌 能做什么？
 * ─────────────────────────
 *   1️⃣ 合约钱包（Smart Wallet）
 *      合约可以定义自己的签名验证逻辑（单签、多签、社交恢复等）
 *      任何人都可以通过统一接口验证来自合约的签名
 *
 *   2️⃣ 统一验证（EOA + 合约）
 *      传统方式只能验 EOA。有了 ERC-1271，验证逻辑只需要：
 *        if (isContract(signer)) → 调用 signer.isValidSignature()
 *        else                   → 使用 ecrecover
 *      不需要区分调用方是人是合约！
 *
 *   3️⃣ 链下授权
 *      合约可以签"许可"（Permit），让用户在链下签名后就可在链上执行操作
 *      （例如：DAO 投票委托、meta-transaction 授权）
 *
 * ═══════════════════════════════════════════════════════════════
 *  本合约示例：一个简单的合约钱包
 *   - 合约有一个 owner（EOA 账户）
 *   - 当外部调用 isValidSignature 时，检查签名是否来自 owner
 *   - 如果是 → 接受签名（返回魔法值）
 * ═══════════════════════════════════════════════════════════════
 */
contract ERC1271Wallet is IERC1271 {

    /// @dev ERC-1271 魔法值：isValidSignature(bytes32,bytes) 的 selector
    bytes4 private constant MAGIC_VALUE = bytes4(0x1626ba7e);

    /// @dev 合约钱包的所有者（一个 EOA 地址）
    address public owner;

    /// @notice 当 owner 变更时触发
    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);

    /**
     * @notice 构造函数：设置合约钱包的所有者
     * @param _owner 钱包所有者的 EOA 地址
     *
     * 想象你部署了这个合约——你就是 owner，这个合约就是你的钱包。
     * 你的 EOA 在链下签名，合约帮你验证。
     */
    constructor(address _owner) {
        require(_owner != address(0), "Owner cannot be zero address");
        owner = _owner;
        emit OwnerUpdated(address(0), _owner);
    }

    /**
     * @notice ⭐ ERC-1271 标准签名验证接口（核心！）
     * @param hash     被签名的消息的 keccak256 哈希
     * @param signature 签名数据（打包的 r, s, v，共 65 字节）
     * @return magicValue 有效返回 0x1626ba7e，无效返回 0xffffffff
     *
     * 💡 理解的关键：
     *   1. EOA owner 在链下对消息签名 → 生成 (v, r, s)
     *   2. 合约在链上用 ecrecover 从签名中恢复签名者地址
     *   3. 如果签名者 == owner → 签名有效
     *
     * 💡 这就是 ERC-1271 的精髓：
     *   外部系统不需要知道合约的内部逻辑（"owner 机制"），
     *   只需要调用 isValidSignature 就能知道签名是否被合约认可。
     *   合约可以自定义验证逻辑（多签、阈值签名等），对外接口不变。
     */
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4 magicValue)
    {
        // Step 1: 从签名中恢复签名者的地址
        address recoveredSigner = _recoverSigner(hash, signature);

        // Step 2: 判断签名者是不是合约的 owner
        if (recoveredSigner == owner) {
            return MAGIC_VALUE;  // ✅ 签名有效
        }

        return 0xffffffff;       // ❌ 签名无效
    }

    // ══════════════════════════════════════════════════════════
    //  辅助函数：ECDSA 签名恢复
    // ══════════════════════════════════════════════════════════

    /**
     * @dev 使用 ecrecover 从签名中恢复签名者地址
     * @param hash     消息哈希
     * @param signature 打包的签名（65 字节: r[32] + s[32] + v[1]）
     * @return signer 签名者地址
     */
    function _recoverSigner(bytes32 hash, bytes calldata signature)
        internal
        pure
        returns (address signer)
    {
        require(signature.length == 65, "ERC1271Wallet: invalid signature length");

        // 拆分打包签名
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);

        // ecrecover 是 Solidity 的原生函数
        // 它从 ECDSA 签名中恢复出签名者的地址
        signer = ecrecover(hash, v, r, s);
        require(signer != address(0), "ERC1271Wallet: invalid signature");
    }

    /**
     * @dev 将 65 字节的打包签名拆分为 v, r, s
     *
     * 签名编码格式（以太坊标准）：
     *   第 0-31 字节：r（32 字节）
     *   第 32-63 字节：s（32 字节）
     *   第 64 字节：v（1 字节）
     */
    function _splitSignature(bytes calldata signature)
        internal
        pure
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }

        // EIP-155 兼容：某些情况下 v < 27，需要调整
        if (v < 27) {
            v += 27;
        }
    }
}
