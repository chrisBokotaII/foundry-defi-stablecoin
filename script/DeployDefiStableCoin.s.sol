// SPDX-License-Identifier: MIT 
// SPDX-license-identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {DiFiStableCoin} from "../src/DiFiStableCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";

contract DeployDefiStableCoin is Script {
    DiFiStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public helperConfig;
    address[] public tokenAddresses;
address[] public priceFeedAddresses;
    function run() external returns (DiFiStableCoin, DSCEngine, HelperConfig) {
        helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
       tokenAddresses = [weth, wbtc];
    priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

    vm.startBroadcast();
    dsc = new DiFiStableCoin();
    DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
     dsc.transferOwnership(address(engine));
    vm.stopBroadcast();
    return (dsc, engine,helperConfig);
    }
}