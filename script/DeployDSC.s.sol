// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";

/// @title DSC protocol deployment
/// @notice Deploys the DSC token and collateral engine, then completes token ownership transfer.
/// @dev The deployment signer initially owns the engine and manages its risk and emergency controls.
contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    /// @notice Deploys the DSC protocol contracts and returns their instances
    /// @return dsc The deployed DecentralizedStableCoin contract instance
    /// @return dscEngine The deployed DSCEngine contract instance
    /// @return helperConfig The HelperConfig instance with network configuration
    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        // DSC uses two-step ownership so a bad engine address cannot permanently brick minting.
        dsc.transferOwnership(address(dscEngine));
        dscEngine.acceptDscOwnership();
        vm.stopBroadcast();
        return (dsc, dscEngine, helperConfig);
    }
}
