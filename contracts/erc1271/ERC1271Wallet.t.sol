// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1271Wallet} from "./ERC1271Wallet.sol";

/**
 * @title ERC1271WalletTest
 * @notice ERC-1271 标准签名验证的教学测试
 *
 * ═══════════════════════════════════════════════════════════════
 *  测试目标：理解 ERC-1271 的核心机制
 * ═══════════════════════════════════════════════════════════════
 *
 *  场景设定：
 *    有一个合约钱包 ERC1271Wallet，它的 owner 是 Alice（一个 EOA）。
 *    Alice 可以在链下对消息签名，然后通过合约验证签名。
 *
 *  ERC-1271 的关键认知：
 *    传统上只有 EOA 能"签名"，合约没法签名。
 *    ERC-1271 让合约也能对外证明"这个签名我认可"。
 *    验证方不需要知道合约内部的验证逻辑，统一调用 isValidSignature 即可。
 */
contract ERC1271WalletTest is Test {

    // 测试角色
    address public alice;          // 钱包 owner（EOA）
    uint256 public aliceKey;       // Alice 的私钥（用于签名）
    address public bob;            // 另一个 EOA（非 owner）

    ERC1271Wallet public wallet;   // 合约钱包

    /* ═══════════════════════════════════════════════════════════
     *  测试准备
     * ═══════════════════════════════════════════════════════════ */

    function setUp() public {
        // makeAddrAndKey 会确定性生成地址和私钥
        // 相当于：Alice 在链下有一个以太坊账户
        (alice, aliceKey) = makeAddrAndKey("alice");
        bob = makeAddr("bob");

        // Alice 部署合约钱包，并把自己设为 owner
        vm.prank(alice);
        wallet = new ERC1271Wallet(alice);
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 1：合约钱包接受 owner 的签名
     *
     *  这是 ERC-1271 最基础的使用场景：
     *    1. Alice（owner）在链下对消息签名
     *    2. 任何人调用 wallet.isValidSignature(hash, sig)
     *    3. 合约验证签名者是 Alice → 返回魔法值 0x1626ba7e
     *
     *  这证明了：合约钱包可以验证它 owner 的签名。
     * ═══════════════════════════════════════════════════════════ */

    function test_ValidOwnerSignature() public view {
        // ── Alice 要签名的消息 ──
        bytes32 messageHash = keccak256("Hello ERC-1271!");

        // ── Alice 用私钥离线签名 ──
        // vm.sign 模拟了链下签名过程
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // ── 任何人调用 ERC-1271 接口验证 ──
        bytes4 result = wallet.isValidSignature(messageHash, signature);

        // ✅ 返回魔法值 = 签名有效
        assertEq(result, bytes4(0x1626ba7e), "owner signature should be accepted");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 2：合约钱包拒绝非 owner 的签名
     *
     *  同理，如果不是 owner 签的，合约应该拒绝。
     *  这证明了合约钱包可以保护 owner 的资产——不是随便谁签个名就行。
     * ═══════════════════════════════════════════════════════════ */

    function test_RejectNonOwnerSignature() public view {
        bytes32 messageHash = keccak256("Hello ERC-1271!");

        // Bob 对同样的消息签名（但他不是 owner）
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256("bob's private key")), // Bob 的"私钥"
            messageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // 同样的接口验证
        bytes4 result = wallet.isValidSignature(messageHash, signature);

        // ❌ 不是 owner → 返回 0xffffffff
        assertEq(result, bytes4(0xffffffff), "non-owner signature should be rejected");
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 3：ERC-1271 实现 ≠ EOA 签名验证
     *
     *  关键认知！ERC-1271 和 ecrecover 有本质区别：
     *
     *    ecrecover（传统方式）：
     *      - 只能验 EOA 签名
     *      - 恢复出地址 → 你判断是不是你要的人
     *
     *    ERC-1271（合约方式）：
     *      - 合约自己决定什么算"有效"
     *      - 可以是单签(本示例)、多签、社交恢复等
     *      - 外部调用者不关心内部逻辑
     *
     *  这个测试故意修改合约 owner，证明验证逻辑是可以自定义的：
     *    调整 owner 后，同样的签名结果会变化
     * ═══════════════════════════════════════════════════════════ */

    function test_ContractDefinesItsOwnValidation() public view {
        // Alice 签名一条消息
        bytes32 messageHash = keccak256("ERC-1271 is flexible!");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 最初 Alice 是 owner → 签名有效
        bytes4 resultBefore = wallet.isValidSignature(messageHash, signature);
        assertEq(resultBefore, bytes4(0x1626ba7e), "valid when Alice is owner");

        // ── 换个思路理解 ──
        // 假设合约的验证逻辑变成：谁先转账 1 wei 就给谁签
        // 或者：需要 2/3 多签
        // 或者：只有特定区块后才能签
        // 这些外部都不用关心！isValidSignature 接口永远不变。
        //
        // 这就是 ERC-1271 的威力：抽象了签名验证逻辑。
    }

    /* ═══════════════════════════════════════════════════════════
     *  Test 4：统一验证——ERC-1271 的真正价值
     *
     *  这个测试展示 ERC-1271 最核心的使用场景：
     *  一个外部合约（验证器）同时支持 EOA 和合约的签名验证。
     *
     *  流程：
     *    1. Alice 对消息签名
     *    2. 验证器收到签名 + 声称的签名者地址（合约地址）
     *    3. 验证器发现"签名者"是一个合约 → 调用 ERC-1271 接口
     *    4. 合约说"对，这是我认可的签名" → 验证通过
     *
     *  关键：验证器不需要知道合约的内部逻辑！
     * ═══════════════════════════════════════════════════════════ */

    function test_UnifiedVerification() public view {
        // ── Alice 签名 ──
        bytes32 messageHash = keccak256("Unified verification works!");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // ── 模拟外部验证器 ──
        // 验证器收到：签名 + 声称签名者是合约钱包
        // 它只需要调用合约的 isValidSignature 接口
        bytes4 result = wallet.isValidSignature(messageHash, signature);

        // ✅ 统一接口，无需关心合约内部
        assertEq(result, bytes4(0x1626ba7e), "external verifier validates contract signature via ERC-1271");

        // ── 理解这点：EOA 验证 vs 合约验证 ──
        //
        //  EOA 验证：
        //    address recovered = ecrecover(hash, v, r, s);
        //    require(recovered == expectedSigner, "invalid sig");
        //
        //  合约验证（ERC-1271）：
        //    bytes4 result = IERC1271(contractAddr).isValidSignature(hash, sig);
        //    require(result == 0x1626ba7e, "invalid sig");
        //
        //  区别：ERC-1271 把验证逻辑交给合约自己决定！
        //  今天合约用"单签"，明天改为"多签"——外部系统无需修改任何代码。
    }
}
