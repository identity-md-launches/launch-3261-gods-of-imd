// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GODSToken} from "../src/GODSToken.sol";

/// @dev Closed actor set: every successful movement stays inside this ledger. Rejected calls
/// leave the ledger untouched, so the invariants also check rollback of balances and approvals.
contract GODSHandler is Test {
    GODSToken private immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(GODSToken token_, address[4] memory actors_, uint256 startingBalance) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = startingBalance;
        }
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function transferFrom(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approval = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        uint256 limit = approval < available ? approval : available;
        amount = bound(amount, 0, limit);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approval != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    /// @dev Makes revocation, exact grants and both uint256 allowance boundaries frequent.
    function approveBoundary(uint8 ownerSeed, uint8 spenderSeed, uint8 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[6] memory amounts = [
            uint256(0),
            uint256(1),
            expectedBalance[owner],
            expectedBalance[owner] + 1,
            type(uint256).max - 1,
            type(uint256).max
        ];
        _approve(owner, spender, amounts[mode % amounts.length]);
    }

    function transferFullBalance(uint8 fromSeed, uint8 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    /// @dev Always spends a positive amount, even if earlier actions emptied the chosen owner.
    /// This complements transferFrom, which uses approvals left by previous random calls.
    function approveAndSpend(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount, bool unlimited)
        external
    {
        uint256 ownerIndex = ownerSeed % actors.length;
        for (uint256 i; i < actors.length && expectedBalance[actors[ownerIndex]] == 0; ++i) {
            ownerIndex = (ownerIndex + 1) % actors.length;
        }
        address owner = actors[ownerIndex];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 1, expectedBalance[owner]);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        expectedAllowance[owner][spender] = unlimited ? type(uint256).max : 0;
    }

    function rejectTransfer(uint8 fromSeed, uint8 toSeed, uint256 amount, bool zeroReceiver) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        bytes memory reason;
        if (zeroReceiver) {
            to = address(0);
            amount = bound(amount, 0, expectedBalance[from]);
            reason = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, to);
        } else {
            amount = bound(amount, expectedBalance[from] + 1, type(uint256).max);
            reason = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount
            );
        }
        _assertRejected(from, abi.encodeCall(IERC20.transfer, (to, amount)), reason);
    }

    function rejectTransferFromOverBalance(
        uint8 ownerSeed,
        uint8 spenderSeed,
        uint8 toSeed,
        uint256 amount,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, expectedBalance[owner] + 1, type(uint256).max);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);

        _assertRejected(
            spender,
            abi.encodeCall(IERC20.transferFrom, (owner, to, amount)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, expectedBalance[owner], amount
            )
        );
    }

    function rejectTransferFromOverAllowance(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 approval)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approval = bound(approval, 0, type(uint256).max - 1);
        _approve(owner, spender, approval);

        _assertRejected(
            spender,
            abi.encodeCall(IERC20.transferFrom, (owner, to, approval + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, approval + 1)
        );
    }

    function rejectTransferFromToZero(uint8 ownerSeed, uint8 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);

        _assertRejected(
            spender,
            abi.encodeCall(IERC20.transferFrom, (owner, address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function rejectZeroSpender(uint8 ownerSeed, uint256 amount) external {
        _assertRejected(
            actors[ownerSeed % actors.length],
            abi.encodeCall(IERC20.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    /// @dev The handler itself is never approved. Other actors' grants must not authorize it.
    function rejectUnapprovedSpender(uint8 ownerSeed, uint8 toSeed, uint256 amount) external {
        amount = bound(amount, 1, type(uint256).max);
        _assertRejected(
            address(this),
            abi.encodeCall(
                IERC20.transferFrom, (actors[ownerSeed % actors.length], actors[toSeed % actors.length], amount)
            ),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, amount)
        );
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _assertRejected(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory errorData) = address(token).call(data);
        assertFalse(success, "invalid action succeeded");
        assertEq(errorData, expectedError, "unexpected rejection reason");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
contract GODSTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    GODSToken private token;
    GODSHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new GODSToken();
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        for (uint256 i; i < actors.length; ++i) {
            token.transfer(actors[i], SUPPLY / actors.length);
        }
        handler = new GODSHandler(token, actors, SUPPLY / actors.length);

        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = GODSHandler.transfer.selector;
        selectors[1] = GODSHandler.approve.selector;
        selectors[2] = GODSHandler.transferFrom.selector;
        selectors[3] = GODSHandler.approveBoundary.selector;
        selectors[4] = GODSHandler.transferFullBalance.selector;
        selectors[5] = GODSHandler.approveAndSpend.selector;
        selectors[6] = GODSHandler.rejectTransfer.selector;
        selectors[7] = GODSHandler.rejectTransferFromOverBalance.selector;
        selectors[8] = GODSHandler.rejectTransferFromOverAllowance.selector;
        selectors[9] = GODSHandler.rejectTransferFromToZero.selector;
        selectors[10] = GODSHandler.rejectZeroSpender.selector;
        selectors[11] = GODSHandler.rejectUnapprovedSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariantTotalSupplyAndBalanceSumStayConstant() public view {
        uint256 balanceSum;
        for (uint256 i; i < actors.length; ++i) {
            balanceSum += token.balanceOf(actors[i]);
        }
        assertEq(balanceSum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariantBalancesAndAllowancesMatchIndependentLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]));
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(actors[i], address(handler)), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }

    function invariantMetadataNeverChanges() public view {
        assertEq(token.name(), "GODS OF IMD");
        assertEq(token.symbol(), "GODS");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }
}
