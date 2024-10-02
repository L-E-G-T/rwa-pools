// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "../lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IRouter.sol";

import { IVault } from "../lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import {
    LiquidityManagement,
    PoolRoleAccounts,
    SwapKind
} from "../lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "../lib/balancer-v3-monorepo/pkg/vault/test/foundry/utils/BaseVaultTest.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { StakedGovernanceHook } from "../contracts/hooks/StakedGovernanceHook.sol";
import { IGovernanceToken } from "../contracts/hooks/StakedGovernanceHook.sol";
import { MockGovernanceToken } from "../contracts/mocks/MockGovernanceToken.sol";



contract StakedGovernanceHookTest is BaseVaultTest { 
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    StakedGovernanceHook public hook;
    MockGovernanceToken public governanceToken;
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        governanceToken = new MockGovernanceToken();
        hook = new StakedGovernanceHook(IVault(address(vault)), IGovernanceToken(address(governanceToken)), IERC20(address(dai)));
    }

    function createHook() internal override returns (address) {
        return address(hook);
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "Staked Governance Pool", "SGP");
        vm.label(address(newPool), label);

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.disableUnbalancedLiquidity = true;

        factoryMock.registerPool(
            address(newPool),
            vault.buildTokenConfig(tokens.asIERC20()),
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        return address(newPool);
    }
uint256 public aliceBptBalance;

function testAddLiquidity() public {
            console.log("alice");

    uint256 addAmount = poolInitAmount / 100;
    uint256[] memory maxAmountsIn = new uint256[](2);
    maxAmountsIn[daiIdx] = addAmount;
    maxAmountsIn[usdcIdx] = addAmount;

    // Ensure Alice has enough tokens
    deal(address(dai), alice, addAmount);
    deal(address(usdc), alice, addAmount);

    vm.startPrank(alice);
    
    // Approve router to spend Alice's tokens
    dai.approve(address(router), addAmount);
    usdc.approve(address(router), addAmount);

    // Add liquidity proportionally
   uint256[] memory amountsIn = router.addLiquidityProportional(
        address(pool),
        maxAmountsIn,
        1, // exactBptAmountOut (minimum amount to receive)
        false, // wethIsEth
        abi.encode(alice) // userData (changed from "" to alice)
    );
    aliceBptBalance = IERC20(address(pool)).balanceOf(alice);

    console.log("alice");
     console.log("Alice BPT balance:", aliceBptBalance);
    console.log("Alice governance token balance:", governanceToken.balanceOf(alice));
    console.log("Governance token percentage:", hook.governanceTokenPercentage());
    assertGt(aliceBptBalance, 0, "No BPT tokens received");

    vm.stopPrank();

    assertGt(amountsIn[daiIdx], 0, "No DAI added");
    assertGt(amountsIn[usdcIdx], 0, "No USDC added");

    uint256 expectedGovernanceTokens = aliceBptBalance.mulDown(hook.governanceTokenPercentage());
    assertEq(governanceToken.balanceOf(alice), expectedGovernanceTokens, "Incorrect governance tokens minted");
}
    function testRemoveLiquidity() public {
    // First, add liquidity
    testAddLiquidity();

    uint256 removeAmount = aliceBptBalance / 2; // Remove half of Alice's BPT balance
    uint256 exactBptAmountIn = removeAmount;

    uint256 governanceTokensBefore = governanceToken.balanceOf(alice);

    vm.startPrank(alice);
    
    // Approve the router to spend Alice's BPT tokens
    IERC20(address(pool)).approve(address(router), exactBptAmountIn);

    uint256[] memory amountsOut = router.removeLiquidityProportional(
        address(pool),
        exactBptAmountIn,
        new uint256[](2),
        false, 
        abi.encode(alice) 
    );
    vm.stopPrank();

    uint256 expectedBurnedTokens = exactBptAmountIn.mulDown(hook.governanceTokenPercentage());
    assertEq(governanceToken.balanceOf(alice), governanceTokensBefore - expectedBurnedTokens, "Incorrect governance tokens burned");
}
    function testStakeAndUnstake() public {
    // First, add liquidity to get governance tokens
    testAddLiquidity();

    uint256 stakeAmount = governanceToken.balanceOf(alice);
    console.log("Stake amount:", stakeAmount);
    console.log("Governance token percentage:", hook.governanceTokenPercentage());
    
    require(stakeAmount > 0, "Insufficient governance tokens for test");

    vm.startPrank(alice);
    governanceToken.approve(address(hook), stakeAmount);
    hook.stake(stakeAmount, 20e16, 60e16);
    vm.stopPrank();

    (uint256 amount, uint64 votedGovernancePercentage, uint64 votedMajorityThreshold) = hook.stakes(alice);
    assertEq(amount, stakeAmount, "Incorrect stake amount");
    assertEq(votedGovernancePercentage, 20e16, "Incorrect voted governance percentage");
    assertEq(votedMajorityThreshold, 60e16, "Incorrect voted majority threshold");

    vm.prank(alice);
    hook.unstake();

    (amount, , ) = hook.stakes(alice);
    assertEq(amount, 0, "Stake not removed");
    assertEq(governanceToken.balanceOf(alice), stakeAmount, "Governance tokens not returned");
}
}