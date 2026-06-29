pragma solidity 0.8.35;

import {ERC721} from "@openzeppelin/contracts/token/erc721/ERC721.sol";

contract ProviderNFT is ERC721 {
    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {
        _mint(msg.sender, 0);
    }

    function _baseURI() internal pure override returns (string memory) {
        // just for tests. Rest does not matter
        return "https://images.freeimages.com/variants/p3ueQgCiuGkQ7VYrTbDWQHWn/f4a36f6589a0e50e702740b15352bc00e4bfaf6f58bd4db850e167794d05993d?fmt=avif&h=350";
    }
}
