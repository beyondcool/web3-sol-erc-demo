// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EIP712Demo} from "./EIP712Demo.sol";

/**
 * @title EIP712DemoTest
 * @notice EIP-712 教学合约的测试文件
 * @dev    这个测试展示了完整的 EIP-712 签名流程：
 *
 *         ① 测试中手动计算 Domain Separator（验证学生理解公式）
 *         ② 测试中手动计算 Note 的 structHash
 *         ③ 用 vm.sign 对摘要签名（模拟用户钱包）
 *         ④ 提交到合约验证
 *
 *         虽然合约用了 OZ 的 _hashTypedDataV4，但测试里手动重算了
 *         一遍完整的摘要计算过程——这是为了教学，让学生看到
 *         每一步在做什么。
 */
contract EIP712DemoTest is Test {
    EIP712Demo demo;
    address alice;

    uint256 constant ALICE_PK = 0xA11CE;
    uint256 constant CHAIN_ID = 31337; // Hardhat/Anvil 默认链 ID

    function setUp() public {
        alice = vm.addr(ALICE_PK);
        vm.label(alice, "Alice");

        demo = new EIP712Demo();
        vm.label(address(demo), "EIP712Demo");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  测试 1：基本属性
    // ═══════════════════════════════════════════════════════════════════

    function test_Constructor_SetsDomainSeparator() public view {
        // OZ 自动计算的 domainSeparator 应该与手动计算的一致
        bytes32 expectedDomainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("EIP712Demo")),
            keccak256(bytes("1")),
            CHAIN_ID,
            address(demo)
        ));
        assertEq(demo.domainSeparatorV4(), expectedDomainSeparator, "Domain separator mismatch");
    }

    function test_Constructor_SetsTypeHashes() public view {
        assertEq(
            demo.NOTE_TYPEHASH(),
            keccak256("Note(string content,uint256 nonce)"),
            "NOTE_TYPEHASH should match the struct schema"
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  测试 2：hashNote — 验证结构体哈希
    // ═══════════════════════════════════════════════════════════════════
    //  教学点：hashStruct = keccak256(typeHash || encodeData)

    function test_HashNote_ReturnsCorrectHash() public view {
        EIP712Demo.Note memory note = EIP712Demo.Note("Hello, EIP-712!", 1);

        bytes32 expectedHash = keccak256(abi.encode(
            keccak256("Note(string content,uint256 nonce)"),
            keccak256(bytes("Hello, EIP-712!")),  // string 是动态类型 → 先哈希
            uint256(1)                              // uint256 是值类型 → 直接编码
        ));

        assertEq(demo.hashNote(note), expectedHash, "hashNote should match manual computation");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  测试 3：signNote — 完整签名验签流程
    // ═══════════════════════════════════════════════════════════════════
    //  这个测试模拟了真实世界中的 EIP-712 签名流程：
    //
    //     Alice（链下钱包）                    合约（链上）
    //     ─────────────────────────────     ─────────────────
    //     1. 组装 Note 数据                    —
    //     2. 钱包展示：
    //        Domain: EIP712Demo              —
    //        Chain:  31337
    //        Note:
    //          content: "Hello, EIP-712!"
    //          nonce:   1
    //     3. 用户确认签名                       —
    //     4. 得到 (v, r, s)                    —
    //     5. 调用 signNote(note, v, r, s) ──→  6. _hashTypedDataV4(hashNote(note))
    //                                         7. ecrecover(digest, v, r, s) → alice
    //                                         8. require(alice == msg.sender)
    //                                         9. 存储 Note

    function test_SignNote_AliceSignsNote() public {
        EIP712Demo.Note memory note = EIP712Demo.Note("Hello, EIP-712!", 1);

        // Step 1: 手动计算摘要（测试中重算一遍，验证对公式的理解）
        //         合约内部用的是 OZ 的 _hashTypedDataV4()，效果等价
        bytes32 digest = keccak256(abi.encodePacked(
            hex"1901",
            demo.domainSeparatorV4(),
            keccak256(abi.encode(
                keccak256("Note(string content,uint256 nonce)"),
                keccak256(bytes(note.content)),
                note.nonce
            ))
        ));

        // Step 2: 用 Alice 的私钥签名（模拟钱包）
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // Step 3: Alice 调用合约（prank 模拟 Alice 的身份）
        vm.prank(alice);
        demo.signNote(note, v, r, s);

        // Step 4: 验证笔记已存储
        assertEq(demo.notesCount(), 1, "Should have 1 note");
        assertEq(demo.noteSigners(0), alice, "Signer should be Alice");

        (string memory storedContent, uint256 storedNonce) = demo.notes(0);
        assertEq(storedContent, "Hello, EIP-712!", "Content should match");
        assertEq(storedNonce, 1, "Nonce should match");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  测试 4：防重放 — 同一个 nonce 不能签两次
    // ═══════════════════════════════════════════════════════════════════
    //  教学点：EIP-712 定义了「如何哈希和签名」，但「防重放」需要
    //         应用层自己实现（这里是 nonce 映射）

    function test_SignNote_RevertIfNonceUsed() public {
        EIP712Demo.Note memory note = EIP712Demo.Note("Hello!", 1);

        bytes32 digest = keccak256(abi.encodePacked(
            hex"1901",
            demo.domainSeparatorV4(),
            keccak256(abi.encode(
                keccak256("Note(string content,uint256 nonce)"),
                keccak256(bytes(note.content)),
                note.nonce
            ))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        vm.prank(alice);
        demo.signNote(note, v, r, s);

        vm.prank(alice);
        vm.expectRevert("Nonce already used");
        demo.signNote(note, v, r, s);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  测试 5：纯验签（不改状态）
    // ═══════════════════════════════════════════════════════════════════
    //  教学点：中继器可以先 verify 再提交，避免浪费 gas

    function test_Verify_ReturnsTrueForValidSignature() public view {
        EIP712Demo.Note memory note = EIP712Demo.Note("Verify me", 42);

        bytes32 digest = keccak256(abi.encodePacked(
            hex"1901",
            demo.domainSeparatorV4(),
            keccak256(abi.encode(
                keccak256("Note(string content,uint256 nonce)"),
                keccak256(bytes(note.content)),
                note.nonce
            ))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        assertTrue(demo.verify(note, alice, v, r, s), "Signature should be valid");
    }

    function test_Verify_ReturnsFalseForWrongSigner() public {
        EIP712Demo.Note memory note = EIP712Demo.Note("Verify me", 42);

        bytes32 digest = keccak256(abi.encodePacked(
            hex"1901",
            demo.domainSeparatorV4(),
            keccak256(abi.encode(
                keccak256("Note(string content,uint256 nonce)"),
                keccak256(bytes(note.content)),
                note.nonce
            ))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        address bob = makeAddr("Bob");
        assertFalse(demo.verify(note, bob, v, r, s), "Should be false for wrong signer");
    }

    function test_Verify_ReturnsFalseForModifiedContent() public view {
        EIP712Demo.Note memory original = EIP712Demo.Note("Original", 1);
        EIP712Demo.Note memory tampered = EIP712Demo.Note("Tampered", 1);

        bytes32 digest = keccak256(abi.encodePacked(
            hex"1901",
            demo.domainSeparatorV4(),
            keccak256(abi.encode(
                keccak256("Note(string content,uint256 nonce)"),
                keccak256(bytes(original.content)),
                original.nonce
            ))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        // 内容被篡改 → 摘要不同 → 验签失败
        assertFalse(demo.verify(tampered, alice, v, r, s), "Should fail for tampered content");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  测试 6：跨域安全
    // ═══════════════════════════════════════════════════════════════════
    //  教学点：不同合约的 domainSeparator 不同，签名不能跨合约使用。

    function test_SignatureReplayAcrossContracts() public {
        EIP712Demo anotherDemo = new EIP712Demo();

        EIP712Demo.Note memory note = EIP712Demo.Note("Cross-domain test", 1);

        bytes32 digest = keccak256(abi.encodePacked(
            hex"1901",
            demo.domainSeparatorV4(),         // demo 的域分离器
            keccak256(abi.encode(
                keccak256("Note(string content,uint256 nonce)"),
                keccak256(bytes(note.content)),
                note.nonce
            ))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        vm.prank(alice);
        demo.signNote(note, v, r, s);

        // 在另一个合约上验证失败（域分离器不同！）
        assertFalse(
            anotherDemo.verify(note, alice, v, r, s),
            "Signature from demo should NOT work on anotherDemo"
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  测试 7：签名者必须等于调用者
    // ═══════════════════════════════════════════════════════════════════
    //  教学点：Bob 不能偷用 Alice 的签名

    function test_SignNote_RevertIfCallerIsNotSigner() public {
        EIP712Demo.Note memory note = EIP712Demo.Note("Alice's note", 1);

        bytes32 digest = keccak256(abi.encodePacked(
            hex"1901",
            demo.domainSeparatorV4(),
            keccak256(abi.encode(
                keccak256("Note(string content,uint256 nonce)"),
                keccak256(bytes(note.content)),
                note.nonce
            ))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        address bob = makeAddr("Bob");
        vm.prank(bob);
        vm.expectRevert("Invalid signature");
        demo.signNote(note, v, r, s);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  测试 8：不同 nonce 可以多次签名
    // ═══════════════════════════════════════════════════════════════════
    //  教学点：每个 nonce 只能用一次，但不同 nonce 可以多次签名

    function test_SignNote_MultipleNotesWithDifferentNonces() public {
        _signAndSubmit(EIP712Demo.Note("First", 1));
        _signAndSubmit(EIP712Demo.Note("Second", 42));

        assertEq(demo.notesCount(), 2, "Should have 2 notes");
    }

    /// @dev 辅助函数：计算 digest → 签名 → 提交
    function _signAndSubmit(EIP712Demo.Note memory note) internal {
        bytes32 digest = keccak256(abi.encodePacked(
            hex"1901",
            demo.domainSeparatorV4(),
            keccak256(abi.encode(
                keccak256("Note(string content,uint256 nonce)"),
                keccak256(bytes(note.content)),
                note.nonce
            ))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        vm.prank(alice);
        demo.signNote(note, v, r, s);
    }
}
