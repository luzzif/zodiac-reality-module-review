pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {RealityModuleETH, Enum} from "zmr/RealityModuleETH.sol";
import {RealitioV3} from "zmr/interfaces/RealitioV3.sol";
import {IRealityETH} from "reality/IRealityETH.sol";

contract ArbitratorRequestingFees {
    constructor(address _reality) {
        // require 2 gwei as an anti spam fee
        IRealityETH(_reality).setQuestionFee(2);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
contract ArbitrationFeeETH is Test {
    // reality v3 address on mainnet. As taken from
    // https://github.com/RealityETH/reality-eth-monorepo/blob/main/packages/contracts/chains/deployments/1/ETH/RealityETH-3.0.json
    IRealityETH internal constant REALITY_V3 =
        IRealityETH(address(0x5b7dD1E86623548AF054A4985F7fc8Ccbb554E2c));
    uint32 internal constant TIMEOUT = 10;
    uint32 internal constant COOLDOWN = 10;
    uint32 internal constant EXPIRATION = 70;
    uint256 internal constant BOND = 0;
    uint256 internal constant TEMPLATE_ID = 1;

    RealityModuleETH internal module;

    function setUp() external {
        // mainnet fork
        vm.createSelectFork(
            "https://mainnet.infura.io/v3/12dcaab4d567445bb9cfb64812c7fe0b"
        );

        // deploy module
        module = new RealityModuleETH(
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

    function testArbitrationFeeETH() public {
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
            abi.encodePacked("ETH provided must cover question fee")
        );
        module.addProposal(_proposalId, _hashes);
    }
}
