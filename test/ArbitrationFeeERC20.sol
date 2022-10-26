pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {RealityModuleERC20, Enum} from "zmr/RealityModuleERC20.sol";
import {RealitioV3} from "zmr/interfaces/RealitioV3.sol";
import {IRealityETH_ERC20} from "reality/IRealityETH_ERC20.sol";

contract ArbitratorRequestingFees {
    constructor(address _reality) {
        // require 2 gwei as an anti spam fee
        IRealityETH_ERC20(_reality).setQuestionFee(2);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
contract ArbitrationFeeERC20 is Test {
    // reality v3 ERC20 GNO address on mainnet
    IRealityETH_ERC20 internal constant REALITY_V3 =
        IRealityETH_ERC20(address(0x33aA365A53a4C9bA777fB5F450901a8EEF73F0A9));
    uint32 internal constant TIMEOUT = 10;
    uint32 internal constant COOLDOWN = 10;
    uint32 internal constant EXPIRATION = 70;
    uint256 internal constant BOND = 0;
    uint256 internal constant TEMPLATE_ID = 1;

    RealityModuleERC20 internal module;

    function setUp() external {
        // mainnet fork
        vm.createSelectFork(
            "https://mainnet.infura.io/v3/12dcaab4d567445bb9cfb64812c7fe0b"
        );

        // deploy module
        module = new RealityModuleERC20(
            address(this), // we are the owners
            address(1),
            address(1),
            RealitioV3(address(REALITY_V3)),
            TIMEOUT,
            COOLDOWN,
            EXPIRATION,
            BOND,
            TEMPLATE_ID,
            address(new ArbitratorRequestingFees(address(REALITY_V3)))
        );
    }

    function testArbitrationFeeERC20() public {
        string memory _proposalId = "random-id";
        bytes32[] memory _hashes = new bytes32[](1);
        _hashes[0] = module.getTransactionHash(
            address(this),
            0,
            abi.encode(""),
            Enum.Operation.Call,
            0
        );

        // add new proposal, asking the question on reality.eth. This should
        // fail because the selected arbitrator requires a fee.
        vm.expectRevert(
            abi.encodePacked("Tokens provided must cover question fee")
        );
        module.addProposal(_proposalId, _hashes);
    }
}
