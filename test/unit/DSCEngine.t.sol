//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DeployDefiStableCoin} from "../../script/DeployDefiStableCoin.s.sol";
import {DiFiStableCoin} from "../../src/DiFiStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";

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
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function setUp() external {
        deployer = new DeployDefiStableCoin();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
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

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressMismatchInLength.selector);
        DSCEngine testEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testGetUsdValue() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedWeth, actualWeth);
    }

    function testDepositCollateralAndGetUserInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getUserInformation(USER);
        console.log("Total Collateral Value in USD: ", collateralValueInUsd);
        console.log("Total DSC Minted: ", totalDscMinted);
        uint256 expectedTotalDscMinted = 0;
        assertEq(totalDscMinted, expectedTotalDscMinted);
        uint256 expectedCollateralValueInUsd = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(AMOUNT_COLLATERAL, expectedCollateralValueInUsd);
    }

    function testGetPrecision() public view {
        uint256 precision = dscEngine.getPrecision();
        console.log("Precision: ", precision);
        assertEq(precision, 1e18); // Default precision for most ERC20 tokens
    }

    function testGetAdditionalFeedPrecision() public view {
        uint256 additionalFeedPrecision = dscEngine.getAdditionalFeedPrecision();
        console.log("Additional Feed Precision: ", additionalFeedPrecision);
        assertEq(additionalFeedPrecision, 1e10); // Default precision for price feeds like Chainlink
    }
}
