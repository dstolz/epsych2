# Non-Blocking Hardware I/O Layer (`hw.AsyncInterface`)

## Context

Every hardware parameter access in EPsych v2 is a synchronous round-trip on MATLAB's single thread: `hw.Parameter.get.Value` ([Parameter.m:197-222](../obj/+hw/@Parameter/Parameter.m)) calls `Parent.get_parameter` (COM `ReadTagVEX` for TDT_RPcox, HTTP for TDT_Synapse, TCP busy-poll for Intan_RHX). The 10 ms PsychTimer tick, every GUI monitor timer, and all Helper-event listeners share that thread, so a slow device call stalls the GUI and trial loop — evidenced by `% FIX PERFORMANCE` (OnlinePlot disabled in `cl_AppetitiveDetection_GUI_B.m:96`), the Intan mode-cache workaround, and the >0.25 s selector warning in `ep_TimerFcn_RunTime`.

**Goal**: a non-blocking I/O layer where a background MATLAB worker process (Parallel Computing Toolbox — licensed, currently unused) owns the real hardware connection, and the foreground reads a cache / enqueues writes.

**User decisions (locked)**:
1. Worker-process architecture (background process owns hardware, poll/command loop, push updates).
2. Generalized over `hw.Interface` — works with TDT_RPcox, TDT_Synapse, Intan_RHX, and future backends unchanged.
3. Cached reads + push updates, worker-side trial-data snapshot on TrialComplete edge, synchronous `freshRead` escape hatch.
4. Opt-in decorator/proxy; existing sync path and `hw.Software` untouched.
5. Optional worker-side **JSONL parameter event log** — timestamped, changed-only, one file per run — doubling as an experiment record and an externally pollable secondary channel. Queues remain the primary foreground IPC: in-memory `poll(q,0)` is µs-scale and lossless, while file+`jsondecode` polling from the 10 ms tick would cost ~ms of disk/parse per poll, need torn-line handling, and lose type fidelity (NaN/Inf, single, shapes). See "Parameter event log" section below.

## Verified design constraints (shaped the approach)

- **`hw.Parameter.Parent` and `hw.Module.parent` are `SetAccess=immutable`** (`Parameter.m:42-45`). The parameter tree cannot be re-parented, and cloning it would break handle identity with `COMPILED.parameters`, `RUNTIME.CORE` triggers, and GUIs. → Use **delegate redirection**: a Transient `IODelegate` slot on `hw.Interface`, consulted by `hw.Parameter`. Handle identity preserved everywhere; zero changes to `ep_TimerFcn_RunTime.m` or `dispatchNextTrial.m`.
- **The proxy must NOT be persisted in .eprot**: Protocol serialization is `toStruct`/`fromStruct` and `createInterfaceFromStruct_` has a hard-coded Type switch whose `otherwise` silently degrades to `hw.Software`. → Wrap at runtime (`Runtime.set.Interfaces`), never persist.
- **COM (`actxserver('RPco.X')`) cannot cross processes** — the worker constructs and owns the real interface. Requires a **process** pool (not `backgroundPool`/threads, which don't support COM).
- **Queue directions** (PCT semantics): commands client→worker via `parallel.pool.PollableDataQueue` created **on the worker** (sent back in handshake); updates worker→client via `PollableDataQueue` created **on the client** (passed to `parfeval`). No `afterEach`/`DataQueue` — its callback only runs when the main thread idles, which is unreliable under a 10 ms timer. The client drains with non-blocking `poll(q,0)` at deterministic points instead.
- `RunExpt.onCloseRequest` calls `disconnect()` (not in the abstract contract) — proxy must implement it.
- `prepareRecording` implementations validate `runtime (1,1) epsych.Runtime` in `arguments` — the worker must receive a minimal reconstructed `epsych.Runtime` with plain fields copied, not a struct.
- Expression eval resolves cross-interface refs via `parameter.Module.parent.Runtime` — the wrap step must set `Runtime` on the wrapped twin too, not just the proxy.

## Architecture

```
MAIN MATLAB (GUI + PsychTimer)                    WORKER PROCESS (parfeval)
┌────────────────────────────────────┐            ┌──────────────────────────────┐
│ Protocol owns "twin" interface     │   cmdQ     │ serverLoop / ServerCore      │
│  (never connected; keeps the       │  (worker-  │  deserializes its own copy   │
│   Module/Parameter tree everyone   │   made) ──>│  of the twin, connect()s it  │
│   holds handles into)              │            │  — owns COM/HTTP/TCP         │
│ twin.IODelegate = hw.AsyncInterface│   updQ     │  loop:                       │
│  get_parameter -> cache (instant)  │  (client-  │   drain cmds FIFO            │
│  set_parameter -> enqueue +        │   made) <──│   hot poll (TrialComplete)   │
│    write-through cache             │            │   mode poll (250ms)          │
│  trigger -> enqueue                │            │   warm round-robin (~100ms)  │
│  freshRead -> corrId req/resp      │            │   TrialComplete edge ->      │
│  drains updQ in get.mode /         │            │     snapshot ALL Read params │
│    get_parameter + 0.1s timer      │            │     push trialComplete blob  │
│                                     │            │   tee changed vals -> log    │
└────────────────────────────────────┘            └──────────────────────────────┘
```

- `RUNTIME.Interfaces` holds the proxy; the Protocol keeps the twin. `twin.IODelegate` doubles as the cross-run registry so reruns reuse the same worker/device connection (TDT cannot survive delete/recreate).
- Worker also appends changed parameter values to a per-run JSONL event log (see "Parameter event log" below); the log lands next to `Runtime.SessionDataFilename`, so no `savefcns` changes are needed.
- **Consistency**: the `trialComplete` message carries the full Read-parameter snapshot; the drain applies the snapshot to the cache *before* setting the cached TrialComplete flag. Since the flag is the first thing `ep_TimerFcn_RunTime` reads, the subsequent `all_parameters(valueOnly=true)` reads exactly the trial snapshot. The snapshot is taken in the worker at the moment of the edge — more accurate than today's serial read burst.
- The `pause(0.001)` trigger pulses and all transport latency move into the worker.

## New files

| Path | Contents |
|---|---|
| `obj/+hw/@AsyncInterface/AsyncInterface.m` | Proxy classdef: `Wrapped_` (twin), `CmdQueue_`, `UpdQueue_`, `Future_`, `CacheValues_`/`CacheTimes_` (id-indexed), `IdByFullName_` map, `ModeCache_`, `Faulted_`, `Passthrough_`; `get.mode` (drain + cache), `get.IsConnected`, `get.Module` (returns twin's modules — same handles); static `wrap(iface)`, `ensurePool_`, `serverLoop` |
| `obj/+hw/@AsyncInterface/connect.m` | Pool startup/reuse, `parfeval(serverLoop,...)`, handshake, twin byte-stream capture (`getByteStreamFromArray`; fallback temp-.mat), initial snapshot + tree sync, passthrough fallback |
| `obj/+hw/@AsyncInterface/disconnect.m` | `shutdown` command, future cleanup |
| `obj/+hw/@AsyncInterface/get_parameter.m` | Throttled drain (≥2 ms apart) + cached read; throws `hw:AsyncInterface:WorkerFault` if `Faulted_` (so PsychTimerError fires — never silently stale) |
| `obj/+hw/@AsyncInterface/set_parameter.m` | Write-through cache + enqueue (un-cell the `{array}` wrapper from `set.Value:315` before caching) |
| `obj/+hw/@AsyncInterface/trigger.m` | Enqueue; if id registered Role=ResetTrig, optimistically zero the paired TrialComplete cache entry (prevents double-processing while worker executes the reset) |
| `obj/+hw/@AsyncInterface/freshRead.m` | Correlation-id request; poll `UpdQueue_` with timeout (default 2 s) |
| `obj/+hw/@AsyncInterface/registerHotParameter.m` | Role (NewTrial/ResetTrig/TrialComplete), poll period; forwards `registerHot` to worker |
| `obj/+hw/@AsyncInterface/prepareRecording.m` | Synchronous forwarded call (corrId ack; errors propagate → aborts start) |
| `obj/+hw/@AsyncInterface/drainUpdates_.m` | Message pump: update/modeChange/trialComplete/warn/error/ack dispatch |
| `obj/+hw/+async/@ServerCore/ServerCore.m` | Pool-free, testable worker logic: command execution, poll scheduling, edge detection, snapshotting |
| `obj/+hw/+async/msg.m` | Message-type constants + struct factories (wire protocol vocabulary) |
| `documentation/hw/hw_AsyncInterface.md` | Docs (repo convention) |
| `tmp/AsyncMockInterface.m` | Serializable in-memory `hw.Interface` with injectable latency, scripted TrialComplete, command log |
| `tmp/smoke_test_async_servercore.m` | ServerCore in-process (fake queues): FIFO ordering, edge+snapshot atomicity, warn/error semantics |
| `tmp/smoke_test_async_proxy.m` | Real pool: handshake, cached reads, write-through, freshRead, staleness bounds, worker-kill fault, `ForceSyncFallback` passthrough |
| `tmp/smoke_test_async_trial_cycle.m` | Full Runtime trial loop against the mock: DATA matches scripted values; command log shows reset→writes→newtrial per trial; no double-processed trials; mid-run recompile works |
| `tmp/smoke_test_async_failure.m` | Worker crash / fallback paths |
| `tmp/async_latency_harness.m` | Sync vs async tick-time comparison |
| `obj/+hw/+async/@EventLog/EventLog.m` | Append side (open/append/close, NaN/Inf sentinel encoding, batch flush) + static offset-tailing reader; pool-free and unit-testable |
| `obj/+hw/@AsyncInterface/readEventLog.m` | Client convenience wrapper over `EventLog.read` (diagnostics/GUI use) |
| `tmp/smoke_test_async_eventlog.m` | Round-trip incl. NaN/Inf sentinels; torn-line tolerance (truncate mid-line, read); append-while-reading |

## Modified files (surgical)

1. **[Interface.m](../obj/+hw/@Interface/Interface.m)** — add `properties (Transient) IODelegate = [] end`; make existing `h_listeners`/`Runtime` (lines 41-44) Transient (keeps the twin serializable to the worker; persistence-neutral since .eprot uses toStruct).
2. **[Parameter.m](../obj/+hw/@Parameter/Parameter.m)** — the only hot-path change. Add private helper:
   ```matlab
   function b = backend_(obj)
       b = obj.Parent;
       if isa(b,'hw.Interface') && ~isempty(b.IODelegate), b = b.IODelegate; end
   end
   ```
   Route through it in three places: `get.Value` (replace `obj.Parent` in **both** the line-204 Software/disconnected short-circuit and the line-208 `get_parameter` call — pivotal, since the twin stays disconnected), `set.Value` line 316, `Trigger` line 283. Empty `IODelegate` ⇒ byte-identical behavior.
3. **[Runtime.m](../obj/+epsych/@Runtime/Runtime.m)** — new `UseAsyncIO (1,1) logical = false`; in `set.Interfaces` (103-119), when enabled, replace each non-Software, non-proxy entry with `hw.AsyncInterface.wrap(p)` before the connect loop; set `Runtime` on both proxy and twin. Also new `EventLogEnabled (1,1) logical = true`, plumbed to the proxy alongside `UseAsyncIO`; `savefcns` are otherwise untouched since the log is named from the already-reserved `SessionDataFilename`.
4. **[resolveCoreParameters.m](../obj/+epsych/@Runtime/resolveCoreParameters.m)** — after resolving `p` (line 35): if `p.Parent.IODelegate` is an AsyncInterface, call `registerHotParameter(p, Role=char(cc))`.
5. **[ExptDispatch.m](../obj/+epsych/@RunExpt/ExptDispatch.m)** — after `self.RUNTIME = epsych.Runtime;`: `self.RUNTIME.UseAsyncIO = getpref('ep_RunExpt','UseAsyncIO',false);`
6. **RunExpt `buildUI.m` + toggle callback** — checkable uimenu "Background Hardware I/O (experimental)" under Customize (pattern at buildUI.m:38-42), persisted via setpref.

**Explicitly unchanged**: `ep_TimerFcn_RunTime.m`, `dispatchNextTrial.m`, all concrete backends, `hw.Software`, GUIs, Protocol serialization.

## Wire protocol (plain structs, constants in `hw.async.msg`)

Client→worker (`CmdQueue_`, strict FIFO; worker fully drains commands before each poll pass — preserves reset→writes→newtrial ordering): `connect`, `set{id,value}`, `trigger{id}`, `setMode{mode}`, `freshRead{ids,corrId}`, `prepareRecording{rtInfo,corrId}`, `registerHot{ids,roles}`, `pollConfig{ids,periodSec}`, `logConfig{enabled,pathOverride}`, `ping{corrId}`, `shutdown{haltDevice}`.

Worker→client (`UpdQueue_`): `handshake{cmdQueue}`, `connectResult{ok,errStruct,treeSync,snapshot}`, `update{ids,values}` (batched changed-only), `modeChange{mode}`, `trialComplete{hotId,snapshot}` (snapshot covers `all_parameters(Access='Read')` mirroring `ep_TimerFcn_RunTime:40` defaults), `freshReadResult`/`ack`/`pong{corrId,...}`, `warn{level,msgText}`, `error{fatal,errStruct}`, `bye`.

`prepareRecording{rtInfo,corrId}` additionally (re)opens the JSONL event log from `rtInfo.SessionDataFilename` when logging is enabled (see "Parameter event log" below); every executed `set`/`trigger` and every pushed `update`/`modeChange`/`trialComplete` is teed to the log when open.

Ids are positional over an identical full-tree enumeration on both sides (all params incl. invisible/triggers/arrays); `connectResult.treeSync` reconciles worker-side `setup_interface` renames/additions into the client twin.

## Worker loop (ServerCore.run_once)

1. `poll(cmdQueue, 0.002)` (doubles as loop sleep) → drain ALL pending commands FIFO. `set` failures → `warn` (matches today's non-fatal vprintf); `get`/`connect` failures → `error{fatal}` (matches today's rethrow → PsychTimerError).
2. Hot poll every iteration (~2-5 ms): TrialComplete rising edge → serial snapshot of all Read params → `trialComplete` push; other hot changes → `update`.
3. Mode poll every 250 ms → `modeChange` on change.
4. Warm poll: ~100 ms budget, round-robin K non-array/non-hot Read params per iteration, batched `update`.
5. On fatal device error: stop polling, keep serving `freshRead`/`shutdown` for debugging.

## Ordering & consistency

- **Write-through cache** on `set_parameter`: expressions, `updateTrialsFromParameters`, and GUI read-back see new values immediately; the foreground Parameter pipeline (PreUpdateFcn→randomize→Expression→EvaluatorFcn→clamp) is untouched — the worker only does raw device writes.
- **Trigger/TrialComplete race** handled by the ResetTrig optimistic clear (see trigger.m above); Runtime declares the pairing in resolveCoreParameters so the proxy stays hardware-agnostic.
- Audited read-after-set consumers: `updateTrialsFromParameters` (cache ✓), calibration (drives its own directly-connected interface, never wrapped ✓), `eval_staircase_training_mode` (`isa(P.Parent,'hw.Software')` on the twin ✓).

## Fallback & failure

- No PCT / pool creation fails / thread-only pool → `Passthrough_=true`: connect the twin in-process and delegate synchronously — behavior equals today's.
- Worker crash: drain + 0.1 s maintenance timer check `Future_.State`; `Faulted_` → next read throws → existing PsychTimerError → data saved; `Future_.Diary` logged. No auto-reconnect in v1.
- Client crash: local process-pool workers die with the client.
- Rerun/close: proxy+worker+device persist across runs (mirrors current keep-connected policy); `onCloseRequest` → `disconnect()` → worker halts device and exits; pool stays warm for the session.

## Phases & verification

- **Phase 0 — inert groundwork**: Interface.m + Parameter.m `backend_` routing. Verify byte-identical behavior: run existing `tmp/` smoke tests (`smoke_test_intan_rhx.m`, `smoke_test_stimplayer_standalone.m`) + a Software-only RunExpt preview session.
- **Phase 1 — protocol + ServerCore** (pool-free): `hw.async.msg`, ServerCore, mock; run `tmp/smoke_test_async_servercore.m`.
- **Phase 2 — proxy over a real pool**: complete `hw.AsyncInterface`; run `tmp/smoke_test_async_proxy.m` (incl. worker-kill and passthrough fallback).
- **Phase 3 — runtime integration**: Runtime/RunExpt/resolveCoreParameters + UI toggle; run `tmp/smoke_test_async_trial_cycle.m` (full trial loop vs. mock, ordering + data-integrity asserts).
- **Phase 4 — hardware validation + perf**: **spike `actxserver('RPco.X')` inside a process worker on the rig first — the single biggest unknown**; then Synapse/Intan; `tmp/async_latency_harness.m` sync-vs-async comparison; write docs.

End-to-end check: run a Software+mock protocol via `epsych.RunExpt` with the toggle ON for N trials; confirm saved DATA matches, GUI stays responsive during injected 200 ms mock latency, and toggling OFF reproduces current behavior.

## Top risks

1. RPco.X COM inside a pool worker — unproven; gate on the Phase 4 spike (pull forward if rig access allows).
2. Twin serialization payload (parameter callbacks / `p.handle` GUI slots may capture unserializable state) — capture bytes at first connect (pre-GUI), Transient markers, loud failure otherwise.
3. Parameter.m hot-path edits — mitigated by Phase 0 isolation and tests.
4. First `parpool` startup 10-40 s — vprintf notice; pool persists per session; optional warm-start at RunExpt launch later.
5. Multi-interface protocols need `NumWorkers ≥ nProxies`; surplus falls back to passthrough with a warning.
