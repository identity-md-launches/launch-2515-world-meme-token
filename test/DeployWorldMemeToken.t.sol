// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployWorldMemeToken} from "../script/DeployWorldMemeToken.s.sol";
import {WorldMemeToken} from "../src/WorldMemeToken.sol";

/// @notice The deploy script's `deploy()` is called directly, without broadcasting and without any
/// environment, so the test passes in any order, in parallel and with an empty environment.
contract DeployWorldMemeTokenTest is Test {
    function test_deployMintsSupplyToTheScriptContract() public {
        DeployWorldMemeToken deployScript = new DeployWorldMemeToken();
        WorldMemeToken token = deployScript.deploy();
        assertEq(token.name(), "World Meme Token");
        assertEq(token.symbol(), "WORLD");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000_000 * 1e18);
        // `new` inside the script makes the script contract the deployer, so it holds the supply.
        assertEq(token.balanceOf(address(deployScript)), token.totalSupply());
    }
}
