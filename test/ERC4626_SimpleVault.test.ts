import { expect } from "chai";
import { network } from "hardhat";

const { ethers, networkHelpers } = await network.create();

/**
 * ERC-4626 Tokenized Vault 使用说明
 * =================================
 *
 * ERC-4626 是 ERC-20 的扩展标准，定义了一个"代币化金库"。
 * 它将一笔底层资产（例如 USDC、ETH 或自定义 ERC-20）包装成
 * 份额代币（vault shares），用户存入资产获得份额，销毁份额取回资产。
 *
 * 核心操作：
 *   存入  deposit(assets, receiver) → 存入 assets 数量的资产，receiver 获得份额
 *   铸造   mint(shares, receiver)   → 指定铸造 shares 数量的份额，receiver 获得份额
 *   提取 withdraw(assets, receiver, owner) → 提取 assets 数量的底层资产
 *   赎回  redeem(shares, receiver, owner) → 销毁 shares 份额，赎回对应底层资产
 *
 * 关键概念：
 * - 份额价格 = totalAssets / totalSupply，随金库收益增长而上升
 * - deposit 和 redeem 是"用户友好"的入口：用户指定资产数量
 * - mint 和 withdraw 是"份额友好"的入口：用户指定份额数量
 *
 * 合约文件：contracts/erc4626/SimpleVault.sol
 */

/**
 * 对于 ERC-4626 的份额转换值比较，允许小精度偏差。
 * OpenZeppelin v5 使用 virtual shares 机制（偏移量 = 1），
 * 在份额 ↔ 资产转换时可能产生 1-2 wei 的取整偏差，这是正常行为。
 */
function expectRoughly(actual: bigint, expected: bigint, tolerance: bigint = 2n): void {
  const diff = actual > expected ? actual - expected : expected - actual;
  expect(diff).to.be.lessThanOrEqual(tolerance);
}

describe("ERC-4626 金库操作模拟", function () {
  /**
   * 部署合约：
   * - owner 部署 MockToken（基础资产）并铸造 12_000 MTK
   * - owner 部署 SimpleVault（金库），底层资产为 MockToken
   * - owner 将 5_000 MTK 转给 alice，3_000 MTK 转给 bob
   * - owner 保留 2_000 MTK 用于后续捐赠模拟收益
   */
  async function deployVaultFixture() {
    const [owner, alice, bob] = await ethers.getSigners();

    const token = await ethers.deployContract("MockToken", [
      ethers.parseEther("12000"),
    ]);

    const vault = await ethers.deployContract("SimpleVault", [token.target]);

    await token.transfer(alice.address, ethers.parseEther("5000"));
    await token.transfer(bob.address, ethers.parseEther("3000"));

    return { token, vault, owner, alice, bob };
  }

  // ────────────────────────────────────────────────────────
  // 1. 部署与基本配置查看
  // ────────────────────────────────────────────────────────

  it("1. 部署后查看金库基本信息", async function () {
    const { token, vault } = await networkHelpers.loadFixture(
      deployVaultFixture,
    );

    // 底层资产地址 —— 应该是 MockToken
    const underlyingAsset = await vault.asset();
    expect(underlyingAsset).to.equal(token.target);

    // 金库份额代币的元数据（SimpleVault 同时是一个 ERC-20 代币）
    const name = await vault.name();
    const symbol = await vault.symbol();
    const decimals = await vault.decimals();
    expect(name).to.equal("Vault Share");
    expect(symbol).to.equal("vMTK");
    expect(decimals).to.equal(18n);

    // 初始状态下金库为空
    expect(await vault.totalSupply()).to.equal(0n);
    expect(await vault.totalAssets()).to.equal(0n);

    // sharePrice = convertToAssets(1e18)
    // OZ v5 使用 virtual shares，即使金库为空也返回 1e18（1:1 基准价）
    expect(await vault.sharePrice()).to.equal(ethers.parseEther("1"));

    console.log(
      `  ✅ 金库 "${name}" (${symbol}) 部署完成，底层资产: ${underlyingAsset}`,
    );
  });

  // ────────────────────────────────────────────────────────
  // 2. 存入资产（deposit）
  // ────────────────────────────────────────────────────────

  it("2. Alice 存入 1_000 MTK，获得等量份额", async function () {
    const { token, vault, alice } = await networkHelpers.loadFixture(
      deployVaultFixture,
    );

    const depositAmount = ethers.parseEther("1000");

    // --- 第一步：approve 金库使用 Alice 的 MTK ---
    await token.connect(alice).approve(vault.target, depositAmount);

    // --- 第二步：deposit ---
    // deposit(assets, receiver)：
    //   - 从调用者转入 assets 数量的底层资产到金库
    //   - 向 receiver 铸造对应数量的份额代币
    //   - 返回实际铸造的份额数
    //
    // 初始时 1 资产 = 1 份额（金库尚未产生收益）
    const shares = await vault
      .connect(alice)
      .deposit.staticCall(depositAmount, alice.address);
    expect(shares).to.equal(depositAmount);

    await vault.connect(alice).deposit(depositAmount, alice.address);

    // --- 验证结果 ---
    expect(await vault.balanceOf(alice.address)).to.equal(depositAmount);
    // Alice 原有 5_000，存入 1_000，剩余 4_000
    expect(await token.balanceOf(alice.address)).to.equal(
      ethers.parseEther("4000"),
    );
    expect(await vault.totalAssets()).to.equal(depositAmount);
    expect(await vault.sharePrice()).to.equal(ethers.parseEther("1"));

    console.log(
      `  ✅ Alice 存入 ${ethers.formatEther(depositAmount)} MTK，获得 ${ethers.formatEther(shares)} vMTK 份额`,
    );
    console.log(`     金库总资产: ${ethers.formatEther(await vault.totalAssets())} MTK`);
  });

  // ────────────────────────────────────────────────────────
  // 3. 金库产生收益后份额升值
  // ────────────────────────────────────────────────────────

  it("3. 捐赠产生收益后，份额升值，Alice 获得更多资产", async function () {
    const { token, vault, owner, alice } =
      await networkHelpers.loadFixture(deployVaultFixture);

    // ---------- 3a. Alice 先存入 1_000 MTK ----------
    const aliceDeposit = ethers.parseEther("1000");
    await token.connect(alice).approve(vault.target, aliceDeposit);
    await vault.connect(alice).deposit(aliceDeposit, alice.address);
    expect(await vault.sharePrice()).to.equal(ethers.parseEther("1"));

    // ---------- 3b. Owner 通过 donate() 捐赠 500 MTK 到金库 ----------
    //
    // donate(amount) 是 SimpleVault 的自定义函数（非 ERC-4626 标准）：
    // 它将调用者的底层资产转入金库，但不铸造任何新份额。
    // 教学上用来模拟"金库产生产品收益"——实际 DeFi 金库可能通过
    // 借贷、质押等方式实现类似增长。
    const donateAmount = ethers.parseEther("500");
    await token.connect(owner).approve(vault.target, donateAmount);

    await expect(vault.connect(owner).donate(donateAmount))
      .to.emit(vault, "Donated")
      .withArgs(owner.address, donateAmount);

    // ---------- 3c. 份额价格上涨 ----------
    // 金库总资产 = 1_000 (Alice 存入) + 500 (捐赠) = 1_500
    // 总份额 = 1_000（未增发）
    // 份额价格 ≈ 1_500 / 1_000 = 1.5（允许 1 wei 取整偏差）
    const price = await vault.sharePrice();
    expectRoughly(price, ethers.parseEther("1.5"));
    console.log(`     捐赠后份额价格: 1 vMTK = ${ethers.formatEther(price)} MTK`);

    // ---------- 3d. Alice 赎回全部份额，获得更多资产 ----------
    const aliceShares = await vault.balanceOf(alice.address);

    // previewRedeem 查看预期赎回数量
    const expectedAssets = await vault.previewRedeem(aliceShares);
    console.log(`     previewRedeem: ${ethers.formatEther(aliceShares)} 份额 → ${ethers.formatEther(expectedAssets)} MTK`);

    // Alice 执行赎回
    await vault.connect(alice).redeem(aliceShares, alice.address, alice.address);

    const finalBalance = await token.balanceOf(alice.address);
    // Alice 原有 5_000，存入 1_000（余 4_000），赎回 = expectedAssets
    // 最终 = 4_000 + expectedAssets
    expect(finalBalance).to.equal(
      ethers.parseEther("4000") + expectedAssets,
    );
    expect(await vault.balanceOf(alice.address)).to.equal(0n);

    console.log(
      `  ✅ Alice 存入 1_000 MTK，赎回 ${ethers.formatEther(expectedAssets)} MTK（净收益 ${ethers.formatEther(expectedAssets - aliceDeposit)} MTK）`,
    );
  });

  // ────────────────────────────────────────────────────────
  // 4. withdraw（指定资产）vs redeem（指定份额）
  // ────────────────────────────────────────────────────────

  it("4. withdraw（指定资产数量）vs redeem（指定份额数量）", async function () {
    const { token, vault, alice } = await networkHelpers.loadFixture(
      deployVaultFixture,
    );

    // Alice 存入 2_000 MTK
    const depositAmount = ethers.parseEther("2000");
    await token.connect(alice).approve(vault.target, depositAmount);
    await vault.connect(alice).deposit(depositAmount, alice.address);

    /**
     * withdraw vs redeem 语义区别：
     *
     * redeem(shares, receiver, owner):
     *   用户"想销毁多少份额" → 合约计算能取出多少资产
     *   类似"卖股换钱"：手上有 100 股，全部卖掉
     *
     * withdraw(assets, receiver, owner):
     *   用户"想取出多少资产" → 合约计算需要销毁多少份额
     *   类似"取款指定金额"：我需要 500 元，从存款中扣除
     */

    // --- withdraw 示例：Alice 想要取出 500 MTK ---
    const withdrawAmount = ethers.parseEther("500");

    const sharesToBurn = await vault.previewWithdraw(withdrawAmount);
    expect(sharesToBurn).to.equal(withdrawAmount);
    await vault.connect(alice).withdraw(withdrawAmount, alice.address, alice.address);
    expect(await vault.balanceOf(alice.address)).to.equal(
      ethers.parseEther("1500"),
    );

    // --- redeem 示例：Alice 销毁 600 份额 ---
    const redeemShares = ethers.parseEther("600");

    const assetsToReceive = await vault.previewRedeem(redeemShares);
    expect(assetsToReceive).to.equal(redeemShares);
    await vault.connect(alice).redeem(redeemShares, alice.address, alice.address);
    expect(await vault.balanceOf(alice.address)).to.equal(
      ethers.parseEther("900"),
    );

    // Alice 最终 MTK 余额：
    // 原有 5_000，存入 2_000（余 3_000），提取 500，赎回 600
    expect(await token.balanceOf(alice.address)).to.equal(
      ethers.parseEther("4100"),
    );

    console.log(`  ✅ withdraw(${ethers.formatEther(withdrawAmount)}) 销毁 ${ethers.formatEther(sharesToBurn)} 份额`);
    console.log(`  ✅ redeem(${ethers.formatEther(redeemShares)}) 赎回 ${ethers.formatEther(assetsToReceive)} MTK`);
  });

  // ────────────────────────────────────────────────────────
  // 5. mint —— 指定份额数量来铸造
  // ────────────────────────────────────────────────────────

  it("5. mint 指定份额数，deposit 指定资产数", async function () {
    const { token, vault, alice } = await networkHelpers.loadFixture(
      deployVaultFixture,
    );

    // mint(shares, receiver) vs deposit(assets, receiver)：
    //
    //   deposit: "我有 500 MTK，全部存入" → 算出获得多少份额
    //   mint:    "我想要 800 vMTK 份额"  → 算出需要支付多少资产
    //
    // 在金库无收益时两者等价（1:1），但语义不同。

    await token.connect(alice).approve(vault.target, ethers.parseEther("5000"));

    // --- mint 800 份额 ---
    const targetShares = ethers.parseEther("800");
    const assetsNeeded = await vault
      .connect(alice)
      .mint.staticCall(targetShares, alice.address);
    expect(assetsNeeded).to.equal(targetShares);

    await vault.connect(alice).mint(targetShares, alice.address);
    expect(await vault.balanceOf(alice.address)).to.equal(targetShares);
    expect(await token.balanceOf(alice.address)).to.equal(
      ethers.parseEther("4200"), // 5_000 - 800
    );

    // --- deposit 500 资产 ---
    const depositAssets = ethers.parseEther("500");
    const sharesFromDeposit = await vault
      .connect(alice)
      .deposit.staticCall(depositAssets, alice.address);
    expect(sharesFromDeposit).to.equal(depositAssets);

    await vault.connect(alice).deposit(depositAssets, alice.address);
    expect(await vault.balanceOf(alice.address)).to.equal(
      ethers.parseEther("1300"), // 800 + 500
    );

    console.log(`  ✅ mint(${ethers.formatEther(targetShares)}) 需要支付 ${ethers.formatEther(assetsNeeded)} MTK`);
    console.log(`  ✅ deposit(${ethers.formatEther(depositAssets)}) 获得 ${ethers.formatEther(sharesFromDeposit)} vMTK`);
  });

  // ────────────────────────────────────────────────────────
  // 6. 份额代币可转账（标准 ERC-20 特性）
  // ────────────────────────────────────────────────────────

  it("6. 份额代币（vMTK）是标准 ERC-20，可在用户间转账", async function () {
    const { token, vault, alice, bob } = await networkHelpers.loadFixture(
      deployVaultFixture,
    );

    // Alice 存入 2_000 MTK
    await token.connect(alice).approve(vault.target, ethers.parseEther("2000"));
    await vault.connect(alice).deposit(ethers.parseEther("2000"), alice.address);

    // Alice 转 500 vMTK 给 Bob
    const transferAmount = ethers.parseEther("500");
    await vault.connect(alice).transfer(bob.address, transferAmount);

    expect(await vault.balanceOf(alice.address)).to.equal(
      ethers.parseEther("1500"),
    );
    expect(await vault.balanceOf(bob.address)).to.equal(transferAmount);

    // Bob 用他的份额赎回底层资产
    // redeem(shares, receiver, owner)：owner 是份额持有者
    await vault.connect(bob).redeem(transferAmount, bob.address, bob.address);

    expect(await vault.balanceOf(bob.address)).to.equal(0n);
    // Bob 原有 3_000 MTK（来自 fixture），赎回获得 500 MTK
    expect(await token.balanceOf(bob.address)).to.equal(
      ethers.parseEther("3500"), // 3_000 + 500
    );

    console.log(`  ✅ Alice 转 ${ethers.formatEther(transferAmount)} vMTK 给 Bob`);
    console.log(`  ✅ Bob 赎回份额获得 ${ethers.formatEther(transferAmount)} MTK`);
    console.log(`     Bob 的 MTK 余额: ${ethers.formatEther(await token.balanceOf(bob.address))}`);
  });

  // ────────────────────────────────────────────────────────
  // 7. 多用户共享金库，按份额比例分配收益
  // ────────────────────────────────────────────────────────

  it("7. 多用户存入金库，按份额公平分配收益", async function () {
    const { token, vault, owner, alice, bob } =
      await networkHelpers.loadFixture(deployVaultFixture);

    // Alice 存入 1_000 MTK（25% 份额）
    await token.connect(alice).approve(vault.target, ethers.parseEther("1000"));
    await vault.connect(alice).deposit(ethers.parseEther("1000"), alice.address);

    // Bob 存入 3_000 MTK（75% 份额）
    await token.connect(bob).approve(vault.target, ethers.parseEther("3000"));
    await vault.connect(bob).deposit(ethers.parseEther("3000"), bob.address);

    // 总份额 = 4_000，总资产 = 4_000，份额占比：Alice 25%，Bob 75%
    expect(await vault.totalSupply()).to.equal(ethers.parseEther("4000"));
    expect(await vault.totalAssets()).to.equal(ethers.parseEther("4000"));

    // Owner 捐赠 1_200 MTK 作为金库收益
    await token.connect(owner).approve(vault.target, ethers.parseEther("1200"));
    await vault.connect(owner).donate(ethers.parseEther("1200"));

    // 总资产 = 5_200，总份额 = 4_000
    // 份额价格 ≈ 5_200 / 4_000 = 1.3
    expectRoughly(await vault.sharePrice(), ethers.parseEther("1.3"));

    // --- preview Alice 的预期赎回值 ---
    const aliceShares = ethers.parseEther("1000");
    const bobShares = ethers.parseEther("3000");
    const aliceExpected = await vault.previewRedeem(aliceShares);

    // Alice 赎回全部 1_000 份额
    // 注意：Alice 的赎回会改变金库状态（减少 totalShares 和 totalAssets）
    await vault.connect(alice).redeem(aliceShares, alice.address, alice.address);
    // Alice 原有 5_000，存入 1_000（余 4_000），赎回 aliceExpected
    expect(await token.balanceOf(alice.address)).to.equal(
      ethers.parseEther("4000") + aliceExpected,
    );

    // --- Alice 赎回后金库状态已变，preview Bob 的预期值 ---
    const bobExpected = await vault.previewRedeem(bobShares);

    // Bob 赎回全部 3_000 份额
    await vault.connect(bob).redeem(bobShares, bob.address, bob.address);
    // Bob 原有 3_000，全部存入（余 0），赎回 bobExpected
    expect(await token.balanceOf(bob.address)).to.equal(bobExpected);

    // 按 25% / 75% 份额比例分配 1_200 捐赠收益
    const aliceProfit = aliceExpected - ethers.parseEther("1000");
    const bobProfit = bobExpected - ethers.parseEther("3000");
    const totalProfit = aliceProfit + bobProfit;

    console.log(`  ✅ 按份额比例分配收益:`);
    console.log(`     Alice (25%): 赎回 ${ethers.formatEther(aliceExpected)} MTK，收益 ${ethers.formatEther(aliceProfit)} MTK`);
    console.log(`     Bob   (75%): 赎回 ${ethers.formatEther(bobExpected)} MTK，收益 ${ethers.formatEther(bobProfit)} MTK`);
    console.log(`     总收益分配: ${ethers.formatEther(totalProfit)} / 1_200 MTK`);

    // 由于整数取整，总收益可能比 1_200 少 1-2 wei
    expectRoughly(totalProfit, ethers.parseEther("1200"));
  });
});
