// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
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

function testAddLiquidity() public {
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
        "" // userData
    );

    vm.stopPrank();

    assertGt(amountsIn[daiIdx], 0, "No DAI added");
    assertGt(amountsIn[usdcIdx], 0, "No USDC added");

    uint256 expectedGovernanceTokens = amountsIn[daiIdx].mulDown(hook.governanceTokenPercentage());
    assertEq(governanceToken.balanceOf(alice), expectedGovernanceTokens, "Incorrect governance tokens minted");
}
    // function testRemoveLiquidity() public {
    //     // First, add liquidity
    //     testAddLiquidity();

    //     uint256 removeAmount = poolInitAmount / 200; // Remove half of what was added
    //     uint256[] memory amountsOut = new uint256[](2);
    //     amountsOut[daiIdx] = removeAmount;
    //     amountsOut[usdcIdx] = removeAmount;

    //     uint256 governanceTokensBefore = governanceToken.balanceOf(alice);

    //     vm.prank(alice);
    //     (bool success, ) = address(router).call(
    //         abi.encodeWithSelector(
    //             IRouter.removeLiquidity.selector,
    //             address(pool),
    //             amountsOut,
    //             type(uint256).max,
    //             alice,
    //             false,
    //             bytes("")
    //         )
    //     );

    //     assertTrue(success, "Remove liquidity failed");

    //     uint256 expectedBurnedTokens = removeAmount.mulDown(hook.governanceTokenPercentage());
    //     assertEq(governanceToken.balanceOf(alice), governanceTokensBefore - expectedBurnedTokens, "Incorrect governance tokens burned");
    // }

    // function testStakeAndUnstake() public {
    //     // First, add liquidity to get governance tokens
    //     testAddLiquidity();

    //     uint256 stakeAmount = governanceToken.balanceOf(alice) / 2;
    //     vm.prank(alice);
    //     hook.stake(stakeAmount, 20e16, 60e16);

    //     assertEq(hook.stakes(alice).amount, stakeAmount, "Incorrect stake amount");
    //     assertEq(hook.stakes(alice).votedGovernancePercentage, 20e16, "Incorrect voted governance percentage");
    //     assertEq(hook.stakes(alice).votedMajorityThreshold, 60e16, "Incorrect voted majority threshold");

    //     vm.prank(alice);
    //     hook.unstake();

    //     assertEq(hook.stakes(alice).amount, 0, "Stake not removed");
    //     assertEq(governanceToken.balanceOf(alice), stakeAmount, "Governance tokens not returned");
    // }

    // function testExecuteGovernanceUpdate() public {
    //     // Add liquidity and stake for multiple users
    //     testAddLiquidity();
    //     vm.prank(alice);
    //     hook.stake(governanceToken.balanceOf(alice), 20e16, 60e16);

    //     vm.prank(bob);
    //     (bool success, ) = address(router).call(
    //         abi.encodeWithSelector(
    //             IRouter.addLiquidity.selector,
    //             address(pool),
    //             [poolInitAmount / 100, poolInitAmount / 100],
    //             0,
    //             bob,
    //             false,
    //             bytes("")
    //         )
    //     );
    //     assertTrue(success, "Add liquidity for Bob failed");

    //     vm.prank(bob);
    //     hook.stake(governanceToken.balanceOf(bob), 15e16, 55e16);

    //     // Execute governance update
    //     hook.executeGovernanceUpdate();

    //     // Check if governance parameters were updated
    //     assertEq(hook.governanceTokenPercentage(), 20e16, "Governance token percentage not updated");
    //     assertEq(hook.majorityThreshold(), 60e16, "Majority threshold not updated");

    //     // Check if stakes were returned
    //     assertEq(hook.stakes(alice).amount, 0, "Alice's stake not returned");
    //     assertEq(hook.stakes(bob).amount, 0, "Bob's stake not returned");
    // }
}