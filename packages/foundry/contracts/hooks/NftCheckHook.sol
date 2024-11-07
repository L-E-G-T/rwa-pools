// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    AddLiquidityParams,
    LiquidityManagement,
    RemoveLiquidityKind,
    TokenConfig,
    HookFlags,
    PoolSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

import { MockNft } from "../mocks/MockNft.sol";
import { MockStable } from "../mocks/MockStable.sol";
import { MockLinked } from "../mocks/MockLinked.sol";


// Interface for ERC721 NFT contract
interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

// Interface for the custom NFT contract
interface ICustomNFT is IERC721 {
    struct NFTData {
        string status;
        address linkedToken;
        string[] linkedTokenInterfaces;
        bool locked;
        bool paused;
    }

    function getNftData(uint256 tokenId) external view returns (NFTData memory);
}

contract NftCheckHook is BaseHooks, VaultGuard, Ownable {
    using FixedPoint for uint256;

    address private nftContract;
    uint256 public nftId;
    uint256 public initialToken1Amount;
    uint256 public initialToken2Amount;
    uint256 public redeemRatio;
    address public poolAddress;
    address private linkedToken;
    address private stableToken;
    TokenConfig[] private tokenConfigs;
    bool private initialLiquidityRecorded;
    bool private poolIsSettled;

    error DoesNotOwnRequiredNFT(address hook, address nftContract, uint256 nftId);
    error LinkedTokenNotInPool(address linkedToken);
    error InsufficientLiquidityToRemove(address user, uint256 currentAmount, uint256 initialAmount);
    error InsufficientStableForSettlement(uint256 required, uint256 available);
    error PoolDoesNotSupportDonation();
    error PoolIsSettled();
    error CantAddLinkedTokenLiquidity();

    event NftCheckHookRegistered(address indexed hooksContract, address indexed pool);
    event NftContractUpdated(address indexed oldContract, address indexed newContract);
    event NftIdUpdated(uint256 oldId, uint256 newId);
    event InitialLiquidityRecorded(address indexed user, uint256 token1Amount, uint256 token2Amount);
    event LiquiditySettled(uint256 totalEscrowedAmount, address indexed originalDepositor);
    event Redeemed(address indexed user, uint256 poolTokenAmount, uint256 stableTokenAmount);

    constructor(IVault vault, address _nftContract, uint256 _nftId, address _stableToken, string memory erc20name, string memory erc20symbol, uint256 erc20supply) VaultGuard(vault) Ownable(msg.sender) {
        nftContract = _nftContract;
        nftId = _nftId;
        stableToken = _stableToken;

        MockLinked mockLinked = new MockLinked(erc20name, erc20symbol, erc20supply);
        mockLinked.transfer(owner(), erc20supply);
        linkedToken = address(mockLinked);
    }

    function onRegister(
        address,
        address pool,
        TokenConfig[] memory _tokenConfigs,
        LiquidityManagement calldata liquidityManagement
    ) public override onlyVault returns (bool) {
        if (liquidityManagement.enableDonation == false) {
            revert PoolDoesNotSupportDonation();
        }
        tokenConfigs = _tokenConfigs;
        poolAddress = pool;

        emit NftCheckHookRegistered(address(this), pool);
        return true;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        hookFlags.shouldCallBeforeInitialize = true;
        hookFlags.shouldCallBeforeRemoveLiquidity = true;
        hookFlags.shouldCallBeforeSwap = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
        return hookFlags;
    }

    function onBeforeInitialize(uint256[] memory exactAmountsIn, bytes memory /*userData*/) public override returns (bool) {
        // Check if the hook owns the required NFT
        if (IERC721(nftContract).ownerOf(nftId) != address(this)) {
            revert DoesNotOwnRequiredNFT(address(this), nftContract, nftId);
        }

        // Check if the linked token is one of the pool tokens
        bool linkedTokenFound = false;
        for (uint256 i = 0; i < tokenConfigs.length; i++) {
            if (address(tokenConfigs[i].token) == linkedToken) {
                linkedTokenFound = true;
                break;
            }
        }
        if (!linkedTokenFound) {
            revert LinkedTokenNotInPool(linkedToken);
        }
        // Record the initial liquidity amounts
        // recordInitialLiquidity(
        //     tokenConfigs[0].token.balanceOf(address(_vault)),
        //     tokenConfigs[1].token.balanceOf(address(_vault))
        // );
        recordInitialLiquidity(exactAmountsIn[0], exactAmountsIn[1]);
        
        return true;
    }

    /// @inheritdoc IHooks
    function onBeforeRemoveLiquidity(
        address,
        address pool,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public view override returns (bool success) {
        
        // Ensure the first depositor has the same amount of both tokens after removal (no rug pulling allowed)
        if (msg.sender == owner()) {  // msg.sender is the vault !!!!!
            IERC20[] memory poolTokens = _vault.getPoolTokens(pool);

            uint256 currentToken1Amount = poolTokens[0].balanceOf(owner());
            uint256 currentToken2Amount = poolTokens[1].balanceOf(owner());

            if (currentToken1Amount < initialToken1Amount) {
                revert InsufficientLiquidityToRemove(owner(), currentToken1Amount, initialToken1Amount);
            }
            if (currentToken2Amount < initialToken2Amount) {
                revert InsufficientLiquidityToRemove(owner(), currentToken2Amount, initialToken2Amount);
            }
        }

        return true;
    }

    /// @inheritdoc IHooks
    // random user cannot add linked token liquidity because problem at settlement
    function onBeforeAddLiquidity(
        address,
        address,
        AddLiquidityKind,
        uint256[] memory maxAmountsInScaled18,
        uint256,
        uint256[] memory,
        bytes memory
    ) public view override returns (bool success) {
       uint256 linkedTokenIndex = linkedToken > stableToken ? 1 : 0;
       if (maxAmountsInScaled18[linkedTokenIndex] > 0)
           revert CantAddLinkedTokenLiquidity();
        success = true;
    }

    /// @inheritdoc IHooks
    // random users cannot swap after pool is settled, but owner should be able to (TODO)
    function onBeforeSwap(PoolSwapParams calldata, address) public view override returns (bool success) {
        if (poolIsSettled) revert PoolIsSettled();
        success = true;
    }

    //////// Permissioned functions - onlyOwner ////////
    
    // New function to update nftContract
    function setNftContract(address _newNftContract) external onlyOwner {
        address oldContract = nftContract;
        nftContract = _newNftContract;
        emit NftContractUpdated(oldContract, _newNftContract);
    }

    // New function to update nftId
    function setNftId(uint256 _newNftId) external onlyOwner {
        uint256 oldId = nftId;
        nftId = _newNftId;
        emit NftIdUpdated(oldId, _newNftId);
    }

    //////// Permissioned functions - onlyVault ////////

    function recordInitialLiquidity(uint256 token1Amount, uint256 token2Amount) public onlyVault {
        require(!initialLiquidityRecorded, "Initial liquidity already recorded");
        initialLiquidityRecorded = true;
        initialToken1Amount = token1Amount;
        initialToken2Amount = token2Amount;
        emit InitialLiquidityRecorded(owner(), token1Amount, token2Amount);
    }

    //////// Getter functions ////////

    function getLinkedToken() external view returns(address) {
        return linkedToken;
    }

    function getStableToken() external view returns(address) {
        return stableToken;
    }

    function getPoolIsSettled() external view returns(bool) {
        return poolIsSettled;
    }

    function getInitialLiquidityRecorded() external view returns(bool) {
        return initialLiquidityRecorded;
    }

    function getNftContract() external view returns(address) {
        return nftContract;
    }

    //////// Escrow functions ////////

    function getSettlementAmount() public returns(uint256 stableAmountRequired) {
        // Calculate total outstanding shares in the pool
        MockLinked linkedTokenErc20 = MockLinked(linkedToken);
        MockStable stableTokenErc20 = MockStable(stableToken);
        uint256 totalSupply = linkedTokenErc20.totalSupply();  // 1000e18
        uint256[] memory poolBalance = _vault.getCurrentLiveBalances(poolAddress); // 0?
        uint256 linkedTokenIndex = linkedToken > stableToken ? 1 : 0;
        uint256 ownerBalance = linkedTokenErc20.balanceOf(owner());  // 950e18
        uint256 outstandingShares = totalSupply - poolBalance[linkedTokenIndex] - ownerBalance;  // 50e18

        // Calculate the equivalent stable token amount using the current pool/stable ratio
        uint256 linkedTokenBalance = linkedTokenErc20.balanceOf(poolAddress);
        uint256 stableTokenBalance = stableTokenErc20.balanceOf(poolAddress);
        uint256 stablePoolRatio = (stableTokenBalance != 0 ? linkedTokenBalance / stableTokenBalance : 1) * 1 ether;
        // Ensure the stable pool ratio is not below what the initial ratio
        redeemRatio = stablePoolRatio > 1.1 ether ? stablePoolRatio : 1.1 ether;

        // how much stable tokens are required to settle the outstanding shares
        stableAmountRequired = outstandingShares * redeemRatio / 1 ether;
    }

    /**
    * @notice Allows the contract owner to settle and release the NFT to the original depositor.
    * @dev This function calculates outstanding shares and deposits the equivalent stable token amount in escrow.
    */
    function settle() external onlyOwner {
        require(initialLiquidityRecorded, "Initial liquidity not recorded");
        if (poolIsSettled) revert PoolIsSettled();
        uint256 stableAmountRequired = getSettlementAmount();

        // Transfer the necessary stable tokens from the user
        MockStable(stableToken).transferFrom(msg.sender, address(this), stableAmountRequired);
        // Return the nft to the user
        MockNft(nftContract).transferFrom(address(this), msg.sender, nftId);

        poolIsSettled = true;
        emit LiquiditySettled(stableAmountRequired, owner());
    }

    /**
    * @notice Allows users with linked tokens to redeem their tokens for the stable token in escrow.
    */
    function redeem() external {
        MockLinked linkedTokenErc20 = MockLinked(linkedToken);
        MockStable stableTokenErc20 = MockStable(stableToken);
        uint256 redeemableBalance = linkedTokenErc20.balanceOf(msg.sender);
        require(redeemableBalance > 0, "Sender has no redeemable tokens");

        // Calculate the stable token amount to be transferred based on the ratio
        uint256 stableAmountToTransfer = redeemableBalance * redeemRatio / 1 ether;

        // Transfer the linked tokens from the user and the stable tokens to the user
        linkedTokenErc20.transferFrom(msg.sender, owner(), redeemableBalance);
        stableTokenErc20.transfer(msg.sender, stableAmountToTransfer);

        emit Redeemed(msg.sender, redeemableBalance, stableAmountToTransfer);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view onlyOwner returns (bytes4) {
        return this.onERC721Received.selector;
    }
}