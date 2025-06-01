// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployDefiStableCoin} from "../../script/DeployDefiStableCoin.s.sol";
import {DiFiStableCoin} from "../../src/DiFiStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import{MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
contract DefiStableCoinTest is Test {
    DiFiStableCoin public dsc;
    DeployDefiStableCoin public deployer;
    DSCEngine public dscEngine;
    HelperConfig public helperConfig;

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 1000 ether; // $1000 worth of DSC
    uint256 public constant COLLATERAL_PRICE = 2000e8; // $2000 per WETH (Chainlink price feed format)

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }
    

    function setUp() external {
        deployer = new DeployDefiStableCoin();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
        // Mint DSC for user and liquidator
        vm.startPrank(address(dscEngine));
        dsc.mint(USER, AMOUNT_DSC_TO_MINT * 2); // Extra for safety
        dsc.mint(LIQUIDATOR, AMOUNT_DSC_TO_MINT * 2);
        vm.stopPrank();
        
        
    }

    /////////////////////////////
    // Constructor Tests //
    /////////////////////////////

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressMismatchInLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////////////
    // depositCollateral Tests //
    /////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfTokenNotAllowed() public {
        address randomToken = address(0x123);
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector, randomToken));
        dscEngine.depositCollateral(randomToken, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralSuccess() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = dscEngine.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, true);
        emit DSCEngine.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTransferFails() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL / 2);
        vm.expectRevert("ERC20: insufficient allowance");
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /////////////////////////////
    // depositCollateralAndMintDsc Tests //
    /////////////////////////////

    function testDepositCollateralAndMintDscSuccess() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getUserInformation(USER);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
        assertEq(collateralValueInUsd, AMOUNT_COLLATERAL * COLLATERAL_PRICE * 1e10 / 1e18);
    }

    function testRevertsIfMintBreaksHealthFactor() public {
        uint256 excessiveDsc = 20000 ether; // $20,000, equal to collateral value
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0.5e18));
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, excessiveDsc);
        vm.stopPrank();
    }

    /////////////////////////////
    // mintDsc Tests //
    /////////////////////////////

    function testMintDscSuccess() public depositedCollateral {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        (uint256 totalDscMinted,) = dscEngine.getUserInformation(USER);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
    }

    function testRevertsIfMintAmountZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfMintFails() public depositedCollateral {
        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(DiFiStableCoin.mint.selector),
            abi.encode(false)
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        dscEngine.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    /////////////////////////////
    // redeemCollateral Tests //
    /////////////////////////////

    function testRedeemCollateralSuccess() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = dscEngine.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, 0);
    }

    function testRedeemCollateralEmitsEvent() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true);
        emit DSCEngine.CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfHealthFactorBreaksOnRedeem() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /////////////////////////////
    // redeemCollateralForDsc Tests //
    /////////////////////////////

    function testRedeemCollateralForDscSuccess() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getUserInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
    }

    function testRevertsIfBurnFailsInRedeemForDsc() public depositedCollateralAndMintedDsc {
       vm.mockCall(
    address(dsc),
    abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(dscEngine), AMOUNT_DSC_TO_MINT),
    abi.encode(false)
);

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dscEngine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    /////////////////////////////
    // burnDsc Tests //
    /////////////////////////////

    function testBurnDscSuccess() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.burnDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        (uint256 totalDscMinted,) = dscEngine.getUserInformation(USER);
        assertEq(totalDscMinted, 0);
    }

    function testRevertsIfBurnAmountZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfBurnFails() public depositedCollateralAndMintedDsc {
        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(dscEngine), AMOUNT_DSC_TO_MINT),
            abi.encode(false)
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dscEngine.burnDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    /////////////////////////////
    // liquidate Tests //
    /////////////////////////////

    function testRevertsIfHealthFactorOk() public depositedCollateralAndMintedDsc {
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, USER, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

   

    /////////////////////////////
    // getHealthFactor Tests //
    /////////////////////////////

    function testGetHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        assertEq(healthFactor, 10e18);
    }

    function testHealthFactorMaxIfNoDscMinted() public depositedCollateral {
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        assertEq(healthFactor, type(uint256).max);
    }

    /////////////////////////////
    // View Function Tests //
    /////////////////////////////

    function testGetUsdValue() public view {
        uint256 usdAmount = 100 ether; // $100
        uint256 expectedWeth = 0.05 ether; // $100 / $2000 per WETH
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 collateralValueInUsd = dscEngine.getAccountCollateralValue(USER);
        uint256 expectedValue = AMOUNT_COLLATERAL * COLLATERAL_PRICE * 1e10 / 1e18;
        assertEq(collateralValueInUsd, expectedValue);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
        assertEq(collateralTokens[1], wbtc);
    }

    function testGetPriceFeedAddress() public view {
        address priceFeed = dscEngine.getPriceFeedAddress(weth);
        assertEq(priceFeed, wethUsdPriceFeed);
    }

    function testGetLiquidationThreshold() public view {
        uint256 threshold = dscEngine.getLiquidationThreshold();
        assertEq(threshold, 50);
    }

    function testGetLiquidationPrecision() public view {
        uint256 precision = dscEngine.getLiquidationPrecision();
        assertEq(precision, 100);
    }

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = dscEngine.getMinHealthFactor();
        assertEq(minHealthFactor, 1e18);
    }

    function testGetLiquidationBonus() public view {
        uint256 bonus = dscEngine.getLiquidationBonus();
        assertEq(bonus, 10);
    }

    function testGetCollateralBalanceOfUser() public depositedCollateral {
        uint256 balance = dscEngine.getCollateralBalanceOfUser(USER, weth);
        assertEq(balance, AMOUNT_COLLATERAL);
    }

    function testGetUserInformation() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getUserInformation(USER);
        uint256 expectedCollateralValueInUsd = AMOUNT_COLLATERAL * COLLATERAL_PRICE * 1e10 / 1e18;
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }


    
}