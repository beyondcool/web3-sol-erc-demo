// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title MyERC1155Demo 测试（教学精简版）
 * @dev 仅展示各重要方法的正常调用方式及参数，帮助学生快速上手
 */

import {Test} from "forge-std/Test.sol";
import {MyERC1155Demo} from "./MyERC1155Demo.sol";

contract MyERC1155DemoTest is Test {
    MyERC1155Demo token;
    address admin = makeAddr("admin");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address operator = makeAddr("operator");

    string constant BASE_URI = "https://game.example.com/api/item/{id}.json";

    uint256 GOLD;
    uint256 SILVER;
    uint256 SWORD;
    uint256 SHIELD;

    function setUp() public {
        vm.prank(admin);
        token = new MyERC1155Demo(BASE_URI);

        GOLD   = token.GOLD();
        SILVER = token.SILVER();
        SWORD  = token.SWORD();
        SHIELD = token.SHIELD();
    }

    /// @notice 构造方法：new MyERC1155Demo(uri)
    /// @notice URI 查询：token.uri(id)        owner 查询：token.owner()
    /// @notice 常量：GOLD / SILVER / SWORD / SHIELD
    /// @notice 接口检测：token.supportsInterface(interfaceId)
    function test_ConstructorAndConstants() public view {
        assertEq(token.uri(1), BASE_URI);
        assertEq(token.owner(), admin);
        assertEq(GOLD, 1);
        assertEq(SILVER, 2);
        assertEq(SWORD, 3);
        assertEq(SHIELD, 4);
        assertTrue(token.supportsInterface(0xd9b67a26)); // IERC1155
    }

    /// @notice 铸造单种：mint(to, id, amount, data)
    /// @notice 铸造 NFT：mintNFT(to, data) → 返回新 id
    /// @notice 查询余额：balanceOf(account, id)
    /// @notice 总供应量：totalSupply(id)
    /// @notice NFT 检测：isNonFungible(id)
    function test_Mint() public {
        // 铸造同质化代币
        vm.prank(admin);
        token.mint(user1, GOLD, 1000, "");

        assertEq(token.balanceOf(user1, GOLD), 1000);
        assertEq(token.totalSupply(GOLD), 1000);

        // 铸造 NFT
        vm.prank(admin);
        uint256 nftId = token.mintNFT(user1, "");

        assertEq(token.balanceOf(user1, nftId), 1);
        assertTrue(token.isNonFungible(nftId));

        // 铸造预设 NFT（SWORD 供应量=1，也是 NFT）
        vm.prank(admin);
        token.mint(user1, SWORD, 1, "");

        assertEq(token.balanceOf(user1, SWORD), 1);
        assertTrue(token.isNonFungible(SWORD));
    }

    /// @notice 批量铸造：mintBatch(to, ids, amounts, data)
    /// @notice 批量余额查询：balanceOfBatch(accounts, ids)
    function test_MintBatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = GOLD;
        ids[1] = SILVER;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 200;

        vm.prank(admin);
        token.mintBatch(user1, ids, amounts, "");

        // 批量查询余额
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user1;

        uint256[] memory balances = token.balanceOfBatch(accounts, ids);

        assertEq(balances[0], 100);
        assertEq(balances[1], 200);
        assertEq(token.totalSupply(GOLD), 100);
        assertEq(token.totalSupply(SILVER), 200);
    }

    /// @notice 单种转账：safeTransferFrom(from, to, id, amount, data)
    /// @notice 批量转账：safeBatchTransferFrom(from, to, ids, amounts, data)
    function test_Transfer() public {
        // 准备代币
        vm.startPrank(admin);
        token.mint(user1, GOLD, 500, "");
        token.mint(user1, SILVER, 300, "");
        vm.stopPrank();

        // 单种转账
        vm.prank(user1);
        token.safeTransferFrom(user1, user2, GOLD, 200, "");

        // 批量转账
        uint256[] memory ids = new uint256[](2);
        ids[0] = GOLD;
        ids[1] = SILVER;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 150;

        vm.prank(user1);
        token.safeBatchTransferFrom(user1, user2, ids, amounts, "");
    }

    /// @notice 授权：setApprovalForAll(operator, approved)
    /// @notice 查询授权：isApprovedForAll(account, operator)
    /// @notice 操作者代转账
    function test_Approval() public {
        // 授权
        vm.prank(user1);
        token.setApprovalForAll(operator, true);
        assertTrue(token.isApprovedForAll(user1, operator));

        // 铸造一些代币供操作者转账
        vm.prank(admin);
        token.mint(user1, GOLD, 500, "");

        // 操作者代转账
        vm.prank(operator);
        token.safeTransferFrom(user1, user2, GOLD, 200, "");

        // 取消授权
        vm.prank(user1);
        token.setApprovalForAll(operator, false);
        assertFalse(token.isApprovedForAll(user1, operator));
    }

    /// @notice 销毁单种：burn(from, id, amount)
    /// @notice 批量销毁：burnBatch(from, ids, amounts)
    function test_Burn() public {
        vm.startPrank(admin);
        token.mint(user1, GOLD, 500, "");
        token.mint(user1, SILVER, 300, "");
        vm.stopPrank();

        // 单种销毁（需要 admin）
        vm.prank(admin);
        token.burn(user1, GOLD, 200);
        assertEq(token.totalSupply(GOLD), 300);

        // 批量销毁（需要 admin）
        uint256[] memory ids = new uint256[](2);
        ids[0] = GOLD;
        ids[1] = SILVER;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 50;

        vm.prank(admin);
        token.burnBatch(user1, ids, amounts);
        assertEq(token.totalSupply(SILVER), 250);
    }

    /// @notice 更新 URI：setURI(newUri)
    function test_SetURI() public {
        string memory newUri = "https://new-game.example.com/meta/";

        vm.prank(admin);
        token.setURI(newUri);

        assertEq(token.uri(1), newUri);
    }
}
