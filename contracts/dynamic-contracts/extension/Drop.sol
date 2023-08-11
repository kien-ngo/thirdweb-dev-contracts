// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// @author thirdweb

import "../../extension/interface/IDrop.sol";
import "../../lib/MerkleProof.sol";

library DropStorage {
    bytes32 public constant DROP_STORAGE_POSITION = keccak256("drop.storage");

    struct Data {
        /// @dev The active conditions for claiming tokens.
        IDrop.ClaimConditionList claimCondition;
    }

    function dropStorage() internal pure returns (Data storage dropData) {
        bytes32 position = DROP_STORAGE_POSITION;
        assembly {
            dropData.slot := position
        }
    }
}

abstract contract Drop is IDrop {
    function claimCondition() public view returns (uint256, uint256) {
        DropStorage.Data storage data = DropStorage.dropStorage();
        return (data.claimCondition.currentStartId, data.claimCondition.count);
    }

    /*///////////////////////////////////////////////////////////////
                            Drop logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Lets an account claim tokens.
    function claim(
        address _receiver,
        uint256 _quantity,
        address _currency,
        uint256 _pricePerToken,
        AllowlistProof calldata _allowlistProof,
        bytes memory _data
    ) public payable virtual override {
        _beforeClaim(_receiver, _quantity, _currency, _pricePerToken, _allowlistProof, _data);

        uint256 activeConditionId = getActiveClaimConditionId();

        verifyClaim(activeConditionId, _dropMsgSender(), _quantity, _currency, _pricePerToken, _allowlistProof);

        // Update contract state.
        DropStorage.Data storage data = DropStorage.dropStorage();
        data.claimCondition.conditions[activeConditionId].supplyClaimed += _quantity;
        data.claimCondition.supplyClaimedByWallet[activeConditionId][_dropMsgSender()] += _quantity;

        // If there's a price, collect price.
        _collectPriceOnClaim(address(0), _quantity, _currency, _pricePerToken);

        // Mint the relevant tokens to claimer.
        uint256 startTokenId = _transferTokensOnClaim(_receiver, _quantity);

        emit TokensClaimed(activeConditionId, _dropMsgSender(), _receiver, startTokenId, _quantity);

        _afterClaim(_receiver, _quantity, _currency, _pricePerToken, _allowlistProof, _data);
    }

    /// @dev Lets a contract admin set claim conditions.
    function setClaimConditions(ClaimCondition[] calldata _conditions, bool _resetClaimEligibility)
        external
        virtual
        override
    {
        if (!_canSetClaimConditions()) {
            revert("Not authorized");
        }

        DropStorage.Data storage data = DropStorage.dropStorage();
        uint256 existingStartIndex = data.claimCondition.currentStartId;
        uint256 existingPhaseCount = data.claimCondition.count;

        /**
         *  The mapping `supplyClaimedByWallet` uses a claim condition's UID as a key.
         *
         *  If `_resetClaimEligibility == true`, we assign completely new UIDs to the claim
         *  conditions in `_conditions`, effectively resetting the restrictions on claims expressed
         *  by `supplyClaimedByWallet`.
         */
        uint256 newStartIndex = existingStartIndex;
        if (_resetClaimEligibility) {
            newStartIndex = existingStartIndex + existingPhaseCount;
        }

        data.claimCondition.count = _conditions.length;
        data.claimCondition.currentStartId = newStartIndex;

        uint256 lastConditionStartTimestamp;
        for (uint256 i; i < _conditions.length; ) {
            require(i == 0 || lastConditionStartTimestamp < _conditions[i].startTimestamp, "ST");

            uint256 supplyClaimedAlready = data.claimCondition.conditions[newStartIndex + i].supplyClaimed;
            if (supplyClaimedAlready > _conditions[i].maxClaimableSupply) {
                revert("max supply claimed");
            }

            data.claimCondition.conditions[newStartIndex + i] = _conditions[i];
            data.claimCondition.conditions[newStartIndex + i].supplyClaimed = supplyClaimedAlready;

            lastConditionStartTimestamp = _conditions[i].startTimestamp;
            unchecked { ++i; }
        }

        /**
         *  Gas refunds (as much as possible)
         *
         *  If `_resetClaimEligibility == true`, we assign completely new UIDs to the claim
         *  conditions in `_conditions`. So, we delete claim conditions with UID < `newStartIndex`.
         *
         *  If `_resetClaimEligibility == false`, and there are more existing claim conditions
         *  than in `_conditions`, we delete the existing claim conditions that don't get replaced
         *  by the conditions in `_conditions`.
         */
        if (_resetClaimEligibility) {
            for (uint256 i = existingStartIndex; i < newStartIndex; ) {
                delete data.claimCondition.conditions[i];
                unchecked { ++i; }
            }
        } else {
            if (existingPhaseCount > _conditions.length) {
                for (uint256 i = _conditions.length; i < existingPhaseCount; ) {
                    delete data.claimCondition.conditions[newStartIndex + i];
                    unchecked { ++i; }
                }
            }
        }

        emit ClaimConditionsUpdated(_conditions, _resetClaimEligibility);
    }

    /// @dev Checks a request to claim NFTs against the active claim condition's criteria.
    function verifyClaim(
        uint256 _conditionId,
        address _claimer,
        uint256 _quantity,
        address _currency,
        uint256 _pricePerToken,
        AllowlistProof calldata _allowlistProof
    ) public view returns (bool isOverride) {
        DropStorage.Data storage data = DropStorage.dropStorage();
        ClaimCondition memory currentClaimPhase = data.claimCondition.conditions[_conditionId];
        uint256 claimLimit = currentClaimPhase.quantityLimitPerWallet;
        uint256 claimPrice = currentClaimPhase.pricePerToken;
        address claimCurrency = currentClaimPhase.currency;

        if (currentClaimPhase.merkleRoot != bytes32(0)) {
            (isOverride, ) = MerkleProof.verify(
                _allowlistProof.proof,
                currentClaimPhase.merkleRoot,
                keccak256(
                    abi.encodePacked(
                        _claimer,
                        _allowlistProof.quantityLimitPerWallet,
                        _allowlistProof.pricePerToken,
                        _allowlistProof.currency
                    )
                )
            );
        }

        if (isOverride) {
            claimLimit = _allowlistProof.quantityLimitPerWallet != 0
                ? _allowlistProof.quantityLimitPerWallet
                : claimLimit;
            claimPrice = _allowlistProof.pricePerToken != type(uint256).max
                ? _allowlistProof.pricePerToken
                : claimPrice;
            claimCurrency = _allowlistProof.pricePerToken != type(uint256).max && _allowlistProof.currency != address(0)
                ? _allowlistProof.currency
                : claimCurrency;
        }

        uint256 supplyClaimedByWallet = data.claimCondition.supplyClaimedByWallet[_conditionId][_claimer];

        if (_currency != claimCurrency || _pricePerToken != claimPrice) {
            revert("!PriceOrCurrency");
        }

        if (_quantity == 0 || (_quantity + supplyClaimedByWallet > claimLimit)) {
            revert("!Qty");
        }
        if (currentClaimPhase.supplyClaimed + _quantity > currentClaimPhase.maxClaimableSupply) {
            revert("!MaxSupply");
        }

        if (currentClaimPhase.startTimestamp > block.timestamp) {
            revert("cant claim yet");
        }
    }

    /// @dev At any given moment, returns the uid for the active claim condition.
    function getActiveClaimConditionId() public view returns (uint256) {
        DropStorage.Data storage data = DropStorage.dropStorage();
        for (
            uint256 i = data.claimCondition.currentStartId + data.claimCondition.count;
            i > data.claimCondition.currentStartId;
        ) {
            if (block.timestamp >= data.claimCondition.conditions[i - 1].startTimestamp) {
                return i - 1;
            }
            unchecked { --i; }
        }

        revert("!CONDITION.");
    }

    /// @dev Returns the claim condition at the given uid.
    function getClaimConditionById(uint256 _conditionId) external view returns (ClaimCondition memory condition) {
        DropStorage.Data storage data = DropStorage.dropStorage();
        condition = data.claimCondition.conditions[_conditionId];
    }

    /// @dev Returns the supply claimed by claimer for a given conditionId.
    function getSupplyClaimedByWallet(uint256 _conditionId, address _claimer)
        public
        view
        returns (uint256 supplyClaimedByWallet)
    {
        DropStorage.Data storage data = DropStorage.dropStorage();
        supplyClaimedByWallet = data.claimCondition.supplyClaimedByWallet[_conditionId][_claimer];
    }

    /*////////////////////////////////////////////////////////////////////
        Optional hooks that can be implemented in the derived contract
    ///////////////////////////////////////////////////////////////////*/

    /// @dev Exposes the ability to override the msg sender.
    function _dropMsgSender() internal virtual returns (address) {
        return msg.sender;
    }

    /// @dev Runs before every `claim` function call.
    function _beforeClaim(
        address _receiver,
        uint256 _quantity,
        address _currency,
        uint256 _pricePerToken,
        AllowlistProof calldata _allowlistProof,
        bytes memory _data
    ) internal virtual {}

    /// @dev Runs after every `claim` function call.
    function _afterClaim(
        address _receiver,
        uint256 _quantity,
        address _currency,
        uint256 _pricePerToken,
        AllowlistProof calldata _allowlistProof,
        bytes memory _data
    ) internal virtual {}

    /*///////////////////////////////////////////////////////////////
        Virtual functions: to be implemented in derived contract
    //////////////////////////////////////////////////////////////*/

    /// @dev Collects and distributes the primary sale value of NFTs being claimed.
    function _collectPriceOnClaim(
        address _primarySaleRecipient,
        uint256 _quantityToClaim,
        address _currency,
        uint256 _pricePerToken
    ) internal virtual;

    /// @dev Transfers the NFTs being claimed.
    function _transferTokensOnClaim(address _to, uint256 _quantityBeingClaimed)
        internal
        virtual
        returns (uint256 startTokenId);

    /// @dev Determine what wallet can update claim conditions
    function _canSetClaimConditions() internal view virtual returns (bool);
}
