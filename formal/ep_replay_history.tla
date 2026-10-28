---------------------- MODULE ep_replay_history ----------------------
EXTENDS Naturals, Sequences, TLC
CONSTANT Mode
VARIABLE s
vars == <<s>>
\* One exact identity, two admission attempts; roots are collision-free sequences.
Empty == <<>>
Init == s = [log |-> Empty, checkpoint |-> Empty, anchor |-> Empty,
  frontier |-> 0, highWater |-> 0, coverage |-> "COMPLETE",
  anchorState |-> "CURRENT", continuity |-> TRUE,
  receipt |-> 0, linearized |-> {}, entries |-> Empty,
  dispatch |-> FALSE, terminal |-> FALSE, faults |-> {}]
Complete == /\ s.coverage = "COMPLETE"
            /\ s.continuity
            /\ s.anchorState = "CURRENT"
            /\ s.frontier = Len(s.log)
            /\ s.checkpoint = s.log
            /\ Len(s.anchor) <= Len(s.log)
            /\ s.anchor = SubSeq(s.log, 1, Len(s.anchor))
            /\ Len(s.anchor) = s.highWater
Unused == Len(s.log) = 0
ConsumeLinearized ==
  /\ Complete /\ Unused /\ s.receipt = 0 /\ Len(s.entries) < 2
  /\ s' = [s EXCEPT !.log = <<"identity">>,
      !.checkpoint = <<"identity">>, !.frontier = 1,
      !.receipt = 1, !.linearized = @ \cup {Len(s.entries) + 1}]
ProviderEntry ==
  /\ Complete /\ s.receipt = 1 /\ Len(s.entries) < 2
  /\ s' = [s EXCEPT !.entries = Append(@,
       [consume |-> Len(s.entries) + 1, seq |-> s.receipt,
        complete |-> Complete, anchored |-> Len(s.anchor)]),
       !.receipt = 0, !.dispatch = TRUE]
CheckpointAnchored ==
  /\ s.continuity /\ s.anchorState = "CURRENT"
  /\ Len(s.log) > Len(s.anchor)
  /\ s' = [s EXCEPT !.anchor = s.log, !.highWater = Len(s.log)]
Finish == /\ s.dispatch /\ ~s.terminal
          /\ s' = [s EXCEPT !.terminal = TRUE]
\* Every local destructive event invalidates continuity, including an unanchored tail.
LocalLoss(kind) ==
  /\ Mode # "live" /\ kind \notin s.faults
  /\ s' = [s EXCEPT !.faults = @ \cup {kind}, !.coverage = "INCOMPLETE",
      !.continuity = FALSE, !.receipt = 0,
      !.log = IF kind \in {"LoseReplayRows", "RollbackPrimaryAndCheckpoint"}
               THEN Empty ELSE @,
      !.checkpoint = IF kind \in {"LoseCheckpoint", "RollbackPrimaryAndCheckpoint"}
                      THEN Empty ELSE @,
      !.frontier = IF kind = "RollbackPrimaryAndCheckpoint" THEN 0 ELSE @,
      !.dispatch = IF kind = "LoseDispatchRows" THEN FALSE ELSE @,
      !.terminal = IF kind = "LoseTerminalEvidence" THEN FALSE ELSE @]
AnchorFault(kind) ==
  /\ Mode # "live" /\ kind \notin s.faults
  /\ s' = [s EXCEPT !.faults = @ \cup {kind}, !.receipt = 0,
      !.anchorState = kind,
      !.anchor = IF kind = "ROLLED_BACK" THEN Empty ELSE @]
\* Reconstruct only a covered range: no missing unanchored suffix can be forgotten.
Recover ==
  /\ ~s.continuity /\ s.anchorState = "CURRENT"
  /\ Len(s.anchor) = s.highWater /\ s.frontier <= Len(s.anchor)
  /\ ("RollbackPrimaryAndCheckpoint" \in s.faults => Len(s.anchor) = 1)
  /\ s.checkpoint = s.anchor /\ s.log = s.anchor
  /\ s' = [s EXCEPT !.coverage = "COMPLETE", !.continuity = TRUE]
\* H0 (never consumed) and H1 (consumed then all evidence lost) look identical.
UnsafeTreatMissingHistoryAsUnused ==
  /\ Mode = "missing" /\ Len(s.entries) = 1
  /\ "MissingAsUnused" \notin s.faults
  /\ s' = [s EXCEPT !.log = Empty, !.checkpoint = Empty,
      !.anchor = Empty, !.frontier = 0, !.highWater = 0,
      !.coverage = "COMPLETE", !.continuity = TRUE,
      !.anchorState = "CURRENT", !.receipt = 0,
      !.dispatch = FALSE, !.terminal = FALSE,
      !.faults = @ \cup {"MissingAsUnused"}]
UnsafeAllowRolledBackAnchor ==
  /\ Mode = "rollback" /\ Len(s.entries) = 1 /\ s.highWater = 1
  /\ "AcceptedOldAnchor" \notin s.faults
  /\ s' = [s EXCEPT !.log = Empty, !.checkpoint = Empty,
      !.anchor = Empty, !.frontier = 0, !.highWater = 0,
      !.coverage = "COMPLETE", !.continuity = TRUE,
      !.anchorState = "CURRENT", !.receipt = 0,
      !.faults = @ \cup {"AcceptedOldAnchor"}]
\* Explicit assumption failure: every continuity witness restored to common snapshot.
CommonSnapshotRestore ==
  /\ Mode = "common" /\ Len(s.entries) = 1 /\ s.highWater = 1
  /\ "AllWitnessesRestored" \notin s.faults
  /\ s' = [s EXCEPT !.log = Empty, !.checkpoint = Empty,
      !.anchor = Empty, !.frontier = 0, !.highWater = 0,
      !.coverage = "COMPLETE", !.continuity = TRUE,
      !.anchorState = "CURRENT", !.receipt = 0,
      !.faults = @ \cup {"AllWitnessesRestored"}]
Next == \/ ConsumeLinearized \/ ProviderEntry \/ CheckpointAnchored \/ Finish
        \/ \E k \in {"LoseReplayRows", "LoseDispatchRows", "LoseTerminalEvidence",
                      "LoseCheckpoint", "RollbackPrimaryAndCheckpoint"}: LocalLoss(k)
        \/ \E k \in {"UNAVAILABLE", "ROLLED_BACK", "EQUIVOCATED"}: AnchorFault(k)
        \/ Recover \/ UnsafeTreatMissingHistoryAsUnused
        \/ UnsafeAllowRolledBackAnchor \/ CommonSnapshotRestore
Spec == Init /\ [][Next]_vars
LiveSpec == Spec /\ WF_vars(ConsumeLinearized) /\ WF_vars(ProviderEntry)
TypeOK == /\ s.log \in {Empty, <<"identity">>}
          /\ s.anchor \in {Empty, <<"identity">>}
          /\ s.frontier \in 0..1 /\ s.highWater \in 0..1
          /\ s.receipt \in 0..1 /\ Len(s.entries) <= 2
AtMostOnce == Len(s.entries) <= 1
EntryHasPriorConsume == \A i \in 1..Len(s.entries):
  /\ s.entries[i].consume \in s.linearized /\ s.entries[i].seq = 1
  /\ s.entries[i].complete
UncertainCannotAdmit == (~Complete) => ~ENABLED ProviderEntry
NeverUsedEventuallyEnters == <> (Len(s.entries) = 1)
=============================================================================
