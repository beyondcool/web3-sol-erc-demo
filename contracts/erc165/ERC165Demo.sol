// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

// 1. 导入openzeppelin的ERC165或者自定义其中的标准接口 (IERC165)
// interface IERC165 {
//     /// @notice 查询合约是否实现了某个接口
//     /// @param interfaceId 要查询的接口ID
//     /// @return 支持返回true，否则返回false
//     function supportsInterface(bytes4 interfaceId) external view returns (bool);
// }

// 2. 自定义接口
// 假设这是我们定义的一套“可升级且可暂停”合约的标准
interface ICustomInterface {
    function upgrade(address newImplementation) external;
    function pause() external; // 新增的第二个方法
}

// 3. 实现一个合约 (MyCustomImplContract)，它“支持”ICustomInterface
// 合约允许不写 `is ICustomInterface`, 实际上实现了该接口中的全部方法即可。
contract MyCustomImplContract is IERC165 {
    // 步骤1: 计算我们支持的接口ID
    // IERC165 本身的 interfaceId 是固定的
    bytes4 private constant _INTERFACE_ID_IERC165 = 0x01ffc9a7;
    
    // 计算包含两个函数的 ICustomInterface 的 interfaceId
    // 规则：将所有函数的 selector 进行 XOR 运算
    // 注意：XOR运算时，运算顺序不影响结果，且相同的数值会抵消掉
    bytes4 private constant _INTERFACE_ID_CUSTOM = 
        ICustomInterface.upgrade.selector ^ 
        ICustomInterface.pause.selector;

    /// @notice 实现 IERC165 接口的核心函数
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == _INTERFACE_ID_IERC165 || interfaceId == _INTERFACE_ID_CUSTOM;
    }

    // 实现 ICustomInterface 定义的函数
    function upgrade(address /* newImplementation */) external pure {
        // 升级逻辑
    }

    // 实现 ICustomInterface 定义的函数
    function pause() external pure {
        // 暂停逻辑
    }
}

// 4. 查询脚本 (QueryScript)，保持不变
contract QueryScript {
    event InterfaceSupported(address indexed contractAddress, bytes4 interfaceId, bool supported);

    function checkSupportsInterface(address _contract, bytes4 _interfaceId) external view returns (bool) {
        return IERC165(_contract).supportsInterface(_interfaceId);
    }
}