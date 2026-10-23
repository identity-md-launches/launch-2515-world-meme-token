// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {WorldMemeToken} from "src/WorldMemeToken.sol";
import {WorldMemeTokenHandler} from "./handlers/WorldMemeTokenHandler.sol";

/// @notice A closed set of holders makes both conservation and individual ownership observable.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract WorldMemeTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WorldMemeTokenHandler private handler;
    WorldMemeToken private token;

    function setUp() public {
        handler = new WorldMemeTokenHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.transferFromRaw.selector;
        selectors[4] = handler.transferAboveBalance.selector;
        selectors[5] = handler.transferFromAboveBalance.selector;
        selectors[6] = handler.transferToZero.selector;
        selectors[7] = handler.approveZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndMetadataRemainFixed() public view {
        assertEq(token.totalSupply(), SUPPLY, "constructor supply changed");
        assertEq(token.name(), "World Meme Token");
        assertEq(token.symbol(), "WORLD");
        assertEq(token.decimals(), 18);
        assertEq(token.balanceOf(address(0)), 0, "zero address acquired tokens");
    }

    function invariant_allBalancesSumToOriginalSupply() public view {
        uint256 sum = token.balanceOf(address(token));
        uint256 count = handler.ACTOR_COUNT();
        for (uint256 i; i < count; ++i) {
            uint256 balance = token.balanceOf(handler.actors(i));
            assertLe(balance, SUPPLY);
            sum += balance;
        }
        assertEq(sum, SUPPLY, "tokens were created, destroyed or sent outside the tracked set");
    }

    /// @dev Conservation alone misses moving tokens from the wrong payer or crediting the wrong
    /// recipient. Compare every balance with the ledger of authorized successful movements.
    function invariant_eachHolderOwnsExactlyItsAccountedTokens() public view {
        uint256 count = handler.ACTOR_COUNT();
        for (uint256 i; i < count; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "holder accounting mismatch");
        }
        assertEq(token.balanceOf(address(token)), handler.expectedBalance(address(token)), "token sink mismatch");
        assertEq(token.balanceOf(address(this)), 0, "test controller received unearned tokens");
    }

    /// @dev Covers overwrite, revoke, finite spend, infinite spend, unrelated pairs and rollback.
    function invariant_allowancesMatchOnlyOwnerAuthorizations() public view {
        uint256 count = handler.ACTOR_COUNT();
        for (uint256 i; i < count; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < count; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "approval changed without owner authorization or a successful spend"
                );
            }
        }
    }
}
