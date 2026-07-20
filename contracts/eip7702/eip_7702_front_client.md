## 页面申请EIP-7702授权示例代码

网页js代码：

```javascript
// 1. 准备授权参数
const authorization = {
  chain_id: await provider.getNetwork().then(n => n.chainId),
  address: eip7702DemoContractAddress,  // 要实现合约地址
  nonce: await provider.getTransactionCount(userEOA),
}

// 2. 请求用户签名（钱包弹出确认框）
// 不同钱包实现不同，核心是让用户签署这个授权
const signature = await signer.signMessage(
  encodeAuthorization(authorization)  // 按 EIP-7702 格式编码
);

// 3. 构造 type 0x04 交易提交
const tx = {
  type: 4,                                    // EIP-7702 交易类型
  authorizationList: [{                        // 授权列表
    chain_id: authorization.chain_id,
    address: authorization.address,
    nonce: authorization.nonce,
    ...signature,                              // v, r, s
  }],
  to: null,          // 可选：后续要调用的目标
  data: '0x...',     // 可选：后续要执行的 calldata
};
await signer.sendTransaction(tx);
```

## EOA钱包弹窗的交互

实际用户体验很简单——钱包会弹出类似这样的确认框：

> **授权账户委托**
> 
> 您正在授权将您的账户委托给合约 **EIP7702Demo**
> 
> 委托后，此合约将能以您的身份执行操作
> 
> **[拒绝] [确认]**

你点 **"确认"**（签名），这笔 type 0x04 交易就提交了。***EVM 处理完，你的 EOA code 就被写入了 `0xef0100 + EIP7702Demo地址`。***


