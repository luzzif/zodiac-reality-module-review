pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {RealityModuleETH, Enum} from "zmr/RealityModuleETH.sol";
import {RealitioV3} from "zmr/interfaces/RealitioV3.sol";
import {IRealityETH} from "reality/IRealityETH.sol";

// SPDX-License-Identifier: GPL-3.0-or-later
contract StateUpdates is Test {
    // reality v3 address on mainnet. As taken from
    // https://github.com/RealityETH/reality-eth-monorepo/blob/main/packages/contracts/chains/deployments/1/ETH/RealityETH-3.0.json
    IRealityETH internal constant REALITY_V3 =
        IRealityETH(address(0x5b7dD1E86623548AF054A4985F7fc8Ccbb554E2c));
    uint32 internal constant TIMEOUT = 10;
    uint32 internal constant COOLDOWN = 10;
    uint32 internal constant EXPIRATION = 70;
    uint256 internal constant BOND = 0;
    uint256 internal constant TEMPLATE_ID = 1;
    address internal constant ARBITRATOR = address(0);

    RealityModuleETH internal module;

    function setUp() external {
        // mainnet fork
        vm.createSelectFork(
            "https://mainnet.infura.io/v3/12dcaab4d567445bb9cfb64812c7fe0b"
        );

        // mock avatar calls
        address _avatar = address(2);
        vm.mockCall(_avatar, bytes(""), abi.encode(true));

        // deploy module
        module = new RealityModuleETH(
            address(this), // we are the owners
            address(1),
            _avatar,
            RealitioV3(address(REALITY_V3)),
            TIMEOUT,
            COOLDOWN,
            EXPIRATION,
            BOND,
            TEMPLATE_ID,
            ARBITRATOR
        );
    }

    function testCooldownUpdate() public {
        string memory _proposalId = "random-id";
        bytes32[] memory _hashes = new bytes32[](1);
        _hashes[0] = module.getTransactionHash(
            address(this),
            0,
            abi.encode(""),
            Enum.Operation.Call,
            0
        );

        // add new proposal, asking the question on reality.eth
        module.addProposal(_proposalId, _hashes);

        // determine reality.eth question id
        string memory _question = module.buildQuestion(_proposalId, _hashes);
        bytes32 _questionId = module.getQuestionId(_question, 0);

        // answer the question
        REALITY_V3.submitAnswer{value: 1}(_questionId, bytes32(uint256(1)), 0);

        // wait until the answer is finalized and reach half of the cooldown period
        // (t15) + 1 (+1 because the check at line 370 uses < and not <1, so the
        // proposal becomes executable the next second the cooldown period passes)
        vm.warp(block.timestamp + TIMEOUT + COOLDOWN / 2 + 1);

        // make sure the answer is finalized
        assertTrue(IRealityETH(REALITY_V3).isFinalized(_questionId));

        // try to execute the attached proposal (it should fail due to cooldown not being passed)
        vm.expectRevert();
        module.executeProposal(
            _proposalId,
            _hashes,
            address(this),
            0,
            abi.encode(""),
            Enum.Operation.Call
        );

        // now update the cooldown and reduce it to half of the original value
        module.setQuestionCooldown(COOLDOWN / 2);

        uint256 _finalizeTs = REALITY_V3.getFinalizeTS(_questionId);

        // the attached proposal is now executable
        module.executeProposal(
            _proposalId,
            _hashes,
            address(this),
            0,
            abi.encode(""),
            Enum.Operation.Call
        );
    }

    function testMinBondUpdate() public {
        // keep in mind initially bond is set to 0
        string memory _proposalId = "random-id";
        bytes32[] memory _hashes = new bytes32[](1);
        _hashes[0] = module.getTransactionHash(
            address(this),
            0,
            abi.encode(""),
            Enum.Operation.Call,
            0
        );

        // add new proposal, asking the question on reality.eth
        module.addProposal(_proposalId, _hashes);

        // determine reality.eth question id
        string memory _question = module.buildQuestion(_proposalId, _hashes);
        bytes32 _questionId = module.getQuestionId(_question, 0);

        // answer the question with a bond of 1 (the minimum enforced in
        // the contract is respected)
        REALITY_V3.submitAnswer{value: 1}(_questionId, bytes32(uint256(1)), 0);

        // wait until the answer is finalized
        vm.warp(block.timestamp + TIMEOUT);

        // make sure the answer is finalized
        assertTrue(IRealityETH(REALITY_V3).isFinalized(_questionId));

        // at this point the cooldown period needs to pass before the proposal
        // execution, let's update the minimum bond to 2
        module.setMinimumBond(2);

        // fast forward to the end of the cooldown period + 1
        vm.warp(block.timestamp + COOLDOWN + 1);

        // try to execute the attached proposal (it should fail due to the
        // minimum bond update). The proposal should be executable since the
        // whole process was done in good faith using and respecting the
        // creation-time parameters.
        vm.expectRevert(abi.encodePacked("Bond on question not high enough"));
        module.executeProposal(
            _proposalId,
            _hashes,
            address(this),
            0,
            abi.encode(""),
            Enum.Operation.Call
        );
    }
}
