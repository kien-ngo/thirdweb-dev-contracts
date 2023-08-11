// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.0 (metatx/ERC2771Context.sol)

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @dev Context variant with ERC2771 support.
 */
abstract contract ERC2771Context is Context {
    mapping(address => bool) private _trustedForwarder;

    constructor(address[] memory trustedForwarder) {
        uint256 length = trustedForwarder.length;
        for (uint256 i; i < length; ) {
            _trustedForwarder[trustedForwarder[i]] = true;
            unchecked { ++i; }
        }
    }

    function isTrustedForwarder(address forwarder) public view virtual returns (bool) {
        return _trustedForwarder[forwarder];
    }

    function _msgSender() internal view virtual override returns (address sender) {
        if (isTrustedForwarder(msg.sender)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return super._msgSender();
        }
    }

    function _msgData() internal view virtual override returns (bytes calldata) {
        if (isTrustedForwarder(msg.sender)) {
            return msg.data[:msg.data.length - 20];
        } else {
            return super._msgData();
        }
    }

    uint256[49] private __gap;
}
