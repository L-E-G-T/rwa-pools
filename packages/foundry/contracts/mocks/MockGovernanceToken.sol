// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGovernanceToken } from "../hooks/StakedGovernanceHook.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockGovernanceToken is ERC20, IGovernanceToken, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

    event TokenMinted(address indexed to, uint256 amount);
    event TokenBurned(address indexed from, uint256 amount);

    function mint(address to, uint256 amount) external override onlyOwner {
        _mint(to, amount);
        emit TokenMinted(to, amount);
    }

    function burn(address from, uint256 amount) external override onlyOwner {
        _burn(from, amount);
        emit TokenBurned(from, amount);
    }

    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return super.balanceOf(account);
    }

    function transfer(address recipient, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        return super.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override(ERC20, IERC20) returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return super.totalSupply();
    }

    function allowance(address owner, address spender) public view override(ERC20, IERC20) returns (uint256) {
        return super.allowance(owner, spender);
    }

    function approve(address spender, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        return super.approve(spender, amount);
    }
    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
    }
}
