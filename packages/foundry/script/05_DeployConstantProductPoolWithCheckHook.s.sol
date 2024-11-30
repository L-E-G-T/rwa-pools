//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
