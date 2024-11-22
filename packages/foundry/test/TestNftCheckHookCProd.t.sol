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

    function testOwnerCanRemoveLiquidityAfterSettlement() public transferNFT_approveBPT_initializePool {
        _testOwnerCanRemoveLiquidityAfterSettlement(49999999999999000000);
    }

    function testRugPulling() public transferNFT_approveBPT_initializePool {
        _testRugPulling();
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

    function _firstUserSwaps(uint256 _swapFeePercentage) internal override returns (uint256 expectedLinkedTokenOut) {
        _swap(randomUser, usdc, IERC20(linkedTokenAddress), USDC_SWAP_AMOUNT_IN, false);
        assertEq(usdc.balanceOf(randomUser), RANDOM_USER_USDC_INITIAL_BALANCE - USDC_SWAP_AMOUNT_IN, "RandomUser wrong usdc tokens balance");
        assertEq(linkedToken.balanceOf(randomUser), EXPECTED_LINKED_TOKEN_AMOUNT_OUT, "RandomUser has some linked tokens");
        expectedLinkedTokenOut = EXPECTED_LINKED_TOKEN_AMOUNT_OUT;
    }

    function _userRedeemsAfterFirstSwapAndOwnerSettlement(uint256 expectedLinkedTokenOut) internal override {
        _userRedeems();
        assertEq(usdc.balanceOf(hookOwner), 940925000000000000002, 'hookOwner wrong usdc balance');
        assertEq(linkedToken.balanceOf(hookOwner), 958249999999999999999, 'hookOwner wrong linked token balance');
        assertEq(usdc.balanceOf(randomUser), 99074999999999999998, 'randomUser wrong usdc balance');
        assertEq(linkedToken.balanceOf(randomUser), 0, 'randomuser wrong linked token balance');
    }
}
