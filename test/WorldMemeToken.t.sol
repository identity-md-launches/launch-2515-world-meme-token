// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WorldMemeToken} from "../src/WorldMemeToken.sol";

/// @notice Stands in for the launch factory: deploys the token with `new` so the constructor's
/// `msg.sender` is this contract, exactly as it is when the factory deploys the token.
contract DeployerProbe {
    WorldMemeToken public token;

    function deploy() external returns (WorldMemeToken deployed) {
        deployed = new WorldMemeToken();
        token = deployed;
    }

    function send(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract WorldMemeTokenTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 * 1e18;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    WorldMemeToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SupplyMinted(address indexed deployer, uint256 amount);

    function setUp() public {
        vm.prank(deployer);
        token = new WorldMemeToken();
    }

    // ------------------------------------------------------------------
    // Metadata and supply
    // ------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "World Meme Token");
        assertEq(token.symbol(), "WORLD");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "World Meme Token");
        assertEq(token.TOKEN_SYMBOL(), "WORLD");
        assertEq(token.TOKEN_DECIMALS(), 18);
    }

    function test_supplyConstants() public view {
        assertEq(token.TOTAL_SUPPLY_WHOLE(), 1_000_000_000);
        assertEq(token.TOTAL_SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1e27);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_constructorEmitsMintAndSupplyEvents() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, EXPECTED_SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit SupplyMinted(alice, EXPECTED_SUPPLY);
        vm.prank(alice);
        new WorldMemeToken();
    }

    /// @dev The supply goes to whichever address runs the constructor, so a contract deployer (the
    /// launch factory) receives it, not whoever called that contract.
    function test_contractDeployerReceivesSupply() public {
        DeployerProbe probe = new DeployerProbe();
        vm.prank(alice);
        WorldMemeToken deployed = probe.deploy();
        assertEq(deployed.totalSupply(), EXPECTED_SUPPLY);
        assertEq(deployed.balanceOf(address(probe)), EXPECTED_SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    /// @dev Each deployment is independent: a second token does not touch the first.
    function test_secondDeploymentIsIndependent() public {
        vm.prank(bob);
        WorldMemeToken second = new WorldMemeToken();
        assertEq(second.balanceOf(bob), EXPECTED_SUPPLY);
        assertEq(second.balanceOf(deployer), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    // ------------------------------------------------------------------
    // Transfers
    // ------------------------------------------------------------------

    function test_transferMovesExactAmount() public {
        uint256 amount = 1_234_567 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, alice, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 5e18));
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_transferWholeBalance() public {
        vm.prank(deployer);
        token.transfer(alice, EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), EXPECTED_SUPPLY);
    }

    function test_RevertWhen_transferExceedsBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10e18, 11e18));
        vm.prank(alice);
        token.transfer(bob, 11e18);
    }

    function test_RevertWhen_transferFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transfer(alice, 1);
    }

    function test_RevertWhen_transferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1e18);
    }

    // ------------------------------------------------------------------
    // Allowances
    // ------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, alice, 42e18);
        vm.prank(deployer);
        assertTrue(token.approve(alice, 42e18));
        assertEq(token.allowance(deployer, alice), 42e18);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(deployer);
        token.approve(alice, 42e18);
        token.approve(alice, 7e18);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 7e18);
    }

    function test_RevertWhen_approveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 100e18);

        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, bob, 60e18);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 60e18));

        assertEq(token.balanceOf(bob), 60e18);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - 60e18);
        assertEq(token.allowance(deployer, alice), 40e18);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_transferFromWithInfiniteAllowanceDoesNotDecrease() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1e18);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_RevertWhen_transferFromExceedsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 10e18, 11e18));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 11e18);
    }

    function test_RevertWhen_transferFromWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
    }

    function test_RevertWhen_transferFromExceedsOwnerBalance() public {
        vm.prank(deployer);
        token.transfer(bob, 5e18);
        vm.prank(bob);
        token.approve(alice, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, 5e18, 6e18));
        vm.prank(alice);
        token.transferFrom(bob, carol, 6e18);
    }

    /// @dev Nobody, the deployer included, can pull a holder's tokens without that holder's approval.
    function test_RevertWhen_deployerPullsFromHolderWithoutApproval() public {
        vm.prank(deployer);
        token.transfer(alice, 5e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 5e18);
    }

    // ------------------------------------------------------------------
    // Fixed supply: no admin surface
    // ------------------------------------------------------------------

    /// @dev Every common mint or admin selector is absent. The call must fail and must change nothing,
    /// whether a stranger or the deployer sends it.
    function test_noAdminCallChangesSupplyOrBalances() public {
        address attacker = makeAddr("attacker");
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "pause()",
            "setMinter(address)",
            "burnFrom(address,uint256)",
            "blacklist(address)",
            "freeze(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);

            vm.prank(attacker);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("stranger call unexpectedly succeeded: ", signatures[i]));

            vm.prank(deployer);
            (ok,) = address(token).call(data);
            assertFalse(ok, string.concat("deployer call unexpectedly succeeded: ", signatures[i]));

            assertEq(token.totalSupply(), EXPECTED_SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY, signatures[i]);
        }
    }

    function test_RevertWhen_callingUnknownSelector() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok);
    }

    function test_RevertWhen_sendingEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "token must not accept ether");
        assertEq(address(token).balance, 0);
    }

    /// @dev The runtime must not reach DELEGATECALL, CALLCODE or SELFDESTRUCT, scanned the way the
    /// launch floor scans it: only opcodes execution can reach, skipping PUSH immediates.
    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ------------------------------------------------------------------
    // Launch flows: everything arrives whole
    // ------------------------------------------------------------------

    /// @dev The factory moves 10% to the distributor, the distributor pays a claimant, the factory
    /// forwards the remainder. No tax, so every leg arrives exactly and the supply is unchanged.
    function test_launchFlowsArriveWhole() public {
        DeployerProbe factory = new DeployerProbe();
        WorldMemeToken launched = factory.deploy();
        address distributor = makeAddr("distributor");
        address claimant = makeAddr("claimant");
        address remainderTo = makeAddr("remainderTo");

        uint256 swarm = (EXPECTED_SUPPLY * 1_000) / 10_000;
        uint256 pool = (EXPECTED_SUPPLY * 8_000) / 10_000;
        uint256 remainder = EXPECTED_SUPPLY - swarm - pool;

        assertTrue(factory.send(distributor, swarm));
        assertEq(launched.balanceOf(distributor), swarm);

        vm.prank(distributor);
        assertTrue(launched.transfer(claimant, swarm));
        assertEq(launched.balanceOf(claimant), swarm);
        assertEq(launched.balanceOf(distributor), 0);

        assertTrue(factory.send(remainderTo, remainder));
        assertEq(launched.balanceOf(remainderTo), remainder);
        assertEq(launched.balanceOf(address(factory)), pool);
        assertEq(launched.totalSupply(), EXPECTED_SUPPLY);
    }

    // ------------------------------------------------------------------
    // Fuzz: conservation of supply
    // ------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 amount) public {
        amount = bound(amount, EXPECTED_SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, EXPECTED_SUPPLY, amount)
        );
        vm.prank(deployer);
        token.transfer(alice, amount);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowanceAmount, uint256 spend) public {
        allowanceAmount = bound(allowanceAmount, 0, EXPECTED_SUPPLY);
        spend = bound(spend, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowanceAmount);

        vm.prank(alice);
        if (spend > allowanceAmount) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, allowanceAmount, spend)
            );
            token.transferFrom(deployer, bob, spend);
        } else {
            assertTrue(token.transferFrom(deployer, bob, spend));
            assertEq(token.balanceOf(bob), spend);
            assertEq(token.allowance(deployer, alice), allowanceAmount - spend);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    /// @dev A chain of transfers among several holders never creates or destroys tokens.
    function testFuzz_multiHopConservesSupply(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, EXPECTED_SUPPLY);
        b = bound(b, 0, a);
        c = bound(c, 0, b);
        vm.prank(deployer);
        token.transfer(alice, a);
        vm.prank(alice);
        token.transfer(bob, b);
        vm.prank(bob);
        token.transfer(carol, c);
        uint256 sum = token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(carol);
        assertEq(sum, EXPECTED_SUPPLY);
        assertEq(token.balanceOf(carol), c);
        assertEq(token.balanceOf(bob), b - c);
        assertEq(token.balanceOf(alice), a - b);
    }

    // ------------------------------------------------------------------
    // Interface
    // ------------------------------------------------------------------

    function test_implementsIERC20() public {
        IERC20 erc20 = IERC20(address(token));
        assertEq(erc20.totalSupply(), EXPECTED_SUPPLY);
        vm.prank(deployer);
        assertTrue(erc20.transfer(alice, 1));
        assertEq(erc20.balanceOf(alice), 1);
    }
}
