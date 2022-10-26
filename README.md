# ImmuneFi Zodiac bug bountry - Reality.eth module findings

In this `README` you can find findings for Zodiac's Reality.eth module. Most of
them are gas optimizations (low hanging fruits) and a couple are potential
issues (medium to low severity).

1. Question cooldown is meant to (as the name suggests) act as a cooldown before
   the proposal associated to a question that was answered positively can be
   executed. Since the variable is set globally in the state, if any proposal is
   currently active (i.e. non-executed), setting the cooldown by the owner can
   have the unexpected side effect of also applying the new cooldown to old non
   executed proposals. Example: <br/><br/>We have a proposal submitted at time
   `t0` with a cooldown of `10` seconds. At time `t5` the question associated
   with the proposal is answered positively, which makes the cooldown timer
   start (it will end at `t15` with the current setup). Now let's say at `t10`
   the cooldown is reduced to `5` seconds (might be due to another proposal
   being asked which needs that configuration), the proposal associated with the
   question immediately becomes executable the next second, which is something
   that the user might not necessarily want nor expect. <br/><br/>A recreation
   of this scenario is implemented in
   `test/StateUpdate.t.sol:testCooldownUpdate`.

2. The same logic above applies to `minBond`, which is a state variable and can
   be updated "at runtime" while old questions were asked with different values.
   This has a potential worse effect though. For example: <br/><br/> We have a
   proposal submitted at time `t0` with a minBond of `0`. If at this point we
   increase the `minBond` to `2`, it doesn't matter what the answer to the
   question is, if the bond attached to that answer is any less than `2`, the
   attached proposal can never be executed due to the check at line `364`. This
   might be wanted, but then it looks off that the `minimumBond` state variable
   seems to govern 2 different things: <br/>

- The _initial_ minimum bond setup when asking a question on Reality.
- The _final_ bond check when executing a proposal. <br/><br/> These 2 IMHO are
  different things and having the same state variable govern them could lead to
  unexpected behaviors. <br/><br/> A recreation of this scenario is implemented
  in `test/StateUpdate.t.sol:testMinBondUpdate`.

3. Regarding the ETH (i.e. native currency in a multichain world) version of the
   module, if an arbitrator requires an arbitration fee the module cannot be
   used with that arbitrator, which limits the arbitration choice and overall
   the usability of the solution. While asking a question, enough value must be
   passed to the Reality.eth ETH contract to cover the arbitration fee.
   Additionally, passing value might be useful to add a bounty for whoever
   answers the question correctly, acting as an additional incentivization
   mechanism (please notice this can be done after asking the question and by
   anyone since there's a `fundAnswerBounty` in the Reality.eth contract, but it
   incurs additional gas costs/UX headaches). <br/><br/> The suggestion in this
   case is to make the `addProposalWithNonce` and `askQuestion` functions
   `payable` and to handle value forwarding in the latter. <br/><br/> A
   recreation of this scenario is implemented in
   `test/ArbitrationFeeETH.t.sol:testArbitrationFeeETH`.

4. Regarding the ERC20 version of the module, following the logic above, if an
   arbitrator requires an arbitration fee the module cannot be used with that
   arbitrator, which limits the arbitration choice. While asking a question,
   enough target ERC20 must be passed to the Reality.eth ERC20 contract to cover
   the arbitration fee. Additionally, giving tokens might be useful to add a
   bounty for whoever answers the question correctly, acting as an additional
   incentivization mechanism (please notice this can be done after asking the
   question and by anyone since there's a `fundAnswerBounty` in the Reality.eth
   contract, but it incurs additional gas cost/UX headaches). <br/><br/> The
   suggestion in this case is to handle ERC20 token forwarding with additional
   parameters to the `addProposalWithNonce` and `askQuestion` that specify the
   amount of tokens to be taken from msg.sender and forwarded to the Reality.eth
   contract instance. <br/><br/> A recreation of this scenario is implemented in
   `test/ArbitrationFeeERC20.t.sol:testArbitrationFeeERC20`.

5. The module seems to be intended to work through a proxy pattern. If that's
   the case, the constructor might be dropped since an useless initialization
   might be performed (the state of the proxied contract is never taken into
   account while using delegatecall, only the implementation itself).

6. Reality.eth v3 supports reopening a question that is settled too soon (i.e.
   when a result is not known even after the question becomes answerable). In
   that case anyone can answer with `UNRESOLVED_ANSWER`
   (`0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe`,
   constant defined in Reality.eth v3 contracts), and if the question is
   finalized with that answer, anyone can go ahead and trigger a reopen later by
   calling `reopenQuestion`. This feature is currently not leveraged by the
   module, but most important of all, if a question is finalized with
   `UNRESOLVED_ANSWER` in good faith, the check at line `221` might break (in
   that case `oracle.resultFor()` would return `UNRESOLVED_ANSWER`). This would
   result in a scenario where the question was answered in the "right way" and
   in good faith if the result isn't actually known at the time, but still
   resulting in the proposal associated to it not being executable (which might
   not be the right behavior). At the same time the proposal itself could not be
   resubmitted with the same parameters but different nonce due to the check at
   line `221` (the module won't see the question as failed, so the proposal is
   in a limbo). In order to fix this behavior and leverage the reopen feature
   the suggestion would be to replace usages of `resultFor` with
   `resultForOnceSettled`. Keep in mind that this breaks compatibility with
   Reality.eth v2 contracts, for which the current logic can be kept alive.
   <br/><br/> A recreation of this scenario is implemented in
   `test/ReopenShouldBlock.t.sol:testReopenShouldBlock`.

7. In order to reduce gas consumption, using custom errors instead of strings +
   requires can be used (starting from Solidity 0.8.4).

8. In order to reduce gas consumption, the calculations of expiration in
   function `markProposalWithExpiredAnswerAsInvalid` (line 286) and of
   cooldown/expiration in function `executeProposalWithIndex` (lines 370, 375)
   can be included in an `unchecked` block. Both sums are performed with 32-bit
   numbers. An uint40 would be sufficient to contain the result without
   overflowing but a prudent uint256 is used in these specific cases. This makes
   sure that no overflowing will happen. This means the unchecked block can be
   added to shave off some gas.

9. In `executeProposalWithIndex`, the oracle state variable is read several
   times. A quick gas saving trick can be used to read the oracle address once
   right when it's needed the first time and store it in memory for future use.

10. Floating pragmas can lead to unexpected behaviors. While floating pragmas
    can (and should) be used on contracts that are intended to be consumed by
    other developers, they should be locked in contracts that are meant to be
    deployed and leveraged by users in production environments. This will lead
    to deterministic builds and will help in keeping the compiler in use up to
    date (release notes of solc should be checked for bugfixes and known
    vulnerabilities introduced by certain versions).

11. The following functions can be marked external instead of public, saving
    some gas in the process:

- `setQuestionTimeout`
- `setQuestionCooldown`
- `setAnswerExpiration`
- `setArbitrator`
- `setMinimumBond`
- `setTemplate`
- `addProposal`
- `markProposalAsInvalid`
- `markProposalWithExpiredAnswerAsInvalid`
- `executeProposal`

12. The `getChainId` function can be marked as `internal` (use
    `const { chainId } = await waffle.provider.getNetwork()` to get the chain id
    in tests). This will reduce gas consumption.

13. Rearranging storage variables in the following way can bring down gas cost
    slightly due to Solidity packing (all variables will be put in only 3
    storage slots):

```
RealitioV3 public oracle;
address public questionArbitrator;
uint32 public questionTimeout;
uint32 public questionCooldown;
uint32 public answerExpiration;
uint256 public template;
uint256 public minimumBond;
```
