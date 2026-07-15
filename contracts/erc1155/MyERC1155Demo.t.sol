// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title MyERC1155Demo 测试（教学精简版）
 * @dev 仅展示各重要方法的正常调用方式及参数，删除 revert/边界/模糊测试
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
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) external override returns (bytes4) {
        emit LogReceivedBatch(operator, from, ids, values, data);
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
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

    string constant BASE_URI = "https://game.example.com/api/item/{id}.json";

    // 缓存代币 ID 常量
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

        vm.prank(admin);
        token = new MyERC1155Demo(BASE_URI);

        // 预缓存代币类型 ID
        GOLD   = token.GOLD();
        SILVER = token.SILVER();
        SWORD  = token.SWORD();
        SHIELD = token.SHIELD();
    }

    // ============================================================
    // 🏗️ Constructor
    // ============================================================

    function test_Constructor_URI() public view {
        assertEq(token.uri(1), BASE_URI);
    }

    function test_Constructor_Owner() public view {
        assertEq(token.owner(), admin);
    }

    // ============================================================
    // 🆔 代币类型常量
    // ============================================================

    function test_TokenTypeConstants() public view {
        assertEq(GOLD,   1);
        assertEq(SILVER, 2);
        assertEq(SWORD,  3);
        assertEq(SHIELD, 4);
    }

    // ============================================================
    // 🎯 铸造（Mint）
    // ============================================================

    /// @notice 铸造单种同质化代币：mint(to, id, amount, data)
    function test_Mint_SingleFungible() public {
        uint256 amount = 1000;

        vm.prank(admin);
        token.mint(user1, GOLD, amount, "");

        assertEq(token.balanceOf(user1, GOLD), amount);
        assertEq(token.totalSupply(GOLD), amount);
    }

    /// @notice 批量铸造：mintBatch(to, ids, amounts, data)
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

    /// @notice 铸造 NFT：mintNFT(to, data) 返回新 id
    function test_Mint_NFT() public {
        vm.prank(admin);
        uint256 nftId = token.mintNFT(user1, "");

        assertTrue(nftId >= 10);
        assertEq(token.balanceOf(user1, nftId), 1);
        assertEq(token.totalSupply(nftId), 1);
        assertTrue(token.isNonFungible(nftId));
    }

    /// @notice 铸造预设 NFT（SWORD 为 NFT，供应量=1）
    function test_Mint_PresetNFT() public {
        vm.prank(admin);
        token.mint(user1, SWORD, 1, "");

        assertEq(token.balanceOf(user1, SWORD), 1);
        assertEq(token.totalSupply(SWORD), 1);
        assertTrue(token.isNonFungible(SWORD));
    }

    /// @notice 铸造事件：TransferSingle — 使用 vm.expectEmit
    function test_Mint_Event() public {
        uint256 amount = 500;

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit IERC1155.TransferSingle(admin, address(0), user1, GOLD, amount);
        token.mint(user1, GOLD, amount, "");
    }

    // ============================================================
    // 👀 批量余额查询：balanceOfBatch
    // ============================================================

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
        assertEq(balances[0], 100);
        assertEq(balances[1], 200);
        assertEq(balances[2], 50);
        assertEq(balances[3], 1);
    }

    // ============================================================
    // 📤 转账：safeTransferFrom / safeBatchTransferFrom
    // ============================================================

    /// @notice 单种代币转账：safeTransferFrom(from, to, id, amount, data)
    function test_Transfer_Single() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 1000, "");

        vm.prank(user1);
        token.safeTransferFrom(user1, user2, GOLD, 300, "");

        assertEq(token.balanceOf(user1, GOLD), 700);
        assertEq(token.balanceOf(user2, GOLD), 300);
    }

    /// @notice 批量转账：safeBatchTransferFrom(from, to, ids, amounts, data)
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

    // ============================================================
    // ✅ 授权：setApprovalForAll / isApprovedForAll
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

    // ============================================================
    // 🏦 向合约转账（IERC1155Receiver）
    // ============================================================

    /// @notice 向实现了 IERC1155Receiver 的合约转单种代币
    function test_TransferToReceiverContract() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 500, "");

        vm.prank(user1);
        token.safeTransferFrom(user1, address(vault), GOLD, 200, "");

        assertEq(token.balanceOf(address(vault), GOLD), 200);
        assertEq(token.balanceOf(user1, GOLD), 300);
    }

    /// @notice 向实现了 IERC1155Receiver 的合约批量转账
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

    // ============================================================
    // 🔥 销毁：burn / burnBatch
    // ============================================================

    /// @notice 单种代币销毁：burn(from, id, amount)
    function test_Burn_Single() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 1000, "");

        vm.prank(admin);
        token.burn(user1, GOLD, 300);

        assertEq(token.balanceOf(user1, GOLD), 700);
        assertEq(token.totalSupply(GOLD), 700);
    }

    /// @notice 批量销毁：burnBatch(from, ids, amounts)
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

    // ============================================================
    // 🔍 非同质化检测：isNonFungible
    // ============================================================

    /// @notice 预设 NFT 未被铸造前也视为 NFT
    function test_IsNonFungible_Initial() public view {
        assertTrue(token.isNonFungible(SWORD));
        assertTrue(token.isNonFungible(SHIELD));
    }

    /// @notice 同质化代币（已铸造）不是 NFT
    function test_IsNonFungible_FungibleIsFalse() public {
        vm.prank(admin);
        token.mint(user1, GOLD, 100, "");

        assertFalse(token.isNonFungible(GOLD));
    }

    // ============================================================
    // 📝 元数据 URI：setURI
    // ============================================================

    function test_SetURI() public {
        string memory newUri = "https://new-game.example.com/meta/";

        vm.prank(admin);
        token.setURI(newUri);

        assertEq(token.uri(1), newUri);
    }

    // ============================================================
    // 🔌 接口检测：supportsInterface（ERC-165）
    // ============================================================

    function test_SupportsInterface() public view {
        assertTrue(token.supportsInterface(0xd9b67a26));  // IERC1155
        assertTrue(token.supportsInterface(0x0e89341c));  // IERC1155MetadataURI
        assertTrue(token.supportsInterface(0x01ffc9a7));  // IERC165
        assertFalse(token.supportsInterface(0x12345678)); // 随机
    }
}
