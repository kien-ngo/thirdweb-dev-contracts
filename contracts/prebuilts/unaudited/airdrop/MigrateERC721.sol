// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/// @author kien-ngo
/// This contract is a simplified version of thirdweb's AirdropERC721 contract
/// where users can only airdrop multiple tokens from ONE collection to ONE recipient
/// Use this for migrating your NFTs to your new wallet

//  ==========  External imports    ==========
import { IERC721 } from "../../../eip/interface/IERC721.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { MulticallUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";

//  ==========  Internal imports    ==========
import { ERC2771ContextUpgradeable, Initializable } from "../../../external-deps/openzeppelin/metatx/ERC2771ContextUpgradeable.sol";

contract MigrateERC721 is Initializable, ReentrancyGuardUpgradeable, ERC2771ContextUpgradeable, MulticallUpgradeable {
    constructor() initializer {}

    /// @dev Initiliazes the contract, like a constructor.
    function initialize(address[] memory _trustedForwarders) external initializer {
        __ERC2771Context_init_unchained(_trustedForwarders);
        __ReentrancyGuard_init();
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
        uint256 i;
        do {
            try IERC721(_tokenAddress).safeTransferFrom(_tokenOwner, _recipient, _tokenIds[i]) {} catch {
                require(
                    (IERC721(_tokenAddress).ownerOf(_tokenIds[i]) == _tokenOwner &&
                        address(this) == IERC721(_tokenAddress).getApproved(_tokenIds[i])) ||
                        IERC721(_tokenAddress).isApprovedForAll(_tokenOwner, address(this)),
                    "Not owner or approved"
                );
            }
            unchecked {
                ++i;
            }
        } while (i < len);
    }

    /*///////////////////////////////////////////////////////////////
                        Miscellaneous
    //////////////////////////////////////////////////////////////*/

    /// @dev See ERC2771
    function _msgSender() internal view virtual override returns (address sender) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /// @dev See ERC2771
    function _msgData() internal view virtual override returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }
}
