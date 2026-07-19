# 前端页面的代码逻辑：

``` typescript
import { ethers } from 'ethers';

// 1. 获取签名者
const signer = provider.getSigner();

// 2. 构造 EIP-712 数据
// 只能合约实现了EIP-712，就会有个 eip712Domain() 方法，返回domain中的值。
const domain = {
  name: 'EIP712Demo',
  version: '1',
  chainId: (await provider.getNetwork()).chainId,
  verifyingContract: contractAddress
};

// 这个types往往是开发人员看着智能合约代码，手写出来的：
const types = {
  Note: [
    { name: 'content', type: 'string' },
    { name: 'nonce',   type: 'uint256' }
  ]
};

const value = {
  content: 'Hello, EIP-712!',
  nonce: 1
};

// 3. 用户钱包弹出签名确认窗口
const signature = await signer.signTypedData(domain, types, value);

// signature 是 bytes，需要拆成 v, r, s
const { v, r, s } = ethers.Signature.from(signature);

// 4. 调用合约
await contract.signNote(value, v, r, s);
```
