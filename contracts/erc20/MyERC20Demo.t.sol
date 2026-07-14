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

    function test_Constructor_Name() public view {
        assertEq(token.name(), "MyERC20Demo");
    }

    function test_Constructor_Symbol() public view {
        assertEq(token.symbol(), "MED");
    }

    function test_Constructor_Decimals() public view {
        assertEq(token.decimals(), 18);
    }

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

    function testFuzz_Mint_OwnerCanMint(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max - token.totalSupply());
        vm.prank(owner);
        token.mint(user, amount);

        assertEq(token.balanceOf(user), amount);
    }

    function test_Mint_RevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, 100);
    }

    function test_Mint_Event() public {
        uint256 amount = 500 * 10 ** token.decimals();
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), user, amount);
        token.mint(user, amount);
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

    function testFuzz_Burn_OwnerCanBurn(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_SUPPLY * 10 ** token.decimals());
        vm.prank(owner);
        token.transfer(user, amount);

        vm.prank(owner);
        token.burn(user, amount);

        assertEq(token.balanceOf(user), 0);
    }

    function test_Burn_RevertIfNotOwner() public {
        uint256 amount = 100 * 10 ** token.decimals();
        // 先由 owner 转一笔给 user，确保 user 有余额可被 burn
        vm.prank(owner);
        token.transfer(user, amount);

        // other 不是 owner，调用 burn 应 revert
        vm.prank(other);
        vm.expectRevert();
        token.burn(user, amount);
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

    function test_Burn_Event() public {
        uint256 amount = 300 * 10 ** token.decimals();
        vm.prank(owner);
        token.transfer(user, amount);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(user, address(0), amount);
        token.burn(user, amount);
    }

    // ========== ERC20 transfer 测试 ==========

    function test_Transfer() public {
        uint256 amount = 100 * 10 ** token.decimals();
        vm.prank(owner);
        token.transfer(user, amount);

        assertEq(token.balanceOf(owner), INITIAL_SUPPLY * 10 ** token.decimals() - amount);
        assertEq(token.balanceOf(user), amount);
    }

    function test_Transfer_RevertIfInsufficientBalance() public {
        vm.prank(user);
        vm.expectRevert();
        token.transfer(other, 1);
    }

    function test_Transfer_Event() public {
        uint256 amount = 50 * 10 ** token.decimals();
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(owner, user, amount);
        token.transfer(user, amount);
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

    function test_Approve_Event() public {
        uint256 amount = 100 * 10 ** token.decimals();
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(owner, user, amount);
        token.approve(user, amount);
    }

    function test_TransferFrom_RevertIfNotApproved() public {
        vm.prank(user);
        vm.expectRevert();
        token.transferFrom(owner, other, 100);
    }

    function test_TransferFrom_RevertIfInsufficientAllowance() public {
        uint256 approved = 50 * 10 ** token.decimals();
        uint256 transferAmount = 100 * 10 ** token.decimals();
        vm.prank(owner);
        token.approve(user, approved);

        vm.prank(user);
        vm.expectRevert();
        token.transferFrom(owner, other, transferAmount);
    }
}

