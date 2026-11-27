# EPsych v3 — envisioned major improvements

## Context

Request: describe the major improvements a hypothetical "v3" would make in three areas —
backend processing during experiments, the hardware abstraction layer, and ease of building
behavior GUIs — with the UI staying in MATLAB and the backend otherwise open.

This is a design description, not an implementation plan. It is based on a survey of the
current code and on the repository's own measurements (`documentation/overviews/Runtime_Performance.md`,
`plans/runtime-performance-review.md`, `plans/async-hardware-io.md`,
`plans/uihtml-behavior-gui-assessment.md`, `plans/multi-subject-support.md`). Nothing was
run. Numbers below are quoted from those documents; every stated benefit of v3 is a
projection that would have to be measured.

**Nothing described here has been implemented.** Each spike in the last sections would be
a separate piece of work.

## What v2's structure cannot fix by further tuning

| Limit | Evidence |
|---|---|
| The host is in the latency path of every trial. Trial end is found by polling a tag on a MATLAB timer (10 ms default; 25 ms in the rig benchmark); the next trial's parameters are then written one at a time while the subject waits. | `ep_TimerFcn_RunTime.m:22`, `CreateTimer.m:17-23`. Rig median wait 64 ms, 39 ms of it parameter writes; 8-20% of boundaries 5-7x slower, cause unknown, and not explained by running headless (`Runtime_Performance.md:276-307`). |
| One MATLAB thread carries I/O, selection, analysis, journaling and graphics. | 197 ms of thread per boundary, 94 ms of it graphics after the tick (same table). No `parfeval`/`backgroundPool`/serial callbacks under `obj/` (the `obj/stimgen` and `obj/granary` submodules were not checked out for this survey and were not searched). |
| The record is one scalar sweep per trial with a host timestamp. There is no event stream. | `data.computerTimestamp = datetime('now')` (`ep_TimerFcn_RunTime.m:78`). Only `hw.Bpod` records device-timestamped events; `hw.Teensy.drainEvents` has no runtime caller. |
| The trial record has no schema; the journal is MATLAB's undocumented byte-stream serialization. | Fields derive from parameter names; `TrialJournal.m:115` uses `getByteStreamFromArray`. The sweep is unscoped: every box's record holds every box's readouts. |
| `hw.Parameter.Value` is a property accessor that performs device I/O, redraws random values, evaluates expressions, clamps and runs callbacks; the backend's write result is discarded. | `Parameter.m:389-449` (`set_parameter` return unused at :440). Caches and epochs have since been added around it: `HostValue_`, `DeviceValue_`/`DeviceEpoch_`, `ExpressionPlan_`, the `ioReady` and `mode` caches, `hw.ReadPlan`. |
| The HAL has no events, streams, clocks or declared capabilities. Capability is discovered by sentinel returns (`''`, `false`, `NaN`, an empty struct) from optional hooks, of which the base class now has 14. Adding a backend edits four hardcoded sites, one of which falls back silently to `hw.Software`. | `Interface.m:242-491`; `createInterfaceFromStruct_.m:156-157`. Error handling differs per backend (throw / log-and-continue / silent `true` while disconnected). |
| The six paradigm and example behavior GUIs are 159 to 1007 lines each (the minimal template is 93). Layout plumbing is roughly 5-17% of their code (a survey estimate by pattern match, not checked line by line); the rest is wiring and paradigm logic that lives in the GUI class. | `cl_AppetitiveDetection_BehaviorGUI/build.m` (827 lines) creates a parameter on the rig (`:624`) and greys controls by hand (`:701`, `:748`, `:822`); `TwoAFCBehaviorGUI` runs its own timer (`:279`) and writes `x_TrialComplete_1` (`:381`, `:507`). |
| The GUI builder emits source that then diverges from its spec; components have no common base class or shared data model. | `generateCode.m:51-52` ("hand edits are not reflected in the spec"). Six components checked have six constructor shapes: `Parameter_Control(parent,Parameter,options)`, `Parameter_Update(RUNTIME,parent,options)`, `OnlinePlot(RUNTIME,source,hax,BoxID,options)`, `PsychPlot(pObj,ax)`, `PhaseSelector(RUNTIME,PhasePath)`, `Triggers(RUNTIME,TDTActiveX,container,BoxID)`. Each attaches its own listener and recomputes from the whole `DATA`. |
| No automated tests or CI. | 176 `tmp/smoke_test_*.m` scripts, no `matlab.unittest`, one non-MATLAB workflow. |

## 1. Execution core

**1.1 Take the subject's wait off the host.** Hard timing belongs on the device; the host
prepares, the device latches. During trial N the engine computes the next trial for each
possible outcome and stages each candidate's parameters (and stimulus buffers, by content
hash) into shadow registers. At trial end the device selects a bank and starts trial N+1
itself. Dispatch leaves the boundary for everything staged; the host is then only in the
path for throughput, not latency. This is the "latch-on-NewTrial" and "device-side trial
record" redesign the performance review already identified and did not attempt
(`runtime-performance-review.md:421-425`), made the default rather than an optimisation.
It is the only item here that addresses the unexplained slow boundaries, and it does so by
making them irrelevant to the subject, not by finding the cause.

**1.2 One trial-program representation, executed on the device where possible.**
Generalise `teensy.Program` (states, transitions, timers, counters, `@Variable` references)
into the paradigm's contingency for every backend: compiled to a Teensy state table, a Bpod
state matrix, or a standard RPvds latch/event-FIFO macro set; emulated on the host at tick
rate for backends without a state machine. Which tier ran, and its timing resolution, is
written into the data file. `teensy.Simulator` becomes the reference semantics.

**1.3 Split engine and UI into separate processes, at the session level.** A headless
engine owns hardware, the trial program, selection, the clock and the journal. The MATLAB
UI is a client: it subscribes to a state stream and sends commands. Rendering can then
never delay a trial, a UI crash does not end a session, and a UI can reattach or observe
remotely. The earlier `hw.AsyncInterface` design (`plans/async-hardware-io.md`) split at
the parameter-I/O level: a cache plus queue under `hw.Parameter`, with trial logic still in
the UI process. Much of that plan is consistency handling (sequence gating, snapshot
ordering, synchronous mode changes), and the performance review records it as "designed,
partly built and removed unvalidated". The proposal here is to cut where messages are
coarse (trial completed, state snapshot, command) rather than per parameter access.

**1.4 Pure, replayable trial selection.** `[next, state] = step(state, outcome)` with a
selector-owned seeded stream (as `epsych.BlockSequence` already does). v2 selectors mutate
on `selectNext`, which is why Regenerate must avoid re-selecting. Purity is what makes 1.1
possible (asking "what if hit / what if miss" without consuming state) and makes rewind,
preview and regenerate trivial. It also allows a replay audit: re-run the selector over the
saved outcomes and confirm it reproduces the saved trial sequence.

**1.5 Layered parameter resolution with provenance.** One compiled per-trial dataflow
graph: protocol design -> project template -> subject defaults -> phase -> operator edit
-> selector output -> expression -> calibration/clamp -> device channel. Each layer is an
explicit override with a recorded source; the effective value and who set it are queryable
and saved per trial as both *requested* and *applied*. This replaces the interplay of
`Values` vs `Value` vs trial-table column vs `holdCommittedValues` vs phase
`Exclude`/`Override` vs `ParameterDefaults` restore state, which accounts for a large share
of the traps documented in `CLAUDE.md`.

**1.6 The event log is the record.** Every device edge, stimulus onset, reward, parameter
write and operator action is an event with a device timestamp. Trials are a derived table
over the log with a declared, typed schema (name, type, unit, source) fixed at compile and
scoped per box. A session clock model aligns each device clock to the host (paired
timestamps or sync pulses) and stores the fit and residuals. Storage is append-only,
crash-safe, self-describing and language-neutral (HDF5-based, NWB-exportable), written
once rather than seed + journal + merged `.mat`. v2 files remain readable.

**1.7 One engine per box.** Independent loops under a session supervisor: per-box
run/pause/stop, per-box GUI, no cross-box blocking. Intended to address the items listed in
`plans/multi-subject-support.md`.

**1.8 Simulation and tests as part of the core.** Every backend ships a simulator on the
same contract, with a scriptable virtual subject and virtual time, so a full session runs
in seconds without hardware. `matlab.unittest` suites and CI replace the smoke scripts;
golden-file tests pin the data format.

## 2. Hardware abstraction layer

- **Descriptors without I/O.** A parameter is a value object (name, type, unit, range,
  shape, access, role). I/O is explicit and batched: a transaction of reads and writes
  returns, per item, the requested value, the applied value, a device timestamp and a
  status. Nothing happens inside a property accessor.
- **Typed channel kinds** in place of one `Parameter` with a `Type` string: setting,
  buffer (chunked, hash-tracked), pulse/trigger (device-timed width), event input
  (timestamped), stream (sampled, with rate), counter, clock.
- **Declared capabilities**: `BatchIO`, `AtomicLatch`, `DeviceTimestamps`, `EventPush`,
  `StateMachine`, `OfflineRun`, `Recovery`, ... as a set the core queries, replacing
  sentinel-returning hooks.
- **Roles bound in the protocol**, not inferred from names: TrialStart, TrialEnd, Reset,
  Reward map to channels explicitly. `x_NewTrial_<box>`, `!`, `~`, `#` become one
  backend's import convention, absent from core.
- **Backends as discovered plugins**: one package per backend carrying its own descriptor,
  serialiser and editor spec. An unknown backend type in a file is a named error.
- **One error model**: typed errors or per-item results everywhere; a write while
  disconnected is an error unless the device is declared offline; no result is discarded.
- **A device clock** on every backend (rate, monotonic time, sync method); an unset rate is
  unrepresentable instead of `Fs = 1`.
- **A conformance suite** every backend and its simulator must pass, replacing per-backend
  smoke scripts and the SelfTest A3 tripwire.
- **A v2 adapter** wrapping existing `hw.Interface` backends at reduced capability, so
  migration is per backend.

## 3. Behavior GUIs

- **Three tiers.** (a) Zero code: a default GUI generated from the protocol — controls
  grouped from parameter metadata (group, order, widget hint, `enabledBy`), standard
  displays chosen from the analysis type. (b) Declarative: a layout spec that is
  *interpreted at runtime*, edited in place on the live or previewed GUI; no generated
  classdef to drift. (c) Code: only for a genuinely new component, referenced from the
  spec by name.
- **One component contract**: a base class with a fixed lifecycle, declared inputs,
  a declared options schema (`gui.ComponentSpec` made mandatory), and automatic
  persistence. Constructor shapes stop varying.
- **Views and commands only.** A component reads from a shared session store and sends
  commands to the engine; it never writes hardware. In review or simulation there is no
  command bus, so controls are inert by construction and per-GUI `ReviewMode` guards
  disappear. Live, review and simulated sessions present the same store interface.
- **Paradigm logic leaves the GUI.** Shape trials, session settings, response emulation
  and dependency greying become named protocol actions and parameter metadata that a
  button or control binds to.
- **One decode per trial.** The store holds a typed trials table and incremental analysis
  state; displays subscribe and render coalesced. With the UI in its own process the
  deferral machinery (`EventHub.defer`, write-if-changed guards) is no longer needed for
  correctness of timing.
- **Layout model**: nested containers, tabs, splitters, dockable pop-outs, per-rig and
  per-study layout profiles with export/import, light/dark themes, one spec instantiated
  per box.
- **Rendering**: native widgets for anything that writes (per the uihtml assessment);
  `uihtml` for dense read-only displays, where "MATLAB owns the state, the page renders it"
  is now the natural pattern. That assessment puts a `uitable` property set at about
  30-40 ms.
- **New display the event log enables**: a per-trial event raster/timeline (licks, pokes,
  stimulus, reward) aligned on any event.

## What carries over

The roster/project/membership model and protocol versioning, session notes, crash-safe
journaling, offline review, key bindings, pop-outs, the self-test, and the stimgen/granary
separation are sound and operator-facing; v3 keeps them and replaces the execution core
beneath them.

## Backend technology — recommendation

Engine as a second, headless MATLAB process first. Trial selectors, stimgen and the
psychophysics package are MATLAB, and RPco.x is COM, which in principle any Windows process
can host (not verified; see the table below). Define
the engine/UI and engine/driver wire protocols as language-neutral from the start, so a
driver that needs threaded I/O (serial event pumps), or eventually the whole engine, can
move to Python or native code without touching the UI. Neither MATLAB nor Python gives hard
real time on Windows, so the language choice matters for concurrency, tooling and CI, not
for subject-facing timing; that is decided by 1.1 and 1.2.

## Unverified, and how each would be tested

| Claim | Test |
|---|---|
| Device-side latching removes parameter writes from the subject's wait on the RZ6. | Spike: shadow tags + latch macro in the appetitive circuit; rerun `tmp/bench_rig_preview.m`; compare wait distribution including the slow-boundary tail. |
| An engine process is free of the 5-7x slow boundaries. | Unknown. The cause is not identified; measure the same loop in a second process before relying on it. |
| COM (`RPco.X`) and stimulus upload work from a non-UI MATLAB process at current speeds. | The `smoke_test_com_in_worker` spike proposed in `plans/async-hardware-io.md`, plus `hw.benchmarkIO` from that process. |
| Engine-to-UI messaging cost at trial rate and 10-20 Hz state stream is negligible. | Loopback benchmark of the chosen transport with a realistic trials table. |
| Selectors in current paradigms can be expressed as pure step functions. | Port `cl_AppetitiveStimDetect`'s selector; replay saved sessions and compare sequences. |
| A protocol-derived default GUI covers a real paradigm. | Generate one for the appetitive detection protocol; list what still needs code. |

## Suggested order

1. Data model and event log (1.6) with a v2 reader — nothing else is trustworthy without it.
2. HAL contract, simulator, conformance suite, v2 adapter (2, 1.8).
3. Device-side latching spike on the RZ6 (1.1) — the largest timing effect, and independent of the rest.
4. Engine process and session store (1.3-1.5, 1.7).
5. Component contract, interpreted layouts, protocol-derived default GUI (3).
