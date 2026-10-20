// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {YoloToken} from "../src/YoloToken.sol";

/// @notice Edge cases and failure paths of YoloToken, plus stateless fuzz properties.
contract YoloTokenEdgesTest is Test {
    uint256 constant SUPPLY = 1_000_000_000e18;

    YoloToken token;
    address deployer = address(0xFAC7);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA201);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new YoloToken();
    }

    // ---------------------------------------------------------------- constants

    function test_totalSupplyConstantMatchesState() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_eachDeploymentMintsToItsOwnDeployer() public {
        vm.prank(alice);
        YoloToken other = new YoloToken();
        assertEq(other.balanceOf(alice), SUPPLY);
        assertEq(other.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    // ---------------------------------------------------------------- transfer

    function test_transferZeroSucceedsAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferWholeSupply() public {
        vm.prank(deployer);
        token.transfer(alice, SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferOneMoreThanBalanceReverts() public {
        vm.prank(deployer);
        token.transfer(alice, 100);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientBalance.selector, alice, 100, 101));
        token.transfer(bob, 101);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferMoreThanSupplyReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1));
        token.transfer(alice, SUPPLY + 1);
    }

    function test_transferMaxUintReverts() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(YoloToken.InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_selfTransferKeepsBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, deployer, SUPPLY);
        vm.prank(deployer);
        token.transfer(deployer, SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_selfTransferOverBalanceReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1));
        token.transfer(deployer, SUPPLY + 1);
    }

    function test_transferZeroAmountToZeroAddressReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_transferToTokenContractIsAccepted() public {
        // Not a defect: no recovery path exists, so tokens sent here are locked but supply is intact.
        vm.prank(deployer);
        token.transfer(address(token), 5);
        assertEq(token.balanceOf(address(token)), 5);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 7);
        vm.prank(deployer);
        token.transfer(alice, 7);
    }

    // ---------------------------------------------------------------- approve

    function test_approveEmitsAndOverwrites() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, bob, 10);
        vm.prank(alice);
        assertTrue(token.approve(bob, 10));
        assertEq(token.allowance(alice, bob), 10);

        vm.prank(alice);
        token.approve(bob, 3);
        assertEq(token.allowance(alice, bob), 3);

        vm.prank(alice);
        token.approve(bob, 0);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_approveWithoutBalanceIsAllowed() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientBalance.selector, alice, 0, 1));
        token.transferFrom(alice, carol, 1);
    }

    function test_approveIsPerOwnerSpenderPair() public {
        vm.prank(alice);
        token.approve(bob, 10);
        assertEq(token.allowance(bob, alice), 0);
        assertEq(token.allowance(alice, carol), 0);
    }

    function test_approveSelfAsSpender() public {
        vm.prank(deployer);
        token.approve(deployer, 5);
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 5);
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(alice), 5);
    }

    // ---------------------------------------------------------------- transferFrom

    function test_transferFromWithoutAllowanceReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_ownerCannotTransferFromSelfWithoutAllowance() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_transferFromZeroWithoutAllowanceSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromExactAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 50);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 50);
        assertEq(token.allowance(deployer, alice), 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_transferFromToZeroRevertsAndKeepsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 50);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 10);
        assertEq(token.allowance(deployer, alice), 50);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromOverBalanceRevertsAndKeepsAllowance() public {
        vm.prank(deployer);
        token.transfer(bob, 10);
        vm.prank(bob);
        token.approve(alice, 100);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientBalance.selector, bob, 10, 11));
        token.transferFrom(bob, carol, 11);
        assertEq(token.allowance(bob, alice), 100);
        assertEq(token.balanceOf(bob), 10);
    }

    function test_infiniteAllowanceCannotExceedBalance() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1));
        token.transferFrom(deployer, bob, SUPPLY + 1);
    }

    function test_allowanceMaxMinusOneIsDecremented() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max - 1);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, alice), type(uint256).max - 2);
    }

    function test_transferFromDoesNotEmitApproval() public {
        vm.prank(deployer);
        token.approve(alice, 50);
        vm.recordLogs();
        vm.prank(alice);
        token.transferFrom(deployer, bob, 20);
        assertEq(vm.getRecordedLogs().length, 1);
    }

    function test_spenderCannotUseAnotherSpendersAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 50);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    // ---------------------------------------------------------------- no privileged surface

    function test_noAdminOrSupplyChangingEntryPoints() public {
        string[12] memory sigs = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "pause()",
            "blacklist(address)",
            "renounceOwnership()",
            "setFee(uint256)",
            "increaseAllowance(address,uint256)",
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"
        ];
        for (uint256 i; i < sigs.length; ++i) {
            vm.prank(deployer);
            (bool ok,) = address(token).call(abi.encodeWithSignature(sigs[i], alice, 1));
            assertFalse(ok, sigs[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_rejectsEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
    }

    // ---------------------------------------------------------------- fuzz

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferMovesExactly(address to, uint256 seedAmount, uint256 amount) public {
        to = to == address(0) ? bob : to;
        seedAmount = bound(seedAmount, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, seedAmount);
        amount = bound(amount, 0, seedAmount);

        uint256 fromBefore = token.balanceOf(alice);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(alice);
        token.transfer(to, amount);
        if (to == alice) {
            assertEq(token.balanceOf(alice), fromBefore);
        } else {
            assertEq(token.balanceOf(alice), fromBefore - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferOverBalanceReverts(uint256 bal, uint256 amount) public {
        bal = bound(bal, 0, SUPPLY);
        amount = bound(amount, bal + 1, type(uint256).max);
        vm.prank(deployer);
        token.transfer(alice, bal);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientBalance.selector, alice, bal, amount));
        token.transfer(bob, amount);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromSpendsAllowance(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, type(uint256).max - 1);
        amount = bound(amount, 0, allowed < SUPPLY ? allowed : SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        token.transferFrom(deployer, bob, amount);
        assertEq(token.allowance(deployer, alice), allowed - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromOverAllowanceReverts(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, SUPPLY - 1);
        amount = bound(amount, allowed + 1, SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.InsufficientAllowance.selector, alice, allowed, amount));
        token.transferFrom(deployer, bob, amount);
        assertEq(token.allowance(deployer, alice), allowed);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_infiniteAllowanceIsNeverSpent(uint256 a, uint256 b) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, SUPPLY - a);
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.startPrank(alice);
        token.transferFrom(deployer, bob, a);
        token.transferFrom(deployer, carol, b);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), type(uint256).max);
        assertEq(token.balanceOf(bob) + token.balanceOf(carol) + token.balanceOf(deployer), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactValue(address spender, uint256 first, uint256 second) public {
        spender = spender == address(0) ? bob : spender;
        vm.startPrank(alice);
        token.approve(spender, first);
        assertEq(token.allowance(alice, spender), first);
        token.approve(spender, second);
        assertEq(token.allowance(alice, spender), second);
        vm.stopPrank();
    }
}
