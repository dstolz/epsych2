# `hw.Psychtoolbox` — EPsych↔Psychtoolbox hardware abstraction

## Context

The lab wants to run Psychtoolbox-3 (`C:\src\Psychtoolbox-3`) visual/auditory experiments under
EPsych's session framework (trial dispatch, protocol files, DATA logging, online analysis) instead
of as standalone scripts. EPsych already supports heterogeneous hardware backends through
`hw.Interface`, so the natural approach is a new concrete backend, `hw.Psychtoolbox`, that lets the
EPsych coder issue commands to a PTB experiment the same way they'd drive a TDT rig or an Intan
system — via protocol parameters and triggers.

The hard constraint driving the whole design: a running PTB trial loop **blocks its MATLAB
interpreter** (`Screen('Flip')` is synchronous; `Screen` cannot leave the main thread or run
cross-process), while EPsych's `RunExpt` runs a 10 ms timer that must never block. The two cannot
share one MATLAB process. The user has decided:

1. PTB runs in a **second MATLAB process**, preferring the **Parallel Computing Toolbox**
   (`parfeval` process-pool worker + `parallel.pool.PollableDataQueue`) if Screen actually works
   there — this is **unverified** and gates everything, so Phase 0 is a feasibility spike. A
   spawned-MATLAB-plus-TCP transport is built regardless, both as the fallback if PCT fails and as
   the **manual-attach** path.
2. epsych2 ships a generic **PTB-side runner** (owns the window, serves the command link); the
   EPsych coder writes one **trial function** per paradigm — analogous to `hw.Bpod`'s
   `StateMatrixFcn` indirection — that presents a trial given dispatched parameters and returns a
   result struct.
3. Command surface = normal `hw.Parameter` writes/triggers **plus** a raw escape hatch
   (`sendCommand`/`remoteEval`) for arbitrary PTB calls from scripts or custom GUIs.
4. Launch = auto-spawn/own the PTB process by default, with manual-attach as a documented fallback
   via the connect-recovery dialog.

This closely parallels a previously reviewed (but unrelated-backend) design at
`plans/async-hardware-io.md` — a worker-owned-device architecture over `PollableDataQueue`s — and
reuses several of its verified constraints (queue creation direction, why `afterEach`/`DataQueue`
doesn't work under a 10 ms timer, `hw.Parameter.Parent` being immutable). It also reuses house
patterns from `hw.Bpod` (external engine, frozen result-field set, mode-getter-as-pump, watchdogs),
`hw.NE1000` (isolated transport seam for mockability, offline no-op semantics, connect-recovery
hooks), and `hw.VlcRecorder` (owning a spawned external process via .NET `Process`/`TcpListener`).

## Architecture

```
MAIN MATLAB (RunExpt, 10 ms PsychTimer)              PTB MATLAB PROCESS
┌─────────────────────────────────────────┐          ┌──────────────────────────────┐
│ hw.Psychtoolbox < hw.Interface           │  cmd──▶  │ ptb.Runner.serve loop        │
│  get.mode / get_parameter = msg pump     │          │  owns Screen window, KbQueue,│
│  set_parameter -> shadow + setParams msg │  ◀──upd  │  PsychPortAudio              │
│  trigger(x_NewTrial) -> startTrial msg   │          │  startTrial -> feval(TrialFcn)│
│  result shadow (frozen NaN-filled set)   │          │  polls cmd link per frame /  │
│  heartbeat watchdog -> mode=Idle on death│          │  between trials              │
└─────────────────────────────────────────┘          └──────────────────────────────┘
Transport A (default, gated on Phase-0 spike): PCT process-pool worker + PollableDataQueue pair
Transport B (fallback + manual attach): spawned MATLAB (-batch, zero-arg bootstrap) + tcpclient / pnet
Both behind one 5-method protected transport seam; a mock subclass overrides the seam for headless tests.
```

## Phase 0 — feasibility spike (must run before anything else)

New file `tmp/smoke_test_ptb_worker_screen.m` (self-bootstrapping, no epsych2 classes involved).
On a `parfeval` process-pool worker: addpath PTB + `PsychStartup`, `AssertOpenGL`,
`Screen('OpenWindow', ...)` (report pass/fail plus a `SkipSyncTests` retry), 60 flips with
monotonic-timestamp/ifi checks, `KbQueueCreate/Start` with an operator keypress window (tests
**background-process keyboard focus**, a real risk since the PTB window is never the OS
foreground shell), `GetSecs` offset vs the client (confirms shared-QPC time base), `Priority()`,
clean `sca` + reopen. Reports each check over a `PollableDataQueue` with a PASS/FAIL table.

**Decision gate:** all green → default transport = `pct`, TCP built as the attach/fallback.
Any hard failure (window/flip/KbQueue) → default transport = `tcp` (spawned MATLAB); the PCT link
stays in the codebase behind the seam but non-default. Record the verdict in
`documentation/hw/hw_Psychtoolbox.md` and in `hw.Psychtoolbox.DEFAULT_TRANSPORT`. Nothing else in
the plan depends on which way this goes except which link gets wired first in Phase 3.

## Package layout

### PTB-side runner — new package `obj/+ptb/` (self-contained: base MATLAB + PTB + PCT only, no
`hw.*`/`epsych.*`, so it stays usable from a bare MATLAB session)

| File | Purpose |
|---|---|
| `obj/+ptb/msg.m` | Shared message vocabulary + struct factories + TCP encode/decode framing (§ Protocol). |
| `obj/+ptb/@Runner/Runner.m` | Owns `win`, `ifi`, `audio` handle, `params_` shadow, `state`, the link adapter. |
| `obj/+ptb/@Runner/serve.m` | Main loop: poll link, dispatch messages, heartbeat replies, `try/catch` + `onCleanup(@sca)` so a crash never strands a fullscreen window. |
| `obj/+ptb/@Runner/runTrial_.m` | `feval(str2func(TrialFcn), obj, P)` in try/catch; normalizes the result against the frozen field set; sends `trialResult`. |
| `obj/+ptb/@Runner/openWindow_.m`, `closeWindow_.m` | `Screen('OpenWindow')`, `KbQueueCreate/Start`, optional `PsychPortAudio('Open', ...)`. |
| `obj/+ptb/@Runner/checkAbort.m` | Public — trial functions call this once per frame to absorb `abortTrial`/`setMode Idle`/`shutdown` mid-trial without blocking. |
| `obj/+ptb/@Runner/kbEvents.m`, `flushKb.m` | `KbEventGet`/`KbEventFlush` wrappers. |
| `obj/+ptb/serve_pct.m` | `parfeval` entry point: creates the worker-side `PollableDataQueue`, sends `hello`, builds `Runner`, runs `serve`. |
| `obj/+ptb/serve_tcp.m` | Spawned/manual-attach entry: `pnet('tcplisten', ...)` accept loop, `hello`, `Runner`, `serve`. This is the documented manual-attach command an operator can run by hand. |
| `obj/+ptb/PctLink.m`, `obj/+ptb/PnetLink.m` | Adapters: `send(msg)`, `msgs = poll(timeoutSec)`, `tf = alive()`. |

### EPsych-side backend — new package `obj/+hw/@Psychtoolbox/`

`Psychtoolbox.m` (classdef), `setup_interface.m`/`close_interface.m`, `get_parameter.m`/
`set_parameter.m`/`trigger.m`, `drainMessages_.m` (message pump + heartbeat + watchdogs),
`populateModule_.m` (fixed parameter table, merge-idempotent by hardware name — modeled on
`obj/+hw/@Bpod/populateModule_.m`), `getCreationSpec.m`, `selfTest.m`, `recoverConnection.m`,
`sendCommand.m`/`remoteEval.m`/`waitForReply.m` (escape hatch), and the protected transport seam
(`transportOpen_.m`, `transportClose_.m`, `transportSend_.m`, `transportPoll_.m`,
`transportAlive_.m` — the only 5 methods a mock subclass overrides, same discipline as
`hw.NE1000`/`hw.Intan_RHX`), plus `launchWorkerPct_.m`/`launchWorkerTcp_.m` for pool/process
startup (spawn uses the zero-arg-bootstrap-file pattern from `tmp/crash_test_trialjournal.m`,
since `-sd` is ignored under `-batch` and `Start-Process -ArgumentList` mangles quoted args; port
allocation copies `hw.VlcRecorder.pickFreePort_` — a .NET `TcpListener` on port 0).

## Message protocol (`ptb.msg`)

Plain structs, `type` + `t` (GetSecs). **Client→runner**: `configure`, `openWindow`, `setParams`,
`resetTrial`, `startTrial{trialID, params}` (fire-and-forget — must return immediately, same
lesson as `hw.Bpod/trigger.m`), `abortTrial`, `setMode`, `remoteEval{expr, corrId}`, `ping`,
`shutdown`. **Runner→client**: `hello`, `windowOpened`, `state`, `trialResult{trialID, results}`,
`pong`, `evalResult`, `log`, `error{fatal}`, `windowClosed`, `bye`.

Serialization: PCT passes structs natively through `PollableDataQueue`. TCP frames as
`uint32` length + `getByteStreamFromArray`/`getArrayFromByteStream` payload (handles large float
stimulus arrays and NaN/Inf losslessly, unlike JSON); note this pair is undocumented-but-stable —
a hand-rolled typecast codec is the documented fallback if it's ever an issue.

**Heartbeat/watchdog** (driven from `get.mode`/`get_parameter`, the two per-tick service hooks the
runtime guarantees, exactly where `hw.Bpod` pumps its byte protocol): `ping` every 0.25 s; on
`~transportAlive_()` **or** 5 s of silence → close transport, **`mode = Idle`** (not Error — only
Idle triggers `RunExpt.PsychTimerRunTime`'s auto-stop, and this is a *confirmed*-death condition,
not a slow one, so it doesn't violate the never-fabricate-Idle rule). `MaxTrialSeconds` (default
3600, Bpod-style) force-completes a hung trial with `Aborted=true` rather than freezing the
session at a trial boundary.

## `hw.Psychtoolbox` class

Key properties: `TrialFcn` (char, function name resolved on the runner), `BoxID`, `ScreenNumber`,
`Windowed`/`WindowRect`, `BackgroundColor`, `TransportMode` (`'auto'|'pct'|'tcp'`), `Host`/`Port`,
`SpawnMatlab`, `PtbRoot` (default `C:\src\Psychtoolbox-3\Psychtoolbox`), `EnableAudio`/`AudioFs`,
`SkipSyncTests`, `AbortOnWindowClose`, `HeartbeatInterval`/`HeartbeatTimeout`/`LaunchTimeout`/
`MaxTrialSeconds`, `HW` (required by `hw.Parameter`'s constructor). `mode` (SetObservable/AbortSet)
pumps `drainMessages_` then returns a cached value, matching `hw.Bpod.get.mode`. `IsConnected`
declared as a bare `Dependent` (MATLAB rejects validation on an abstract-implementing property, per
the `hw.NE1000`/`hw.Bpod` comments). `canRunOffline = false` — PTB *is* the stimulus/response
device, unlike a peripheral pump; a session without it would dispatch trials into nothing.

**`get_parameter`**: never touches `P.Value` (recursion), never blocks, never returns `[]`. Serves
`x_TrialComplete_<B>` from a cache flag, the frozen result names from a NaN-seeded shadow struct,
`_TrigState~<B>`/`_TrialNum~<B>` (GUI literals), else the parameter shadow or `P.Values{1}`.
Offline → return `P(i).Value` directly (safe: `hw.Parameter.get.Value` already short-circuits when
`~Parent.IsConnected`).

**`set_parameter`**: un-cell the array-value convention; route `hw.Interface.isStimulusValue`
values through `hw.Interface.stimulusPayload(stim, Module.Fs)` so the runner receives a ready
`PsychPortAudio`/draw payload; store in the shadow; send `setParams` immediately if connected
(so large stimulus buffers ship once, on change, not re-sent every trial).

**`trigger`**: never throws, always returns `now` (`Parameter.Trigger` assigns into a
`(1,1) double`). `x_ResetTrig_` clears the result shadow and sends `resetTrial`. `x_NewTrial_`
snapshots the parameter shadow, sends `startTrial`, and **returns immediately** — waiting here
would block the session timer, exactly the lesson documented in `hw.Bpod/trigger.m`.

## Module / parameters (`populateModule_`)

Trial control (all `Visible=false`, matching the documented Visible/Access matrix in
`hw/@Bpod/populateModule_.m`): `x_ResetTrig_<B>`/`x_NewTrial_<B>` (`Access='Any'`, `isTrigger=true`
— the runtime looks these up literally and errors if missing), `x_TrialComplete_<B>`
(`Access='Read'`), `_TrigState~<B>`/`_TrialNum~<B>` (Read, invisible, `gui.components.OnlinePlot` literals).

Trial configuration: `TrialType`, `TrialDuration` seeded by the backend; **the paradigm author adds
their own dispatched parameters in ProtocolDesigner on the module** — no backend code needed, since
`set_parameter` forwards any unrecognized name as a plain value the runner exposes to the trial
function under its `validName`. A `Type='StimType'` parameter (e.g. `Stimulus`) automatically
routes through `stimulusPayload`.

**Frozen result set** (`RESULT_PARAMETERS` constant, `Visible=true, Access='Read'`, no `Min` so
NaN survives clamping — copying the exact discipline `hw.Bpod.RESULT_PARAMETERS` documents,
because `RUNTIME.TRIALS(i).DATA(k) = data` throws on a field-set mismatch between trials):
`RespCode` (an `epsych.BitMask` mask — the literal name `gui.components.History`/`psychophysics.*` look up),
`RespLatency`, `StimOnsetTimestamp`, `RespTimestamp`, `TrialStartTimestamp`, `TrialDuration_Actual`,
`Aborted`, `MissedFrames`, `TrialFcnError`. `TrialID`/`computerTimestamp` are added by
`ep_TimerFcn_RunTime` itself, not by the backend.

## Trial-function contract + escape hatch

```matlab
function result = myParadigmTrial(R, P)
% R: ptb.Runner  — R.win, R.winRect, R.ifi, R.audio, R.checkAbort() (call once per frame),
%    R.kbEvents()/R.flushKb()
% P: struct, validName -> dispatched value (StimType params arrive as stimulusPayload structs)
% result: struct with fields from hw.Psychtoolbox.RESULT_PARAMETERS
```
On an uncaught error the runner reports `TrialFcnError=true, Aborted=true`, NaN elsewhere, and the
session keeps running — never throw-from-timer-context. Ship `tmp/ptb_demo_trialfcn.m` as a
working reference (fixation + timed stimulus + key-response scoring).

Escape hatch: `corrId = sendCommand(obj, type, payload)` (fire-and-forget) and
`out = remoteEval(obj, code, Timeout=5, Async=false)` (runner `eval`s `code` with `R` in scope).
The sync form is documented as script/GUI-callback-only — **never** from `get_parameter`/`trigger`
or a listener, since polling to completion there would violate the never-block rule; use
`Async=true` + `waitForReply` instead.

## Registry edits (all four sites; site 4 fails silently if skipped)

1. `obj/+epsych/@ProtocolDesigner/private/getAvailableInterfaceSpecs.m` — add the spec + factory,
   constructing with `Connect=false` (designer builds interfaces on every add/modify).
2. `obj/+epsych/@ProtocolDesigner/private/getInterfaceEditState.m` — `case 'Psychtoolbox'` reading
   live properties back into the options struct for Modify.
3. `obj/+epsych/@Protocol/toStruct.m` — guarded `isprop` blocks for the new property names
   (`TrialFcn`, `ScreenNumber`, `Windowed`, `WindowRect`, `BackgroundColor`, `TransportMode`,
   `SpawnMatlab`, `PtbRoot`, `EnableAudio`, `AudioFs`, `SkipSyncTests`); `Host`/`Port`/`BoxID` are
   already generic.
4. `obj/+epsych/@Protocol/createInterfaceFromStruct_.m` — `case 'Psychtoolbox'`, `Connect=false`.
   Missing this degrades a restored protocol to `hw.Software` with no error.

`getCreationSpec` options mirror the properties above (dropdown for `TransportMode`, folder-picker
for `PtbRoot`). Timing/engineering knobs (`Heartbeat*`, `MaxTrialSeconds`, `LaunchTimeout`) stay
plain properties, not spec options — rig configuration vs. engineering tuning.

## Connect / recovery / selfTest

`setup_interface`: resolve transport (`'auto'` → the Phase-0 verdict) → pct: reuse/create a
`parpool('Processes')`, `parfeval(@ptb.serve_pct, ...)`, block for `hello` up to `LaunchTimeout`;
tcp: allocate a free port, write cfg + a zero-arg bootstrap file, spawn via
`System.Diagnostics.ProcessStartInfo` (VlcRecorder pattern), `tcpclient` retry-connect — or, if
`SpawnMatlab=false`, attach directly to an operator-started `ptb.serve_tcp`. Send `openWindow`,
wait for `windowOpened`, create the module only if empty (keeps restored-protocol handles), and
merge-populate parameters idempotently. `close_interface` runs the VlcRecorder-style graceful-then-
kill shutdown ladder (`shutdown` → wait for `bye` → cancel/kill) and leaves the PCT pool warm for
reruns. `connectionRecoveryLabel` = `'PTB Session Options...'`; `recoverConnection` offers retry,
transport switch, or **attach to a running session** (Host/Port fields) — the documented
manual-attach path. `selfTest` checks `PtbRoot`/`Screen.mexw64` presence, `TrialFcn` resolvability,
PCT/pool state, and (invasive only) a full launch→flip→shutdown cycle.

## Test plan

- `tmp/smoke_test_ptb_worker_screen.m` — Phase 0 spike (rig display, PCT).
- `tmp/smoke_test_ptb_msg.m` — message factories, TCP frame round-trip incl. large arrays and torn
  frames (headless, MCP-safe).
- `tmp/Psychtoolbox_Mock.m` — overrides the 5 transport-seam methods with a scripted in-memory
  runner (headless).
- `tmp/smoke_test_ptb_iface_contract.m` — against the mock: module table shape, frozen Read-field
  consistency across trials with dissimilar results (the exact `DATA(k) = data` failure mode this
  must avoid), full `dispatchNextTrial` simulation (ResetTrig → parameter writes incl. a StimType
  param → NewTrial → tick-poll `TrialComplete` → `all_parameters` sweep), heartbeat-death →
  `mode==Idle`, `MaxTrialSeconds` force-complete, `Protocol.toStruct`/`fromStruct` round trip
  (proves registry site 4 doesn't silently degrade to `hw.Software`).
- `tmp/smoke_test_ptb_transport_pct.m` / `_tcp.m` — real link end-to-end on the rig: handshake,
  window open, a few trials via the demo trial function, kill-mid-trial recovery.
- `tmp/smoke_test_ptb_end2end.m` — full `epsych.RunExpt` session on the rig with a real protocol;
  verifies `RespCode`/`TrialID`/`computerTimestamp` land correctly in saved DATA.

Headless tests (msg, mock contract) run under the MCP persistent MATLAB session; transport/spike/
end2end tests need the rig's real display.

## Documentation

`documentation/hw/hw_Psychtoolbox.md` (architecture, transport verdict, full protocol table,
trial-function contract, manual-attach recipe); add `hw.Psychtoolbox` to CLAUDE.md's Concrete
Backends list; spot-check `documentation/hw/hw_Interface_Tutorial.md`'s registry-site list while
touching those files.

## Step ordering

1. **Phase 0** — spike, on the rig → transport verdict recorded.
2. **Phase 1** — transport-free core: `ptb.msg`, `ptb.Runner` (fake in-process link),
   `hw.Psychtoolbox` contract methods + `populateModule_` + seam stubs, mock + contract smoke test
   green (no display, no PCT needed).
3. **Phase 2** — the four registry edits + `getCreationSpec`; verify a `.eprot` round-trips through
   ProtocolDesigner.
4. **Phase 3** — implement the Phase-0-preferred transport end-to-end; transport smoke test green;
   `selfTest`/`recoverConnection`.
5. **Phase 4** — the second transport (TCP is needed regardless, for manual attach).
6. **Phase 5** — end-to-end RunExpt session on the rig with a real paradigm; audio path; docs.

## Known risks (cannot be resolved without the rig)

- Screen-on-PCT-worker viability (the whole point of Phase 0).
- Keyboard focus for a non-foreground window — spiked in Phase 0; mitigation is a focus assert at
  trial start if unreliable.
- `getByteStreamFromArray`/`getArrayFromByteStream` are undocumented (TCP path only); documented
  fallback is a hand-rolled codec.
- `RunExpt.PsychTimerRunTime`'s `any(get(Interfaces,'mode')==...)` may behave oddly across a
  heterogeneous multi-interface array — worth a direct check in Phase 5 since PTB will usually run
  alongside other hardware.
- GStreamer runtime required by Screen's multimedia path on Windows — `selfTest` warns rather than
  hard-fails; verify presence on the actual rig in Phase 5.

## Critical files to read before implementing

- `obj/+hw/@Bpod/Bpod.m`, `populateModule_.m`, `trigger.m` — donor pattern for the frozen result
  set, trigger dispatch, watchdogs.
- `obj/+hw/@Interface/Interface.m` — abstract contract, `stimulusPayload`, hardware-name helpers.
- `obj/+epsych/@Protocol/createInterfaceFromStruct_.m` — registry site 4 template.
- `obj/+epsych/@ProtocolDesigner/private/getAvailableInterfaceSpecs.m` — registry site 1 template.
- `plans/async-hardware-io.md` — reviewed PCT queue-direction/drain design this transport reuses.
- `obj/+hw/@NE1000/NE1000.m` — transport-seam isolation and offline no-op semantics.
- `obj/+hw/@VlcRecorder/VlcRecorder.m` — process spawn, port allocation, shutdown ladder.

## Verification

Run each `tmp/smoke_test_*.m` via the MATLAB MCP server (`run_matlab_file`, absolute paths) as it's
written — headless tests (msg, mock contract) first since they need no display or PCT license,
then the rig-dependent ones. After Phase 5, run a real session through `epsych.RunExpt` with a
protocol containing `hw.Psychtoolbox` and a working trial function, inspect the saved `.mat`/DATA
for `RespCode`/`TrialID`/`computerTimestamp`, and confirm `View Trials` in RunExpt shows the
dispatched parameter columns correctly.
