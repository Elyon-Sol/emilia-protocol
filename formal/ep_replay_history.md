# Replay-history completeness model (#906)

Model-only bounded artifact, based on main
`c7408b6e7923095cd359ef976666ce21ba178177`. This does not establish a
production external anchor, an independent witness operator, runtime
implementation refinement, or universal recovery safety.

## Separate hot path and recovery evidence

`ConsumeLinearized` atomically consumes one exact identity and returns an
identity-bound sequence receipt. `ProviderEntry` is a separate later transition
requiring that receipt and complete authoritative history. The receipt cannot
be reused. `CheckpointAnchored` is independent and asynchronous: the first
provider entry may carry `anchored = 0`. A later anchor is never treated as a
pre-entry timestamp. Synchronous anchoring is not modeled or required.

The two stores are (1) authoritative replay log plus local checkpoint, dispatch
and terminal rows, and (2) external anchor root/frontier and retained high-water
mark. A root is the exact ordered sequence, abstracting collision resistance;
frontiers are sequence lengths. `Complete` requires local checkpoint/log root
agreement and consistency with the anchor prefix and high-water mark. This
single-identity, two-attempt abstraction deliberately has only roots `<<>>`
and `<<"identity">>`; it does not model multi-identity cryptography or races.

Loss of replay rows, dispatch rows, terminal evidence, local checkpoint, or
rollback of primary plus checkpoint explicitly invalidates continuity and
outstanding receipts. Unavailable, rolled-back and equivocating anchor views
block entry. `Recover` can restore COMPLETE only for a matching covered root
and frontier. Rollback with an empty anchor stays uncertain even if it happened
in a never-used history: this conservative availability cost prevents treating
an uncovered lost suffix as unused. Recovery does not reconstruct lost bytes;
matching bytes must already have been restored. There is no compaction algorithm
or automatic recovery liveness claim.

## Assumptions and their failure

The safe model assumes authoritative consume-if-absent linearization, valid
receipts, complete mediation, trustworthy continuity/loss detection, and an
independent retained anchor high-water mark. The fault labels denote detected
faults, not an implemented loss detector. Arbitrary silent local rollback cannot
be made detectable by a periodic anchor that never saw the missing suffix.
Such a deployment must retain trustworthy continuity evidence or stay uncertain;
this model does not invent that evidence. Dispatch/effect truth is not proved.

`CommonSnapshotRestore` explicitly violates independence: local log/checkpoint,
anchor, high-water mark and continuity view all return to a shared old snapshot.
The observer's provider-entry history remains solely to expose the replay.
The resulting counterexample shows why safe results cannot be extended to an
attacker controlling every continuity witness. Those observer records and the
`linearized` set are specification history, never recovery inputs.

## Checked properties and negative controls

- `TypeOK`: bounded root, frontier, receipt and entry types.
- `AtMostOnce`: at most one entry for this identity, including after destruction.
- `EntryHasPriorConsume`: each observed entry has a prior consume receipt,
  nonzero sequence and complete history at admission.
- `UncertainCannotAdmit`: incomplete or inconsistent history disables entry.
- `NeverUsedEventuallyEnters`: under weak fairness of consume and entry and
  no faults, a never-used identity eventually enters. This prevents a vacuous
  deny-everything model; faulted histories have no liveness guarantee.

`missing` uses `UnsafeTreatMissingHistoryAsUnused`: H1 consumes and enters, all
local replay evidence is forgotten, and the recovered empty view is treated as
H0 (never used). The shortest trace has no anchor; a second consume and entry
violate AtMostOnce. `rollback` first anchors the consumed root, then deliberately
accepts the earlier empty checkpoint/anchor and resets its high-water pin;
a second consume/entry exposes rollback. `common` produces the analogous
counterexample when every independent-witness assumption fails. These unsafe
transitions are excluded from `safe` and `live` configs.

## Reproduction

```
python3 formal/ep_replay_history_check.py [path/to/tla2tools-1.7.4.jar]
```

The default is `~/.cache/emilia/formal/tla2tools-1.7.4.jar`; SHA256 is checked
against `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.
Each run uses one worker, 512 MiB heap and a 60-second wall-time bound, with
isolated temporary state deleted afterwards. Raw logs are preserved here in
`ep_replay_history_results/`. The runner requires success for safe/liveness
and the named mutation, two consumes, two entries and AtMostOnce failure for
each negative control. It does not count a parser failure as a counterexample.
No repository-wide suite or shared evidence generation is needed for this
standalone model. It is not added to existing formal/runtime claim counts.
