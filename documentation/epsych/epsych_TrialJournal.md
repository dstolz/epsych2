# epsych.TrialJournal — Crash-Safe Per-Trial Data Journal

## Why it exists

`ep_TimerFcn_RunTime` must persist every completed trial immediately, so a
mid-session crash (MATLAB segfault, power event, TDT ActiveX fault) loses
nothing. The original implementation appended each trial to a MAT-file with
`save(..., '-append', '-v6')`. That call rewrites the MAT variable index on
every append, so its cost grows with the file: measured 6.9 ms over trials
1–50 and 22.7 ms by trial 600 — most of a 10 ms PsychTimer tick, spent on one
line, getting worse for the whole session. It also rewrites the index *in
place*, so a crash during the rewrite can corrupt the entire file, not just
one trial.

`epsych.TrialJournal` keeps the same durability contract at a flat cost
(~2 ms, independent of session length): each record is serialized with
`getByteStreamFromArray` and appended as a length-prefixed block; the file is
opened, written, and closed on every append. Earlier bytes are never touched,
so at most the single in-flight record can be torn by a crash — and the
reader detects and skips a torn tail.

**Why not an asynchronous writer?** It was measured and rejected: a
`backgroundPool` write chain recovered **1 record out of thousands** after a
hard process kill, because the queued writes die with the process. The write
must stay synchronous.

## File format (`.epj`, version 1)

```
bytes 1-4   signature 'EPJ1'
per record: uint64 length  +  <length> bytes of getByteStreamFromArray(rec)
            where rec = struct('name', 'data_0004', 'data', <trial struct>)
```

Byte-stream serialization preserves full MATLAB type fidelity (datetime,
cell, string, logical, uint32, arrays) — which JSON would not.

## Lifecycle in a session

1. `ep_TimerFcn_Start` still creates the seed `.mat` (info only) at
   `RUNTIME.DataFile(i)`, then creates the journal beside it (same name,
   `.epj`) and writes `info` as its first record. `RUNTIME.Journal(i)` holds
   the handle.
2. `ep_TimerFcn_RunTime` appends one `data_%04d` record per completed trial.
3. `ep_TimerFcn_Stop` merges the journal into the seed `.mat`
   (`epsych.TrialJournal.mergeToMat`) — one save call per session — so the
   recovery artifact keeps the legacy `info + data_NNNN` layout and every
   downstream consumer is unchanged.

A fourth writer appends out of band: `epsych.SessionNotes` rewrites the
**whole** notes log under the single record name `notes` every time the
operator commits one. That is affordable because notes are typed at human
rates and run to a few hundred bytes, and it is what removes any need to
stitch fragments together after a crash — the reader resolves records
last-wins, so the newest complete log is the one that comes back. Records
are keyed by name, so a repeated name replaces rather than duplicates; the
per-trial writer relies on the same rule never firing, since each trial
gets a name of its own.

The `.epj` is left in place after the merge. It costs a second copy of the
trial records in the temporary data directory and buys a recovery path if the
merge itself is interrupted; delete it with the `.mat` when clearing that
directory.

## Reading a session that is still running

The seed `.mat` holds only `info` until `ep_TimerFcn_Stop` merges — mid-run,
the trials are in the `.epj`. Read them without disturbing the session (the
journal file is closed between appends):

```matlab
S = epsych.TrialJournal.read('...\RUNTIME_DATA_Subj_Box_01_260813084500.epj');
```

## Crash recovery

```matlab
epsych.TrialJournal.recover('...\RUNTIME_DATA_Subj_Box_01_260813084500.epj')
```

rebuilds the `.mat` from the orphaned journal and reports how many trials
were recovered and whether the final record was torn.

## Failure policy

A journal write failure latches `Faulted`, logs once at level 0, and reroutes
that record and all later ones to `save('-append')` on `FallbackMatFile`
(the seed `.mat`). `append` never throws after construction — losing the
recovery channel must never abort a live experiment.

## Compatibility

- A **custom Start function** that predates the journal seeds only the
  `.mat`; `ep_TimerFcn_RunTime` detects the missing journal and keeps the
  legacy `save('-append')` path for that session.
- The primary save path (`ep_SaveDataFcn` over `RUNTIME.TRIALS(i).DATA`) is
  untouched; the journal only replaces the crash-recovery channel.

## Tests

- `tmp/smoke_test_trialjournal.m` — round-trip fidelity, mergeToMat parity
  with the legacy artifact, torn-tail truncation sweep, fallback latch,
  flat-cost assertion.
- `tmp/smoke_test_runtime_journal.m` — the real
  Start → RunTime → Stop chain over `hw.Software`.
- `tmp/crash_test_trialjournal.m` — **the test that matters**: spawns a
  writer MATLAB, hard-kills it mid-write, asserts recovered records are
  contiguous `1..N`. Last run: 7,370/7,370 completed records survived. Run it
  after any change to this class; the durability property is invisible to
  every throughput benchmark.
- `epsych.SelfTest` check H3 exercises the same seed → append → merge chain
  against the operator's configured run-time data directory.
