// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {YoloToken} from "../src/YoloToken.sol";

/// @notice Drives YoloToken with bounded random calls from a fixed set of actors and keeps ghost
/// balances and allowances that the token must agree with after every call.
contract YoloHandler is Test {
    YoloToken public immutable token;
    address[] public actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public calls;
    uint256 public successfulMoves;
    uint256 public expectedReverts;
    uint256 public unexpectedFailures;

    constructor(YoloToken token_, address[] memory actors_, address holder) {
        token = token_;
        actors = actors_;
        ghostBalance[holder] = token_.totalSupply();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        calls++;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = ghostBalance[from];
        // Mostly in range; occasionally one over to exercise the failure path.
        amount = bound(amount, 0, bal + 1);

        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            if (!ok || amount > bal) {
                unexpectedFailures++;
                return;
            }
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            successfulMoves++;
        } catch (bytes memory reason) {
            bytes memory want = abi.encodeWithSelector(YoloToken.InsufficientBalance.selector, from, bal, amount);
            if (amount <= bal || keccak256(reason) != keccak256(want)) unexpectedFailures++;
            else expectedReverts++;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        calls++;
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (infinite) amount = type(uint256).max;
        vm.prank(owner);
        try token.approve(spender, amount) returns (bool ok) {
            if (!ok) unexpectedFailures++;
            ghostAllowance[owner][spender] = amount;
        } catch {
            unexpectedFailures++;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        calls++;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = ghostBalance[from];
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = bal < allowed ? bal : allowed;
        amount = bound(amount, 0, cap + 1);

        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool ok) {
            if (!ok || amount > cap) {
                unexpectedFailures++;
                return;
            }
            if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            successfulMoves++;
        } catch (bytes memory reason) {
            bytes memory want = amount > allowed
                ? abi.encodeWithSelector(YoloToken.InsufficientAllowance.selector, spender, allowed, amount)
                : abi.encodeWithSelector(YoloToken.InsufficientBalance.selector, from, bal, amount);
            if (amount <= cap || keccak256(reason) != keccak256(want)) unexpectedFailures++;
            else expectedReverts++;
        }
    }

    /// @dev The zero address is never a valid receiver and a failed call must change nothing.
    function transferToZero(uint256 fromSeed, uint256 amount) external {
        calls++;
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        try token.transfer(address(0), amount) {
            unexpectedFailures++;
        } catch (bytes memory reason) {
            if (keccak256(reason) != keccak256(abi.encodeWithSelector(YoloToken.InvalidReceiver.selector, address(0))))
            {
                unexpectedFailures++;
            } else {
                expectedReverts++;
            }
        }
    }
}

contract YoloTokenInvariantTest is Test {
    uint256 constant SUPPLY = 1_000_000_000e18;

    YoloToken token;
    YoloHandler handler;
    address[] actors;

    function setUp() public {
        address deployer = address(0xFAC7);
        actors.push(deployer);
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA201));
        actors.push(address(0xD00D));

        vm.prank(deployer);
        token = new YoloToken();
        handler = new YoloHandler(token, actors, deployer);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = YoloHandler.transfer.selector;
        selectors[1] = YoloHandler.approve.selector;
        selectors[2] = YoloHandler.transferFrom.selector;
        selectors[3] = YoloHandler.transferToZero.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesMatchGhost() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]));
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchGhost() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.ghostAllowance(actors[i], actors[j]));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_everyCallBehavedAsSpecified() public view {
        assertEq(handler.unexpectedFailures(), 0);
    }
}
