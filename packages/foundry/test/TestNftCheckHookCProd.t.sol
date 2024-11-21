// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import {
    TokenType,
    HooksConfig,
    LiquidityManagement,
    PoolRoleAccounts,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";
import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { RouterMock } from "@balancer-labs/v3-vault/contracts/test/RouterMock.sol";
import { ConstantProductFactory } from "../contracts/factories/ConstantProductFactory.sol";
import { ConstantProductPool } from "../contracts/pools/ConstantProductPool.sol";

import { NftCheckHook } from "../contracts/hooks/NftCheckHook.sol";
import { MockNft } from "../contracts/mocks/MockNft.sol";
import { MockLinked } from "../contracts/mocks/MockLinked.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { InitializationConfig } from "../script/PoolHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { HelperForTests } from "./HelperForTests.t.sol";

contract TestNftCheckHookCProd is HelperForTests {
    using ArrayHelpers for *;


    function setUp() public override {
        address hookOwnerP;
        (hookOwnerP, hookOwnerKey) = makeAddrAndKey("hookOwner");
        hookOwner = payable(hookOwnerP);
        address randomUserP;
        (randomUserP, randomUserKey) = makeAddrAndKey("randomUser");
        randomUser = payable(randomUserP);

        mintNft();

        super.setUp();
        poolInitAmount = POOL_INITIAL_AMOUNT; // overriding
        poolHooksContract = nftCheckHook; // overriding
        usdc.mint(hookOwner, OWNER_USDC_INITIAL_BALANCE);
        usdc.mint(randomUser, RANDOM_USER_USDC_INITIAL_BALANCE);

        linkedTokenAddress = NftCheckHook(nftCheckHook).getLinkedToken(); // get linked token address
        linkedToken = MockLinked(linkedTokenAddress); // linked token
        tokens.push(ERC20TestToken(linkedTokenAddress)); // push linked token to tokens as ERC20TestToken
        linkedTokenIsMinted = true; // to enable the pool creation
        (linkedTokenIdx, usdcIdx) = getSortedIndexes(address(linkedToken), address(usdc));

        pool = createPool();
        vaultConvertFactor = vault.getConvertFactor();

        // Grants hookOwner the ability to change the static swap fee percentage.
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), hookOwner);
    }

    ////////////////////////////////////////
    // Tests ///////////////////////////////
    ////////////////////////////////////////

    function testInitialBalances() public {
        _testInitialBalances();
    }

    function testSwapFeeOne() public transferNFT_approveBPT_initializePool {
        _userSwapsOwnerSettlesUserRedeemsUserSwapsWithRevert(SWAP_FEE_PERCENTAGE);
    }

    function testOwnerCanRemoveLiquidityAfterSettlement() public transferNFT_approveBPT_initializePool {
        console.log("BPT amount of hook: ", IERC20(pool).balanceOf(nftCheckHook));
        _userSwapsOwnerSettlesUserRedeemsUserSwapsWithRevert(SWAP_FEE_PERCENTAGE);

        uint256 bptAmount = IERC20(pool).balanceOf(hookOwner);
        // for some reason the bpt amount is a lot different than 2*POOL_INITIAL_AMOUNT, TODO
        assertEq(bptAmount, 49999999999999000000, "Wrong bpt amount");
        _ownerRemovesLiquidityProportional(bptAmount, false);
    }

    function testRugPulling() public transferNFT_approveBPT_initializePool {
        // random user swaps usdc for linked token
        uint256 expectedLinkedTokenOut = _firstUserSwaps(SWAP_FEE_PERCENTAGE);

        // Owner removes liquidity but has no bpt
        uint256 bptAmount = IERC20(pool).balanceOf(hookOwner);
        assertEq(bptAmount, 0, "Wrong bpt amount");
        // true means it reverts
        _ownerRemovesLiquidityProportional(POOL_INITIAL_AMOUNT/10, true);
    }

    // amount of linked tokens in the pool = 2 * amount of usdc in the pool
    function testRedeemRationWhenStablePoolRatioIsBig() public transferNFT_approveBPT_initializePool {
        // random user swaps 10e18 usdc for 8.249~e18 linked token
        uint256 expectedLinkedTokenOut = _firstUserSwaps(SWAP_FEE_PERCENTAGE);
        // pool 41.751~e18/60e18 linked/usdc

        // Owner adds enough linked tokens so that linked tokens = 2 * usdc
        uint256 linkedAmountIn = 2*60e18 - (USDC_SWAP_AMOUNT_IN - EXPECTED_LINKED_TOKEN_AMOUNT_OUT);
        uint256[] memory amountsToAdd = linkedTokenIdx == 0 ? 
            [linkedAmountIn, uint256(0)].toMemoryArray() : [uint256(0), linkedAmountIn].toMemoryArray();
        _ownerAddsLiquidity(amountsToAdd);
        // pool 120e18/60e18 linked/usdc so linked/usdc rato is 2

        uint256 stableAmountRequired = NftCheckHook(nftCheckHook).getSettlementAmount();

        // user has EXPECTED_LINKED_TOKEN_AMOUNT_OUT linked tokens so stableAmountRequired = EXPECTED_LINKED_TOKEN_AMOUNT_OUT * 2
        uint256 expectedStableAmountRequired = EXPECTED_LINKED_TOKEN_AMOUNT_OUT * 2;
        assertEq(stableAmountRequired, expectedStableAmountRequired, "Wrong stableAmountRequired");
    }

    ////////////////////////////////////////
    // Helpers /////////////////////////////
    ////////////////////////////////////////

    function mintNft() internal {
        vm.prank(hookOwner);
        mockNft = new MockNft("NFTFactory", "NFTF");
        vm.prank(hookOwner);
        tokenId = mockNft.mintNft("https://0a050602b1c1aeae1063a0c8f5a7cdac.ipfscdn.io/ipfs/QmSiA82PQNuWuBfQtuzWKwnZV94qs34jrW1L6PaR69jeoE/metadata.json");
    }

    function createHook() internal override returns (address) {
        // hookOwner will be the owner of the hook
        vm.prank(hookOwner);
        nftCheckHook = address(
            new NftCheckHook(
                vault,
                address(mockNft),
                tokenId,
                address(usdc),
                "RWA Token",
                "RWAT",
                OWNER_LINKED_TOKEN_INITIAL_BALANCE,
                SETTLEMENT_FEE
            )
        );
        vm.label(nftCheckHook, "Nft Check Hook");
        return nftCheckHook;
    }

    function createPool() internal override returns (address) {
        if (!linkedTokenIsMinted) return address(0);
        return _createPool([address(linkedToken), address(usdc)].toMemoryArray(), "pool");
    }

    function _createPool(address[] memory tokens, string memory label) internal virtual override returns (address) {
        ConstantProductFactory factory = new ConstantProductFactory(vault, 365 days);
        CustomPoolConfig memory poolConfig = getProductPoolConfig(address(linkedToken), address(usdc));

        address newPool = factory.create(
            poolConfig.name,
            poolConfig.symbol,
            poolConfig.salt,
            poolConfig.tokenConfigs,
            poolConfig.swapFeePercentage,
            poolConfig.protocolFeeExempt,
            poolConfig.roleAccounts,
            nftCheckHook, // poolHooksContract
            poolConfig.liquidityManagement
        );
        vm.label(address(newPool), label);

        return address(newPool);
    }

    function initPool() internal override {
        if (mockNft.ownerOf(tokenId) == nftCheckHook) {
            vm.startPrank(hookOwner);
            usdc.approve(address(permit2), type(uint256 ).max);
            linkedToken.approve(address(permit2), type(uint256 ).max);
            permit2.approve(address(linkedToken), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(usdc), address(router), type(uint160).max, type(uint48).max);
            _initPool(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
            vm.stopPrank();
        }
    }

    function _initPool(
        address poolToInit,
        uint256[] memory amountsIn,
        uint256 minBptOut
    ) internal override returns (uint256 bptOut) {
        
        IERC20[] memory tokens =  new IERC20[](2);
        if (address(linkedToken) > address(usdc)) {
            tokens[0] = IERC20(address(usdc));
            tokens[1] = IERC20(linkedTokenAddress);

        } else {
            tokens[1] = IERC20(address(usdc));
            tokens[0] = IERC20(linkedTokenAddress);
        }

        return router.initialize(poolToInit, tokens, amountsIn, minBptOut, false, bytes(""));
    }

    // user and owner actions


    function _firstUserSwaps(uint256 _swapFeePercentage) internal override returns (uint256 expectedLinkedTokenOut) {
        _swap(randomUser, usdc, IERC20(linkedTokenAddress), USDC_SWAP_AMOUNT_IN, false);
        assertEq(usdc.balanceOf(randomUser), RANDOM_USER_USDC_INITIAL_BALANCE - USDC_SWAP_AMOUNT_IN, "RandomUser wrong usdc tokens balance");
        assertEq(linkedToken.balanceOf(randomUser), EXPECTED_LINKED_TOKEN_AMOUNT_OUT, "RandomUser has some linked tokens");
        expectedLinkedTokenOut = EXPECTED_LINKED_TOKEN_AMOUNT_OUT;
    }

    function _userRedeemsAfterFirstSwapAndOwnerSettlement(uint256 expectedLinkedTokenOut) internal override {
        // random user redeems
        vm.startPrank(randomUser);
        linkedToken.approve(nftCheckHook, type(uint256).max);
        NftCheckHook(nftCheckHook).redeem();
        vm.stopPrank();
        assertEq(usdc.balanceOf(hookOwner), 940925000000000000002, 'hookOwner wrong usdc balance');
        assertEq(linkedToken.balanceOf(hookOwner), 958249999999999999999, 'hookOwner wrong linked token balance');
        assertEq(usdc.balanceOf(randomUser), 99074999999999999998, 'randomUser wrong usdc balance');
        assertEq(linkedToken.balanceOf(randomUser), 0, 'randomuser wrong linked token balance');
    }
}
