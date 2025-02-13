// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC721Base.sol";

import { TokenStore, ERC1155Receiver, IERC1155Receiver } from "../extension/TokenStore.sol";
import { Multicall } from "../extension/Multicall.sol";
import "../extension/SoulboundERC721A.sol";

/**
 *      BASE:      ERC721Base
 *      EXTENSION: TokenStore, SoulboundERC721A
 *
 *  The `ERC721Multiwrap` contract uses the `ERC721Base` contract, along with the `TokenStore` and
 *   `SoulboundERC721A` extension.
 *
 *  The `ERC721Multiwrap` contract lets you wrap arbitrary ERC20, ERC721 and ERC1155 tokens you own
 *  into a single wrapped token / NFT.
 *
 *  The `SoulboundERC721A` extension lets you make your NFTs 'soulbound' i.e. non-transferrable.
 *
 */

contract ERC721Multiwrap is Multicall, TokenStore, SoulboundERC721A, ERC721Base {
    /*//////////////////////////////////////////////////////////////
                    Permission control roles
    //////////////////////////////////////////////////////////////*/

    /// @dev Only MINTER_ROLE holders can wrap tokens, when wrapping is restricted.
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @dev Only UNWRAP_ROLE holders can unwrap tokens, when unwrapping is restricted.
    bytes32 private constant UNWRAP_ROLE = keccak256("UNWRAP_ROLE");
    /// @dev Only assets with ASSET_ROLE can be wrapped, when wrapping is restricted to particular assets.
    bytes32 private constant ASSET_ROLE = keccak256("ASSET_ROLE");

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted when tokens are wrapped.
    event TokensWrapped(
        address indexed wrapper,
        address indexed recipientOfWrappedToken,
        uint256 indexed tokenIdOfWrappedToken,
        Token[] wrappedContents
    );

    /// @dev Emitted when tokens are unwrapped.
    event TokensUnwrapped(
        address indexed unwrapper,
        address indexed recipientOfWrappedContents,
        uint256 indexed tokenIdOfWrappedToken
    );

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the caller holds `role`, when restrictions for `role` are switched on.
    modifier onlyRoleWithSwitch(bytes32 role) {
        _checkRoleWithSwitch(role, msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _nativeTokenWrapper
    ) ERC721Base(_name, _symbol, _royaltyRecipient, _royaltyBps) TokenStore(_nativeTokenWrapper) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
        _setupRole(TRANSFER_ROLE, msg.sender);

        _setupRole(ASSET_ROLE, address(0));
        _setupRole(UNWRAP_ROLE, address(0));

        restrictTransfers(false);
    }

    /*///////////////////////////////////////////////////////////////
                        Public gette functions
    //////////////////////////////////////////////////////////////*/

    /// @dev See ERC-165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155Receiver, ERC721Base)
        returns (bool)
    {
        return
            super.supportsInterface(interfaceId) ||
            ERC721Base.supportsInterface(interfaceId) ||
            interfaceId == type(IERC1155Receiver).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                        Overriden ERC721 logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the URI for a given tokenId.
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        return getUriOfBundle(_tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                    Wrapping / Unwrapping logic
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice Wrap multiple ERC1155, ERC721, ERC20 tokens into a single wrapped NFT.
     *
     *  @param _tokensToWrap    The tokens to wrap.
     *  @param _uriForWrappedToken The metadata URI for the wrapped NFT.
     *  @param _recipient          The recipient of the wrapped NFT.
     *
     *  @return tokenId The tokenId of the wrapped NFT minted.
     */
    function wrap(
        Token[] calldata _tokensToWrap,
        string calldata _uriForWrappedToken,
        address _recipient
    ) public payable virtual onlyRoleWithSwitch(MINTER_ROLE) returns (uint256 tokenId) {
        if (!hasRole(ASSET_ROLE, address(0))) {
            for (uint256 i = 0; i < _tokensToWrap.length; i += 1) {
                _checkRole(ASSET_ROLE, _tokensToWrap[i].assetContract);
            }
        }

        tokenId = nextTokenIdToMint();

        _storeTokens(msg.sender, _tokensToWrap, _uriForWrappedToken, tokenId);

        _safeMint(_recipient, 1);

        emit TokensWrapped(msg.sender, _recipient, tokenId, _tokensToWrap);
    }

    /**
     *  @notice Unwrap a wrapped NFT to retrieve underlying ERC1155, ERC721, ERC20 tokens.
     *
     *  @param _tokenId   The token Id of the wrapped NFT to unwrap.
     *  @param _recipient The recipient of the underlying ERC1155, ERC721, ERC20 tokens of the wrapped NFT.
     */
    function unwrap(uint256 _tokenId, address _recipient) public virtual onlyRoleWithSwitch(UNWRAP_ROLE) {
        require(_tokenId < nextTokenIdToMint(), "wrapped NFT DNE.");
        require(isApprovedOrOwner(msg.sender, _tokenId), "caller not approved for unwrapping.");

        _burn(_tokenId);
        _releaseTokens(_recipient, _tokenId);

        emit TokensUnwrapped(msg.sender, _recipient, _tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev See {ERC721-_beforeTokenTransfer}.
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override(ERC721A, SoulboundERC721A) {
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
        SoulboundERC721A._beforeTokenTransfers(from, to, startTokenId, quantity);
    }

    /// @dev Returns whether transfers can be restricted in a given execution context.
    function _canRestrictTransfers() internal virtual override returns (bool) {
        return msg.sender == owner();
    }

    /*///////////////////////////////////////////////////////////////
                        Miscellaneous
    //////////////////////////////////////////////////////////////*/

    function mintTo(address, string memory) public virtual override {
        revert("Not implemented for Multiwrap");
    }

    function batchMintTo(
        address,
        uint256,
        string memory,
        bytes memory
    ) public virtual override {
        revert("Not implemented for Multiwrap");
    }
}
