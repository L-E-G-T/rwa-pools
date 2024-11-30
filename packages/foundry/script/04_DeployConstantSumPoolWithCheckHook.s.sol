//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
