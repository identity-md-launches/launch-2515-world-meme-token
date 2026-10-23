// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title World Meme Token (WORLD)
/// @notice A fixed-supply ERC-20. The whole supply is minted once, to the deployer, in the
/// constructor. There is no owner, no minter, no pause, no blacklist, no tax and no burn hook:
/// after deployment the contract has no privileged functions at all, and the supply can never
/// change.
/// @dev Built on OpenZeppelin's audited ERC20 (v5.1.0). The contract name is kept short so a launch
/// manifest can record it; the long name is what `name()` returns.
contract WorldMemeToken is ERC20 {
    /// @notice Token name, as returned by `name()`.
    string public constant TOKEN_NAME = "World Meme Token";

    /// @notice Token symbol, as returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "WORLD";

    /// @notice Number of decimals, as returned by `decimals()`.
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @notice Whole-token supply before scaling by decimals: one billion.
    uint256 public constant TOTAL_SUPPLY_WHOLE = 1_000_000_000;

    /// @notice The fixed total supply in minor units (1,000,000,000 * 10**18).
    uint256 public constant TOTAL_SUPPLY = TOTAL_SUPPLY_WHOLE * 10 ** TOKEN_DECIMALS;

    /// @notice Emitted once, at deployment, recording who received the entire supply.
    /// @param deployer The address the supply was minted to (`msg.sender` of the constructor).
    /// @param amount The amount minted, always `TOTAL_SUPPLY`.
    event SupplyMinted(address indexed deployer, uint256 amount);

    /// @notice Mints the full supply to `msg.sender` (the deployer). Takes no arguments and makes
    /// no external calls, so it deploys on an empty chain from any deployer.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return TOKEN_DECIMALS;
    }
}
