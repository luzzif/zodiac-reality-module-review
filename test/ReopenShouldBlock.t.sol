pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {RealityModuleETH, Enum} from "zmr/RealityModuleETH.sol";
import {RealitioV3} from "zmr/interfaces/RealitioV3.sol";
import {IRealityETH} from "reality/IRealityETH.sol";

// SPDX-License-Identifier: GPL-3.0-or-later
// Recreation of the scenario
contract ReopenShouldBlock is Test {
    // reality v3 address on mainnet. As taken from
    // https://github.com/RealityETH/reality-eth-monorepo/blob/main/packages/contracts/chains/deployments/1/ETH/RealityETH-3.0.json
    IRealityETH internal constant REALITY_V3 =
        IRealityETH(address(0x5b7dD1E86623548AF054A4985F7fc8Ccbb554E2c));
    bytes32 constant UNRESOLVED_ANSWER =
        0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe;
    uint32 internal constant TIMEOUT = 10;
    uint32 internal constant COOLDOWN = 20;
    uint32 internal constant EXPIRATION = 80;
    uint256 internal constant BOND = 0;
    uint256 internal constant TEMPLATE_ID = 1;
    address internal constant ARBITRATOR = address(0);

    RealityModuleETH internal module;

    function setUp() external {
        // mainnet fork
        vm.createSelectFork(
            "https://mainnet.infura.io/v3/12dcaab4d567445bb9cfb64812c7fe0b"
        );

        // deploy module
        module = new RealityModuleETH(
            address(1),
            address(1),
            address(1),
            RealitioV3(address(REALITY_V3)),
            TIMEOUT,
            COOLDOWN,
            EXPIRATION,
            BOND,
            TEMPLATE_ID,
            ARBITRATOR
        );
    }

    function testReopenShouldBlock() public {
        string memory _proposalId = "random-id";
        bytes32[] memory _hashes = new bytes32[](1);
        _hashes[0] = bytes32("1");

        // add new proposal, asking question on reality.eth
        module.addProposal(_proposalId, _hashes);

        // determine reality.eth question id
        string memory _question = module.buildQuestion(_proposalId, _hashes);
        bytes32 _questionId = module.getQuestionId(_question, 0);

        // answer the question, marking it as unresolved
        REALITY_V3.submitAnswer{value: 1}(_questionId, UNRESOLVED_ANSWER, 0);

        // wait until the answer is finalized and cooldown has passed
        vm.warp(block.timestamp + TIMEOUT + COOLDOWN);

        // make sure the answer is finalized
        assertTrue(IRealityETH(REALITY_V3).isFinalized(_questionId));

        // try to execute the attached proposal (it should fail)
        vm.expectRevert();
        module.executeProposal(
            _proposalId,
            _hashes,
            address(this),
            0,
            abi.encodeWithSelector(
                ReopenShouldBlock(address(this)).target.selector
            ),
            Enum.Operation.Call
        );

        // now since the answer wasn't invalid at all (the oracle didn't
        // have enough data to answer the question just yet) we try to
        // re-submit the proposal wiht the same parameters but +1 nonce.
        // This shouldn't fail, but the check at line 221 misses this scenario.
        vm.expectRevert(
            abi.encodePacked("Previous proposal was not invalidated")
        );
        module.addProposalWithNonce(_proposalId, _hashes, 1);
    }

    function target() external pure {
        revert("should not really be here");
    }
}
