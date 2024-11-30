//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { DeployNftHookHelper, FactoryType } from "./DeployNftHookHelper.s.sol";

/**
 * @title Deploy Weighted Pool 80/20
 * @notice Deploys, registers, and initializes a 80/20 weighted pool that uses an Exit Fee Hook
 */
contract DeployWeightedPool8020WithCheckHook is DeployNftHookHelper {
    function deployWeightedPool8020WithCheckHook(address token) internal {
        deployNftHookHelper(token, FactoryType.Weighted);
    }
}
