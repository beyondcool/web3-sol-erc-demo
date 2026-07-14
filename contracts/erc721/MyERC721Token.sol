// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// 导入 ERC721、ERC721URIStorage 和 Ownable
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MyERC721Token
 * @dev 一个简单的 ERC721 NFT 教学示例（修正版）
 */
contract MyERC721Token is ERC721, ERC721URIStorage, Ownable {

    uint256 private _nextTokenId;

    constructor() ERC721("MyERC721Token", "MNFT") Ownable(msg.sender) {
        _nextTokenId = 1;
    }

    /**
     * @dev 铸造一个新的 NFT，并设置其元数据 URI
     * @param to 接收 NFT 的地址
     * @param uri 该 NFT 的元数据链接（如 IPFS 链接）
     * @return 新铸造的 tokenId
     */
    function mint(address to, string memory uri) public onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId;
        _nextTokenId++;
        _mint(to, tokenId);
        _setTokenURI(tokenId, uri); // ✅ 来自 ERC721URIStorage
        return tokenId;
    }

    /**
     * @dev 销毁一个 NFT
     * @param tokenId 要销毁的 tokenId
     */
    function burn(uint256 tokenId) public onlyOwner {
        _burn(tokenId);
    }

    /**
     * @dev 查询已铸造的 NFT 总数
     */
    function totalSupply() public view returns (uint256) {
        return _nextTokenId - 1;
    }

    // ⚠️ 以下两个函数必须重写，因为 ERC721URIStorage 改变了它们的实现

    /**
     * @dev 重写 tokenURI，多重继承时需要明确指定 override 来源
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev 重写 supportsInterface，多重继承时需要明确指定 override 来源
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev 可选：重写 _baseURI，为所有 tokenId 提供统一的基础路径
     * 实际的 tokenURI = _baseURI() + tokenId.toString()（如果没有单独设置 URI 的话）
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://example.com/metadata/";
    }
}