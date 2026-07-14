// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title MyERC1155Demo 测试
 * @dev 全面测试 ERC-1155 教学合约的每个功能
 */

import {Test} from "forge-std/Test.sol";
import {MyERC1155Demo} from "./MyERC1155Demo.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

// ============================================================
// 🧪 测试辅助合约 —— 一个可以接收 ERC-1155 的虚拟合约
// ============================================================
// 有些合约需要接收代币（如游戏金库、市场合约），
// 它们必须实现 IERC1155Receiver 接口。
// 否则 safeTransferFrom 会拒绝转账！
// ============================================================

contract MockGameVault is IERC1155Receiver {

    /// @dev 收到单种代币时触发
    event LogReceivedSingle(
        address operator, address from, uint256 id, uint256 value, bytes data
    );

    /// @dev 收到批量代币时触发
    event LogReceivedBatch(
        address operator, address from, uint256[] ids, uint256[] values, bytes data
    );

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes memory data
    ) external override returns (bytes4) {
        emit LogReceivedSingle(operator, from, id, value, data);
        return this.onERC1155Received.selector; // 0xf23a6e61
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) external override returns (bytes4) {
        emit LogReceivedBatch(operator, from, ids, values, data);
        return this.onERC1155BatchReceived.selector; // 0xbc197c81
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}


// ============================================================
// 🧪 测试辅助合约 —— 不能接收 ERC-1155 的合约（用于测试安全机制）
// ============================================================

contract NonReceiver {
    // 不实现任何 IERC1155Receiver 接口
}


// ============================================================
// 主测试合约
// ============================================================

contract MyERC1155DemoTest is Test {
    MyERC1155Demo token;
    address admin;
    address user1;
    address user2;
    address operator;
    MockGameVault vault;
    NonReceiver nonReceiver;

    string constant BASE_URI = "https://game.example.com/api/item/";

    // 缓存代币 ID 常量，因为 token.GOLD() 是外部 staticcall，会消耗 vm.prank
    uint256 GOLD;
    uint256 SILVER;
    uint256 SWORD;
    uint256 SHIELD;

    function setUp() public {
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        operator = makeAddr("operator");
        vault = new MockGameVault();
        nonReceiver = new NonReceiver();

        vm.prank(admin);
        token = new MyERC1155Demo(BASE_URI);

        // 预缓存代币类型 ID，后续测试直接使用
        GOLD   = token.GOLD();
        SILVER = token.SILVER();
        SWORD  = token.SWORD();
        SHIELD = token.SHIELD();
    }

    // ============================================================
    // 🏗️ Constructor 测试
    // ============================================================

    function test_Constructor_URI() public view {
        assertEq(token.uri(1), BASE_URI);
    }

    function test_Constructor_Owner() public view {
        assertEq(token.owner(), admin);
    }

    // ============================================================
    // 🆔 代币类型常量测试
    // ============================================================

    function test_TokenTypeConstants() public view {
        assertEq(GOLD,   1);
        assertEq(SILVER, 2);
        assertEq(SWORD,  3);
        assertEq(SHIELD, 4);
    }

    // ============================================================
    // 🎯 铸造（Mint）测试
    // ============================================================

    /// @notice 铸造单种同质化代币
    function test_Mint_SingleFungible() public {
        uint256 amount = 1000;

        vm.prank(admin);
        token.mint(user1, GOLD, amount, "");

        assertEq(token.balanceOf(user1, GOLD), amount);
        assertEq(token.totalSupply(GOLD), amount);
    }

    /// @notice 批量铸造多种同质化代币 ✅ ERC-1155 核心功能
    function test_Mint_BatchFungible() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = GOLD;
        ids[1] = SILVER;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 200;

        vm.prank(admin);
        token.mintBatch(user1, ids, amounts, "");

        assertEq(token.balanceOf(user1, GOLD),  100);
        assertEq(token.balanceOf(user1, SILVER), 200);
        assertEq(token.totalSupply(GOLD),  100);
        assertEq(token.totalSupply(SILVER), 200);
    }

    /// @notice 铸造非同质化代币（NFT）
    function test_Mint_NFT() public {
        vm.prank(admin);
        uint256 nftId = token.mintNFT(user1, "");

        assertTrue(nftId >= 10);

        assertEq(token.balanceOf(user1, nftId), 1);
        assertEq(token.totalSupply(nftId), 1);
        assertTrue(token.isNonFungible(nftId));
    }

    /// @notice 铸造预设的 NFT（传说之剑，id=3，供应量=1）
    function test_Mint_PresetNFT() public {
        vm.prank(admin);
        token.mint(user1, SWORD, 1, "");

        assertEq(token.balanceOf(user1, SWORD), 1);
        assertEq(token.totalSupply(SWORD), 1);
        assertTrue(token.isNonFungible(SWORD));
    }

    /// @notice 铸造 SWORD 第二把会变成供应量 2，不再是 NFT
    function test_Mint_PresetNFT_SecondCopyMakesItFungible() public {
        vm.prank(admin);
        token.mint(user1, SWORD, 1, "");

        vm.prank(admin);
        token.mint(user2, SWORD, 1, "");

        assertEq(token.totalSupply(SWORD), 2);
        assertFalse(token.isNonFungible(SWORD));
        // 这也展示了"半同质化"的概念：
        // 同一个 id 可以有多个副本时，它就从 NFT 变成了同质化代币
    }

    /// @notice 铸造事件：TransferSingle
    /// @dev 注意：_msgSender() 在 _update() 中被记录为 operator，即原始外部调用者
    function test_Mint_Event() public {
        uint256 amount = 500;

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        // operator = msg.sender = admin, from = address(0), to = user1
        emit IERC1155.TransferSingle(admin, address(0), user1, GOLD, amount);
        token.mint(user1, GOLD, amount, "");
    }

    /// @notice 批量铸造事件：TransferBatch
    function test_MintBatch_Event() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = GOLD;
        ids[1] = SILVER;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 200;

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        // operator = msg.sender = admin, from = address(0), to = user1
        emit IERC1155.TransferBatch(admin, address(0), user1, ids, amounts);
        token.mintBatch(user1, ids, amounts, "");
    }

    /// @notice 只有 admin 可以铸造
    function test_Mint_RevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        token.mint(user1, GOLD, 100, "");
    }

    // ============================================================
    // 👀 批量余额查询测试（balanceOfBatch）
    // ============================================================

    /// @notice 批量余额查询 ✅ ERC-1155 独有
    function test_BalanceOfBatch() public {
        vm.startPrank(admin);
        token.mint(user1, GOLD,   100, "");
        token.mint(user1, SILVER, 200, "");
        token.mint(user2, GOLD,   50,  "");
        token.mint(user2, SHIELD, 1,   "");
        vm.stopPrank();

        address[] memory accounts = new address[](4);
        accounts[0] = user1;
        accounts[1] = user1;
        accounts[2] = user2;
        accounts[3] = user2;

        uint256[] memory ids = new uint256[](4);
        ids[0] = GOLD;
        ids[1] = SILVER;
        ids[2] = GOLD;
        ids[3] = SHIELD;

        uint256[] memory balances = token.balanceOfBatch(accounts, ids);

        assertEq(balances.length, 4);
        assertEq(balances[0], 100); // user1 有 100 金币
        assertEq(balances[1], 200); // user1 有 200 银币
        assertEq(balances[2], 50);  // user2 有 50 金币
        assertEq(balances[3], 1);   // user2 有 1 面传说之盾（NFT）
    }

    // ============================================================
    // 📤 转账测试
    // ============================================================

    /// @notice 单种代币转账
    function test_Transfer_Single() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 1000, "");

        vm.prank(user1);
        token.safeTransferFrom(user1, user2, GOLD, 300, "");

        assertEq(token.balanceOf(user1, GOLD), 700);
        assertEq(token.balanceOf(user2, GOLD), 300);
    }

    /// @notice 批量转账 ✅ ERC-1155 核心优势
    function test_Transfer_Batch() public {
        vm.startPrank(admin);
        token.mint(user1, GOLD,   500, "");
        token.mint(user1, SILVER, 300, "");
        token.mint(user1, SWORD,  1,   "");
        vm.stopPrank();

        uint256[] memory ids = new uint256[](3);
        ids[0] = GOLD;
        ids[1] = SILVER;
        ids[2] = SWORD;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 200;
        amounts[1] = 100;
        amounts[2] = 1;

        vm.prank(user1);
        token.safeBatchTransferFrom(user1, user2, ids, amounts, "");

        assertEq(token.balanceOf(user1, GOLD),   300);
        assertEq(token.balanceOf(user1, SILVER), 200);
        assertEq(token.balanceOf(user1, SWORD),  0);

        assertEq(token.balanceOf(user2, GOLD),   200);
        assertEq(token.balanceOf(user2, SILVER), 100);
        assertEq(token.balanceOf(user2, SWORD),  1);
    }

    /// @notice 余额不足时转账应该 revert
    function test_Transfer_RevertIfInsufficientBalance() public {
        // user1 没有任何代币，转账应 revert
        vm.prank(user1);
        vm.expectRevert();
        token.safeTransferFrom(user1, user2, GOLD, 1, "");
    }

    /// @notice 转账事件：TransferSingle
    function test_Transfer_Event() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 500, "");

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        // operator = msg.sender = user1, from = user1, to = user2
        emit IERC1155.TransferSingle(user1, user1, user2, GOLD, 200);
        token.safeTransferFrom(user1, user2, GOLD, 200, "");
    }

    /// @notice 批量转账事件：TransferBatch
    function test_TransferBatch_Event() public {
        vm.startPrank(admin);
        token.mint(user1, GOLD,   500, "");
        token.mint(user1, SILVER, 300, "");
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = GOLD;
        ids[1] = SILVER;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 200;
        amounts[1] = 100;

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        // operator = msg.sender = user1, from = user1, to = user2
        emit IERC1155.TransferBatch(user1, user1, user2, ids, amounts);
        token.safeBatchTransferFrom(user1, user2, ids, amounts, "");
    }

    // ============================================================
    // ✅ 授权（ApprovalForAll）测试
    // ============================================================

    /// @notice 授权操作者管理所有代币
    function test_ApprovalForAll() public {
        vm.prank(user1);
        token.setApprovalForAll(operator, true);

        assertTrue(token.isApprovedForAll(user1, operator));

        vm.prank(user1);
        token.setApprovalForAll(operator, false);

        assertFalse(token.isApprovedForAll(user1, operator));
    }

    /// @notice 授权事件
    function test_ApprovalForAll_Event() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit IERC1155.ApprovalForAll(user1, operator, true);
        token.setApprovalForAll(operator, true);
    }

    /// @notice 被授权的操作者可以代转账
    function test_ApprovalForAll_OperatorCanTransfer() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 500, "");

        vm.prank(user1);
        token.setApprovalForAll(operator, true);

        vm.prank(operator);
        token.safeTransferFrom(user1, user2, GOLD, 300, "");

        assertEq(token.balanceOf(user1, GOLD), 200);
        assertEq(token.balanceOf(user2, GOLD), 300);
    }

    /// @notice 未授权的操作者不能代转账
    function test_Transfer_RevertIfNotApproved() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 100, "");

        // user2 没有授权，不能代 user1 转账
        vm.prank(user2);
        vm.expectRevert();
        token.safeTransferFrom(user1, user2, GOLD, 50, "");
    }

    // ============================================================
    // 🏦 安全转账回调测试
    // ============================================================

    /// @notice 向合约转账时，如果合约实现了 IERC1155Receiver，可以成功
    function test_TransferToReceiverContract() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 500, "");

        vm.prank(user1);
        token.safeTransferFrom(user1, address(vault), GOLD, 200, "");

        assertEq(token.balanceOf(address(vault), GOLD), 200);
        assertEq(token.balanceOf(user1, GOLD), 300);
    }

    /// @notice 向合约批量转账时，如果合约实现了 onERC1155BatchReceived，可以成功
    function test_TransferBatchToReceiverContract() public {
        vm.startPrank(admin);
        token.mint(user1, GOLD,   500, "");
        token.mint(user1, SILVER, 300, "");
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = GOLD;
        ids[1] = SILVER;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 200;
        amounts[1] = 150;

        vm.prank(user1);
        token.safeBatchTransferFrom(user1, address(vault), ids, amounts, "");

        assertEq(token.balanceOf(address(vault), GOLD),   200);
        assertEq(token.balanceOf(address(vault), SILVER), 150);
    }

    /// @notice ⚠️ 向没有实现 IERC1155Receiver 的合约转账应该 revert！
    ///         这是 ERC-1155 的安全机制 —— 防止代币被锁死在合约中。
    function test_TransferToNonReceiver_Revert() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 100, "");

        vm.prank(user1);
        vm.expectRevert();
        token.safeTransferFrom(user1, address(nonReceiver), GOLD, 50, "");
    }

    // ============================================================
    // 🔥 销毁（Burn）测试
    // ============================================================

    /// @notice 单种代币销毁
    function test_Burn_Single() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 1000, "");

        vm.prank(admin);
        token.burn(user1, GOLD, 300);

        assertEq(token.balanceOf(user1, GOLD), 700);
        assertEq(token.totalSupply(GOLD), 700);
    }

    /// @notice 批量销毁
    function test_Burn_Batch() public {
        vm.startPrank(admin);
        token.mint(user1, GOLD,   500, "");
        token.mint(user1, SILVER, 300, "");
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = GOLD;
        ids[1] = SILVER;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 50;

        vm.prank(admin);
        token.burnBatch(user1, ids, amounts);

        assertEq(token.balanceOf(user1, GOLD),   400);
        assertEq(token.balanceOf(user1, SILVER), 250);
        assertEq(token.totalSupply(GOLD),   400);
        assertEq(token.totalSupply(SILVER), 250);
    }

    /// @notice 销毁数超过余额应 revert
    function test_Burn_RevertIfInsufficientBalance() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 100, "");

        vm.prank(admin);
        vm.expectRevert();
        token.burn(user1, GOLD, 200);
    }

    /// @notice 销毁事件
    function test_Burn_Event() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 500, "");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        // operator = msg.sender = admin, from = user1, to = address(0)
        emit IERC1155.TransferSingle(admin, user1, address(0), GOLD, 200);
        token.burn(user1, GOLD, 200);
    }

    /// @notice 只有 admin 可以销毁
    function test_Burn_RevertIfNotOwner() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 100, "");

        vm.prank(user1);
        vm.expectRevert();
        token.burn(user1, GOLD, 50);
    }

    // ============================================================
    // 🔍 非同质化检测测试
    // ============================================================

    /// @notice 预设的 NFT（SWORD, SHIELD）未被铸造前也视为 NFT
    function test_IsNonFungible_Initial() public view {
        assertTrue(token.isNonFungible(SWORD));
        assertTrue(token.isNonFungible(SHIELD));
    }

    /// @notice 同质化代币不是 NFT
    function test_IsNonFungible_FungibleIsFalse() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 100, "");

        assertFalse(token.isNonFungible(GOLD));
    }

    /// @notice 供应量 > 1 时不再是 NFT
    function test_IsNonFungible_MultipleCopiesAreFungible() public {
        vm.prank(admin);
        token.mint(user1, SWORD, 2, "");

        assertFalse(token.isNonFungible(SWORD));
    }

    // ============================================================
    // 📝 元数据 URI 测试
    // ============================================================

    /// @notice 设置新的基础 URI
    function test_SetURI() public {
        string memory newUri = "https://new-game.example.com/meta/";

        vm.prank(admin);
        token.setURI(newUri);

        assertEq(token.uri(1), newUri);
    }

    /// @notice 只有 admin 可以修改 URI
    function test_SetURI_RevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        token.setURI("https://evil.example.com/");
    }

    // ============================================================
    // 🔌 接口检测（ERC-165）测试
    // ============================================================

    function test_SupportsInterface() public view {
        // IERC1155
        assertTrue(token.supportsInterface(0xd9b67a26));
        // IERC1155MetadataURI
        assertTrue(token.supportsInterface(0x0e89341c));
        // IERC165
        assertTrue(token.supportsInterface(0x01ffc9a7));
        // 随机
        assertFalse(token.supportsInterface(0x12345678));
    }

    // ============================================================
    // 🧪 综合场景测试
    // ============================================================

    /// @notice 完整的游戏道具管理场景
    /// @dev 模拟真实游戏流程：发道具 → 交易 → 消耗
    function test_CompleteGameScenario() public {
        // ========== 阶段1：游戏初始化，发放初始道具 ==========
        vm.startPrank(admin);
        token.mint(user1, GOLD,   1000, ""); // 给玩家1 1000 金币
        token.mint(user1, SWORD,  1,    ""); // 给玩家1 传说之剑
        token.mint(user2, GOLD,   500,  ""); // 给玩家2 500 金币
        token.mint(user2, SHIELD, 1,    ""); // 给玩家2 传说之盾
        vm.stopPrank();

        assertEq(token.balanceOf(user1, GOLD),  1000);
        assertEq(token.balanceOf(user1, SWORD), 1);
        assertEq(token.balanceOf(user2, GOLD),  500);
        assertEq(token.balanceOf(user2, SHIELD), 1);

        // ========== 阶段2：玩家之间交易 ==========
        // user1 用 300 金币向 user2 购买传说之盾
        vm.prank(user1);
        token.safeTransferFrom(user1, user2, GOLD, 300, "");

        vm.prank(user2);
        token.safeTransferFrom(user2, user1, SHIELD, 1, "");

        assertEq(token.balanceOf(user1, GOLD),   700);
        assertEq(token.balanceOf(user1, SHIELD), 1);
        assertEq(token.balanceOf(user2, GOLD),   800);
        assertEq(token.balanceOf(user2, SHIELD), 0);

        // ========== 阶段3：游戏运营方回收道具 ==========
        vm.prank(admin);
        token.burn(user1, SWORD, 1);

        assertEq(token.balanceOf(user1, SWORD), 0);
        assertEq(token.totalSupply(SWORD), 0);
    }

    /// @notice 批量操作演示
    /// @dev 批量转账一次完成 4 种代币的转移
    function test_BatchTransferGasEfficiency() public {
        vm.startPrank(admin);
        token.mint(user1, GOLD,   1000, "");
        token.mint(user1, SILVER, 1000, "");
        token.mint(user1, SWORD,  1,    "");
        token.mint(user1, SHIELD, 1,    "");
        vm.stopPrank();

        uint256[] memory ids = new uint256[](4);
        ids[0] = GOLD;
        ids[1] = SILVER;
        ids[2] = SWORD;
        ids[3] = SHIELD;

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 500;
        amounts[1] = 500;
        amounts[2] = 1;
        amounts[3] = 1;

        vm.prank(user1);
        token.safeBatchTransferFrom(user1, user2, ids, amounts, "");

        assertEq(token.balanceOf(user1, GOLD),   500);
        assertEq(token.balanceOf(user1, SILVER), 500);
        assertEq(token.balanceOf(user1, SWORD),  0);
        assertEq(token.balanceOf(user1, SHIELD), 0);

        assertEq(token.balanceOf(user2, GOLD),   500);
        assertEq(token.balanceOf(user2, SILVER), 500);
        assertEq(token.balanceOf(user2, SWORD),  1);
        assertEq(token.balanceOf(user2, SHIELD), 1);
    }
}
