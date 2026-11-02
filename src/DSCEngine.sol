// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";

/// @title DSCEngine
/// @notice Manages collateral, DSC issuance, liquidation, and protocol risk controls.
/// @dev Uses decimal-aware pricing, asymmetric pause controls, delayed risk updates, and explicit
///      bad-debt accounting. The engine must own the DSC token before processing user positions.
contract DSCEngine is ReentrancyGuard, Pausable, Ownable2Step {
    using OracleLib for AggregatorV3Interface;

    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__InvalidParameter();
    error DSCEngine__ZeroAddress();
    error DSCEngine__DuplicateCollateral(address token);
    error DSCEngine__UnsupportedDecimals(address asset, uint8 decimals);
    error DSCEngine__NotGuardianOrOwner();
    error DSCEngine__NoPendingRiskChange();
    error DSCEngine__RiskChangeNotReady(uint256 readyAt);
    error DSCEngine__RiskChangeMismatch();
    error DSCEngine__NoLiquidatableCollateral();
    error DSCEngine__AmountExceedsBadDebt(uint256 requested, uint256 available);

    struct CollateralConfig {
        address priceFeed;
        uint96 heartbeat;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
        uint8 tokenDecimals;
        uint8 feedDecimals;
        bool enabled;
    }

    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant DEFAULT_LIQUIDATION_THRESHOLD = 50;
    uint256 private constant DEFAULT_LIQUIDATION_BONUS = 10;
    uint256 private constant DEFAULT_HEARTBEAT = 3 hours;
    uint256 private constant MIN_RISK_THRESHOLD = 10;
    uint256 private constant MAX_RISK_THRESHOLD = 80;
    uint256 private constant MAX_LIQUIDATION_BONUS = 20;
    uint256 public constant RISK_CHANGE_DELAY = 48 hours;

    uint256 private s_minHealthFactor = 1e18;
    uint256 private s_totalActiveDebt;
    uint256 private s_badDebt;
    address private s_guardian;
    bytes32 private s_pendingRiskChange;
    uint256 private s_pendingRiskChangeEta;

    mapping(address collateralToken => CollateralConfig config) private s_collateralConfigs;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DSCMinted;
    address[] private s_collateralTokens;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed token, uint256 amount
    );
    event DscMinted(address indexed user, uint256 amount);
    event DscBurned(address indexed payer, address indexed onBehalfOf, uint256 amount);
    event Liquidated(
        address indexed liquidator,
        address indexed user,
        address indexed collateral,
        uint256 debtCovered,
        uint256 collateralSeized
    );
    event BadDebtRealized(address indexed user, uint256 amount);
    event BadDebtCovered(address indexed payer, uint256 amount);
    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);
    event RiskChangeScheduled(bytes32 indexed changeHash, uint256 readyAt);
    event RiskChangeCancelled(bytes32 indexed changeHash);
    event RiskParametersUpdated(uint256 liquidationThreshold, uint256 liquidationBonus, uint256 minHealthFactor);

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert DSCEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (!s_collateralConfigs[token].enabled) revert DSCEngine__TokenNotAllowed(token);
        _;
    }

    modifier onlyGuardianOrOwner() {
        if (msg.sender != owner() && msg.sender != s_guardian) revert DSCEngine__NotGuardianOrOwner();
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        if (dscAddress == address(0)) revert DSCEngine__ZeroAddress();

        for (uint256 i; i < tokenAddresses.length; ++i) {
            address token = tokenAddresses[i];
            address feed = priceFeedAddresses[i];
            if (token == address(0) || feed == address(0)) revert DSCEngine__ZeroAddress();
            if (s_collateralConfigs[token].enabled) revert DSCEngine__DuplicateCollateral(token);

            uint8 tokenDecimals = IERC20Metadata(token).decimals();
            uint8 feedDecimals = AggregatorV3Interface(feed).decimals();
            if (tokenDecimals > 18) revert DSCEngine__UnsupportedDecimals(token, tokenDecimals);
            if (feedDecimals > 18) revert DSCEngine__UnsupportedDecimals(feed, feedDecimals);

            s_collateralConfigs[token] = CollateralConfig({
                priceFeed: feed,
                heartbeat: uint96(DEFAULT_HEARTBEAT),
                liquidationThreshold: uint16(DEFAULT_LIQUIDATION_THRESHOLD),
                liquidationBonus: uint16(DEFAULT_LIQUIDATION_BONUS),
                tokenDecimals: tokenDecimals,
                feedDecimals: feedDecimals,
                enabled: true
            });
            s_collateralTokens.push(token);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    // -------------------------------------------------------------------------
    // Governance and emergency controls
    // -------------------------------------------------------------------------

    function setGuardian(address newGuardian) external onlyOwner {
        emit GuardianUpdated(s_guardian, newGuardian);
        s_guardian = newGuardian;
    }

    /// @notice Stops only risk-increasing actions (mint and collateral withdrawal).
    function pause() external onlyGuardianOrOwner {
        _pause();
    }

    /// @notice Recovery is owner-only so a compromised guardian cannot resume operations.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Queue a protocol-wide risk change behind a 48-hour review window.
    function scheduleRiskParameters(
        uint256 newThreshold,
        uint256 newBonus,
        uint256 newMinHealthFactor
    )
        external
        onlyOwner
    {
        _validateRiskParameters(newThreshold, newBonus, newMinHealthFactor);
        bytes32 changeHash = keccak256(abi.encode(newThreshold, newBonus, newMinHealthFactor));
        s_pendingRiskChange = changeHash;
        s_pendingRiskChangeEta = block.timestamp + RISK_CHANGE_DELAY;
        emit RiskChangeScheduled(changeHash, s_pendingRiskChangeEta);
    }

    function cancelRiskParameters() external onlyOwner {
        bytes32 changeHash = s_pendingRiskChange;
        if (changeHash == bytes32(0)) revert DSCEngine__NoPendingRiskChange();
        delete s_pendingRiskChange;
        delete s_pendingRiskChangeEta;
        emit RiskChangeCancelled(changeHash);
    }

    function executeRiskParameters(
        uint256 newThreshold,
        uint256 newBonus,
        uint256 newMinHealthFactor
    )
        external
        onlyOwner
    {
        bytes32 changeHash = s_pendingRiskChange;
        if (changeHash == bytes32(0)) revert DSCEngine__NoPendingRiskChange();
        if (block.timestamp < s_pendingRiskChangeEta) {
            revert DSCEngine__RiskChangeNotReady(s_pendingRiskChangeEta);
        }
        if (changeHash != keccak256(abi.encode(newThreshold, newBonus, newMinHealthFactor))) {
            revert DSCEngine__RiskChangeMismatch();
        }
        _validateRiskParameters(newThreshold, newBonus, newMinHealthFactor);

        for (uint256 i; i < s_collateralTokens.length; ++i) {
            CollateralConfig storage config = s_collateralConfigs[s_collateralTokens[i]];
            config.liquidationThreshold = uint16(newThreshold);
            config.liquidationBonus = uint16(newBonus);
        }
        s_minHealthFactor = newMinHealthFactor;
        delete s_pendingRiskChange;
        delete s_pendingRiskChangeEta;
        emit RiskParametersUpdated(newThreshold, newBonus, newMinHealthFactor);
    }

    /// @notice Complete the DSC token's two-step transfer to this engine.
    function acceptDscOwnership() external onlyOwner {
        i_dsc.acceptOwnership();
    }

    // -------------------------------------------------------------------------
    // User actions
    // -------------------------------------------------------------------------

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

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        whenNotPaused
        nonReentrant
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        whenNotPaused
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Repayment remains available during a pause.
    function burnDsc(uint256 amount) external moreThanZero(amount) nonReentrant {
        _burnDsc(amount, msg.sender, msg.sender);
    }

    /// @notice Burns circulating DSC against protocol bad debt.
    function coverBadDebt(uint256 amount) external moreThanZero(amount) nonReentrant {
        if (amount > s_badDebt) revert DSCEngine__AmountExceedsBadDebt(amount, s_badDebt);
        s_badDebt -= amount;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        if (!success) revert DSCEngine__TransferFailed();
        i_dsc.burn(amount);
        emit BadDebtCovered(msg.sender, amount);
    }

    /// @notice Liquidation remains available during a pause to prevent hidden insolvency.
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
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= s_minHealthFactor) revert DSCEngine__HealthFactorOk();

        uint256 requestedDebt = Math.min(debtToCover, s_DSCMinted[user]);
        (uint256 actualDebtCovered, uint256 collateralSeized) = _liquidationQuote(collateral, user, requestedDebt);
        if (actualDebtCovered == 0 || collateralSeized == 0) revert DSCEngine__NoLiquidatableCollateral();

        _redeemCollateral(collateral, collateralSeized, user, msg.sender);
        _burnDsc(actualDebtCovered, user, msg.sender);

        bool selectedCollateralExhausted = s_collateralDeposited[user][collateral] == 0;
        _settleLiquidation(user, startingHealthFactor, selectedCollateralExhausted);

        emit Liquidated(msg.sender, user, collateral, actualDebtCovered, collateralSeized);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) whenNotPaused nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        s_totalActiveDebt += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) revert DSCEngine__MintFailed();
        emit DscMinted(msg.sender, amountDscToMint);
    }

    /// @notice Credits the measured balance delta, not a caller-supplied nominal amount.
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        uint256 balanceBefore = IERC20(tokenCollateralAddress).balanceOf(address(this));
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();
        uint256 received = IERC20(tokenCollateralAddress).balanceOf(address(this)) - balanceBefore;
        if (received == 0) revert DSCEngine__TransferFailed();

        s_collateralDeposited[msg.sender][tokenCollateralAddress] += received;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, received);
    }

    // -------------------------------------------------------------------------
    // Internal accounting
    // -------------------------------------------------------------------------

    function _redeemCollateral(address token, uint256 amount, address from, address to) private {
        s_collateralDeposited[from][token] -= amount;
        emit CollateralRedeemed(from, to, token, amount);
        bool success = IERC20(token).transfer(to, amount);
        if (!success) revert DSCEngine__TransferFailed();
    }

    function _burnDsc(uint256 amount, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amount;
        s_totalActiveDebt -= amount;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amount);
        if (!success) revert DSCEngine__TransferFailed();
        i_dsc.burn(amount);
        emit DscBurned(dscFrom, onBehalfOf, amount);
    }

    function _liquidationQuote(
        address collateral,
        address user,
        uint256 requestedDebt
    )
        private
        view
        returns (uint256 actualDebtCovered, uint256 collateralSeized)
    {
        uint256 collateralBalance = s_collateralDeposited[user][collateral];
        uint256 bonus = s_collateralConfigs[collateral].liquidationBonus;
        uint256 requestedBaseCollateral = getTokenAmountFromUsd(collateral, requestedDebt);
        uint256 requestedCollateral =
            Math.mulDiv(requestedBaseCollateral, LIQUIDATION_PRECISION + bonus, LIQUIDATION_PRECISION);

        if (requestedCollateral <= collateralBalance) return (requestedDebt, requestedCollateral);

        collateralSeized = collateralBalance;
        actualDebtCovered = Math.mulDiv(
            _getUsdValue(collateral, collateralSeized), LIQUIDATION_PRECISION, LIQUIDATION_PRECISION + bonus
        );
        actualDebtCovered = Math.min(actualDebtCovered, requestedDebt);
    }

    function _settleLiquidation(address user, uint256 startingHealthFactor, bool selectedCollateralExhausted) private {
        uint256 remainingDebt = s_DSCMinted[user];
        if (remainingDebt == 0) return;
        if (!_hasCollateral(user)) {
            s_DSCMinted[user] = 0;
            s_totalActiveDebt -= remainingDebt;
            s_badDebt += remainingDebt;
            emit BadDebtRealized(user, remainingDebt);
            return;
        }
        // Deeply underwater positions can become temporarily less healthy as a collateral type is
        // exhausted. Allow that progress so a later liquidation can clear the remaining collateral
        // and realize the residual debt instead of permanently freezing the position.
        if (selectedCollateralExhausted) return;
        if (_healthFactor(user) <= startingHealthFactor) revert DSCEngine__HealthFactorNotImproved();
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        uint256 debt = s_DSCMinted[user];
        if (debt == 0) return type(uint256).max;
        return Math.mulDiv(_getRiskAdjustedCollateralValue(user), PRECISION, debt);
    }

    function _getRiskAdjustedCollateralValue(address user) private view returns (uint256 adjustedValue) {
        for (uint256 i; i < s_collateralTokens.length; ++i) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount == 0) continue;
            CollateralConfig memory config = s_collateralConfigs[token];
            adjustedValue += Math.mulDiv(
                _getUsdValue(token, amount), config.liquidationThreshold, LIQUIDATION_PRECISION
            );
        }
    }

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        if (amount == 0) return 0;
        CollateralConfig memory config = s_collateralConfigs[token];
        AggregatorV3Interface feed = AggregatorV3Interface(config.priceFeed);
        (, int256 answer,,,) = feed.staleCheckLatestRoundData(config.heartbeat);
        uint256 normalizedPrice = Math.mulDiv(uint256(answer), PRECISION, 10 ** config.feedDecimals);
        return Math.mulDiv(amount, normalizedPrice, 10 ** config.tokenDecimals);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 adjusted = Math.mulDiv(collateralValueInUsd, DEFAULT_LIQUIDATION_THRESHOLD, LIQUIDATION_PRECISION);
        return Math.mulDiv(adjusted, PRECISION, totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < s_minHealthFactor) revert DSCEngine__BreaksHealthFactor(healthFactor);
    }

    function _hasCollateral(address user) private view returns (bool) {
        for (uint256 i; i < s_collateralTokens.length; ++i) {
            if (s_collateralDeposited[user][s_collateralTokens[i]] != 0) return true;
        }
        return false;
    }

    function _validateRiskParameters(uint256 threshold, uint256 bonus, uint256 minHealthFactor) private pure {
        if (
            threshold < MIN_RISK_THRESHOLD || threshold > MAX_RISK_THRESHOLD || bonus > MAX_LIQUIDATION_BONUS
                || minHealthFactor < PRECISION || minHealthFactor > 2 * PRECISION
                || threshold * (LIQUIDATION_PRECISION + bonus) >= LIQUIDATION_PRECISION * LIQUIDATION_PRECISION
        ) revert DSCEngine__InvalidParameter();
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

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

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getUsdValue(address token, uint256 amount) external view isAllowedToken(token) returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i; i < s_collateralTokens.length; ++i) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount == 0) continue;
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    )
        public
        view
        isAllowedToken(token)
        returns (uint256)
    {
        CollateralConfig memory config = s_collateralConfigs[token];
        AggregatorV3Interface feed = AggregatorV3Interface(config.priceFeed);
        (, int256 answer,,,) = feed.staleCheckLatestRoundData(config.heartbeat);
        uint256 normalizedPrice = Math.mulDiv(uint256(answer), PRECISION, 10 ** config.feedDecimals);
        return Math.mulDiv(usdAmountInWei, 10 ** config.tokenDecimals, normalizedPrice);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    /// @dev Legacy compatibility only. Pricing no longer depends on this 8-decimal assumption.
    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return 1e10;
    }

    function getLiquidationThreshold() external view returns (uint256) {
        if (s_collateralTokens.length == 0) return DEFAULT_LIQUIDATION_THRESHOLD;
        return s_collateralConfigs[s_collateralTokens[0]].liquidationThreshold;
    }

    function getLiquidationBonus() external view returns (uint256) {
        if (s_collateralTokens.length == 0) return DEFAULT_LIQUIDATION_BONUS;
        return s_collateralConfigs[s_collateralTokens[0]].liquidationBonus;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external view returns (uint256) {
        return s_minHealthFactor;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_collateralConfigs[token].priceFeed;
    }

    function getCollateralConfig(address token) external view returns (CollateralConfig memory) {
        return s_collateralConfigs[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getGuardian() external view returns (address) {
        return s_guardian;
    }

    function getBadDebt() external view returns (uint256) {
        return s_badDebt;
    }

    function getTotalActiveDebt() external view returns (uint256) {
        return s_totalActiveDebt;
    }

    function getTotalAccountedDebt() external view returns (uint256) {
        return s_totalActiveDebt + s_badDebt;
    }

    function getPendingRiskChange() external view returns (bytes32 changeHash, uint256 readyAt) {
        return (s_pendingRiskChange, s_pendingRiskChangeEta);
    }
}
