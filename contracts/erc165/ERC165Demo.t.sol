// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {Test} from "forge-std/Test.sol";
import "./ERC165Demo.sol";

contract ERC165Test is Test {
        MyCustomImplContract implContract;
    QueryScript queryScript;
    function setUp() public {
        // 初始化测试环境
        implContract = new MyCustomImplContract();
        queryScript = new QueryScript();
    }

    function testSupportsInterface() public view {
        // 是否支持：IERC165 接口
        bool supportsIERC165 = queryScript.checkSupportsInterface(address(implContract), 0x01ffc9a7);
        assertTrue(supportsIERC165, "MyCustomImplContract should support IERC165");

        // 是否支持：ICustomInterface 接口
        bytes4 customInterfaceId = type(ICustomInterface).interfaceId;
        // 算法逻辑：内部所有方法签名的 selector 进行 XOR 运算
        // bytes4 customInterfaceId = 
        //     ICustomInterface.upgrade.selector ^ 
        //     ICustomInterface.pause.selector;

        bool supportsCustomInterface = queryScript.checkSupportsInterface(address(implContract), customInterfaceId);
        assertTrue(supportsCustomInterface, "MyCustomImplContract should support ICustomInterface");
    }
}