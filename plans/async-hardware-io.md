# Non-Blocking Hardware I/O Layer (`hw.AsyncInterface`)

> **Revision note (2026-08-04)**: this plan was critically reviewed against the working tree on
> branch `NewProtocol`. Every code claim below was re-verified; the review corrected ~8 factual
> errors, found a 4th delegation call site, and added 4 design fixes for races the original plan
> would have shipped (see "Review findings" at the end). The core architecture — worker-owned
> device, delegate redirection on the twin, queue IPC, JSONL log — survived review unchanged.

## Context

Every hardware parameter access in EPsych v2 is a synchronous round-trip on MATLAB's single thread: `hw.Parameter.get.Value` ([Parameter.m:197-222](../obj/+hw/@Parameter/Parameter.m)) calls `Parent.get_parameter` (COM `ReadTagVEX` via `TDTRP.m:264` for TDT_RPcox, HTTP `urlread2` via `SynapseAPI.m:183` for TDT_Synapse, TCP busy-poll at `Intan_RHX.m:717-724` for Intan_RHX). The PsychTimer tick (10 ms default, user-configurable), every GUI monitor timer, and all Helper-event listeners share that thread, so a slow device call stalls the GUI and trial loop — evidenced by `% FIX PERFORMANCE` (OnlinePlot disabled in [cl_AppetitiveDetection_GUI_B.m:96](../cl/@cl_AppetitiveDetection_GUI_B/cl_AppetitiveDetection_GUI_B.m)), the Intan mode-cache workaround (`Intan_RHX.m:836-843`, whose docstring says outright that "a blocking TCP round-trip per tick would dominate the trial loop"), and the >0.25 s selector warning in `ep_TimerFcn_RunTime.m:97-106`.

The load is heavier than the trial loop alone suggests. `RunExpt.PsychTimerRunTime` ([RunExpt.m:457-464](../obj/+epsych/@RunExpt/RunExpt.m)) reads `mode` from **every** interface on **every** tick — before `ep_TimerFcn_RunTime` even runs — and each concrete backend implements `get.mode` as a live device query. `gui.OnlinePlotBM` polls at 50 ms and `Parameter_Monitor.poll_parameters` does one blocking read per displayed parameter per tick, all on the same thread.

**Goal**: a non-blocking I/O layer where a background MATLAB worker process (Parallel Computing Toolbox — licensed, and verified *entirely unused* in this repo today) owns the real hardware connection, and the foreground reads a cache / enqueues writes.

**User decisions (locked)**:
1. Worker-process architecture (background process owns hardware, poll/command loop, push updates).
2. Generalized over `hw.Interface` — works with TDT_RPcox, TDT_Synapse, Intan_RHX, and future backends unchanged.
3. Cached reads + push updates, worker-side trial-data snapshot on TrialComplete edge, synchronous `freshRead` escape hatch.
4. Opt-in decorator/proxy; existing sync path and `hw.Software` untouched.
5. Optional worker-side **JSONL parameter event log** — timestamped, changed-only, one file per run — doubling as an experiment record and an externally pollable secondary channel. Queues remain the primary foreground IPC: in-memory `poll(q,0)` is µs-scale and lossless, while file+`jsondecode` polling from the 10 ms tick would cost ~ms of disk/parse per poll, need torn-line handling, and lose type fidelity (NaN/Inf, single, shapes). See "Parameter event log" below.

## Verified design constraints (shaped the approach)

- **`hw.Parameter.Parent` and `hw.Module.parent` are `SetAccess=immutable`** (`Parameter.m:42-45`, `Module.m:37-42`). The parameter tree cannot be re-parented, and cloning it would break handle identity with `COMPILED.parameters`, `RUNTIME.CORE` triggers, and GUIs. → Use **delegate redirection**: a Transient `IODelegate` slot on `hw.Interface`, consulted by `hw.Parameter`. Handle identity preserved everywhere; zero changes to `ep_TimerFcn_RunTime.m` or `dispatchNextTrial.m`.
- **`Parameter.Parent` is the *Interface*, not the Module** — despite the comment on `Parameter.m:43`. Every construction site passes the interface (`Module.add_parameter` → `Module.m:116` `hw.Parameter(obj.parent, ...)`; `Software.m:55`; `createInterfaceFromStruct_`). `Parameter.get.Module` (lines 224-261) exists precisely to resolve the owning module back out. So `Parent.get_parameter/set_parameter/trigger` are interface methods, and `IODelegate` on `hw.Interface` is the correct interception point.
- **The proxy must NOT be persisted in .eprot**: Protocol serialization is `toStruct`/`fromStruct`, and `createInterfaceFromStruct_.m:23-70` has a hard-coded Type switch whose `otherwise` silently degrades to `hw.Software`. → Wrap at runtime (`Runtime.set.Interfaces`), never persist.
- **COM (`actxserver('RPco.X')`) cannot cross processes** — the worker constructs and owns the real interface. Requires a **process** pool (not `backgroundPool`/threads, which don't support COM).
- **Queue directions** (PCT semantics): commands client→worker via `parallel.pool.PollableDataQueue` created **on the worker** (sent back in handshake); updates worker→client via `PollableDataQueue` created **on the client** (passed to `parfeval`). No `afterEach`/`DataQueue` — its callback only runs when the main thread idles, which is unreliable under a 10 ms timer. The client drains with non-blocking `poll(q,0)` at deterministic points instead.
- **`disconnect()` is on none of the base contract** — not abstract, not a base implementation. It exists only on the five concrete classes, and `RunExpt.onCloseRequest.m:32-45` calls it. The proxy must implement it.
- **`prepareRecording` is a no-op on the base class** (`Interface.m:147`), overridden only by `Intan_RHX`, whose `arguments` block enforces `runtime (1,1) epsych.Runtime` (`prepareRecording.m:18-21`). It is called as `arrayfun(@(p) p.prepareRecording(self.RUNTIME), ...)` at `ExptDispatch.m:120`. A struct stand-in fails validation → the worker must receive a reconstructed `epsych.Runtime` with plain fields copied.
- **Expression eval reaches across interfaces** via `thisModule.parent` → `iface.Runtime` → `rt.Interfaces` (`evaluateExpression_.m:91-118`). The wrap step must set `Runtime` on the twin too, not just the proxy. Note `Runtime` is untyped and `Protocol.fromStruct.m:82` temporarily assigns an `epsych.Protocol` into it — keep it untyped.
- **`Parameter.get.Value` has a legacy `TooManyInputs` fallback** (lines 210-215) because `hw.VlcRecorder.get_parameter(obj,name)` takes no options. The proxy must accept the full options form so this path never triggers.
- **Backend I/O signatures diverge** — five different shapes (`Intan_RHX` adds `ReturnRaw`; `Software`'s options block is commented out; `VlcRecorder` has none) with different return contracts (scalar / cell / logical array / unconditional `nan`). The proxy forwards an options struct rather than assuming one shape.

## Architecture

```
MAIN MATLAB (GUI + PsychTimer)                    WORKER PROCESS (parfeval)
┌────────────────────────────────────┐            ┌──────────────────────────────┐
│ Protocol owns "twin" interface     │   cmdQ     │ serverLoop / ServerCore      │
│  (never connected; keeps the       │  (worker-  │  rebuilds its own interface  │
│   Module/Parameter tree everyone   │   made) ──>│  from a struct, connect()s   │
│   holds handles into)              │            │  it — owns COM/HTTP/TCP      │
│ twin.IODelegate = hw.AsyncInterface│   updQ     │  loop:                       │
│  get_parameter -> cache (instant)  │  (client-  │   drain cmds FIFO            │
│  set_parameter -> enqueue +        │   made) <──│   hot poll (TrialComplete)   │
│    write-through cache             │            │   mode poll (250ms)          │
│  trigger -> enqueue                │            │   warm round-robin (~100ms)  │
│  freshRead -> corrId req/resp      │            │   TrialComplete edge ->      │
│  mode = SetObservable property     │            │     snapshot ALL Read params │
│  drains updQ in get_parameter,     │            │     push trialComplete blob  │
│    get.mode + 0.1s timer           │            │   tee changed vals -> log    │
└────────────────────────────────────┘            └──────────────────────────────┘
```

- `RUNTIME.Interfaces` holds the proxy; the Protocol keeps the twin. `twin.IODelegate` doubles as the cross-run registry so reruns reuse the same worker/device connection (TDT cannot survive delete/recreate — see the comment in `Runtime.delete`, `Runtime.m:83-101`).
- Worker also appends changed parameter values to a per-run JSONL event log; the log lands next to `Runtime.SessionDataFilename`, so no `savefcns` changes are needed.
- **Consistency**: the `trialComplete` message carries the full Read-parameter snapshot; the drain applies the snapshot to the cache *before* setting the cached TrialComplete flag. `RunExpt.PsychTimerRunTime` reads `mode` (forcing a drain) at the very top of every tick, and `ep_TimerFcn_RunTime.m:22` then reads `CORE(i).TrialComplete.Value` before anything else — so the `all_parameters` burst at line 40 reads exactly the trial snapshot. The snapshot is taken in the worker at the moment of the edge — more accurate than today's serial read burst.
- Snapshot atomicity is **per interface**. A multi-interface protocol still assembles `DATA` from N independently-snapshotted interfaces — no regression versus today's serial read burst, which has the same property, but it is not an atomicity guarantee across interfaces.
- The `pause(0.001)` trigger pulses (`TDT_RPcox.m:450`, `TDT_Synapse.m:335`) and all transport latency move into the worker.

## New files

| Path | Contents |
|---|---|
| `obj/+hw/@AsyncInterface/AsyncInterface.m` | Proxy classdef: `Wrapped_` (twin), `CmdQueue_`, `UpdQueue_`, `Future_`, `CacheValues_`/`CacheTimes_` (id-indexed), `IdByFullName_` map, `PendingSeq_`, `CmdSeq_`, `Faulted_`, `Passthrough_`; `mode` as a stored `SetObservable, AbortSet` property; `get.IsConnected`; `Module` mirroring the twin's handles; static `wrap(iface)`, `ensurePool_`, `serverLoop` |
| `obj/+hw/@AsyncInterface/connect.m` | Pool startup/reuse, `parfeval(serverLoop,...)` with the twin **struct** payload, handshake, initial snapshot + FullName tree sync, passthrough fallback |
| `obj/+hw/@AsyncInterface/disconnect.m` | `shutdown` command, future cleanup |
| `obj/+hw/@AsyncInterface/get_parameter.m` | Throttled drain (≥2 ms apart) + cached read; throws `hw:AsyncInterface:WorkerFault` if `Faulted_` (so PsychTimerError fires — never silently stale). Accepts the full options form (`includeInvisible`, `silenceParameterNotFound`, `ReturnRaw`) |
| `obj/+hw/@AsyncInterface/set_parameter.m` | Write-through cache + enqueue with `cmdSeq`; un-cells the conditional `{array}` wrapper from `set.Value:315` before caching |
| `obj/+hw/@AsyncInterface/trigger.m` | Enqueue; returns client-side `now` immediately (`Parameter.Trigger` assigns into `lastUpdated (1,1) double`). If id registered Role=ResetTrig, optimistically zero the paired TrialComplete cache entry |
| `obj/+hw/@AsyncInterface/setMode_.m` | **Synchronous** mode change (corrId ack) — see A2 below |
| `obj/+hw/@AsyncInterface/freshRead.m` | Correlation-id request; poll `UpdQueue_` with timeout (default 2 s) |
| `obj/+hw/@AsyncInterface/registerHotParameter.m` | Role (NewTrial/ResetTrig/TrialComplete), poll period; forwards `registerHot` to worker |
| `obj/+hw/@AsyncInterface/prepareRecording.m` | Synchronous forwarded call (corrId ack; errors propagate → aborts start) |
| `obj/+hw/@AsyncInterface/drainUpdates_.m` | Message pump: update/modeChange/trialComplete/warn/error/ack dispatch, with sequence gating |
| `obj/+hw/+async/@ServerCore/ServerCore.m` | Pool-free, testable worker logic: command execution, poll scheduling, edge detection, snapshotting |
| `obj/+hw/+async/msg.m` | Message-type constants + struct factories (wire protocol vocabulary) |
| `obj/+hw/+async/@EventLog/EventLog.m` | Append side (open/append/close, NaN/Inf sentinel encoding, batch flush) + static offset-tailing reader; pool-free and unit-testable |
| `obj/+hw/@AsyncInterface/readEventLog.m` | Client convenience wrapper over `EventLog.read` (diagnostics/GUI use) |
| `documentation/hw/hw_AsyncInterface.md` | Docs (repo convention) |
| `tmp/AsyncMockInterface.m` | Serializable in-memory `hw.Interface` with injectable latency, scripted TrialComplete, command log |
| `tmp/smoke_test_com_in_worker.m` | **Phase 0 spike**: process pool + `actxserver('RPco.X')` + `ReadCOF` on an `.rcx` — no hardware needed |
| `tmp/smoke_test_async_servercore.m` | ServerCore in-process (fake queues): FIFO ordering, edge+snapshot atomicity, warn/error semantics, failed-set readback |
| `tmp/smoke_test_async_proxy.m` | Real pool: handshake, cached reads, write-through, seq gating, freshRead, staleness bounds, worker-kill fault, `ForceSyncFallback` passthrough |
| `tmp/smoke_test_async_trial_cycle.m` | Full Runtime trial loop against the mock: DATA matches scripted values; command log shows reset→writes→newtrial per trial; no double-processed trials; mid-run recompile works |
| `tmp/smoke_test_async_eventlog.m` | Round-trip incl. NaN/Inf sentinels; torn-line tolerance; append-while-reading |
| `tmp/smoke_test_async_failure.m` | Worker crash / fallback paths |
| `tmp/async_latency_harness.m` | Sync vs async tick-time comparison |

## Modified files (surgical)

1. **[Interface.m](../obj/+hw/@Interface/Interface.m)** — add `properties (Transient) IODelegate = [] end`; add `SupportsAsyncIO` (Constant, default `false`; `true` on TDT_RPcox / TDT_Synapse / Intan_RHX). Make `Runtime` (line 43) Transient. **Delete `h_listeners` (line 42) outright** — verified dead: it is declared and never read or written anywhere in the repo.
2. **[Parameter.m](../obj/+hw/@Parameter/Parameter.m)** + **[set_value.m](../obj/+hw/@Parameter/set_value.m)** — the only hot-path change. Add private helper:
   ```matlab
   function b = backend_(obj)
       b = obj.Parent;
       if isa(b,'hw.Interface') && ~isempty(b.IODelegate), b = b.IODelegate; end
   end
   ```
   Route through it in **four** places:
   - `get.Value` — replace `obj.Parent` in **both** the line-204 Software/disconnected short-circuit and the line-208 `get_parameter` call. Pivotal: the twin stays disconnected, so without routing the short-circuit the proxy is never consulted.
   - `set.Value` line 316.
   - `Trigger` line 283.
   - **`set_value.m:15`** — a protected method that bypasses `set.Value` entirely and routes through `obj.HW`. Missed by the original plan; must route the same way.

   Empty `IODelegate` ⇒ byte-identical behavior.
3. **[Runtime.m](../obj/+epsych/@Runtime/Runtime.m)** — new `UseAsyncIO (1,1) logical = false`; in `set.Interfaces` (lines 103-119), when enabled, replace each entry whose `SupportsAsyncIO` is true and which is not already a proxy with `hw.AsyncInterface.wrap(p)` before the connect loop; set `Runtime` on both proxy and twin. Also new `EventLogEnabled (1,1) logical = true`. `savefcns` untouched — the log is named from the already-reserved `SessionDataFilename`. (Incidental: the `Interfaces` comment on line 47 calls it a cell array; it is an object array. Fix while there.)
4. **[resolveCoreParameters.m](../obj/+epsych/@Runtime/resolveCoreParameters.m)** — in the `for cc = obj.REQUIRED_TRIGGERS` loop, alongside the `obj.CORE(subjectIdx).(cc) = p;` cache write at line 35: if `p.Parent.IODelegate` is an AsyncInterface, call `registerHotParameter(p, Role=char(cc))`. Roles come from the Constant `Runtime.REQUIRED_TRIGGERS = ["NewTrial","ResetTrig","TrialComplete"]` (`Runtime.m:63`) — a string array, not an enum.
5. **[ExptDispatch.m](../obj/+epsych/@RunExpt/ExptDispatch.m)** — after `self.RUNTIME = epsych.Runtime;` (line 28): `self.RUNTIME.UseAsyncIO = getpref('ep_RunExpt','UseAsyncIO',false);`
6. **RunExpt [buildUI.m](../obj/+epsych/@RunExpt/buildUI.m) + toggle callback** — add a checkable uimenu "Background Hardware I/O (experimental)" under the existing `mCustom` menu (created at line 38), persisted via the getpref/setpref pattern used by the "Record video" checkbox at lines 127-133. (The original plan cited "the checkable-uimenu-with-prefs pattern at buildUI.m:38-42" — no such pattern exists; the only checkable menu there, `always_on_top`, uses no prefs.)
7. **[stimbridge/InterfaceAdapter.m](../obj/+stimbridge/InterfaceAdapter.m)** — see F2 below: reads must go through `freshRead` when a delegate is present.
8. **[Protocol/createInterfaceFromStruct_.m](../obj/+epsych/@Protocol/createInterfaceFromStruct_.m)** + **[Protocol/toStruct.m](../obj/+epsych/@Protocol/toStruct.m)** — extract the per-interface build/serialize logic into shared helpers (`hw.Interface.toStruct` / static `hw.Interface.buildFromStruct`), with Protocol delegating. See C below. Behavior-preserving refactor.

**Explicitly unchanged**: `ep_TimerFcn_RunTime.m`, `dispatchNextTrial.m`, all concrete backends, `hw.Software`, `hw.VlcRecorder`, GUIs, Protocol serialization *format*.

**Not addressed by this work**: the trial-complete branch also does `save(..., '-append')` on the foreground thread (`ep_TimerFcn_RunTime.m:56`). Async I/O does not remove that latency source. Candidate future work; out of scope here.

## Wire protocol (plain structs, constants in `hw.async.msg`)

Client→worker (`CmdQueue_`, strict FIFO; worker fully drains commands before each poll pass — preserves reset→writes→newtrial ordering): `connect`, `set{id,value,seq}`, `trigger{id,seq}`, `setMode{mode,seq,corrId}`, `freshRead{ids,corrId}`, `prepareRecording{rtInfo,corrId}`, `registerHot{ids,roles}`, `pollConfig{ids,periodSec}`, `logConfig{enabled,pathOverride}`, `ping{corrId}`, `shutdown{haltDevice}`.

Worker→client (`UpdQueue_`): `handshake{cmdQueue}`, `connectResult{ok,errStruct,treeSync,snapshot}`, `update{ids,values,lastSeq}` (batched changed-only), `modeChange{mode,lastSeq}`, `trialComplete{hotId,snapshot,lastSeq}`, `freshReadResult`/`ack`/`pong{corrId,...}`, `warn{level,msgText}`, `error{fatal,errStruct}`, `bye`.

The `trialComplete` snapshot covers the interface's Read parameters, matching what `ep_TimerFcn_RunTime.m:40` collects. Note `valueOnly` is an option on **`Runtime.all_parameters`**, not on `hw.Interface.all_parameters` (which offers `asStruct` and returns handles) — the worker builds the value snapshot itself.

`prepareRecording{rtInfo,corrId}` additionally (re)opens the JSONL event log from `rtInfo.SessionDataFilename` when logging is enabled; every executed `set`/`trigger` and every pushed `update`/`modeChange`/`trialComplete` is teed to the log when open.

### Ids: FullName-keyed, worker-assigned

Ids are **assigned by the worker after `connect()`** and returned in `connectResult.treeSync` as `{id, FullName, module info}`; the client maps twin parameters by `FullName`.

Positional ids over "an identical enumeration on both sides" — the original plan's scheme — is unsound: `TDT_RPcox.connect()` populates parameters only `if isempty(module.Parameters)` (the shipped tree survives), but **`TDT_Synapse.connect()` → `setup_interface.m:50` rebuilds `obj.Module` from scratch**, discarding it. The two backends therefore do not agree on enumeration order or membership.

The client warns on parameters present on only one side; unmapped twin parameters fall back to their stored `Value`, matching today's disconnected behavior.

## Worker loop (ServerCore.run_once)

1. `poll(cmdQueue, 0.002)` (doubles as loop sleep) → drain ALL pending commands FIFO. `set` failures → `warn` (matches today's non-fatal vprintf) **plus an immediate device read-back pushed as an `update`** (A3). `get`/`connect` failures → `error{fatal}` (matches today's rethrow → PsychTimerError).
2. Hot poll every iteration (~2-5 ms): TrialComplete rising edge → serial snapshot of all Read params → `trialComplete` push; other hot changes → `update`.
3. Mode poll every 250 ms → `modeChange` on change.
4. Warm poll: ~100 ms budget, round-robin K non-array/non-hot Read params per iteration, batched `update`.
5. On fatal device error: stop polling, keep serving `freshRead`/`shutdown` for debugging.
6. Tee each pushed `update`/`modeChange`/`trialComplete` batch and each executed `set`/`trigger` to the JSONL event log (when open); flush per batch.

Every outbound push carries `lastSeq` = the highest command sequence number executed so far.

## Ordering & consistency

**Write-through cache** on `set_parameter`: expressions, `updateTrialsFromParameters` (which reads `.Value` back at line ~20 — verified live read-after-write), and GUI read-back see new values immediately. The foreground Parameter pipeline (PreUpdateFcn→randomize→Expression→EvaluatorFcn→clamp, `Parameter.m:299-309`) is untouched — the worker only does raw name-based device writes.

**A1 — Sequence gating (stale updates must not clobber fresh writes).** A warm/hot-poll `update` batch can carry a value the worker read *before* executing a `set` the client already enqueued. Applying it would briefly revert the parameter — visible to expressions and to `updateTrialsFromParameters`. Fix:
- Client stamps every `set`/`trigger`/`setMode` with a monotonic `CmdSeq_`, and records `PendingSeq_(id) = seq`.
- Worker echoes `lastSeq` (highest executed command seq) on every push.
- On drain, a poll-sourced value for `id` is **dropped** while `PendingSeq_(id) > batch.lastSeq`; otherwise applied and the pending entry cleared.
- The same gate applies to `modeChange` versus a pending `setMode`.

**A2 — `setMode` is synchronous (corrId ack).** `ExptDispatch.m:123` sets `mode` on all interfaces and `:125` immediately starts the timer, whose first tick auto-stops the run if any interface reads `Idle` (`RunExpt.m:457-464`). A fire-and-forget `setMode` against a stale mode cache stops the run on tick 1. Mode changes only happen at start/pause/stop, so a blocking round-trip is free — and it matches today's semantics, since concrete `set.mode` implementations already block until applied (`Intan_RHX.applyMode_` even confirms with a poll). The proxy also write-throughs the mode cache on set.

**A3 — Failed writes must not leave the cache diverged.** Today a device write failure is a non-fatal vprintf. Under write-through caching, a cached value for a never-applied write would persist indefinitely for hot or rarely-polled parameters. The worker therefore reads the device value back immediately after a failed `set` and pushes it as an `update` stamped with the failing command's seq, so A1's gate admits it.

**A4 — `mode` must be the proxy's real observable property.** GUI components attach `PostSet` listeners to `mode` (`Parameter_Control.m:464`, `OnlinePlot.m:423`, `MicrophonePlot.m:90`, `PumpCom.m:111`), and they hold the *proxy* from `RUNTIME.Interfaces`. So `mode` is a stored `SetObservable, AbortSet` property (same pattern as every concrete backend), assigned by the drain on `modeChange` — listeners fire, `AbortSet` dedups. Consequence to accept: hardware-initiated Idle detection latency grows from ~10 ms to ~250 ms (the worker mode-poll period).

**Trigger/TrialComplete race** handled by the ResetTrig optimistic clear (see `trigger.m` above); Runtime declares the pairing in `resolveCoreParameters` so the proxy stays hardware-agnostic.

**Dispatch ordering** is order-critical and preserved by FIFO: `dispatchNextTrial.m:20-62` does ResetTrig → per-parameter writes → NewTrial, and the worker drains all commands before each poll pass.

**Audited read-after-set consumers**: `updateTrialsFromParameters` (write-through cache ✓), `eval_staircase_training_mode` — its `isa(P.Parent,'hw.Software')` check at `eval_staircase_training_mode.m:186-198` tests the **twin**, which stays a concrete backend class ✓, calibration — **not** ✓; see F2.

## Scope: which interfaces get wrapped

Wrapping is opt-in per backend via `hw.Interface.SupportsAsyncIO`, not "everything except Software".

**F1 — `hw.VlcRecorder` is excluded.** RunExpt's video methods (`StartVideoRecording_.m:34,36`, `StopVideoRecording_.m`, `ToggleVideoLiveView.m`, and much of `gui.VlcRecorderSetup`) call `set_parameter`/`trigger` **directly on the interface** with string names, bypassing `hw.Parameter` entirely; and its `get_parameter(obj,name)` takes no options. It is not on the hot path and there is nothing to gain.

**F2 — calibration DOES get wrapped, and needs fresh reads.** The original plan asserted calibration "drives its own directly-connected interface, never wrapped". That is true only of the standalone `tmp/run_tdt_calibration.m`, which constructs its own `hw.TDT_RPcox`. But `stimbridge.RuntimeHost.calibrationAdapter` (`RuntimeHost.m:153-189`) adapts interfaces taken **from `obj.Runtime.Interfaces`** — the very ones the run wrapped. `InterfaceAdapter` then busy-polls `pBufferIndex_.Value` at 10 ms (`InterfaceAdapter.m:181-187`, `pollInterval_ = 0.01`) waiting for acquisition to complete, and reads response buffers back. Cached reads would spin until timeout or return stale buffers.

Fix: `InterfaceAdapter` gains a small read helper — if `~isempty(p.Parent.IODelegate)`, read via `IODelegate.freshRead(p)`; else `p.Value`. Writes and triggers stay on the normal path; FIFO ordering guarantees the enqueued play commands execute before the freshRead that follows them, preserving the play→capture sequence.

## Proxy contract checklist

`hw.Interface < matlab.mixin.Heterogeneous & matlab.mixin.SetGet`, and interfaces live in one heterogeneous array (`[Interfaces.mode]` at `UpdateGUIstate.m:66`, `set(Interfaces,'mode',...)` at `ExptDispatch.m:123`). `Runtime.Interfaces` is itself untyped, but the array concatenation still forces the issue: **`hw.AsyncInterface` must subclass `hw.Interface`** and satisfy:

- `Type` (Abstract Constant) — e.g. `'Async'`. Safe because the proxy is never persisted, and every Type-switching code path sees the twin.
- `Module` (Abstract, `SetAccess=protected`) — assigned the **twin's Module handles** at wrap time, so the base class's concrete `find_parameter`/`all_parameters`/`ensureUniqueParameterNames` (which index `obj.Module(:).Parameters` directly, `Interface.m:267`) work unmodified on the proxy.
- `mode` — stored, `SetObservable`, `AbortSet` (per A4). Not `Dependent`.
- `IsConnected` (Abstract, Dependent, `(1,1) logical`) — reflects worker health. (Note the existing contract is already loosely honored: only `TDT_RPcox` implements it as Dependent; the rest use a stored property.)
- `close_interface` / `setup_interface` (Abstract, protected) — no-ops.
- `getCreationSpec` (Abstract, Static) — throw or return empty; never used for a proxy.
- An **`HW` property** — `hw.Parameter`'s constructor does `if ~isempty(Parent.HW)` (`Parameter.m:163`), so anything acting as a `Parent` must expose it, even though `hw.Interface` declares no abstract `HW`.
- `disconnect()` — required by `onCloseRequest`, absent from the base contract.
- Must **not** override `set`/`get` — they are `Sealed` on the base (`Interface.m:412-420`).
- `Runtime` stays untyped (`Protocol.fromStruct.m:82` assigns a Protocol into it).

## Shipping the twin to the worker: struct rebuild, not byte stream

The worker receives a **struct** describing the interface and rebuilds its own copy, rather than a `getByteStreamFromArray` serialization of the live twin.

Serializing the live object graph is hostile: `hw.Parameter` and `hw.Module` have **zero Transient properties and no `saveobj`/`loadobj`**; they hold three function-handle callbacks plus arbitrary arg cells, `SetObservable`/`GetObservable` properties with attachable GUI listeners, `Values` cells that may contain `stimgen.StimType` objects, and immutable `Parent`/`HW` handles that drag in the whole backend (COM automation objects, `tcpclient`, `SynapseAPI`) and transitively reach `epsych.Runtime` and its MATLAB `timer`. That was the original plan's risk #2, and it is avoidable.

A proven struct path already exists: `Protocol.toStruct` writes a full per-interface `InterfaceData` tree, and `Protocol.createInterfaceFromStruct_` rebuilds an unconnected interface with a **fully populated Module/Parameter tree** (all branches pass `Connect=false`). Refactor the per-interface halves of both into shared helpers (`hw.Interface.toStruct` / static `hw.Interface.buildFromStruct`), have Protocol delegate to them, and pass the struct through `parfeval`. The worker rebuilds and calls `connect()`.

This deliberately drops callbacks and Expression machinery on the worker side — which is correct, not a compromise: the plan already keeps the entire PreUpdate→Expression→Evaluator→clamp pipeline in the foreground, and the worker performs only raw name-based device I/O. (Today's `.eprot` round-trip already discards those callbacks anyway — `toStruct.m:23-41` is commented out.) Risk #2 disappears with the byte stream.

## Parameter event log (JSONL, optional — on by default)

Purpose: an experiment record and crash-forensics/external-monitoring channel — **not** the foreground↔worker IPC (that stays the in-memory queues; see decision 5). Rationale: `poll(q,0)` is µs-scale and lossless, while polling a file from the 10 ms PsychTimer tick would add ~ms of open/read/`jsondecode` per tick, torn-line handling, poll-interval latency, and JSON type lossiness.

- **Writer**: `ServerCore` only (single writer, no contention).
- **Lifecycle**: opened by the forwarded `prepareRecording` at run start, path `<SessionDataFilename minus .mat>_paramlog_<ifaceType>.jsonl` (mirrors `Intan_RHX.prepareRecording.m:35`, which derives its recording path from `SessionDataFilename`); closed on `setMode` Stop and on `shutdown`. If `SessionDataFilename` is empty (standalone/smoke-test use), fall back to a pref-configured temp/log directory.
- **File contents**: line 1 = header record (schema version, interface `Type`, wall-clock start, id→FullName table); line 2 = full parameter snapshot; then changed-only records `{"t":"<ISO8601 ms>","tm":<monotonic s>,"src":"poll|set|trigger|mode|trial","id":N,"v":...}`. The TrialComplete edge writes its full Read-snapshot (same blob as the `trialComplete` queue message).
- **NaN/Inf encoding**: reuse the repo's existing convention — `hw.Parameter.numericToSafe_` (`Parameter.m:~520`) and `hw.Parameter.safeToNumeric_`, which map `NaN`/`Inf`/`-Inf` to string sentinels. (Note: those helpers are applied today only to `Min`/`Max` via `toStruct`/`fromStruct`, and live in `hw.Parameter` — *not* in `Runtime.writeParametersJSON`, which merely delegates. The original plan misattributed them.) Extend the same encoding to logged values.
- **Write mechanics**: batched at the same cadence as `update` pushes; open-append-close per batch (durability + Windows read-sharing while the run is live); `jsonencode` per record. A write failure emits one `warn` and disables logging for the rest of the run — it must never abort a run.
- **Reader**: static `hw.async.EventLog.read(path, fromByte)` parses complete lines from a byte offset, returns records plus the next offset, and silently ignores a trailing partial line (crash-safe). Proxy method `readEventLog()` wraps it; the same reader reconstructs a full session offline.
- **Toggle**: `Runtime.EventLogEnabled`, defaulting from `getpref('ep_RunExpt','AsyncEventLog',true)` — opt-out rather than opt-in, since an experiment record can't be recovered retroactively and all the I/O cost lives in the worker.

## Fallback & failure

- No PCT / pool creation fails / thread-only pool → `Passthrough_=true`: connect the twin in-process and delegate synchronously — behavior equals today's.
- Worker crash: drain + 0.1 s maintenance timer check `Future_.State`; `Faulted_` → next read throws → existing PsychTimerError (`RunExpt.m:466-473`) → data saved; `Future_.Diary` logged. No auto-reconnect in v1.
- Client crash: local process-pool workers die with the client.
- Rerun/close: proxy+worker+device persist across runs (mirrors the keep-connected policy documented in `Runtime.delete`); `onCloseRequest` → `disconnect()` → worker halts device and exits; pool stays warm for the session.

## Phases & verification

- **Phase 0 — inert groundwork + the COM spike**.
  - `Interface.m` (`IODelegate`, `SupportsAsyncIO`, Transient `Runtime`, delete `h_listeners`) + the four-site `backend_` routing in `Parameter.m` and `set_value.m`. Verify byte-identical behavior: existing `tmp/` smoke tests (`smoke_test_intan_rhx.m`, `smoke_test_stimplayer_standalone.m`) + a Software-only RunExpt preview session.
  - **`tmp/smoke_test_com_in_worker.m`** — the plan's biggest unknown, de-risked on day one and **without hardware**: `TDT_RPcox.readHardwareParameters.m:65-107` already drives `actxserver('RPco.X')` + `ReadCOF` against an offline `.rcx` (assets in `examples/stimgen/`). A ~20-line script that does the same inside a process-pool worker answers the go/no-go question before any of the architecture is built. The with-hardware confirmation stays in Phase 4.
- **Phase 1 — protocol + ServerCore** (pool-free): `hw.async.msg`, `ServerCore`, mock, `hw.async.EventLog`, and the `hw.Interface.toStruct`/`buildFromStruct` refactor; run `tmp/smoke_test_async_servercore.m` and `tmp/smoke_test_async_eventlog.m`.
- **Phase 2 — proxy over a real pool**: complete `hw.AsyncInterface`; run `tmp/smoke_test_async_proxy.m` (incl. sequence gating, worker-kill, passthrough fallback).
- **Phase 3 — runtime integration**: Runtime/RunExpt/resolveCoreParameters + UI toggle + the `InterfaceAdapter` freshRead helper; run `tmp/smoke_test_async_trial_cycle.m` (full trial loop vs. mock, ordering + data-integrity asserts).
- **Phase 4 — hardware validation + perf**: RPcox on the rig, then Synapse/Intan; a calibration run through `stimbridge.RuntimeHost` with a wrapped interface; `tmp/async_latency_harness.m` sync-vs-async comparison; write docs.

**End-to-end check**: run a Software+mock protocol via `epsych.RunExpt` with the toggle ON for N trials; confirm saved DATA matches, GUI stays responsive during injected 200 ms mock latency, toggling OFF reproduces current behavior, no spurious auto-stop occurs at run start (A2), and `<datafile>_paramlog_*.jsonl` appears next to the reserved data filename with `EventLog.read` replay reproducing the same parameter values recorded in saved DATA.

## Top risks

1. **RPco.X COM inside a pool worker** — unproven, and fatal to the whole approach if it fails. Now gated on the hardware-free Phase 0 spike rather than deferred to Phase 4.
2. **`Parameter.m` hot-path edits** — four call sites now, not three; mitigated by Phase 0 isolation and the existing smoke tests.
3. **Cache coherency** — the three fixes above (A1 seq gating, A2 sync setMode, A3 failed-write readback) are the ones the design actually turns on; they need dedicated asserts in `smoke_test_async_proxy.m`, not just incidental coverage.
4. First `parpool` startup 10-40 s — vprintf notice; pool persists per session; optional warm-start at RunExpt launch later.
5. Multi-interface protocols need `NumWorkers ≥ nProxies`; surplus falls back to passthrough with a warning.
6. **Mode-change detection latency** grows ~10 ms → ~250 ms for hardware-initiated Idle (A4). Tunable via the worker mode-poll period if it proves too slow to stop a run promptly.
7. Disk stalls (e.g. AV scans) in the worker while writing the event log — appends are batched and off the foreground thread; a write failure degrades to `warn` + disables logging rather than aborting the run.
8. JSON type fidelity in the event log — mitigated with the existing `numericToSafe_` sentinels; the log is a record, never the runtime source of truth, so lossiness cannot affect experiment behavior.

## Review findings (2026-08-04)

Verified against branch `NewProtocol`. Design changes are folded into the sections above; this is the audit trail.

**Design gaps found (would have shipped as bugs)**
- **A1** stale poll updates clobbering fresh writes — no sequencing existed.
- **A2** fire-and-forget `setMode` racing the timer's first-tick Idle check → spurious auto-stop at run start.
- **A3** failed device writes leaving the write-through cache permanently diverged.
- **A4** `mode` as a private cache would have silently broken four GUI `PostSet` listeners.

**Missed code path**
- `hw/@Parameter/set_value.m:15` is a **fourth** delegation site (`obj.HW.set_parameter`), bypassing `set.Value`.

**Corrections to claims in the original draft**
| Claim | Reality |
|---|---|
| `set.Value` wraps values in `{array}` | Conditional on `isArray`; whole write skipped when `Type=='StimType'` |
| Positional ids over identical enumeration | Breaks on Synapse — `connect()` rebuilds `obj.Module` from scratch |
| `disconnect()` "not in the abstract contract" but on the base | On *neither*; only on the five concrete classes |
| `all_parameters(valueOnly=true)` | `valueOnly` is a `Runtime.all_parameters` option; the interface method has `asStruct` only |
| NaN/Inf sentinels in `Runtime.writeParametersJSON` | In `hw.Parameter.numericToSafe_`/`safeToNumeric_`; applied to Min/Max only |
| Checkable-uimenu-with-prefs pattern at `buildUI.m:38-42` | Doesn't exist; nearest prefs pattern is the uicheckbox at 127-133 |
| Calibration "never wrapped" | True only for `tmp/run_tdt_calibration.m`; `RuntimeHost.calibrationAdapter` uses the runtime's own interfaces and busy-polls `.Value` at 10 ms |
| Wrap everything non-Software | `hw.VlcRecorder` must also be excluded (direct string-name I/O, no options form) |
| PsychTimer period "10 ms" | 10 ms *default*, user-configurable via prefs; `BusyMode='drop'` |
| Byte-stream the twin to the worker | Replaced with struct rebuild reusing `createInterfaceFromStruct_`; eliminates the original risk #2 |

**Confirmed as correct** — queue directions and the no-`afterEach` rationale; delegate redirection over cloning (both `Parent` and `Module.parent` verified immutable); never-persist-the-proxy (the `otherwise → hw.Software` fallback is real); the wrap point at `Runtime.set.Interfaces:103-119`; setting `Runtime` on the twin for `evaluateExpression_.m:91-118`; the reset→writes→newtrial barrier in `dispatchNextTrial.m:20-62`; `updateTrialsFromParameters` read-after-write; `eval_staircase_training_mode`'s `isa(...,'hw.Software')` operating on the twin; the trialComplete-before-flag consistency argument (strengthened — `PsychTimerRunTime` forces a drain at the top of every tick); the JSONL log design and its IPC rationale; and the `% FIX PERFORMANCE` motivation.

**Pre-existing bugs noticed, out of scope**
- `TDT_RPcox.trigger` references an undefined variable `module` in its two error paths (`TDT_RPcox.m:449,456`) — those error paths will themselves error.
- `TDT_Synapse.trigger` and `Intan_RHX.trigger` return `datetime`, `TDT_RPcox.trigger` returns `now` (double), and `Parameter.Trigger` assigns the result into `lastUpdated (1,1) double`.
- `hw.Software.setup_interface.m:52` creates its module with parent `0` while the constructor uses `hw.Module(obj,...)`.
- The stale comment at `ep_TimerFcn_RunTime.m:37-39` describes `~BoxID` suffix filtering that is not applied.
