// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WorldMemeToken} from "src/WorldMemeToken.sol";

/// @notice Drives real ERC-20 calls; balances and approvals are tracked from requested actions,
/// never copied from the token's getters. All possible recipients belong to the tracked set.
contract WorldMemeTokenHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant ACTOR_COUNT = 4;
    WorldMemeToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new WorldMemeToken();
        actors[0] = address(this);
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
        expectedBalance[address(this)] = SUPPLY;

        // Real constructor mint and transfers only: no token balance/storage cheatcodes.
        for (uint256 i = 1; i < ACTOR_COUNT; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / ACTOR_COUNT));
            _recordTransfer(address(this), actors[i], SUPPLY / ACTOR_COUNT);
        }
        // Seed finite and unlimited permissions so delegated transfers are useful from call one.
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            _approve(actors[i], actors[(i + 1) % ACTOR_COUNT], SUPPLY / ACTOR_COUNT);
            _approve(actors[i], actors[(i + 2) % ACTOR_COUNT], type(uint256).max);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _recipient(toSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid direct transfer rejected");
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 mode = amountSeed % 5;
        uint256 amount = mode == 0
            ? 0
            : mode == 1
                ? type(uint256).max
                : mode == 2 ? type(uint256).max - 1 : mode == 3 ? bound(amountSeed, 0, SUPPLY) : amountSeed;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 available = expectedBalance[owner];
        uint256 allowance = expectedAllowance[owner][spender];
        if (allowance < available) available = allowance;
        _spend(owner, spender, _recipient(toSeed), _amount(amountSeed, available));
    }

    /// @dev Keep an unrestricted amount path as well as the success-oriented bounded path.
    /// Expected failures are asserted here; an unexpected failure must fail the invariant run.
    function transferFromRaw(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _recipient(toSeed);
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        if (allowance != type(uint256).max && amount > allowance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
            );
            vm.prank(spender);
            token.transferFrom(owner, to, amount);
        } else if (amount > balance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
            );
            vm.prank(spender);
            token.transferFrom(owner, to, amount);
        } else {
            _spend(owner, spender, to, amount);
        }
    }

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _recipient(toSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    /// @dev An approved spend can still fail after allowance accounting. Its revert must restore
    /// that allowance, which the independent ledger deliberately leaves untouched.
    function transferFromAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _recipient(toSeed);
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 available = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < available) {
            available = expectedAllowance[owner][spender];
        }
        uint256 amount = _amount(amountSeed, available);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval rejected");
        expectedAllowance[owner][spender] = amount;
    }

    function _spend(address owner, address spender, address to, uint256 amount) private {
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "authorized transfer rejected");
        if (expectedAllowance[owner][spender] != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        _recordTransfer(owner, to, amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, ACTOR_COUNT - 1)];
    }

    function _recipient(uint256 seed) private view returns (address) {
        uint256 index = bound(seed, 0, ACTOR_COUNT);
        // The token can receive its own tokens but cannot originate a transaction to spend them.
        return index == ACTOR_COUNT ? address(token) : actors[index];
    }

    function _amount(uint256 seed, uint256 maximum) private pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return maximum == 0 ? 0 : 1;
        if (seed % 4 == 2) return maximum;
        return bound(seed, 0, maximum);
    }
}
