//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    TokenConfig,
    TokenType,
    LiquidityManagement,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { PoolHelpers, CustomPoolConfig, InitializationConfig } from "./PoolHelpers.sol";
import { ScaffoldHelpers, console } from "./ScaffoldHelpers.sol";
import { ConstantSumFactory } from "../contracts/factories/ConstantSumFactory.sol";
import { NftCheckHook } from "../contracts/hooks/NftCheckHook.sol";
import { MockNft } from "../contracts/mocks/MockNft.sol";
import { Router } from "../contracts/mocks/Router.sol";
import { MockLinked } from "../contracts/mocks/MockLinked.sol";
import { MockStable } from "../contracts/mocks/MockStable.sol";
import { DeployNftHookHelper, FactoryType } from "./DeployNftHookHelper.s.sol";

/**
 * @title Deploy Constant Sum Pool
 * @notice Deploys, registers, and initializes a constant sum pool that uses a swap fee discount hook
 */
contract DeployConstantSumPoolWithCheckHook is DeployNftHookHelper {
    function deployConstantSumPoolWithCheckHook(address token) internal {
        deployNftHookHelper(token, FactoryType.ConstantSum);
    }
}
