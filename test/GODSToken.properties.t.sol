// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GODSToken} from "src/GODSToken.sol";

/// @dev Complements the deployment/event tests with allowance lifecycle and algebraic properties.
/// forge-config: default.fuzz.runs = 1000
contract GODSTokenPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    GODSToken private token;
    address private holder;
    address private recipient;
    address private operator;
    address private otherOperator;

    function setUp() public {
        token = new GODSToken();
        holder = makeAddr("property holder");
        recipient = makeAddr("property recipient");
        operator = makeAddr("property operator");
        otherOperator = makeAddr("property other operator");
    }

    function testOneWeiRoundTripHasNoDustOrFee() public {
        assertTrue(token.transfer(holder, 1));
        vm.prank(holder);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumTransferRevertsWithBalanceError() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(recipient, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumTransferFromDoesNotConsumeInfiniteApproval() public {
        token.approve(operator, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(operator);
        token.transferFrom(address(this), recipient, type(uint256).max);
        assertEq(token.allowance(address(this), operator), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testLargestFiniteApprovalIsDecremented() public {
        token.approve(operator, type(uint256).max - 1);
        vm.prank(operator);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), operator), type(uint256).max - 2);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function testInfiniteApprovalCanBeReducedAndRevokedAfterUse() public {
        token.approve(operator, type(uint256).max);
        vm.prank(operator);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), operator), type(uint256).max);

        token.approve(operator, 2);
        vm.prank(operator);
        assertTrue(token.transferFrom(address(this), recipient, 2));
        assertEq(token.allowance(address(this), operator), 0);
        _expectAllowanceFailure(address(this), operator, recipient, 1);

        token.approve(operator, type(uint256).max);
        token.approve(operator, 0);
        _expectAllowanceFailure(address(this), operator, recipient, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.balanceOf(recipient), 3);
        assertEq(token.allowance(address(this), operator), 0);
    }

    function testApprovalFromEmptyHolderWorksOnceFunded() public {
        vm.prank(holder);
        assertTrue(token.approve(operator, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 1));
        vm.prank(operator);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, operator), SUPPLY);
        assertEq(token.balanceOf(holder), 0);

        token.transfer(holder, SUPPLY);
        vm.prank(operator);
        assertTrue(token.transferFrom(holder, recipient, SUPPLY));
        assertEq(token.allowance(holder, operator), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testRefundDoesNotRestoreSpentAllowance() public {
        token.transfer(holder, 7);
        vm.prank(holder);
        token.approve(operator, 7);
        vm.prank(operator);
        assertTrue(token.transferFrom(holder, recipient, 7));
        vm.prank(recipient);
        assertTrue(token.transfer(holder, 7));

        _expectAllowanceFailure(holder, operator, recipient, 1);
        assertEq(token.allowance(holder, operator), 0);
        assertEq(token.balanceOf(holder), 7);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 7);
    }

    function testTwoSpendersShareBalanceButNotAllowance() public {
        token.transfer(holder, 10);
        vm.startPrank(holder);
        token.approve(operator, 10);
        token.approve(otherOperator, 10);
        vm.stopPrank();

        vm.prank(operator);
        assertTrue(token.transferFrom(holder, recipient, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 10));
        vm.prank(otherOperator);
        token.transferFrom(holder, otherOperator, 10);
        assertEq(token.allowance(holder, operator), 0);
        assertEq(token.allowance(holder, otherOperator), 10);
        assertEq(token.balanceOf(otherOperator), 0);

        vm.prank(recipient);
        token.transfer(holder, 10);
        vm.prank(otherOperator);
        assertTrue(token.transferFrom(holder, otherOperator, 10));
        assertEq(token.allowance(holder, otherOperator), 0);
        assertEq(token.balanceOf(otherOperator), 10);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testOwnerUsingTransferFromNeedsItsOwnAllowance() public {
        token.transfer(holder, 1);
        vm.prank(holder);
        token.approve(operator, type(uint256).max);
        _expectAllowanceFailure(holder, holder, recipient, 1);
        assertEq(token.balanceOf(holder), 1);

        vm.prank(holder);
        token.approve(holder, 1);
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.allowance(holder, operator), type(uint256).max);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
    }

    function testDelegatedSelfTransferStillRequiresEnoughBalance() public {
        token.transfer(holder, 1);
        vm.prank(holder);
        token.approve(operator, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2));
        vm.prank(operator);
        token.transferFrom(holder, holder, 2);
        assertEq(token.allowance(holder, operator), 2);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferStillRequiresEnoughBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroValueDoesNotPermitZeroSpenderOrReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        token.approve(operator, 7);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(operator);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), operator), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApprovalForOneOwnerCannotSpendAnotherOwnersBalance() public {
        token.transfer(holder, 10);
        token.approve(operator, type(uint256).max);
        _expectAllowanceFailure(holder, operator, recipient, 1);
        assertEq(token.allowance(address(this), operator), type(uint256).max);
        assertEq(token.allowance(holder, operator), 0);
        assertEq(token.balanceOf(holder), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testFuzzTransferRoundTripRestoresBalances(uint256 firstBalance, uint256 secondBalance, uint256 amount)
        public
    {
        firstBalance = bound(firstBalance, 0, SUPPLY);
        secondBalance = bound(secondBalance, 0, SUPPLY - firstBalance);
        amount = bound(amount, 0, firstBalance);
        token.transfer(holder, firstBalance);
        token.transfer(recipient, secondBalance);
        vm.prank(holder);
        token.approve(operator, type(uint256).max);

        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(holder), firstBalance - amount);
        assertEq(token.balanceOf(recipient), secondBalance + amount);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        assertEq(token.balanceOf(holder), firstBalance);
        assertEq(token.balanceOf(recipient), secondBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - firstBalance - secondBalance);
        assertEq(token.allowance(holder, operator), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSplittingATransferDoesNotChangeItsResult(uint256 amount, uint256 firstPart) public {
        amount = bound(amount, 0, SUPPLY);
        firstPart = bound(firstPart, 0, amount);
        GODSToken split = new GODSToken();
        assertTrue(token.transfer(recipient, amount));
        assertTrue(split.transfer(recipient, firstPart));
        assertTrue(split.transfer(recipient, amount - firstPart));
        assertEq(split.balanceOf(recipient), token.balanceOf(recipient));
        assertEq(split.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(split.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzApprovalReplacementIsIdempotentAndIsolated(uint256 original, uint256 replacement) public {
        token.approve(operator, original);
        token.approve(otherOperator, 17);
        vm.prank(holder);
        token.approve(operator, 23);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), operator, replacement);
        assertTrue(token.approve(operator, replacement));
        assertEq(token.allowance(address(this), operator), replacement);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), operator, replacement);
        assertTrue(token.approve(operator, replacement));
        assertEq(token.allowance(address(this), operator), replacement);
        assertEq(token.allowance(address(this), otherOperator), 17);
        assertEq(token.allowance(holder, operator), 23);
        assertEq(token.allowance(operator, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(operator), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzBalanceFailurePreservesApprovalForLaterValidSpend(
        uint256 balance,
        uint256 amount,
        uint256 approval
    ) public {
        balance = bound(balance, 1, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        approval = bound(approval, amount, type(uint256).max);
        token.transfer(holder, balance);
        vm.prank(holder);
        token.approve(operator, approval);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(operator);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.allowance(holder, operator), approval);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(operator);
        assertTrue(token.transferFrom(holder, recipient, balance));
        assertEq(token.allowance(holder, operator), approval == type(uint256).max ? approval : approval - balance);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzInvalidReceiverPreservesApprovalForLaterValidSpend(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        approval = bound(approval, amount, type(uint256).max);
        token.approve(operator, approval);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(operator);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), operator), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);

        vm.prank(operator);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        assertEq(token.allowance(address(this), operator), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzArbitraryNonzeroRecipientGetsExactAmount(address to, uint256 amount) public {
        to = address(uint160(bound(uint256(uint160(to)), 1, type(uint160).max)));
        amount = bound(amount, 0, SUPPLY);
        uint256 beforeBalance = token.balanceOf(to);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), to, amount);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), beforeBalance + (to == address(this) ? 0 : amount));
        assertEq(token.balanceOf(address(this)), to == address(this) ? SUPPLY : SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzDelegatedRoundTripConsumesOnlyFiniteAllowance(uint256 amount, uint256 approval, bool unlimited)
        public
    {
        amount = bound(amount, 0, SUPPLY);
        approval = unlimited ? type(uint256).max : bound(approval, amount, type(uint256).max - 1);
        token.transfer(holder, SUPPLY);
        vm.prank(holder);
        token.approve(operator, approval);
        vm.prank(recipient);
        token.approve(operator, approval);

        vm.prank(operator);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.balanceOf(holder), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        vm.prank(operator);
        assertTrue(token.transferFrom(recipient, holder, amount));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(operator), 0);
        assertEq(token.allowance(holder, operator), unlimited ? approval : approval - amount);
        assertEq(token.allowance(recipient, operator), unlimited ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectAllowanceFailure(address owner, address spender, address to, uint256 amount) private {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }
}
