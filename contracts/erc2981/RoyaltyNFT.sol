// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RoyaltyNFT
 * @dev 教学演示 ERC-2981。
 *   - 合约部署时设置全局默认版税 5%（适用于所有未单独设置的 token）
 *   - owner 可以为某个 token 单独设置更高的版税（例如特殊稀有款）
 */
contract RoyaltyNFT is ERC721, ERC2981, Ownable {
    uint256 private _nextTokenId;

    // 事件：记录版税设置（方便教学观察）
    event TokenRoyaltySet(uint256 indexed tokenId, address receiver, uint96 feeNumerator);

    constructor() ERC721("RoyaltyNFT", "RNFT") Ownable(msg.sender) {
        // 默认版税：5%（500/10000），接收人为合约部署者
        _setDefaultRoyalty(msg.sender, 500);
    }

    /**
     * @dev 只有 owner 能铸造
     */
    function mint(address to) public onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    /**
     * @dev 为核心展品单独设置高版税（例如 10% = 1000/10000）
     * 调用后，该 token 不再受默认版税影响，完全使用这个新值。
     */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) public onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
        emit TokenRoyaltySet(tokenId, receiver, feeNumerator);
    }

    /**
     * @dev 重写 supportsInterface，否则无法编译
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}