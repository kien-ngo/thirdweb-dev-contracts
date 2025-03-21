// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import "@std/Test.sol";
import "@ds-test/test.sol";
// import "./Console.sol";
import "./Wallet.sol";
import "./ChainlinkVRF.sol";
import "../mocks/WETH9.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockERC721.sol";
import "../mocks/MockERC1155.sol";
import "contracts/infra/forwarder/Forwarder.sol";
import { ForwarderEOAOnly } from "contracts/infra/forwarder/ForwarderEOAOnly.sol";
import "contracts/infra/TWRegistry.sol";
import "contracts/infra/TWFactory.sol";
import { Multiwrap } from "contracts/prebuilts/multiwrap/Multiwrap.sol";
import { Pack } from "contracts/prebuilts/pack/Pack.sol";
import { PackVRFDirect } from "contracts/prebuilts/pack/PackVRFDirect.sol";
import { Split } from "contracts/prebuilts/split/Split.sol";
import { DropERC20 } from "contracts/prebuilts/drop/DropERC20.sol";
import { DropERC721 } from "contracts/prebuilts/drop/DropERC721.sol";
import { DropERC1155 } from "contracts/prebuilts/drop/DropERC1155.sol";
import { TokenERC20 } from "contracts/prebuilts/token/TokenERC20.sol";
import { TokenERC721 } from "contracts/prebuilts/token/TokenERC721.sol";
import { TokenERC1155 } from "contracts/prebuilts/token/TokenERC1155.sol";
import { Marketplace } from "contracts/prebuilts/marketplace-legacy/Marketplace.sol";
import { VoteERC20 } from "contracts/prebuilts/vote/VoteERC20.sol";
import { SignatureDrop } from "contracts/prebuilts/signature-drop/SignatureDrop.sol";
import { ContractPublisher } from "contracts/infra/ContractPublisher.sol";
import { IContractPublisher } from "contracts/infra/interface/IContractPublisher.sol";
import { AirdropERC721 } from "contracts/prebuilts/unaudited/airdrop/AirdropERC721.sol";
import { AirdropERC721Claimable } from "contracts/prebuilts/unaudited/airdrop/AirdropERC721Claimable.sol";
import { AirdropERC20 } from "contracts/prebuilts/unaudited/airdrop/AirdropERC20.sol";
import "contracts/prebuilts/unaudited/airdrop/AirdropERC20Claimable.sol";
import "contracts/prebuilts/unaudited/airdrop/AirdropERC1155.sol";
import "contracts/prebuilts/unaudited/airdrop/AirdropERC1155Claimable.sol";
import { NFTStake } from "contracts/prebuilts/staking/NFTStake.sol";
import { EditionStake } from "contracts/prebuilts/staking/EditionStake.sol";
import { TokenStake } from "contracts/prebuilts/staking/TokenStake.sol";
import { Mock, MockContract } from "../mocks/Mock.sol";
import "../mocks/MockContractPublisher.sol";

abstract contract BaseTest is DSTest, Test {
    string public constant NAME = "NAME";
    string public constant SYMBOL = "SYMBOL";
    string public constant CONTRACT_URI = "CONTRACT_URI";
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    MockERC20 public erc20;
    MockERC20 public erc20Aux;
    MockERC721 public erc721;
    MockERC1155 public erc1155;
    WETH9 public weth;

    address public forwarder;
    address public eoaForwarder;
    address public registry;
    address public factory;
    address public fee;
    address public contractPublisher;
    address public linkToken;
    address public vrfV2Wrapper;

    address public factoryAdmin = address(0x10000);
    address public deployer = address(0x20000);
    address public saleRecipient = address(0x30000);
    address public royaltyRecipient = address(0x30001);
    address public platformFeeRecipient = address(0x30002);
    uint128 public royaltyBps = 500; // 5%
    uint128 public platformFeeBps = 500; // 5%
    uint256 public constant MAX_BPS = 10_000; // 100%

    uint256 public privateKey = 1234;
    address public signer;

    // airdrop-claimable inputs
    uint256[] internal _airdropTokenIdsERC721;
    bytes32 internal _airdropMerkleRootERC721;

    uint256[] internal _airdropTokenIdsERC1155;
    uint256[] internal _airdropWalletClaimCountERC1155;
    uint256[] internal _airdropAmountsERC1155;
    bytes32[] internal _airdropMerkleRootERC1155;

    bytes32 internal _airdropMerkleRootERC20;

    Wallet internal airdropTokenOwner;
    // airdrop-claimable inputs -- over

    mapping(bytes32 => address) public contracts;

    function setUp() public virtual {
        /// setup main factory contracts. registry, fee, factory.
        vm.startPrank(factoryAdmin);

        signer = vm.addr(privateKey);

        erc20 = new MockERC20();
        erc20Aux = new MockERC20();
        erc721 = new MockERC721();
        erc1155 = new MockERC1155();
        weth = new WETH9();
        forwarder = address(new Forwarder());
        eoaForwarder = address(new ForwarderEOAOnly());
        registry = address(new TWRegistry(forwarder));
        factory = address(new TWFactory(forwarder, registry));
        contractPublisher = address(new ContractPublisher(forwarder, new MockContractPublisher()));
        linkToken = address(new Link());
        vrfV2Wrapper = address(new VRFV2Wrapper());
        TWRegistry(registry).grantRole(TWRegistry(registry).OPERATOR_ROLE(), factory);
        TWRegistry(registry).grantRole(TWRegistry(registry).OPERATOR_ROLE(), contractPublisher);

        TWFactory(factory).addImplementation(address(new TokenERC20()));
        TWFactory(factory).addImplementation(address(new TokenERC721()));
        TWFactory(factory).addImplementation(address(new TokenERC1155()));
        TWFactory(factory).addImplementation(address(new DropERC20()));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("DropERC721"), 1)));
        TWFactory(factory).addImplementation(address(new DropERC721()));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("DropERC1155"), 1)));
        TWFactory(factory).addImplementation(address(new DropERC1155()));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("SignatureDrop"), 1)));
        TWFactory(factory).addImplementation(address(new SignatureDrop()));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("Marketplace"), 1)));
        TWFactory(factory).addImplementation(address(new Marketplace(address(weth))));
        TWFactory(factory).addImplementation(address(new Split()));
        TWFactory(factory).addImplementation(address(new Multiwrap(address(weth))));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("Pack"), 1)));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("AirdropERC721"), 1)));
        TWFactory(factory).addImplementation(address(new AirdropERC721()));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("AirdropERC20"), 1)));
        TWFactory(factory).addImplementation(address(new AirdropERC20()));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("AirdropERC1155"), 1)));
        TWFactory(factory).addImplementation(address(new AirdropERC1155()));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("AirdropERC721Claimable"), 1)));
        TWFactory(factory).addImplementation(address(new AirdropERC721Claimable()));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("AirdropERC20Claimable"), 1)));
        TWFactory(factory).addImplementation(address(new AirdropERC20Claimable()));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("AirdropERC1155Claimable"), 1)));
        TWFactory(factory).addImplementation(address(new AirdropERC1155Claimable()));
        TWFactory(factory).addImplementation(
            address(new PackVRFDirect(address(weth), eoaForwarder, linkToken, vrfV2Wrapper))
        );
        TWFactory(factory).addImplementation(address(new Pack(address(weth), eoaForwarder)));
        TWFactory(factory).addImplementation(address(new VoteERC20()));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("NFTStake"), 1)));
        TWFactory(factory).addImplementation(address(new NFTStake(address(weth))));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("EditionStake"), 1)));
        TWFactory(factory).addImplementation(address(new EditionStake(address(weth))));
        TWFactory(factory).addImplementation(address(new MockContract(bytes32("TokenStake"), 1)));
        TWFactory(factory).addImplementation(address(new TokenStake(address(weth))));
        vm.stopPrank();

        // setup airdrop logic
        setupAirdropClaimable();

        /// deploy proxy for tests
        deployContractProxy(
            "TokenERC20",
            abi.encodeCall(
                TokenERC20.initialize,
                (signer, NAME, SYMBOL, CONTRACT_URI, forwarders(), saleRecipient, platformFeeRecipient, platformFeeBps)
            )
        );
        deployContractProxy(
            "TokenERC721",
            abi.encodeCall(
                TokenERC721.initialize,
                (
                    signer,
                    NAME,
                    SYMBOL,
                    CONTRACT_URI,
                    forwarders(),
                    saleRecipient,
                    royaltyRecipient,
                    royaltyBps,
                    platformFeeBps,
                    platformFeeRecipient
                )
            )
        );
        deployContractProxy(
            "TokenERC1155",
            abi.encodeCall(
                TokenERC1155.initialize,
                (
                    signer,
                    NAME,
                    SYMBOL,
                    CONTRACT_URI,
                    forwarders(),
                    saleRecipient,
                    royaltyRecipient,
                    royaltyBps,
                    platformFeeBps,
                    platformFeeRecipient
                )
            )
        );
        deployContractProxy(
            "DropERC20",
            abi.encodeCall(
                DropERC20.initialize,
                (
                    deployer,
                    NAME,
                    SYMBOL,
                    CONTRACT_URI,
                    forwarders(),
                    saleRecipient,
                    platformFeeRecipient,
                    platformFeeBps
                )
            )
        );
        deployContractProxy(
            "DropERC721",
            abi.encodeCall(
                DropERC721.initialize,
                (
                    deployer,
                    NAME,
                    SYMBOL,
                    CONTRACT_URI,
                    forwarders(),
                    saleRecipient,
                    royaltyRecipient,
                    royaltyBps,
                    platformFeeBps,
                    platformFeeRecipient
                )
            )
        );
        deployContractProxy(
            "DropERC1155",
            abi.encodeCall(
                DropERC1155.initialize,
                (
                    deployer,
                    NAME,
                    SYMBOL,
                    CONTRACT_URI,
                    forwarders(),
                    saleRecipient,
                    royaltyRecipient,
                    royaltyBps,
                    platformFeeBps,
                    platformFeeRecipient
                )
            )
        );
        deployContractProxy(
            "SignatureDrop",
            abi.encodeCall(
                SignatureDrop.initialize,
                (
                    signer,
                    NAME,
                    SYMBOL,
                    CONTRACT_URI,
                    forwarders(),
                    saleRecipient,
                    royaltyRecipient,
                    royaltyBps,
                    platformFeeBps,
                    platformFeeRecipient
                )
            )
        );
        deployContractProxy(
            "Marketplace",
            abi.encodeCall(
                Marketplace.initialize,
                (deployer, CONTRACT_URI, forwarders(), platformFeeRecipient, platformFeeBps)
            )
        );
        deployContractProxy(
            "Multiwrap",
            abi.encodeCall(
                Multiwrap.initialize,
                (deployer, NAME, SYMBOL, CONTRACT_URI, forwarders(), royaltyRecipient, royaltyBps)
            )
        );
        deployContractProxy(
            "Pack",
            abi.encodeCall(
                Pack.initialize,
                (deployer, NAME, SYMBOL, CONTRACT_URI, forwarders(), royaltyRecipient, royaltyBps)
            )
        );

        deployContractProxy(
            "PackVRFDirect",
            abi.encodeCall(
                PackVRFDirect.initialize,
                (deployer, NAME, SYMBOL, CONTRACT_URI, forwarders(), royaltyRecipient, royaltyBps)
            )
        );

        deployContractProxy(
            "AirdropERC721",
            abi.encodeCall(AirdropERC721.initialize, (deployer, CONTRACT_URI, forwarders()))
        );
        deployContractProxy(
            "AirdropERC20",
            abi.encodeCall(AirdropERC20.initialize, (deployer, CONTRACT_URI, forwarders()))
        );
        deployContractProxy(
            "AirdropERC1155",
            abi.encodeCall(AirdropERC1155.initialize, (deployer, CONTRACT_URI, forwarders()))
        );
        deployContractProxy(
            "AirdropERC721Claimable",
            abi.encodeCall(
                AirdropERC721Claimable.initialize,
                (
                    deployer,
                    forwarders(),
                    address(airdropTokenOwner),
                    address(erc721),
                    _airdropTokenIdsERC721,
                    1000,
                    1,
                    _airdropMerkleRootERC721
                )
            )
        );
        deployContractProxy(
            "AirdropERC1155Claimable",
            abi.encodeCall(
                AirdropERC1155Claimable.initialize,
                (
                    deployer,
                    forwarders(),
                    address(airdropTokenOwner),
                    address(erc1155),
                    _airdropTokenIdsERC1155,
                    _airdropAmountsERC1155,
                    1000,
                    _airdropWalletClaimCountERC1155,
                    _airdropMerkleRootERC1155
                )
            )
        );
        deployContractProxy(
            "AirdropERC20Claimable",
            abi.encodeCall(
                AirdropERC20Claimable.initialize,
                (
                    deployer,
                    forwarders(),
                    address(airdropTokenOwner),
                    address(erc20),
                    10_000 ether,
                    1000,
                    1,
                    _airdropMerkleRootERC20
                )
            )
        );
        deployContractProxy(
            "NFTStake",
            abi.encodeCall(
                NFTStake.initialize,
                (deployer, CONTRACT_URI, forwarders(), address(erc20), address(erc721), 60, 1)
            )
        );
        deployContractProxy(
            "EditionStake",
            abi.encodeCall(
                EditionStake.initialize,
                (deployer, CONTRACT_URI, forwarders(), address(erc20), address(erc1155), 60, 1)
            )
        );
        deployContractProxy(
            "TokenStake",
            abi.encodeCall(
                TokenStake.initialize,
                (deployer, CONTRACT_URI, forwarders(), address(erc20), address(erc20Aux), 60, 3, 50)
            )
        );
    }

    function deployContractProxy(string memory _contractType, bytes memory _initializer)
        public
        returns (address proxyAddress)
    {
        vm.startPrank(deployer);
        proxyAddress = TWFactory(factory).deployProxy(bytes32(bytes(_contractType)), _initializer);
        contracts[bytes32(bytes(_contractType))] = proxyAddress;
        vm.stopPrank();
    }

    function getContract(string memory _name) public view returns (address) {
        return contracts[bytes32(bytes(_name))];
    }

    function getActor(uint160 _index) public pure returns (address) {
        return address(uint160(0x50000 + _index));
    }

    function getWallet() public returns (Wallet wallet) {
        wallet = new Wallet();
    }

    function assertIsOwnerERC721(
        address _token,
        address _owner,
        uint256[] memory _tokenIds
    ) internal {
        for (uint256 i = 0; i < _tokenIds.length; i += 1) {
            bool isOwnerOfToken = MockERC721(_token).ownerOf(_tokenIds[i]) == _owner;
            assertTrue(isOwnerOfToken);
        }
    }

    function assertIsNotOwnerERC721(
        address _token,
        address _owner,
        uint256[] memory _tokenIds
    ) internal {
        for (uint256 i = 0; i < _tokenIds.length; i += 1) {
            bool isOwnerOfToken = MockERC721(_token).ownerOf(_tokenIds[i]) == _owner;
            assertTrue(!isOwnerOfToken);
        }
    }

    function assertBalERC1155Eq(
        address _token,
        address _owner,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts
    ) internal {
        require(_tokenIds.length == _amounts.length, "unequal lengths");

        for (uint256 i = 0; i < _tokenIds.length; i += 1) {
            assertEq(MockERC1155(_token).balanceOf(_owner, _tokenIds[i]), _amounts[i]);
        }
    }

    function assertBalERC1155Gte(
        address _token,
        address _owner,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts
    ) internal {
        require(_tokenIds.length == _amounts.length, "unequal lengths");

        for (uint256 i = 0; i < _tokenIds.length; i += 1) {
            assertTrue(MockERC1155(_token).balanceOf(_owner, _tokenIds[i]) >= _amounts[i]);
        }
    }

    function assertBalERC20Eq(
        address _token,
        address _owner,
        uint256 _amount
    ) internal {
        assertEq(MockERC20(_token).balanceOf(_owner), _amount);
    }

    function assertBalERC20Gte(
        address _token,
        address _owner,
        uint256 _amount
    ) internal {
        assertTrue(MockERC20(_token).balanceOf(_owner) >= _amount);
    }

    function forwarders() public view returns (address[] memory) {
        address[] memory _forwarders = new address[](1);
        _forwarders[0] = forwarder;
        return _forwarders;
    }

    function setupAirdropClaimable() public {
        string[] memory inputs = new string[](5);
        inputs[0] = "node";
        inputs[1] = "src/test/scripts/generateRoot.ts";
        inputs[2] = Strings.toString(5);
        inputs[3] = "0";
        inputs[4] = "0x0000000000000000000000000000000000000000";
        bytes memory result = vm.ffi(inputs);
        bytes32 root = abi.decode(result, (bytes32));

        airdropTokenOwner = getWallet();

        // ERC721
        for (uint256 i = 0; i < 1000; i++) {
            _airdropTokenIdsERC721.push(i);
        }
        _airdropMerkleRootERC721 = root;

        // ERC1155
        for (uint256 i = 0; i < 5; i++) {
            _airdropTokenIdsERC1155.push(i);
            _airdropAmountsERC1155.push(100);
            _airdropWalletClaimCountERC1155.push(1);
            _airdropMerkleRootERC1155.push(root);
        }

        // ERC20
        _airdropMerkleRootERC20 = root;
    }
}
