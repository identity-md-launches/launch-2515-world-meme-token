// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WorldMemeToken} from "src/WorldMemeToken.sol";

/// @notice Regression and arithmetic boundaries supplementing the existing deployment tests.
/// forge-config: default.fuzz.runs = 1000
contract WorldMemeTokenEdgeCasesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WorldMemeToken private token;
    address private holder = makeAddr("edge holder");
    address private spender = makeAddr("edge spender");
    address private recipient = makeAddr("edge recipient");
    address private outsider = makeAddr("edge outsider");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new WorldMemeToken();
    }

    function test_zeroTransferEmitsEventFromEmptyHolder() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, recipient, 0);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 0));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 0));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAmountDoesNotPermitZeroRecipient() public {
        bytes memory error = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        vm.expectRevert(error);
        vm.prank(holder);
        token.transfer(address(0), 0);

        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroApprovalDoesNotPermitZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        assertEq(token.allowance(holder, address(0)), 0);
    }

    function test_oneWeiAllowanceCannotBeSpentTwice() public {
        assertTrue(token.transfer(holder, 2));
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), 0);

        _expectNoAllowance(spender, holder, recipient);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalCannotBeBorrowedByAnotherCaller() public {
        assertTrue(token.transfer(holder, 20));
        vm.prank(holder);
        assertTrue(token.approve(spender, 20));

        // An approval made by the attacker affects the attacker's funds only.
        vm.prank(outsider);
        assertTrue(token.approve(outsider, type(uint256).max));
        _expectNoAllowance(outsider, holder, outsider);
        assertEq(token.allowance(holder, spender), 20);
        assertEq(token.balanceOf(holder), 20);
        assertEq(token.balanceOf(outsider), 0);
    }

    function test_approvalForOneOwnerDoesNotAuthorizeAnotherOwner() public {
        assertTrue(token.transfer(holder, 20));
        assertTrue(token.approve(spender, type(uint256).max));
        _expectNoAllowance(spender, holder, recipient);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(holder), 20);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_recipientBeingApprovedDoesNotAuthorizeCaller() public {
        assertTrue(token.transfer(holder, 20));
        vm.prank(holder);
        assertTrue(token.approve(recipient, type(uint256).max));
        _expectNoAllowance(outsider, holder, recipient);
        assertEq(token.allowance(holder, recipient), type(uint256).max);
        assertEq(token.balanceOf(holder), 20);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_finiteAllowanceCanBeRevoked() public {
        _checkRevocation(10);
    }

    function test_infiniteAllowanceCanBeRevoked() public {
        _checkRevocation(type(uint256).max);
    }

    function test_delegatedSelfTransferConsumesFiniteAllowance() public {
        assertTrue(token.transfer(holder, 7));
        vm.prank(holder);
        assertTrue(token.approve(spender, 7));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, holder, 7);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, 7));
        assertEq(token.balanceOf(holder), 7);
        assertEq(token.allowance(holder, spender), 0);
        _expectNoAllowance(spender, holder, holder);
        assertEq(token.balanceOf(holder), 7);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxMinusOneApprovalIsFinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalPersistsButCannotOverdrawBalance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferAmountRevertsWithoutOverflowOrAllowanceLoss() public {
        uint256 maximum = type(uint256).max;
        bytes memory error =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(error);
        token.transfer(recipient, maximum);
        assertTrue(token.approve(spender, maximum));
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(address(this), recipient, maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToTokenContractIsAccountedForWithoutBurning() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_nonpayableTransferRejectsEtherAndPreservesTokens() public {
        vm.deal(address(this), 1);
        (bool ok,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (recipient, 1)));
        assertFalse(ok);
        assertEq(address(this).balance, 1);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testFuzz_failedDelegatedOverdraftPreservesAllowance(uint256 funded, uint256 requested, uint256 approved)
        public
    {
        funded = bound(funded, 0, SUPPLY);
        requested = bound(requested, funded + 1, type(uint256).max);
        approved = bound(approved, requested, type(uint256).max);
        assertTrue(token.transfer(holder, funded));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, funded, requested)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, requested);
        assertEq(token.allowance(holder, spender), approved, "failed transfer consumed approval");
        assertEq(token.balanceOf(holder), funded);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - funded);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_zeroRecipientPreservesApproval(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacementApprovalIsExactAndRevocable(uint256 oldApproval, uint256 newApproval, uint256 spend)
        public
    {
        assertTrue(token.approve(spender, oldApproval));
        assertTrue(token.approve(spender, newApproval));
        assertEq(token.allowance(address(this), spender), newApproval);
        spend = bound(spend, 0, newApproval < SUPPLY ? newApproval : SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, spend));
        uint256 remaining = newApproval == type(uint256).max ? newApproval : newApproval - spend;
        assertEq(token.allowance(address(this), spender), remaining);

        assertTrue(token.approve(spender, 0));
        _expectNoAllowance(spender, address(this), recipient);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(recipient), spend);
        assertEq(token.balanceOf(address(this)), SUPPLY - spend);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitSpendsExhaustExactlyOneApproval(uint256 firstSpend) public {
        firstSpend = bound(firstSpend, 0, SUPPLY);
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, firstSpend));
        assertEq(token.allowance(address(this), spender), SUPPLY - firstSpend);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, SUPPLY - firstSpend));
        _expectNoAllowance(spender, address(this), recipient);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(holder), firstSpend);
        assertEq(token.balanceOf(recipient), SUPPLY - firstSpend);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_selfTransferStillRequiresSufficientBalance(uint256 funded, uint256 excess) public {
        funded = bound(funded, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - funded);
        assertTrue(token.transfer(holder, funded));
        vm.prank(holder);
        assertTrue(token.transfer(holder, funded));
        assertEq(token.balanceOf(holder), funded);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, funded, funded + excess)
        );
        vm.prank(holder);
        token.transfer(holder, funded + excess);
        assertEq(token.balanceOf(holder), funded);
        assertEq(token.balanceOf(address(this)), SUPPLY - funded);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresBalances(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(holder, amount));
        vm.prank(holder);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _checkRevocation(uint256 initialApproval) private {
        assertTrue(token.transfer(holder, 10));
        vm.prank(holder);
        assertTrue(token.approve(spender, initialApproval));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(holder, spender, 0);
        vm.prank(holder);
        assertTrue(token.approve(spender, 0));
        _expectNoAllowance(spender, holder, recipient);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 9);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectNoAllowance(address caller, address from, address to) private {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, caller, 0, 1));
        vm.prank(caller);
        token.transferFrom(from, to, 1);
    }
}
