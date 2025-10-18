// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @notice This is an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin
 * @dev Collateral: Exogenous
 *      Minting (Stability Mechanism): Decentralized (Algorithmic)
 *      Value (Relative Stability): Anchored (Pegged to USD)
 *      Collateral Type: Crypto
 * 
 * This contract is meant to be owned by DSCEngine. It is an ERC20 token that can only be minted and burned by the DSCEngine smart contract.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    /// @notice Thrown when attempting to burn or mint zero amount
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    
    /// @notice Thrown when attempting to burn more than the balance
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    
    /// @notice Thrown when minting to zero address
    error DecentralizedStableCoin__NotZeroAddress();

    /// @notice Initializes the ERC20 token with name "DecentralizedStableCoin" and symbol "DSC"
    constructor() ERC20("DecentralizedStableCoin", "DSC") { }

    /// @notice Burns DSC tokens from the caller's account (only callable by owner - DSCEngine)
    /// @param _amount The amount of tokens to burn
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    /// @notice Mints new DSC tokens to the specified address (only callable by owner - DSCEngine)
    /// @param _to The address to mint tokens to
    /// @param _amount The amount of tokens to mint
    /// @return bool indicating success
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
