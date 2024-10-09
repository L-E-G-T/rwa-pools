// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    AddLiquidityParams,
    RemoveLiquidityKind,
    LiquidityManagement,
    TokenConfig,
    HookFlags
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

interface IGovernanceToken is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

contract StakedGovernanceHook is BaseHooks, VaultGuard, Ownable {
    using FixedPoint for uint256;

    IGovernanceToken public governanceToken;
    IERC20 public stableToken;
    uint256 public incentiveFee; // Stored as percentage * 1e18 (e.g., 10% = 10e16)

    struct Stake {
        uint256 amount;
        uint256 votedIncentiveFee;
    }

    mapping(address => Stake) public stakes;
    uint256 public totalStaked;
    uint256 public constant VOTING_DURATION = 7 days;
    uint256 public votingEndTime;
    uint256 public newIncentiveFeeProposal;
    uint256 public votesForNewFee;

    event GovernanceHookRegistered(address indexed hooksContract, address indexed pool);
    event GovernanceTokensMinted(address indexed user, uint256 amount);
    event GovernanceTokensBurned(address indexed user, uint256 amount);
    event Staked(address indexed user, uint256 amount, uint256 votedIncentiveFee);
    event Unstaked(address indexed user, uint256 amount);
    event IncentiveFeeUpdated(uint256 newFee);
    event NewIncentiveFeeProposed(uint256 proposedFee);
    event VoteCast(address indexed user, uint256 amount, uint256 votedIncentiveFee);

    constructor(
        IVault vault,
        IGovernanceToken _governanceToken,
        IERC20 _stableToken,
        uint256 _initialIncentiveFee
    ) VaultGuard(vault) Ownable(msg.sender) {
        governanceToken = _governanceToken;
        stableToken = _stableToken;
        incentiveFee = _initialIncentiveFee;
    }

    function onRegister(
        address,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public override onlyVault returns (bool) {
        // NOTICE: In real hooks, make sure this function is properly implemented (e.g. check the factory, and check
        // that the given pool is from the factory). Returning true unconditionally allows any pool, with any
        // configuration, to use this hook.
        emit GovernanceHookRegistered(address(this), pool);

        return true;
    }

    function onAfterAddLiquidity(
        address,
        address,
        AddLiquidityKind,
        uint256[] memory amountsIn,
        uint256,
        uint256,
        bytes memory
    ) public  onlyVault returns (bool) {
        uint256 stableTokenIndex = getStableTokenIndex();
        uint256 stableTokenAmount = amountsIn[stableTokenIndex];
        uint256 governanceTokenAmount = stableTokenAmount.mulDown(incentiveFee);
        governanceToken.mint(msg.sender, governanceTokenAmount);
        emit GovernanceTokensMinted(msg.sender, governanceTokenAmount);
        return true;
    }

    function onBeforeRemoveLiquidity(
        address sender,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory amountsOut,
        uint256,
        bytes memory
    ) public  onlyVault returns (bool, uint256[] memory hookAdjustedAmountsOutRaw) {
        uint256 stableTokenIndex = getStableTokenIndex();
        uint256 stableTokenAmount = amountsOut[stableTokenIndex];
        uint256 governanceTokenAmount = stableTokenAmount.mulDown(incentiveFee);
        require(governanceToken.balanceOf(sender) >= governanceTokenAmount, "Insufficient governance tokens");
        governanceToken.burn(sender, governanceTokenAmount);
        emit GovernanceTokensBurned(sender, governanceTokenAmount);
        return (true, amountsOut);
    }

    function getStableTokenIndex() internal view returns (uint256) {
        IERC20[] memory tokens = _vault.getPoolTokens(address(this));
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == stableToken) {
                return i;
            }
        }
        revert("Stable token not found in pool");
    }

    function stake(uint256 amount, uint256 votedIncentiveFee) external {
        require(amount > 0, "Amount must be greater than 0");
        require(governanceToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        stakes[msg.sender].amount += amount;
        stakes[msg.sender].votedIncentiveFee = votedIncentiveFee;
        totalStaked += amount;

        if (votingEndTime == 0) {
            votingEndTime = block.timestamp + VOTING_DURATION;
            newIncentiveFeeProposal = votedIncentiveFee;
        }

        votesForNewFee += amount;

        emit Staked(msg.sender, amount, votedIncentiveFee);
        emit VoteCast(msg.sender, amount, votedIncentiveFee);
    }

    function unstake() external {
        require(block.timestamp > votingEndTime, "Voting period not ended");
        uint256 amount = stakes[msg.sender].amount;
        require(amount > 0, "No stake to unstake");

        delete stakes[msg.sender];
        totalStaked -= amount;
        require(governanceToken.transfer(msg.sender, amount), "Transfer failed");

        emit Unstaked(msg.sender, amount);
    }

    function executeIncentiveFeeUpdate() external {
        require(block.timestamp > votingEndTime, "Voting period not ended");
        require(votingEndTime != 0, "No active proposal");

        if (votesForNewFee > totalStaked / 2) {
            incentiveFee = newIncentiveFeeProposal;
            emit IncentiveFeeUpdated(incentiveFee);
        }

        votingEndTime = 0;
        newIncentiveFeeProposal = 0;
        votesForNewFee = 0;
    }

    function proposeNewIncentiveFee(uint256 newFee) external {
        require(votingEndTime == 0, "Voting already in progress");
        require(newFee <= 100e16, "Fee cannot exceed 100%");

        votingEndTime = block.timestamp + VOTING_DURATION;
        newIncentiveFeeProposal = newFee;
        emit NewIncentiveFeeProposed(newFee);
    }

    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        hookFlags.shouldCallAfterAddLiquidity = true;
        hookFlags.shouldCallBeforeRemoveLiquidity = true;
        return hookFlags;
    }
}