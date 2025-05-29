//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DiFiStableCoin} from "./DiFiStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/**
 * @title DSCEngine
 * @author  Christian Inyekaka
 * The system is designed to be a minamal as possible ,and have the tokens maintain a 1 token ==1$ peg.
 * -Exogenous Collateral
 * -Dollar pegged stablecoin
 * - Algorithmic stablecoin
 * it's simillar to DAI if it had no governace,no fees and wa only backed by WETH and WBTC
 * @notice this contract is the core of the DSC system.it handles all the logic for minting and redeeming DSC,as well as depositing & withdrawing collateral.
 * @notice this contract is very loosely based on the MakerDAO DSS(DAI) system
 * our DSC system should always be overcollateralized. at no point ,should the value of all collateral <== the $ backed value of all the DSC
 */

contract DSCEngine is ReentrancyGuard {
    //////////////////////////////////////////////////////////////
    //errors
    /////////////////////////////////////////////////////////////
    error DSCEngine__NotZeroAddress();
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__NotEnoughCollateral();
    error DSCEngine__NotEnoughDSC();
    error DSCEngine__NotOwner();
    error DSCEngine__TransferFailed();
    error DSCEngine__NotAllowedToken(address token);
    error DSCEngine__TokenAddressMismatchInLength();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    //events
    // event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    // event CollateralWithdrawn(address indexed user, address indexed token, uint256 amount);
    // event DSCMinted(address indexed user, uint256 amount);
    // event DSCBurned(address indexed user, uint256 amount);
    //////////////////////////////////////////////////////////////
    //state variables//
    /////////////////////////////////////////////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds;
    address private s_dcsAddress;
    DiFiStableCoin private immutable i_dsc;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    /////////////////////////////////////////////////////////////////
    //events//
    /////////////////////////////////////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);
    /////////////////////////////////////////////////////////////////////
    //modifiers//
    /////////////////////////////////////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenCollateralAddress) {
        if (s_priceFeeds[tokenCollateralAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken(tokenCollateralAddress);
        }
        _;
    }
    /////////////////////////////////////////////////////////////////
    // Functions//
    /////////////////////////////////////////////////////////////

    constructor(address[] memory tokenAddress, address[] memory priceFeedAddresses, address _dcsAddress) {
        //USD price feeds
        if (tokenAddress.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressMismatchInLength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        s_dcsAddress = _dcsAddress;
        i_dsc = DiFiStableCoin(_dcsAddress);
    }
    //////////////////////////////////////////////////////////////
    //external functions//
    /////////////////////////////////////////////////////////////
    /*
    * @param tokenCollateralAddress: the address of the token to deposit as collateral
    * @param amountCollateral: The amount of collateral to deposit
    * @param amountDscToMint: The amount of DecentralizedStableCoin to mint
    * @notice: This function will deposit your collateral and mint DSC in one transaction
    */

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) public {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amount)
        public
        moreThanZero(amount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amount);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
    /*
    * @param tokenCollateralAddress: the collateral address to redeem
    * @param amountCollateral: amount of collateral to redeem
    * @param amountDscToBurn: amount of DSC to burn
    * This function burns DSC and redeems underlying collateral in one transaction
    */

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
         _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }
    /*
     * @Param amountDscToMInt: The amount of DSC to mint
     * You can only mint DSC if you have enough collateral
     */

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_dsc.mint(msg.sender, amountDscToMint);
        if (!success) {
            revert DSCEngine__MintFailed();
        }
    }

    function withdrawCollateral() external {}

    function burnDsc(uint256 amount) public moreThanZero(amount) {
      _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    /*
    * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
    * This is collateral that you're going to take from the user who is insolvent.
    * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
    * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
    * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
    *
    * @notice: You can partially liquidate a user.
    * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
    * For example, if the price of the collateral plummeted before anyone could be liquidated.
    */

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor > MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered + bonusCollateral;
         _redeemCollateral(collateral, totalCollateralRedeemed, user, msg.sender);
          _burnDsc(debtToCover, user, msg.sender);
           uint256 endingUserHealthFactor = _healthFactor(user);
    if(endingUserHealthFactor <= startingUserHealthFactor){
        revert DSCEngine__HealthFactorNotImproved();
    }

    _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getHealthFactor() external view {}

    ///////////////////////////////////////////
    //   Private & Internal View Functions   //
    ///////////////////////////////////////////

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
    s_DSCMinted[onBehalfOf] -= amountDscToBurn;

    bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
    // This conditional is hypothetically unreachable
    if (!success) {
        revert DSCEngine__TransferFailed();
    }
    i_dsc.burn(amountDscToBurn);
}
    /*
    * Returns how close to liquidation a user is
    * If a user goes below 1, then they can be liquidated.
    */

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
    s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
    bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
    if(!success){
        revert DSCEngine__TransferFailed();
    }
}
    //////////////////////////////////////////
    //   Public & External View Functions   //
    //////////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 totalCollateralValueInUsd = 0;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION);
    }
}
