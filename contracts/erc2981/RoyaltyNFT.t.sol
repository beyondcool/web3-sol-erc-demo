// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title RoyaltyNFT 测试（教学版）
 * @dev 展示各主要方法的正常调用方式及参数，帮助学生快速上手 ERC-721 + ERC-2981
 */

import {Test} from "forge-std/Test.sol";
import {RoyaltyNFT} from "./RoyaltyNFT.sol";

contract RoyaltyNFTTest is Test {
    RoyaltyNFT nft;
    address admin = makeAddr("admin");
    address user1  = makeAddr("user1");
    address user2  = makeAddr("user2");
    address operator = makeAddr("operator");

    function setUp() public {
        vm.prank(admin);
        nft = new RoyaltyNFT();
    }


    /// @notice 查询版税：royaltyInfo(tokenId, salePrice)
    ///         → (receiver, royaltyAmount)  默认 5%
    function test_RoyaltyInfo() public {
        vm.prank(admin);
        uint256 tokenId = nft.mint(user1);

        uint256 salePrice = 100 ether;
        (address receiver, uint256 amount) = nft.royaltyInfo(tokenId, salePrice);

        assertEq(receiver, admin);
        assertEq(amount, 5 ether); // 5% of 100 ETH
    }

    /// @notice 设置独立版税：setTokenRoyalty(tokenId, receiver, feeNumerator)
    ///         改后 royaltyInfo 返回新值，不再使用默认版税。
    function test_SetTokenRoyalty() public {
        vm.prank(admin);
        uint256 tokenId = nft.mint(user1);

        // 为这个 token 单独设置 10% 版税给 user2
        vm.prank(admin);
        nft.setTokenRoyalty(tokenId, user2, 1000); // 1000/10000 = 10%

        uint256 salePrice = 100 ether;
        (address receiver, uint256 amount) = nft.royaltyInfo(tokenId, salePrice);

        assertEq(receiver, user2);
        assertEq(amount, 10 ether);
    }

}
