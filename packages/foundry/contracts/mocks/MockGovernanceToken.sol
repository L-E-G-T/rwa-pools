// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGovernanceToken } from "../hooks/StakedGovernanceHook.sol";


contract MockGovernanceToken is IGovernanceToken {
    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    function mint(address to, uint256 amount) external override {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function burn(address from, uint256 amount) external override {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _totalSupply -= amount;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(_balances[sender] >= amount, "Insufficient balance");
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        return true;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return type(uint256).max; // For simplicity, always return max allowance
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        return true; // Always approve for simplicity
    }
}