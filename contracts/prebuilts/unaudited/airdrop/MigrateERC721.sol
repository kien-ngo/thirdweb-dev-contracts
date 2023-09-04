// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/// @author kien-ngo
/// This contract is a simplified version of thirdweb's AirdropERC721 contract
/// where users can only airdrop multiple tokens to ONE recipient
/// Use this for migrating your NFTs to your new wallet

//  ==========  External imports    ==========
import "../../../eip/interface/IERC721.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { MulticallUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";

//  ==========  Internal imports    ==========
import "../../../external-deps/openzeppelin/metatx/ERC2771ContextUpgradeable.sol";

//  ==========  Features    ==========
import "../../../extension/PermissionsEnumerable.sol";
import "../../../extension/ContractMetadata.sol";

contract MigrateERC721 is
    Initializable,
    ContractMetadata,
    PermissionsEnumerable,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable,
    MulticallUpgradeable
{
    /*///////////////////////////////////////////////////////////////
                            State variables
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant MODULE_TYPE = bytes32("MigrateERC721");
    uint256 private constant VERSION = 1;

    /*///////////////////////////////////////////////////////////////
                    Constructor + initializer logic
    //////////////////////////////////////////////////////////////*/

    constructor() initializer {}

    /// @dev Initiliazes the contract, like a constructor.
    function initialize(
        address _defaultAdmin,
        string memory _contractURI,
        address[] memory _trustedForwarders
    ) external initializer {
        __ERC2771Context_init_unchained(_trustedForwarders);

        _setupContractURI(_contractURI);
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        __ReentrancyGuard_init();
    }

    /*///////////////////////////////////////////////////////////////
                        Generic contract logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the type of the contract.
    function contractType() external pure returns (bytes32) {
        return MODULE_TYPE;
    }

    /// @dev Returns the version of the contract.
    function contractVersion() external pure returns (uint8) {
        return uint8(VERSION);
    }

    /*///////////////////////////////////////////////////////////////
                            Airdrop logic
    //////////////////////////////////////////////////////////////*/

    function migrate(
        address _tokenAddress,
        address _tokenOwner,
        address _recipient,
        uint256[] calldata _tokenIds
    ) external nonReentrant {
        uint256 len = _tokenIds.length;
        IERC721 _tokenContract = IERC721(_tokenAddress);
        for (uint256 i; i < len; ) {
            _tokenContract.safeTransferFrom(_tokenOwner, _recipient, _tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                        Miscellaneous
    //////////////////////////////////////////////////////////////*/

    /// @dev Checks whether contract metadata can be set in the given execution context.
    function _canSetContractURI() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @dev See ERC2771
    function _msgSender() internal view virtual override returns (address sender) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /// @dev See ERC2771
    function _msgData() internal view virtual override returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }
}
