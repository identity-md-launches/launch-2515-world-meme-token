// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {WorldMemeToken} from "../src/WorldMemeToken.sol";

/// @title Deploy script for World Meme Token
/// @notice Reviewable reference deployment. The IdentityMD launch does not run this script: its
/// factory deploys the token from the attested bytecode, and the token mints the whole supply to
/// that factory. This script exists for dry runs on a local fork and for independent reviewers.
/// @dev The token takes no constructor arguments, so there is nothing to read from the environment.
/// `deploy()` is the function the tests call directly.
contract DeployWorldMemeToken is Script {
    /// @notice Deploys the token. Whoever broadcasts the transaction receives the whole supply.
    function run() external returns (WorldMemeToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }

    /// @notice The deployment itself, separated so tests can call it without broadcasting.
    function deploy() public returns (WorldMemeToken token) {
        token = new WorldMemeToken();
    }
}
