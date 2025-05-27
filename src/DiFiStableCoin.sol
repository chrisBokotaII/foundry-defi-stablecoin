// SPDX-License-Identifier: MIT
//SPDX-license-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DiFiStableCoin
 * @author  Christian Inyekaka
 * @notice A stablecoin contract for decentralized finance applications
 * Minting:Algorithmic stablecoin
 * Collateralization: Overcollateralized
 * Stability Mechanism: Pegged to a USD
 * Governance: by DSCEngine
 */
contract DiFiStableCoin is ERC20Burnable, Ownable {
    //errors
    error DiFiStableCoin__InsufficientBalance(uint256 balance, uint256 amount);
    error DiFiStableCoin__MustBeMoreThanZero();
    error DiFiStableCoin__NotZeroAddress();

    constructor() ERC20("DiFiStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DiFiStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DiFiStableCoin__InsufficientBalance(balance, _amount);
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DiFiStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DiFiStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
