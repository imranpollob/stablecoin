// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";

/**
 * @title DSCEngine
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @dev This contract is based on the MakerDAO DSS system
 *      The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 *      This is a stablecoin with the properties:
 *      - Exogenously Collateralized
 *      - Dollar Pegged
 *      - Algorithmically Stable
 *      
 *      It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *      
 *      Our DSC system should always be "overcollateralized". At no point, should the value of
 *      all collateral < the $ backed value of all the DSC.
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    
    /// @notice Thrown when token addresses and price feed addresses arrays have different lengths
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    
    /// @notice Thrown when a zero amount is provided where a positive amount is required
    error DSCEngine__NeedsMoreThanZero();
    
    /// @notice Thrown when a token is not allowed as collateral
    error DSCEngine__TokenNotAllowed(address token);
    
    /// @notice Thrown when a token transfer fails
    error DSCEngine__TransferFailed();
    
    /// @notice Thrown when an action would break the health factor (bring it below the minimum)
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    
    /// @notice Thrown when DSC minting fails
    error DSCEngine__MintFailed();
    
    /// @notice Thrown when trying to liquidate a user with acceptable health factor
    error DSCEngine__HealthFactorOk();
    
    /// @notice Thrown when liquidation does not improve user's health factor
    error DSCEngine__HealthFactorNotImproved();

    ///////////////////
    // Types
    ///////////////////
    using OracleLib for AggregatorV3Interface;

    ///////////////////
    // State Variables
    ///////////////////
    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    /// @dev Mapping of token address to price feed address
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    /// @dev Amount of DSC minted by user
    mapping(address user => uint256 amount) private s_DSCMinted;
    /// @dev If we know exactly how many tokens we have, we could make this immutable!
    address[] private s_collateralTokens;

    ///////////////////
    // Events
    ///////////////////
    
    /// @notice Emitted when collateral is deposited
    /// @param user The address of the user who deposited collateral
    /// @param token The address of the collateral token
    /// @param amount The amount of collateral deposited
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    
    /// @notice Emitted when collateral is redeemed
    /// @param redeemFrom The address from which collateral was redeemed
    /// @param redeemTo The address to which collateral was sent
    /// @param token The address of the collateral token
    /// @param amount The amount of collateral redeemed
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount); // if
        // redeemFrom != redeemedTo, then it was liquidated

    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////
    /// @notice Initializes the DSCEngine with supported collateral tokens and their price feeds
    /// @param tokenAddresses Array of collateral token addresses
    /// @param priceFeedAddresses Array of corresponding price feed addresses
    /// @param dscAddress Address of the DecentralizedStableCoin contract
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        // These feeds will be the USD pairs
        // For example ETH / USD or MKR / USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////
    /// @notice Deposits collateral and mints DSC in one transaction
    /// @param tokenCollateralAddress The ERC20 token address of the collateral being deposited
    /// @param amountCollateral The amount of collateral being deposited
    /// @param amountDscToMint The amount of DSC to mint
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    )
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /// @notice Withdraws collateral and burns DSC in one transaction
    /// @param tokenCollateralAddress The ERC20 token address of the collateral being withdrawn
    /// @param amountCollateral The amount of collateral being withdrawn
    /// @param amountDscToBurn The amount of DSC to burn
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Redeems collateral from the protocol
    /// @param tokenCollateralAddress The ERC20 token address of the collateral being redeemed
    /// @param amountCollateral The amount of collateral being redeemed
    /// @notice This function will redeem your collateral.
    /// @notice If you have DSC minted, you will not be able to redeem until you burn your DSC
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Burns DSC to reduce user's debt without redeeming collateral
    /// @param amount The amount of DSC to burn
    /// @dev This function can be used if you're concerned about potential liquidation and want to reduce debt while keeping collateral deposited
    function burnDsc(uint256 amount) external moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    /// @notice Liquidates an undercollateralized position
    /// @param collateral The ERC20 token address of the collateral being liquidated
    /// @param user The address of the user whose position is being liquidated
    /// @param debtToCover The amount of DSC debt to cover during liquidation
    /// @dev To liquidate, you must burn DSC to pay off the user's debt, and in return you receive collateral at a discount
    /// @dev You can partially liquidate a user
    /// @dev Liquidators receive a 10% bonus for taking on the risk of liquidation
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    )
        external
        isAllowedToken(collateral)
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // If covering 100 DSC, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // Burn DSC equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////
    // Public Functions
    ///////////////////
    /// @notice Mints DSC stablecoins against deposited collateral
    /// @param amountDscToMint The amount of DSC to mint
    /// @dev You can only mint DSC if you have sufficient collateral to maintain the required health factor
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if (minted != true) {
            revert DSCEngine__MintFailed();
        }
    }

    /// @notice Deposits collateral into the protocol
    /// @param tokenCollateralAddress The ERC20 token address of the collateral being deposited
    /// @param amountCollateral The amount of collateral being deposited
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    ///////////////////
    // Private Functions
    ///////////////////
    /// @notice Internal function to redeem collateral and transfer it to the specified address
    /// @param tokenCollateralAddress The address of the collateral token
    /// @param amountCollateral The amount of collateral to redeem
    /// @param from The address from which to deduct collateral
    /// @param to The address to which to send the collateral
    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    )
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /// @notice Internal function to burn DSC and update user's debt
    /// @param amountDscToBurn The amount of DSC to burn
    /// @param onBehalfOf The address whose DSC debt will be reduced
    /// @param dscFrom The address from which to transfer DSC for burning
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;

        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        // This conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////

    /// @notice Internal function to get account information (total DSC minted and collateral value)
    /// @param user The address of the user to get information for
    /// @return totalDscMinted The total amount of DSC minted by the user
    /// @return collateralValueInUsd The total value of collateral in USD terms
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /// @notice Internal function to calculate the health factor for a user
    /// @param user The address of the user to calculate health factor for
    /// @return The health factor value (higher is safer)
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /// @notice Internal function to get the USD value of a given amount of tokens
    /// @param token The address of the token
    /// @param amount The amount of tokens
    /// @return The USD value of the tokens
    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /// @notice Internal function to calculate the health factor
    /// @param totalDscMinted The total amount of DSC minted
    /// @param collateralValueInUsd The total value of collateral in USD
    /// @return The calculated health factor
    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /// @notice Internal function to revert if a user's health factor is below the minimum
    /// @param user The address of the user to check
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    /// @notice Calculates the health factor for given DSC minted and collateral value
    /// @param totalDscMinted The total amount of DSC minted
    /// @param collateralValueInUsd The total value of collateral in USD
    /// @return The calculated health factor
    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /// @notice Gets account information for a user (total DSC minted and collateral value)
    /// @param user The address of the user
    /// @return totalDscMinted The total amount of DSC minted by the user
    /// @return collateralValueInUsd The total value of collateral in USD terms
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    /// @notice Gets the USD value of a given amount of tokens
    /// @param token The address of the token
    /// @param amount The amount of tokens
    /// @return The USD value of the tokens
    function getUsdValue(
        address token,
        uint256 amount // in WEI
    )
        external
        view
        returns (uint256)
    {
        return _getUsdValue(token, amount);
    }

    /// @notice Gets the collateral balance of a user for a specific token
    /// @param user The address of the user
    /// @param token The address of the collateral token
    /// @return The amount of collateral deposited by the user
    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    /// @notice Gets the total value of all collateral deposited by a user
    /// @param user The address of the user
    /// @return totalCollateralValueInUsd The total value of all collateral in USD terms
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /// @notice Calculates the token amount needed for a given USD value
    /// @param token The address of the token
    /// @param usdAmountInWei The USD amount in wei
    /// @return The required amount of tokens
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    /// @notice Gets the precision constant used in calculations
    /// @return The precision value
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    /// @notice Gets the additional feed precision constant
    /// @return The additional feed precision value
    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    /// @notice Gets the liquidation threshold percentage
    /// @return The liquidation threshold value
    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    /// @notice Gets the liquidation bonus percentage
    /// @return The liquidation bonus value
    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    /// @notice Gets the liquidation precision constant
    /// @return The liquidation precision value
    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    /// @notice Gets the minimum health factor required
    /// @return The minimum health factor value
    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    /// @notice Gets the list of supported collateral tokens
    /// @return Array of collateral token addresses
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    /// @notice Gets the address of the DSC contract
    /// @return The DSC contract address
    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    /// @notice Gets the price feed address for a collateral token
    /// @param token The address of the collateral token
    /// @return The price feed address
    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    /// @notice Gets the health factor for a specific user
    /// @param user The address of the user
    /// @return The health factor value
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
