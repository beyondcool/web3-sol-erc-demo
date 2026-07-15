// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MyERC20Demo} from "./MyERC20Demo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MyERC20DemoTest is Test {
    MyERC20Demo token;
    address owner;
    address user;
    address other;

    uint256 constant INITIAL_SUPPLY = 1000;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        other = makeAddr("other");
        vm.prank(owner);
        token = new MyERC20Demo(INITIAL_SUPPLY);
    }

    // ========== Constructor 测试 ==========

    function test_Constructor_InitialSupplyToOwner() public view {
        uint256 expected = INITIAL_SUPPLY * 10 ** token.decimals();
        assertEq(token.totalSupply(), expected);
        assertEq(token.balanceOf(owner), expected);
    }

    // ========== mint 测试 ==========

    function test_Mint_OwnerCanMint() public {
        uint256 amount = 100 * 10 ** token.decimals();
        vm.prank(owner);
        token.mint(user, amount);

        assertEq(token.balanceOf(user), amount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY * 10 ** token.decimals() + amount);
    }

    // ========== burn 测试 ==========

    function test_Burn_OwnerCanBurn() public {
        uint256 amount = 200 * 10 ** token.decimals();
        vm.prank(owner);
        token.transfer(user, amount);

        vm.prank(owner);
        token.burn(user, amount);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.totalSupply(), INITIAL_SUPPLY * 10 ** token.decimals() - amount);
    }

    function test_Burn_RevertIfInsufficientBalance() public {
        uint256 userBalance = 50 * 10 ** token.decimals();
        uint256 burnTooMuch = 100 * 10 ** token.decimals();

        // 先由 owner 转少量给 user
        vm.prank(owner);
        token.transfer(user, userBalance);

        // owner 尝试 burn 超过 user 余额的数量，应 revert
        vm.prank(owner);
        vm.expectRevert();
        token.burn(user, burnTooMuch);
    }


    // ========== ERC20 transfer 测试 ==========

    function test_Transfer() public {
        uint256 amount = 100 * 10 ** token.decimals();
        vm.prank(owner);
        token.transfer(user, amount);

        assertEq(token.balanceOf(owner), INITIAL_SUPPLY * 10 ** token.decimals() - amount);
        assertEq(token.balanceOf(user), amount);
    }

    // ========== ERC20 approve / transferFrom 测试 ==========

    function test_ApproveAndTransferFrom() public {
        uint256 amount = 100 * 10 ** token.decimals();
        vm.prank(owner);
        token.approve(user, amount);

        assertEq(token.allowance(owner, user), amount);

        vm.prank(user);
        token.transferFrom(owner, other, amount);

        assertEq(token.balanceOf(other), amount);
        assertEq(token.allowance(owner, user), 0);
    }
}