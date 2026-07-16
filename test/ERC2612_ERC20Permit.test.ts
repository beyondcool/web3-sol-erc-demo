import { expect } from "chai";
import { network } from "hardhat";

const { ethers, networkHelpers } = await network.create();

/**
 * 
 *  当前文件演示了如何使用 ERC-2612 的 permit 方法实现无 gas 授权转账的模拟测试。
 *  涉及的合约文件在 contracts/erc2612 目录下：
 * 
 */

describe("ERC-2612 无 gas 授权转账模拟", function () {
  /**
   * 部署合约并分配初始代币
   * - owner 部署 MyToken 和 GaslessTransfer
   * - owner 铸造 1000 MTK，并转给 alice 500 MTK
   */
  async function deployContracts() {
    const [owner, alice, bob] = await ethers.getSigners();

    // 部署 MyToken，铸造 1000 MTK 给部署者（owner）
    const token = await ethers.deployContract("MyToken", [ethers.parseEther("1000")]);

    // 部署 GaslessTransfer，用于接收授权并代付 gas 转账
    const gasless = await ethers.deployContract("GaslessTransfer");

    // 从 owner 转移 500 MTK 给 alice，使她成为代币持有者
    await token.transfer(alice.address, ethers.parseEther("500"));

    return { token, gasless, owner, alice, bob };
  }

  it("应该通过链下签名实现无 gas 授权转账", async function () {
    const { token, gasless, alice, bob } = await networkHelpers.loadFixture(deployContracts);

    // ====== 阶段 1：Alice 链下签名（完全不需要 ETH） ======

    // 授权 GaslessTransfer 合约提取代币
    const spender = gasless.target;
    const value = ethers.parseEther("100");                        // 授权 100 MTK
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 小时后过期

    // 读取 Alice 当前的 nonce（签名计数器，防重放）
    const nonce = await token.nonces(alice.address);

    // 读取合约的 EIP-712 域信息（name, version, chainId, verifyingContract）
    const domain = await token.eip712Domain();

    // 构造 permit 签名所需的消息内容
    const message = {
      owner: alice.address,
      spender: spender,
      value: value,
      nonce: nonce,
      deadline: deadline,
    };

    // 定义 EIP-712 类型结构，必须与合约中 PERMIT_TYPEHASH 的定义一致
    const types = {
      Permit: [
        { name: "owner", type: "address" },
        { name: "spender", type: "address" },
        { name: "value", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    };

    // 使用从合约读取的实际域参数，避免硬编码出错
    const domainData = {
      name: domain.name,
      version: domain.version,
      chainId: domain.chainId,
      verifyingContract: domain.verifyingContract,
    };

    // Alice 调用钱包进行 EIP-712 签名（纯本地操作，不发起交易）
    const signature = await alice.signTypedData(domainData, types, message);

    // 从签名中提取 v, r, s
    const { v, r, s } = extractVRS(signature);

    // ====== 阶段 2：Bob 使用签名调用合约，支付 gas 完成转账 ======

    // 确认 Bob 初始余额为 0
    const bobBefore = await token.balanceOf(bob.address);
    expect(bobBefore).to.equal(0n);

    // Bob 发送交易，调用 permitAndTransferFrom
    // 该函数内部先执行 permit（链上验证签名并授权），再执行 transferFrom（转走代币）
    await gasless.connect(bob).permitAndTransferFrom(
      token.target,        // 代币合约地址
      alice.address,       // 签名者（持有者）
      bob.address,         // 接收者
      value,               // 转账数额
      deadline,            // 签名截止时间
      v,                   // 签名 v
      r,                   // 签名 r
      s,                   // 签名 s
    );

    // 验证最终余额
    const bobAfter = await token.balanceOf(bob.address);
    const aliceAfter = await token.balanceOf(alice.address);
    const contractBalance = await token.balanceOf(gasless.target);

    expect(bobAfter).to.equal(value);                       // Bob 收到 100 MTK
    expect(aliceAfter).to.equal(ethers.parseEther("400"));  // Alice 减少 100 MTK
    expect(contractBalance).to.equal(0n);                   // 合约未截留资金

    console.log("  ✅ 测试通过：Alice 未支付 gas，Bob 成功提取 100 MTK");
  });
});

/**
 * 从完整的 EIP-712 签名（0x + 65 字节）中解析出 v, r, s
 * 签名格式：r(32字节) + s(32字节) + v(1字节)
 */
function extractVRS(signature: string): {
  v: number;
  r: string;
  s: string;
} {
  const sig = signature.slice(2); // 去掉 0x 前缀
  const r = "0x" + sig.slice(0, 64);
  const s = "0x" + sig.slice(64, 128);
  const v = parseInt(sig.slice(128, 130), 16);
  return { v, r, s };
}