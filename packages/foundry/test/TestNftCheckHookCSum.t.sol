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

import { NftCheckHook } from "../contracts/hooks/NftCheckHook.sol";
import { MockNft } from "../contracts/mocks/MockNft.sol";
import { MockLinked } from "../contracts/mocks/MockLinked.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { InitializationConfig } from "../script/PoolHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { ConstantSumFactory } from "../contracts/factories/ConstantSumFactory.sol";
import { ConstantSumPool } from "../contracts/pools/ConstantSumPool.sol";
import { HelperForTests } from "./HelperForTests.t.sol";

contract TestNftCheckHookCSum is HelperForTests {
    using ArrayHelpers for *;
    

    function setUp() public override {
        _setUp();
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

    function testSwapFeeFive() public transferNFT_approveBPT_initializePool {
        uint256 swapFeePercentage = 5e16; // 5%
        vm.prank(hookOwner);
        vault.setStaticSwapFeePercentage(pool, swapFeePercentage);
        _userSwapsOwnerSettlesUserRedeemsUserSwapsWithRevert(swapFeePercentage);
    }

    function testSwapFeeTen() public transferNFT_approveBPT_initializePool {
        uint256 swapFeePercentage = 10e16; // 10% (max)
        vm.prank(hookOwner);
        vault.setStaticSwapFeePercentage(pool, swapFeePercentage);
       _userSwapsOwnerSettlesUserRedeemsUserSwapsWithRevert(swapFeePercentage);
    }

    function testOwnerCanRemoveLiquidityAfterSettlement() public transferNFT_approveBPT_initializePool {
        _testOwnerCanRemoveLiquidityAfterSettlement(99999999999999000000);
    }

    function testRugPulling() public transferNFT_approveBPT_initializePool {
        _testRugPulling();
    }

    // amount of linked tokens in the pool = 2 * amount of usdc in the pool 
    function testRedeemRationWhenStablePoolRatioIsBig() public transferNFT_approveBPT_initializePool {
        // random user swaps 10e18 usdc for 9.9e18 linked token
        uint256 expectedLinkedTokenOut = _firstUserSwaps(SWAP_FEE_PERCENTAGE);
        // pool 40e18/60e18 linked/usdc

        // Owner adds 80e18 linked tokens
        uint256 linkedAmountIn = 80e18;
        uint256[] memory amountsToAdd = linkedTokenIdx == 0 ? 
            [linkedAmountIn, uint256(0)].toMemoryArray() : [uint256(0), linkedAmountIn].toMemoryArray();
        _ownerAddsLiquidity(amountsToAdd);
        // pool 180e18/90e18 linked/usdc so linked/usdc rato is 2

        uint256 stableAmountRequired = NftCheckHook(nftCheckHook).getSettlementAmount();

        // user has 9.9 linked tokens so stableAmountRequired = 9.9e18 * 2 = 19.8e18
        uint256 expectedStableAmountRequired = 19.8e18;
        assertEq(stableAmountRequired, expectedStableAmountRequired, "Wrong stableAmountRequired");
    }

    ////////////////////////////////////////
    // Helpers /////////////////////////////
    ////////////////////////////////////////

    function _createPool(address[] memory tokens, string memory label) internal virtual override returns (address) {
        ConstantSumFactory factory = new ConstantSumFactory(vault, 365 days);
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

    function _firstUserSwaps(uint256 _swapFeePercentage) internal override returns (uint256 expectedLinkedTokenOut) {
        _swap(randomUser, usdc, IERC20(linkedTokenAddress), USDC_SWAP_AMOUNT_IN, false);
        uint256 expectedPoolFee = USDC_SWAP_AMOUNT_IN * _swapFeePercentage / 1e18;
        expectedLinkedTokenOut = USDC_SWAP_AMOUNT_IN - expectedPoolFee;
        assertEq(usdc.balanceOf(randomUser), RANDOM_USER_USDC_INITIAL_BALANCE - USDC_SWAP_AMOUNT_IN, "RandomUser wrong usdc tokens balance");
        assertEq(linkedToken.balanceOf(randomUser), expectedLinkedTokenOut, "RandomUser has some linked tokens");
    }

    function _userRedeemsAfterFirstSwapAndOwnerSettlement(uint256 expectedLinkedTokenOut) internal override {
        _userRedeems();
        uint256 settlementAmount = (expectedLinkedTokenOut * (1 ether + SETTLEMENT_FEE)) / 1 ether;
        assertEq(usdc.balanceOf(hookOwner), OWNER_USDC_INITIAL_BALANCE - POOL_INITIAL_AMOUNT - settlementAmount, 'hookOwner wrong usdc balance');
        assertEq(linkedToken.balanceOf(hookOwner), OWNER_LINKED_TOKEN_INITIAL_BALANCE - POOL_INITIAL_AMOUNT + expectedLinkedTokenOut, 'hookOwner wrong linked token balance');
        assertEq(usdc.balanceOf(randomUser), RANDOM_USER_USDC_INITIAL_BALANCE - USDC_SWAP_AMOUNT_IN + settlementAmount, 'randomUser wrong usdc balance');
        assertEq(linkedToken.balanceOf(randomUser), 0, 'randomuser wrong linked token balance');
    }
}
