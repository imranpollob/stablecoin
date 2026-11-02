// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Decentralized Stable Coin
/// @notice Debt token minted and burned exclusively by the DSCEngine owner.
/// @dev Ownership is intentionally two-step. Deployment must nominate the engine and have the
///      engine accept ownership before users interact with the protocol.
contract DecentralizedStableCoin is ERC20Burnable, Ownable2Step {
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") { }

    function burn(uint256 amount) public override onlyOwner {
        if (amount == 0) revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        if (balanceOf(msg.sender) < amount) revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        super.burn(amount);
    }

    /// @notice Only the engine may destroy DSC, including through the allowance-based path.
    /// @dev Inherited burnFrom would otherwise reduce supply without updating engine debt.
    function burnFrom(address account, uint256 amount) public override onlyOwner {
        super.burnFrom(account, amount);
    }

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (to == address(0)) revert DecentralizedStableCoin__NotZeroAddress();
        if (amount == 0) revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        _mint(to, amount);
        return true;
    }
}
