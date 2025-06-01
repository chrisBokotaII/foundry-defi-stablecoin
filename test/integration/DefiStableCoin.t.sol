// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DiFiStableCoin} from "../../src/DiFiStableCoin.sol"; // Adjust the path as needed

contract DiFiStableCoinTest is Test {
    DiFiStableCoin stableCoin;
    address owner = address(this);
    address user = address(1);

    function setUp() public {
        stableCoin = new DiFiStableCoin();
    }

    // ------------------ Mint ------------------

    function testMintSuccess() public {
        uint256 amount = 1000e18;
        bool success = stableCoin.mint(user, amount);
        assertTrue(success);
        assertEq(stableCoin.balanceOf(user), amount);
    }

    function testMintFailsIfToIsZero() public {
        vm.expectRevert(DiFiStableCoin.DiFiStableCoin__NotZeroAddress.selector);
        stableCoin.mint(address(0), 1000e18);
    }

    function testMintFailsIfAmountIsZero() public {
        vm.expectRevert(DiFiStableCoin.DiFiStableCoin__MustBeMoreThanZero.selector);
        stableCoin.mint(user, 0);
    }

    // ------------------ Burn ------------------

    function testBurnSuccess() public {
        uint256 amount = 500e18;
        stableCoin.mint(owner, amount);
        stableCoin.burn(amount / 2);
        assertEq(stableCoin.balanceOf(owner), amount / 2);
    }

    function testBurnFailsIfNotEnoughBalance() public {
        stableCoin.mint(owner, 100e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                DiFiStableCoin.DiFiStableCoin__InsufficientBalance.selector,
                100e18,
                200e18
            )
        );
        stableCoin.burn(200e18);
    }

    function testBurnFailsIfZeroAmount() public {
        stableCoin.mint(owner, 100e18);
        vm.expectRevert(DiFiStableCoin.DiFiStableCoin__MustBeMoreThanZero.selector);
        stableCoin.burn(0);
    }

    // ------------------ Ownership ------------------

    function testOnlyOwnerCanMint() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        stableCoin.mint(user, 1000e18);
    }

    function testOnlyOwnerCanBurn() public {
        stableCoin.mint(owner, 1000e18);
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        stableCoin.burn(100e18);
    }

// ------------------ Total Supply ------------------

    function testTotalSupplyAfterMint() public {
        uint256 initialSupply = stableCoin.totalSupply();
        stableCoin.mint(user, 1000e18);
        assertEq(stableCoin.totalSupply(), initialSupply + 1000e18);
    }

    function testTotalSupplyAfterBurn() public {
        stableCoin.mint(owner, 1000e18);
        uint256 initialSupply = stableCoin.totalSupply();
        stableCoin.burn(500e18);
        assertEq(stableCoin.totalSupply(), initialSupply - 500e18);
    }

// ------------------ Balance Of ------------------

    function testBalanceOf() public {
        stableCoin.mint(user, 1000e18);
        assertEq(stableCoin.balanceOf(user), 1000e18);
        assertEq(stableCoin.balanceOf(owner), 0);
    }

    function testBalanceOfAfterBurn() public {
        stableCoin.mint(owner, 1000e18);
        stableCoin.burn(500e18);
        assertEq(stableCoin.balanceOf(owner), 500e18);
    }
}