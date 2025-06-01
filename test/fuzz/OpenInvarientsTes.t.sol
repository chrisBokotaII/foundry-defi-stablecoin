// //SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;
// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {DeployDefiStableCoin} from "../../script/DeployDefiStableCoin.s.sol";
// import {DiFiStableCoin} from "../../src/DiFiStableCoin.sol";
// import{IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// contract OpenInvariantsTest is  StdInvariant, Test{
// DeployDefiStableCoin deployer;
// DSCEngine dsce;
// DiFiStableCoin dsc;
// HelperConfig config;
// address weth;
// address wbtc;
//     function setUp() public {
//         // Set up any necessary state or variables for the invariants
//         // This could include deploying contracts, initializing variables, etc.
//     deployer = new DeployDefiStableCoin();
//     (dsc,dsce,config) = deployer.run();
//     (,,weth,wbtc,) = config.activeNetworkConfig();
//     targetContract(address(dsce));
        
//     }
//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view{
// uint256 totalSupply = dsc.totalSupply();
// uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
// uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
// uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
// uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);
// assert(wbtcValue+wbtcValue>=totalSupply);
//     }
// }