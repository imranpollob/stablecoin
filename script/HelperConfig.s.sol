// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { MockV3Aggregator } from "../test/mocks/MockV3Aggregator.sol";
import { Script } from "forge-std/Script.sol";
import { ERC20Mock } from "../test/mocks/ERC20Mock.sol";

/**
 * @title HelperConfig
 * @author Patrick Collins
 * @notice This contract provides configuration for different networks (Sepolia, Anvil).
 * It handles the deployment of mock contracts on Anvil and returns the appropriate addresses for each network.
 */
contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    /// @notice Number of decimals for price feeds
    uint8 public constant DECIMALS = 8;
    /// @notice Initial ETH/USD price for mock price feed (2000 USD)
    int256 public constant ETH_USD_PRICE = 2000e8;
    /// @notice Initial BTC/USD price for mock price feed (1000 USD)
    int256 public constant BTC_USD_PRICE = 1000e8;

    /// @notice Structure containing network-specific configuration
    struct NetworkConfig {
        address wethUsdPriceFeed;  // Chainlink price feed for WETH/USD
        address wbtcUsdPriceFeed;  // Chainlink price feed for WBTC/USD
        address weth;              // WETH token address
        address wbtc;              // WBTC token address
        uint256 deployerKey;       // Private key of the deployer
    }

    /// @notice Default private key for Anvil network deployment
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// @notice Constructor that sets the appropriate network configuration based on chain ID
    constructor() {
        if (block.chainid == 11_155_111) { // Sepolia network
            activeNetworkConfig = getSepoliaEthConfig();
        } else { // Default to Anvil
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    /// @notice Retrieves the configuration for Sepolia network
    /// @return sepoliaNetworkConfig Network configuration for Sepolia
    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    /// @notice Retrieves or creates the configuration for Anvil network
    /// @return anvilNetworkConfig Network configuration for Anvil
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed), // ETH / USD
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
