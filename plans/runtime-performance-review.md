# EPsych runtime performance review

2026-11-21, against `master` at `6ad145d8`. A review, not a change: nothing in the
repository was modified and no fix below has been built or tested.

> **Since built.** Everything from Step 0 to R10 is implemented on branch
> `perf/runtime-review`; see [Implementation status](#implementation-status) at
> the end for what was built, what the measurements corrected in this review,
> and what was left. The text between here and there is the review as written.
> The settings it led to are described in
> [Runtime_Performance.md](../documentation/overviews/Runtime_Performance.md).

## Summary

A trial boundary on a TDT rig with the lab's behavior GUI currently carries three
costs. Which is largest depends on the rig's per-call device latency, which has
never been measured:

1. **Display work done before the next trial starts** — ~50–70 ms of plot and table
   updates per trial (repo-measured), plus the render, which a `pause` inside the
   hardware trigger forces into the boundary.
2. **Redundant device calls** — roughly 700 COM calls per trial on an illustrative
   rig, where about 115 would do after the local fixes below.
3. **Trace logging** — about 95 log records per trial at 200–330 µs each.

Between trials, every 10 ms tick makes 5 COM calls where 1 is needed, and the
behavior GUI's monitor adds ~330 more per second.

Step 0 turns the call counts into milliseconds on the rig before anything is
changed. The fixes are listed in the order they should be made.

## Context

Everything at runtime shares ONE MATLAB thread: the PsychTimer trial loop
(`fixedSpacing`, 10 ms, `BusyMode='drop'`, [CreateTimer.m:20](../obj/+epsych/@RunExpt/CreateTimer.m#L20)),
every GUI polling timer, every EventHub listener, and all graphics. Three budgets:

- **A. Trial boundary** — trial N complete → trial N+1 started. Dead time the animal
  waits through; its variance is ITI jitter. Within-trial timing lives in the
  hardware and is not affected.
- **B. Per-tick idle cost** — paid up to 100×/s whether or not anything happened.
- **C. Background GUI load** — polling timers and redraws that delay the tick.

**How this was established.**

- *Findings* were read out of the code and cross-checked by three independent
  searches. Device costs are **call counts, not timings**: the repository holds no
  per-call COM, HTTP or serial latency.
- *Millisecond figures* are the repository's own recorded numbers (logging, History,
  ParameterScatter, Staircase, TrialJournal). Nothing was timed for this review.
- *Fixes* were each checked in a separate read-only pass against the invariants
  recorded in `CLAUDE.md`. That pass reversed three of the original proposals. Its
  two decisive claims were re-read first-hand (Bpod's byte pump hanging off
  `get.mode`; `PendingBase_` being a device read-back); its other file references
  were not re-checked line by line.
- Three inferences still need a five-line MATLAB script each; see
  [Confirm first](#confirm-first).

Symbols: M = modules on the RPcox interface, N = visible non-write-only parameters,
W = parameters written per trial, K = on-screen `Parameter_Control`s bound to
dispatched hardware parameters. GUI figures refer to the lab's
`cl_AppetitiveDetection_BehaviorGUI`.

## Findings

### A. Trial boundary

Order inside [ep_TimerFcn_RunTime.m](../runtime/timerfcns/ep_TimerFcn_RunTime.m): read
everything (51) → journal (70) → `notify('NewData')` (84) → select (127) → dispatch
(144: ResetTrig, W writes, NewTrial).

| # | Cost | Where | Size |
|---|------|-------|------|
| A1 | **Display work runs before the next trial is dispatched.** Every analysis object and plot updates synchronously inside `notify('NewData')`. | [ep_TimerFcn_RunTime.m:84](../runtime/timerfcns/ep_TimerFcn_RunTime.m#L84) | Repo harness, no `drawnow` ([smoke_test_incremental_perf.m:10](../tmp/smoke_test_incremental_perf.m#L10)): History 3.7–8.4 ms, ParameterScatter 29–33 ms, Staircase plot 16–30 ms per trial at 200–1000 trials. **~50–70 ms/trial measured** for the lab GUI. |
| A2 | **A yield inside the boundary forces the render into it.** `trigger` does `pause(0.001)` between writing 1 and 0; `pause` drains the event queue, so the graphics queued by A1 — and any other timer's or button's callback — run inside the ResetTrig pulse, before one parameter is written. `gui.AdaptiveTraining` calls `drawnow limitrate` from its `NewData` handler. | [TDT_RPcox.m:554](../obj/+hw/@TDT_RPcox/TDT_RPcox.m#L554), [TDT_Synapse.m:496](../obj/+hw/@TDT_Synapse/TDT_Synapse.m#L496), [AdaptiveTraining.m:318](../obj/+gui/@AdaptiveTraining/AdaptiveTraining.m#L318), [Parameter_Update.m:135](../obj/+gui/+components/Parameter_Update.m#L135) | History's table costs 30–40 ms of view round trip per changed property ([gui_History.md](../documentation/gui/gui_History.md), "Update Cost"). **Tens of ms/trial** and a variable trigger pulse width — inferred from that figure and from `pause`'s documented behaviour, not timed in the loop. |
| A3 | **Trial-end sweep: 2M+1 device calls per parameter, one at a time.** `get.Value` probes `IsConnected` (one `GetStatus` per module), then the backend probes it again, then one `ReadTagVEX`. RPcox makes every discovered tag `Any` + visible, so values the host itself wrote are read back, and so are whole `Buffer` and `Coefficient Buffer` tags. | [all_parameters.m:54](../obj/+epsych/@Runtime/all_parameters.m#L54), [Parameter.m:266](../obj/+hw/@Parameter/Parameter.m#L266), [TDT_RPcox.m:650](../obj/+hw/@TDT_RPcox/TDT_RPcox.m#L650), [populateModuleParametersFromTags.m:42](../obj/+hw/@TDT_RPcox/populateModuleParametersFromTags.m#L42) | **N·(2M+1) COM calls** where N+M would do, plus full buffer transfers: ~2.3 MB/trial for a 3 s stimulus ([hw_benchmarkIO.md](../documentation/hw/hw_benchmarkIO.md), "Deciding per-trial upload"), which also accumulates in `DATA` and the journal for the whole session. |
| A4 | **Each on-screen control reads the device back on every dispatch write.** The `PostSet` listener calls `Parameter.Value`, assigns the widget unconditionally, then `refreshDependents_` reads again. A changed value also creates, starts and deletes a MATLAB `timer` per flash. | [Parameter_Control.m:1018](../obj/+gui/+components/Parameter_Control.m#L1018), [:1063](../obj/+gui/+components/Parameter_Control.m#L1063), [Helper.m:53](../obj/+gui/@Helper/Helper.m#L53) | **K·(2M+1) to 2K·(2M+1) COM calls** + K widget writes, between ResetTrig and NewTrial. The lab GUI has ~20 Value-bound controls. |
| A5 | **Expression evaluation reads every sibling parameter** in the module — named or not, invisible tags and whole buffers included — then runs one `eval` per context field. Likely the largest dispatch cost wherever a protocol uses expressions on a hardware module. | [resolveExpressionContext.m:54](../obj/+hw/@Parameter/resolveExpressionContext.m#L54), [evalExpressionInContext.m:22](../obj/+hw/@Parameter/evalExpressionInContext.m#L22) | **(siblings)·(2M+1) COM calls per expression per trial**, plus a full transfer for each readable buffer sibling. |
| A6 | **Syringe pump over RS-232** (protocols with an `hw.NE1000`). The sweep queries `Rate`, `Volume` and the dispensed volume every trial; dispatch rewrites `Rate`/`Volume` unchanged. Each is a blocking transaction, and a blocking serial read lets other timers run. | [NE1000.m:393](../obj/+hw/@NE1000/NE1000.m#L393), [:972](../obj/+hw/@NE1000/NE1000.m#L972), [:1626](../obj/+hw/@NE1000/NE1000.m#L1626) | **~5 serial transactions/trial**, 3–4 redundant when the settings do not change. |
| A7 | **Dispatch rewrites every per-trial parameter, changed or not** (M+1 COM each). A `StimType` write regenerates the waveform and uploads the whole buffer every trial. | [dispatchNextTrial.m:77](../obj/+epsych/@Runtime/dispatchNextTrial.m#L77), [Interface.m:750](../obj/+hw/@Interface/Interface.m#L750) | **W·(M+1) COM calls**; one full upload per stimulus per trial. |
| A8 | **Trace logging.** `GLogVerbosity` defaults to `Inf`, so every level-4 record is built (`dbstack`) and written. Dispatch logs one per parameter and the backend logs the same write again. | [dispatchNextTrial.m:78](../obj/+epsych/@Runtime/dispatchNextTrial.m#L78), [TDT_RPcox.m:618](../obj/+hw/@TDT_RPcox/TDT_RPcox.m#L618), [callerFrame.m:37](../obj/granary/+granary/callerFrame.m#L37) | 200 µs documented, 332 µs measured live in the August review. **≈2W+15 records ≈ 20–30 ms/trial at W=40.** |

### B. Per tick

| # | Cost | Where |
|---|------|-------|
| B1 | The idle watchdog reads every interface's live `mode` each tick: M+1 `GetStatus` on RPcox, **one HTTP GET on Synapse**. The August review measured the comparison itself (`get(array,'mode') == Idle`, a cell against an enum) as always false with two or more interfaces; the line is unchanged, so on a real rig this likely costs device calls and can never fire. Not re-run here. | [RunExpt.m:623](../obj/+epsych/@RunExpt/RunExpt.m#L623), [TDT_Synapse.m:422](../obj/+hw/@TDT_Synapse/TDT_Synapse.m#L422) |
| B2 | `TrialComplete.Value` per subject: 2M+1 COM on RPcox. On Synapse a read that returns 0 — the normal case — costs a **second** HTTP GET, because `SynapseAPI.checkMode` calls `getMode()` whenever the value is 0. | [ep_TimerFcn_RunTime.m:22](../runtime/timerfcns/ep_TimerFcn_RunTime.m#L22), [SynapseAPI.m:97](../TDTfun/SynapseAPI/SynapseAPI.m#L97) |

Per tick today: **3M+2 COM calls on RPcox, 3 HTTP requests on Synapse**; one is needed.
No tick duration is recorded anywhere, so an overrun is invisible.

### C. Background GUI load

| # | Cost | Where |
|---|------|-------|
| C1 | `Parameter_Monitor` reads one parameter per widget per poll, unbatched. The lab GUI polls 11 parameters at 10 Hz: **110 reads/s = 110·(2M+1) COM calls/s**, all session — comparable to the trial loop's own polling. | [update_graphical_.m:17](../obj/+gui/+components/@Parameter_Monitor/update_graphical_.m#L17), [build.m:186](../paradigms/BehaviorGUIs/@cl_AppetitiveDetection_BehaviorGUI/build.m#L186) |
| C2 | Every pop-out is a second instance with its own timer, reads and analysis (Monitor, OnlinePlot, Staircase, History, SessionPerformance). | by design ([gui_PopOut.md](../documentation/gui/gui_PopOut.md)) |
| C3 | The same session is decoded 3–5 times per trial: Staircase, a separate `SessionMetrics` built for the performance panel, and History each extract and bit-decode every trial's response code. | [Psych.m:111](../obj/+psychophysics/Psych.m#L111), [SessionPerformance.m:503](../obj/+gui/+components/@SessionPerformance/SessionPerformance.m#L503) |
| C4 | Unguarded per-trial property writes: ParameterScatter rewrites ~10 axes properties, the colormap and the colorbar every trial; Staircase rewrites its labels and limits every trial. | [ParameterScatter.m:817](../obj/+gui/+components/@ParameterScatter/ParameterScatter.m#L817), [updatePlotLabels_.m:8](../obj/+psychophysics/@Staircase/updatePlotLabels_.m#L8) |
| C5 | Where a `SyringePump` panel is open it polls by name at 4 Hz: ~8 RS-232 round trips/s, each preceded by a parameter-name scan. | [SyringePump.m:1059](../obj/+gui/+components/@SyringePump/SyringePump.m#L1059) |

### Already solved — not re-proposed

Per-trial persistence (`epsych.TrialJournal`, flat ~2 ms); the History, ParameterScatter
and Staircase per-trial caches; OnlinePlot's batched reads; phase fast-parse and
cache; cached `mode` on NE1000, Teensy and Intan. No `setpref`, `save` or fit runs
per trial.

## Step 0 — measure first (no behaviour change)

1. **Call-count harness**, `tmp/bench_trial_boundary.m`, headless.
   - Extend the counting double [tmp/BatchProbeInterface.m](../tmp/BatchProbeInterface.m)
     (it already counts reads) to count writes, triggers, connection probes and mode
     reads, with options for injected per-call latency, float32 coercion of written
     values, and a write that is refused.
   - Drive it as [smoke_test_runtime_journal.m](../tmp/smoke_test_runtime_journal.m)
     does: `ep_TimerFcn_Start`, then a loop that sets `FORCE_TRIAL` and calls
     `ep_TimerFcn_RunTime` directly. Do not read `RUNTIME.TRIALS` from top-level code
     while a session timer runs ([tmp/OddballSessionDriver.m](../tmp/OddballSessionDriver.m)
     documents why).
   - Report per trial and per tick: backend calls by kind, `Value` reads (counted
     with `PostGet` listeners, which also works on `hw.Software`), log records, and
     ms per phase. Take boundary-entry, ResetTrig and NewTrial timestamps from the
     double's `trigger`.
   - Run a 1 ms sentinel timer to detect any yield inside dispatch.
   - The counts are deterministic, so each fix below gets an assertion.
2. **Tick statistics in the loop**: `tic`/`toc` stamps into a preallocated ring on
   `epsych.Runtime` (tick duration, boundary duration per phase, overruns), off by
   default, summarised at Stop.
3. **On the rig, between sessions**: `hw.benchmarkIO(iface)` once at the default
   `GLogVerbosity` and once at 3 for per-call medians, and one Preview session under
   the MATLAB profiler with the lab GUI open. Multiply the medians by the counts in
   the Findings to rank them for that rig.

## Workarounds available today (no code change)

- **Logging:** set `GLogVerbosity = 3` on the rig before Run. Trace records then cost
  the ~4–7 µs gate instead of 200–330 µs each (A8). The cost is losing per-parameter
  dispatch detail from the log.
- **Sweep size:** in the protocol, make tags the session never needs in `DATA`
  invisible (a `_` or `~` prefix in RPvds, or `Visible = false`), buffer tags above
  all (A3). The documented cost: an invisible buffer is not in the trial record.
- **Monitor:** raise the lab GUI's `pollPeriod` from 0.1 s toward 0.25–0.5 s and hide
  rows nobody watches; hidden rows are not polled (C1).
- **Pop-outs:** close the ones not in use; each is a second timer and a second
  analysis (C2).
- **Synapse rigs:** a longer `TimerPeriod` (20 ms) halves the per-tick HTTP load at
  the price of up to 10 ms more trial-end latency (B1, B2).

## Fixes, in recommended order

Lowest risk and highest value first. Each is independently shippable, and the
Step 0 harness gives each a before/after count.

### R1. One log record per dispatch (A8)

- Replace the per-parameter trace in `dispatchNextTrial` with one record listing
  `name=value`, built with `P(j).formatValue`. The present `%g` is already wrong
  for char and `StimType` values.
- Suppress the backend's per-write *success* record only while a transient
  in-dispatch flag on the interface is set. Failure records always go out, and an
  operator's write keeps its record.
- Do not add a `visenabled` guard: it is true by default and costs more than the
  arguments it would protect.
- No test asserts on these lines. About 40 lines in 3–4 files.
- Tests: `smoke_test_granary_integration`, `smoke_test_runtime_journal`,
  `smoke_test_writeonly_parameter_reads`.

### R2. Expressions read only what they name (A5)

- In `resolveExpressionContext`, scan the expression text for identifiers
  (`[A-Za-z]\w*`, no dot lookarounds) and read only those siblings. Call
  `makeValidName` once over all sibling names, and collect the cross-module
  parameter list only when the text contains a `Name.Name` pattern.
- **Do not drive this from `info.references`.** Its sibling pattern
  ([resolveExpressionContext.m:92](../obj/+hw/@Parameter/resolveExpressionContext.m#L92))
  rejects a name followed by `.`, so `A.*B`, `A./B` and `A.^2` are not reported.
  Today they still evaluate because the context is unconditional; a lazy context
  built from `info.references` would throw mid-dispatch.
- Fix that pattern separately (`(?!\.)` → `(?!\.[A-Za-z])` at lines 92 and 103).
  The same gap means `orderByDependencies` may already miss those dependencies.
- The raw scan misses only names built at eval time (`eval(['Fo' 'o'])`). Document it.
- Keep `ProtocolDesigner/private/rewriteExpressionReferences.m` in step; it mirrors
  the resolver.
- One file, about 25 lines.
- Tests: `smoke_test_expression_check`, `smoke_test_dispatch_order`,
  `smoke_test_index_expressions`, `smoke_test_checkcalc_random`,
  `smoke_test_dependency_graph`, `smoke_test_crossinterface_expression_restore`,
  plus a new dot-operator case.

### R3. No yields inside the trial boundary (A2)

- Replace `pause(0.001)` in `hw.TDT_RPcox.trigger` and `hw.TDT_Synapse.trigger` with
  a non-yielding 1 ms hold (`tic`/`toc` spin) in one shared helper. Graphics queued
  during the boundary are then drawn after the timer callback returns.
- Remove the `drawnow limitrate` in `gui.AdaptiveTraining.updateParameter` and the
  `drawnow` in `Parameter_Update.value_changed`.
- `hw.Bpod` already does this and says why: "no pause or drawnow in this loop on
  purpose: both process the event queue" ([trigger.m:183](../obj/+hw/@Bpod/trigger.m#L183)).
- Nothing relies on the yield: SessionGate, calibration and the benchmark's Stop
  button each have their own. It also closes two races — a queued click nesting a
  second dispatch inside the ResetTrig pulse, and an autoCommit edit landing in the
  pulse and being overwritten by the row dispatch copied earlier.
- Yields that remain: NE1000 transactions (so a protocol with a pump is not fully
  isolated) and `pause(0.001)` in `Intan_RHX.sendGet_`.
- Constraint: `smoke_test_hw_benchmark_io` scans the source of `TDT_RPcox.trigger`.
  Keep its header, its position before `set_parameter`, the
  `hw:TDT_RPcox:TriggerFailed` id and `P.Module.Label`.
- About 15 lines in 2–3 files; update `hw_benchmarkIO.md`'s trigger rows.
- Tests: `smoke_test_synapse_legacy`, `smoke_test_hw_benchmark_io`,
  `smoke_test_regenerate_trial`, `smoke_test_sessiongate`.

### R4. One connection probe per access (A3, B2, C1)

- Keep the public `IsConnected` live; connect, connect-recovery, SelfTest,
  `hw.benchmarkIO` and the parameter debugger need the truth.
- Add a concrete `hw.Interface` hook that defaults to `obj.IsConnected`.
  `hw.TDT_RPcox` overrides it with a short-lived cache (~0.25 s) and uses it in
  `trigger`, `set_parameter`, `get_parameter` and the mode query. `get.Value` calls
  the hook.
- `get.Value` must keep *some* probe: every backend's offline branch reads
  `P(i).Value` and relies on `get.Value` short-circuiting, or it recurses.
- Invalidate on connect, `close_interface`, `resetSession` (before and after the
  reload), `setModules`, any write returning 0, any read returning `[]`, and a COM
  exception.
- Resolve `isprop(Parent,'IsConnected')` once in the `hw.Parameter` constructor;
  `Parent` is immutable. Keep the mirrored predicate in
  `Protocol/dryRunExpressions.m` and `sweepExpressions.m` in step.
- A scalar read drops from 2M+1 COM calls to 1; the monitor (C1) gets most of its
  saving from this alone.
- **Not testable headlessly** — there is no RPcox mock. Validate on the rig with
  `hw.benchmarkIO` before and after.
- About 55 lines in 3 files.
- Tests: `smoke_test_reset_session`, `smoke_test_connect_recovery`,
  `smoke_test_runexpt_selftest`, `smoke_test_parameter_debugger`,
  `smoke_test_onlineplot`, `smoke_test_writeonly_parameter_reads`.

### R5. Cached `mode` on the TDT backends; no second request on Synapse (B1, B2)

- Cache the mode inside `TDT_RPcox.queryModeState_` and
  `TDT_Synapse.queryModeState_` for ~0.1 s, as `hw.Teensy` already does. Write
  through on set — Synapse must store the mode `awaitMode_` actually reached, not
  the one requested — and invalidate on connect, disconnect and `resetSession`.
- **Do not throttle the watchdog in `RunExpt`.** `hw.Bpod`'s `get.mode` is "the
  guaranteed per-tick hook the byte pump hangs off"
  ([Bpod.m:292](../obj/+hw/@Bpod/Bpod.m#L292)); skipping ticks would starve it.
- In `TDT_Synapse.readOne_`, read scalars without the vendor `checkMode` second
  request, through a seam `tmp/SynapseAPI_Mock` can honour.
- Large on Synapse (one HTTP GET per tick, two on a zero read); small on RPcox
  after R4.
- About 30 lines in 2 files.
- Tests: `smoke_test_synapse_legacy`, `smoke_test_sessionclock_stop`.

### R6. Controls stop reading the device when nothing changed (A4)

- Give `hw.Parameter` a host-side copy of the value `set.Value` last stored — a
  shadow property set beside `obj.Value = value`, not a bypass flag (`Value` is
  `GetObservable`, and a test counts `PostGet` as a device read).
- Use it in `Parameter_Control.value_change_external` **only to detect change,
  never as what the widget shows**:
  - host value unchanged, no pending edit, not committing → return before any read
    or widget write;
  - host value unchanged with a pending edit → a re-assert; keep the edit. Record a
    host-side base in `value_changed` beside `PendingBase_`;
  - host value changed → today's code, device read-back included.
- **Why not simply show the host value.** `PendingBase_` is a device read-back
  ([Parameter_Control.m:597](../obj/+gui/+components/Parameter_Control.m#L597)).
  Compared against a host value it fails on any float32 tag (0.1 against
  0.100000001490116), so every staged edit would be discarded at the next boundary.
  `smoke_test_pending_edit_survives_dispatch` runs on `hw.Software` and cannot see
  that. The read-back on a real change is also the only place an operator sees a
  coerced or refused write.
- Keep `runPostUpdateFcn` on the unchanged path, or make skipping it opt-in: an
  out-of-repo GUI may use it as a per-trial tick.
- Replace the timer-per-flash in `gui.Helper.timed_color_change` with one reusable
  timer per control.
- About 50 lines in 2 files.
- Tests: `smoke_test_pending_edit_survives_dispatch`, `smoke_test_autocommit_trialsync`,
  `smoke_test_parameter_control_bounds`, `smoke_test_parameter_control_range`,
  `smoke_test_modifier_buttons`, `smoke_test_adaptive_training`, plus a new test on
  a coercing counting double: zero reads on a re-assert, the edit survives float32,
  a real change shows the read-back.

### R7. Cheaper sweep (A3)

- First, inside `Runtime.all_parameters(valueOnly=true)`: cache the `validName`
  strings, validated each trial by handle and `Name` equality the way
  `DispatchOrderCache_` is. `makeValidName` runs once per parameter per trial today.
  About 20 lines, no semantic change. Other callers of that method
  (`examples/detection_task`, `examples/syringepump`, a lab's custom
  `TIMERfcn.RunTime`) benefit too.
- After R4 a per-parameter read is already one COM call, so a shared batched read
  plan (hoisted from [OnlinePlot.m:731](../obj/+gui/+components/@OnlinePlot/OnlinePlot.m#L731))
  saves only MATLAB-side overhead. Build it only if the harness still shows the
  sweep as significant. If built, it must:
  - apply `double()` to numerics as `get.Value` does;
  - leave `StimType`, write-only and `hw.Software` parameters on `get.Value`;
  - probe connectivity once per group and fall back to `get.Value` when
    disconnected (`hw.Intan_RHX.get_parameter` returns empty cells then);
  - not batch a group of one, or a group with duplicate names;
  - keep field order — it drives History's columns;
  - demote a backend permanently only for an argument-validation error, and
    otherwise retry per parameter so a throw still ends the session as today.
- Do not scope the sweep by box; that changes `DATA`.
- Tests: `smoke_test_runtime_journal`, `smoke_test_onlineplot`, `smoke_test_bufferplot`,
  `smoke_test_pump_trial_cycle`, plus a new test asserting `isequaln` with the
  legacy struct, field order included.

### R8. Draw after the trigger (A1)

- A dirty flag and a `flushRender()` on each display component (a small mixin, like
  `gui.PopOut`). Policy and trigger live in `gui.BehaviorGUI`: enrol the registered
  components, flush from `dispatchNewTrial_` and `dispatchModeChange_`, with a
  one-shot safety timer.
- Analysis stays synchronous. `Psych.recomputeResults_` runs on `NewData` as now,
  because a selector or a paradigm hook may read `Results`.
- **Do not move `notify('NewData')` after dispatch.** `gui.AdaptiveTraining` steps
  the next trial's parameter and rewrites the trials column from `NewData`
  ([eval_adaptive_training_mode.m:270](../obj/+gui/eval_adaptive_training_mode.m#L270)),
  and out-of-repo `onNewData` hooks are unknowable.
- Guards:
  - opt-in by the host only — a standalone or offline component renders
    immediately, so the display smoke tests are unchanged;
  - never defer in `ReviewMode` (`ReviewSession.seek` sends no `NewTrial` at the
    last trial);
  - `BufferPlot` must still *read* an invisible buffer at `NewData` and defer only
    the draw, since the next dispatch may overwrite it;
  - pop-out instances must be enrolled.
- Moves about 50–75 ms of handler work behind the NewTrial trigger. R3 alone
  already moves the graphics flush.
- About 250 lines in ~11 files.
- Tests: `smoke_test_incremental_render`, `smoke_test_history_render`,
  `smoke_test_parameter_scatter`, `smoke_test_session_performance`,
  `smoke_test_staircase_plot`, `smoke_test_bufferplot`, `smoke_test_review_session`,
  `smoke_test_psych_offline_fixes`, `smoke_test_behaviorgui`,
  `smoke_test_appetitive_behaviorgui`, `smoke_test_adaptive_training`.

### R9. Skip the upload of an unchanged stimulus (A7)

- Still call `update_signal` on every dispatch. `stimgen.Noise` draws from the
  global random stream, so skipping the call would change the stimulus and shift
  every later global draw, the selector's catch-trial draw included.
- Compare the generated `Signal`, in device precision, with the last upload to that
  tag, and skip only the transfer.
- Keep the record in the backend, keyed by module and tag, so every writer
  invalidates it — including a raw-array write to the same tag, as calibration
  makes.
- Clear on reload/`resetSession`, connect, any Synapse mode write, and a failed
  write. Give the interface an opt-out for a circuit that records into the same
  buffer.
- About 40 lines in each of 2 files. `obj/stimgen` is not touched.
- Tests: `smoke_test_stimtype_any_hardware`, `smoke_test_synapse_legacy`,
  `smoke_test_stimtype_calibration_roundtrip`, `smoke_test_reset_session`.

### R10. Skip unchanged device writes; cache pump settings (A6, A7)

Highest stale-state risk, so last and opt-in per backend.

- Skip the device write — not the rest of `set.Value`; `PostSet` still fires, which
  is all the staged-edit logic needs.
- Only during dispatch (the in-dispatch flag from R1). The parameter debugger,
  operator commits, phase loads and calibration always write.
  `RegenerateTrial.redispatch` and the trial-1 dispatch get a force-write option.
- Skip only when the device demonstrably holds the value: the last trial-end
  read-back equals it in device precision, and nothing has written the tag since.
  A tag the device changes therefore never qualifies and is always written.
- Only visible, `Any`-access, scalar numeric parameters. Never triggers, `StimType`,
  buffers, or write-only parameters.
- Invalidate on `TDT_RPcox.resetSession` (a reload restores circuit defaults; a
  stale skip on trial 1 would be issue #19 in a new form), connect,
  `close_interface`, every Synapse mode write or observed mode change, and any
  failed write.
- NE1000 traps: the `RAT` reply's units are discarded, so a units change is
  invisible to the read-back — do not skip `Rate` unless units are verified;
  `set_parameter` clears the dispensed-volume cache on every write, so keep that
  invalidation at dispatch; invalidate on any alarm.
- Separately, cache the pump's *settings* reads (`Rate`, `Volume`), invalidated by
  a write, an alarm and connect. No other fix here removes them from the sweep.
- About 170 lines in 6–7 files.
- Tests: `smoke_test_reset_session`, `smoke_test_dispatch_order`,
  `smoke_test_regenerate_trial`, `smoke_test_ne1000`, `smoke_test_pump_trial_cycle`,
  `smoke_test_setonce_param`, `smoke_test_synapse_legacy`.

## Smaller items and open decisions

- **Display-side guards (C4).** Write axes, colorbar, label and limit properties
  only when they change. ParameterScatter's remaining ~30 ms per trial is graphics,
  not data.
- **Buffers in the trial record (A3).** A visible buffer tag is read, converted to
  double, stored in `DATA` and journalled every trial. Check the rig's protocol for
  one. Making "record this buffer every trial" an explicit choice changes `DATA`,
  so it is a decision, not a clean-up.
- **Idle watchdog (B1).** Whether it should *work* on a multi-interface rig is a
  separate decision: it has apparently never fired there, so making it effective is
  a behaviour change.
- **One decode per trial (C3).** A decoded-response cache per subject, extended by
  the new trial, read by Staircase, SessionMetrics and History.
- **One sampler for display polling (C1, C2, C5).** A single runtime-owned timer
  reading the union of what the displays watch. After R4 the saving is mostly
  duplicate reads from pop-outs.
- **Selector reads.** `cl_AppetitiveStimDetect.selectNext` reads several parameter
  values between `NewData` and dispatch; each is a device read if the parameter is
  hardware-backed.
- **To check:** whether a readable `StimType` parameter puts a handle object into
  `DATA` and the journal's byte stream each trial.

## Considered and not recommended

| Idea | Why not |
|------|---------|
| Rate-limit the watchdog in `RunExpt` | Starves `hw.Bpod`'s per-tick byte pump (R5). |
| Move `notify('NewData')` after dispatch | Breaks adaptive training and unknown paradigm hooks (R8). |
| Show the host value in a control, or use it in expression contexts | Differs from the device wherever a value is coerced (float32, integer tags, pump formatting). |
| Compile each expression into a function handle | About 0.3 ms per expression after R2, against invalidation on `Expression`, sibling names and runtime-added parameters. |
| A map for `TDTRP.check_tag` | Saves ~15 µs against a COM call. |
| Worker-process I/O ([async-hardware-io.md](async-hardware-io.md)) | Designed, partly built and removed unvalidated. R1–R10 take out most of what motivated it; revisit only if the boundary is still transport-bound afterwards. |

## Redesigns to consider

- **Device-side trial record.** Have the circuit latch a trial's results into one
  buffer tag, read with a single `ReadTagVEX`; fire triggers with `SoftTrg`.
- **Latch-on-NewTrial parameters.** Write the next trial's values into shadow tags
  during the current trial and let the circuit latch them, taking dispatch out of
  the boundary for everything that is not outcome-dependent.

## Expected effect

Device calls for an **illustrative** single-module RPcox rig (M=1, N=60 swept, W=40
written, K=20 controls, 2 expressions in a 60-parameter module). Counts from the
formulas above, not measurements.

| Per trial | Today | After R1–R7 | After R8–R10 |
|---|---|---|---|
| Sweep | 180 | 61 | 61 |
| Dispatch writes | 80 | 41 | ~5 |
| Control read-backs | 60–120 | ~3 (changed values only) | ~3 |
| Expressions | 360 | ~4 | ~4 |
| Triggers | 6 | 4 | 4 |
| **COM calls** | **~690–750** | **~115** | **~80** |
| Log records | ~95 | ~15 | ~15 |
| Display work before the next trial | 50–70 ms + render | 50–70 ms, render after | analysis only; drawing after the trigger |

| Continuous | Today | After R4–R5 |
|---|---|---|
| COM calls per 10 ms tick | 5 | 1, plus about 10–15 status calls/s |
| Monitor, 11 parameters at 10 Hz | 330 COM/s | ~115 COM/s |

## Confirm first

Three inferences the fixes rest on. Each needs a five-line script, run when no
session is using the MATLAB thread:

1. `PostSet` fires after `set.Value` returns (R6 and the read-back behaviour
   `CLAUDE.md` describes both assume it).
2. The dot-operator gap in the sibling pattern: an expression such as `A.*B` is
   absent from `info.references` (R2).
3. A blocking `serialport` read yields to timers (taken from the NE1000 comments;
   it decides how much R3 isolates a protocol with a pump).

## Critical files

- Trial loop: [ep_TimerFcn_RunTime.m](../runtime/timerfcns/ep_TimerFcn_RunTime.m),
  [dispatchNextTrial.m](../obj/+epsych/@Runtime/dispatchNextTrial.m),
  [all_parameters.m](../obj/+epsych/@Runtime/all_parameters.m)
- Hardware: [Parameter.m](../obj/+hw/@Parameter/Parameter.m),
  [resolveExpressionContext.m](../obj/+hw/@Parameter/resolveExpressionContext.m),
  [Interface.m](../obj/+hw/@Interface/Interface.m),
  [TDT_RPcox.m](../obj/+hw/@TDT_RPcox/TDT_RPcox.m),
  [TDT_Synapse.m](../obj/+hw/@TDT_Synapse/TDT_Synapse.m),
  [NE1000.m](../obj/+hw/@NE1000/NE1000.m)
- GUI: [Parameter_Control.m](../obj/+gui/+components/Parameter_Control.m),
  [Helper.m](../obj/+gui/@Helper/Helper.m),
  [AdaptiveTraining.m](../obj/+gui/@AdaptiveTraining/AdaptiveTraining.m),
  [BehaviorGUI.m](../obj/+gui/@BehaviorGUI/BehaviorGUI.m)
- Docs that describe behaviour these fixes change: `hw_benchmarkIO.md` (the trigger
  rows and the `get.Value` probe count), `hw_TDT_Synapse.md`, `gui_OnlinePlot.md`,
  `Parameter_Control.md`, and the matching `CLAUDE.md` paragraphs.

`obj/granary` and `obj/stimgen` are separate repositories and are not touched.

## Verification

- **Counts**: `tmp/bench_trial_boundary.m` asserts backend calls per trial and per
  tick before and after each fix (deterministic, no hardware).
- **Behaviour unchanged**: the tests named under each fix, run one at a time through
  the MATLAB MCP session (`-batch` for the modal ones). Record each test's result on
  `master` first and compare against that baseline.
- **Saved data unchanged**: run the same seeded software session before and after
  R4 and R7 and compare `DATA` field for field (names, order, class, values).
- **On the rig**: `hw.benchmarkIO` before and after R4; one Preview session with
  tick statistics on, comparing boundary and tick durations; scope the
  ResetTrig/NewTrial pulses once after R3.

## Implementation status

Built on branch `perf/runtime-review` (2026-11-21), one commit per fix. Tested
headlessly against a counting stand-in for the device
(`tmp/CountingProbeInterface.m`, `tmp/bench_trial_boundary.m`), the Synapse and
NE-1000 mocks, and on an RZ6 over the GB link running the repository's benchmark
circuit, including the real trial loop.

### What was built

| | Change | Default | Standing proof |
|---|---|---|---|
| Step 0 | `epsych.TickStats` (preference `EPsych/TickStats`), `tmp/bench_trial_boundary.m` | off | the benchmark itself |
| R1 | One trace record per dispatch; backends leave per-write records out while `hw.Interface.InDispatch` | on | `smoke_test_dispatch_order` |
| R2 | An Expression reads only the siblings it names; the dot-operator gap in the dependency scan fixed | on | `smoke_test_dispatch_order` groups 2b, 2c |
| R3 | `hw.Interface.holdPulse` (a busy wait) in the TDT triggers; `drawnow` removed from the `NewData` and commit paths | on | benchmark yield count |
| R4 | `hw.Interface.ioReady`; `hw.TDT_RPcox` caches its `GetStatus` probe for 0.25 s | on | `smoke_test_readplan`, `hw_benchmark_io` |
| R5 | Mode cached for 0.1 s on both TDT backends; Synapse scalar reads without the vendor's second request; `RunExpt.StopOnIdleHardware` | watchdog off for several interfaces, as it effectively was | `smoke_test_idle_watchdog` |
| R6 | `Parameter_Control` skips the device read-back when the host value did not change; one shared flash timer | on | `smoke_test_pending_edit_survives_dispatch` group 9 |
| R7 | `hw.ReadPlan`: the trial-end sweep and `Parameter_Monitor` read one batch per interface | on | `smoke_test_readplan` |
| R8 | `epsych.EventHub.defer`: displays draw after the `NewTrial` pulse | opt-in (`gui.BehaviorGUI.deferDisplayWork`, preference `EPsych/DeferDisplays`); on for the lab's appetitive GUI | `smoke_test_eventhub_deferral` |
| R9 | `hw.Interface.SkipUnchangedStimulus`: an unchanged `StimType` waveform is not uploaded again | **on** | `smoke_test_stimulus_upload_skip` |
| R10 | `hw.Interface.SkipUnchangedWrites`; `hw.NE1000.SettingsCacheInterval` | opt-in (preference `EPsych/SkipUnchangedWrites`) | `smoke_test_skip_unchanged_writes`, `smoke_test_ne1000_settings_cache` |
| Smaller | Display-side guards in ParameterScatter and the Staircase plot; each distinct colour converted once | on | `smoke_test_incremental_perf` (a measurement) |
| Smaller | `epsych.Runtime.trialRecord`, `RecordBuffers`, `RecordStimulusSettings` | both opt-in | `smoke_test_trial_record` |

### What measurement corrected

- **Timers do not nest.** Code in a timer callback is never interrupted by
  another timer, not even at a `pause` or `drawnow` (R2024b, `-batch` and
  interactive). A2's "any other timer's callback runs inside the ResetTrig
  pulse" was wrong. What `pause` does do is force every pending graphics
  update to render there: 24 ms for one table change against 1 ms for a busy
  wait. R3 stands, for that reason alone. It also means a benchmark has to
  drive the loop from inside a timer callback; from a script the measured
  boundary is interrupted by whatever timers are running.
- **The multi-interface watchdog cost nothing and never fired (B1).**
  `get(heterogeneousArray,'mode')` returns a cell of `[]` and calls no
  backend's `get.mode`, so on a rig with two or more interfaces the idle check
  made no device call and could not be true. R5 keeps that as the default and
  makes "stop when hardware goes idle" an explicit choice.
- **The device is fast; MATLAB is what a call costs.** On the RZ6 over GB a
  raw RPcoX `GetStatus` is 19 µs, `ReadTagVEX` 40 µs, `SetTagVal` 42 µs, while
  `P.Value` was 362 µs and `P.Value = x` 598 µs. The findings' call counts
  rank the costs correctly but understate how much of each is host-side.
- **The largest single costs were not in the Summary.** A 1 s `StimType`
  stimulus uploaded every trial is 278 ms of the boundary; a visible
  million-sample buffer tag in the trial record is 196 ms plus 7.8 MB of
  journal. Both were listed under A7 and A3 without a size.
- **A readable `StimType` does put the live object in every record** (the "to
  check" item): the same handle in every trial, and 0.9 MB of journal per
  trial for a 1 s stimulus.
- **Half the staircase redraw was colour conversion.** `hex2rgb` over every
  trial's colour string on every trial: 16 of 32 ms at 1000 trials.

### Measured after

The real trial loop on the RZ6 (benchmark circuit, software triggers, median
wait per trial): a recorded million-sample buffer 230 ms, without it 6.5 ms; a
1 s stimulus uploaded every trial 291 ms, unchanged upload skipped 15 ms, with
unchanged writes skipped and the stimulus recorded as settings 12 ms. Through
`hw.Parameter` on that device: a read 362 → 122 µs, a mode read 122 → under
1 µs, an idle tick 546 → 176 µs.

The benchmark with 20 controls at 200 µs per call: 470 device calls per trial
→ 112 (72 with `SkipUnchangedWrites`), 56 log records → 6, a 180 ms wait →
47 ms. Per appended trial, the scatter 30 → 11 ms and the staircase plot
28 → 12 ms at 1000 trials.

### Not done

- **One decode per trial (C3).** Profiled at about 1 ms per analysis object
  per trial at 1000 trials (`Psych.perTrialNumeric_`, already vectorized, is
  0.47 ms a call, and the Staircase already memoizes within a refresh). A
  cache shared across objects needs an identity for "the same DATA" that a
  struct array does not have; not worth a wrong-trial hazard for a
  millisecond.
- **One sampler for display polling (C1, C2, C5).** After R4 and R7 a monitor
  poll is one batch per interface with no probe of its own (two parameters:
  180 µs on the RZ6, against 237 µs read one at a time, and 724 µs before).
  A shared sampler would save only the reads a pop-out duplicates.
- **Compile each expression once.** As under *Considered and not
  recommended*: an expression now costs 0.4–0.7 ms over a plain write, of
  which the device read of each parameter it names is 0.12 ms and cannot go
  without changing what the expression sees.
- **OnlinePlot** keeps its own read plan rather than `hw.ReadPlan`; it was
  already batched.
- **The redesigns** (a device-side trial record, latch-on-NewTrial
  parameters) need RPvds circuit changes and were not attempted.
- **Not validated on hardware:** `hw.TDT_Synapse` (mock only), `hw.NE1000`
  (mock only), a full `epsych.RunExpt` session with the lab's protocol and
  behavior GUI, and the trigger pulse width on a scope. The benchmark circuit
  has no trial triggers, so on the RZ6 those three lived on the software
  module.
- **Pre-existing failures**, unchanged by this work and failing the same way
  on `master`: `smoke_test_expression_check`, two checks of
  `smoke_test_staircase_weighted_toggle`, and
  `smoke_test_hw_benchmark_runexpt`. Of the 98 smoke tests in the final run,
  the other 96 pass.
