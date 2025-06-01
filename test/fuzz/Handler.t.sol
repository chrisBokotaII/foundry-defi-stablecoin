// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DiFiStableCoin} from "../../src/DiFiStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dsce;
    DiFiStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timeMintIsCalled;

    mapping(address => bool) public hasDeposited;
    address[] public usersWithCollateralDeposited;

    constructor(DSCEngine _engine, DiFiStableCoin _dsc) {
        dsce = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;

        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getUserInformation(sender);

        if (collateralValueInUsd <= totalDscMinted) return;

        uint256 maxDscToMint = (collateralValueInUsd / 2) - totalDscMinted;
        amount = bound(amount, 0, maxDscToMint);
        if (amount == 0) return;

        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
        timeMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        address user = address(
            uint160(uint256(keccak256(abi.encode(collateralSeed, amountCollateral))))
        );
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(user);
        collateral.mint(user, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        if (!hasDeposited[user]) {
            usersWithCollateralDeposited.push(user);
            hasDeposited[user] = true;
        }
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address user = msg.sender;
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), user);

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) return;

        vm.startPrank(user);
        dsce.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // Helper function
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        return collateralSeed % 2 == 0 ? weth : wbtc;
    }
}
