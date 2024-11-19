//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    TokenConfig,
    TokenType,
    LiquidityManagement,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolHelpers, CustomPoolConfig, InitializationConfig } from "./PoolHelpers.sol";
import { ScaffoldHelpers, console } from "./ScaffoldHelpers.sol";
import { ConstantProductFactory } from "../contracts/factories/ConstantProductFactory.sol";
import { LotteryHookExample } from "../contracts/hooks/LotteryHookExample.sol";
import { DeployNftHookHelper, FactoryType } from "./DeployNftHookHelper.s.sol";

/**
 * @title Deploy Constant Product Pool
 * @notice Deploys, registers, and initializes a constant product pool that uses a Lottery Hook
 */
contract DeployConstantProductPoolWithCheckHook is DeployNftHookHelper {
    function deployConstantProductPoolWithCheckHook(address token) internal {
        deployNftHookHelper(token, FactoryType.ConstantProduct);
    }
}
