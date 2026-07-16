// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ------------------------------------------------------------
// 1. 基础资产（ERC20），模拟用户想要存入金库的代币
// ------------------------------------------------------------
contract MockToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Mock Token", "MTK") {
        _mint(msg.sender, initialSupply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ------------------------------------------------------------
// 2. ERC-4626 金库 —— 教学用简化版
// ------------------------------------------------------------
contract SimpleVault is ERC4626 {
    using SafeERC20 for IERC20;

    // 记录捐赠事件，便于观察金库总资产变化
    event Donated(address indexed donor, uint256 amount);

    /**
     * @param _asset 金库接受的基础资产（例如上面的 MockToken）
     *
     * 继承的 ERC4626 合约会：
     *  - 将 _asset 永久记录为金库的底层资产
     *  - 将金库份额代币（vMTK）部署为 18 位小数的 ERC20
     *  - 内部实现 deposit/mint/redeem/withdraw 等核心逻辑
     */
    constructor(IERC20 _asset) ERC4626(_asset) ERC20("Vault Share", "vMTK") {}

    // ------------------------------------------------------------
    // 3. 模拟收益：任何人都可以向金库“捐赠”基础资产
    //    捐赠不会铸造新的份额，因此现有份额的兑换比例会立刻上升
    // ------------------------------------------------------------
    function donate(uint256 amount) external {
        // 将调用者的基础资产转移到金库
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount);
        emit Donated(msg.sender, amount);
    }

    // ------------------------------------------------------------
    // 4. 辅助视图：查看当前 1 份额能兑换多少基础资产（18位精度）
    // ------------------------------------------------------------
    function sharePrice() external view returns (uint256) {
        return convertToAssets(1e18);
    }
}