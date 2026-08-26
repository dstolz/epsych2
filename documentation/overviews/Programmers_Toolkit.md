# EPsych Programmer's Toolkit

A catalog of the classes and functions worth knowing **before writing your own**. EPsych has accumulated a lot of small, sharp tools — a block randomizer, a crash-safe trial journal, a signal-detection metric object, a pop-out mixin, a serial-port picker — and most of them are invisible from the outside: they live one folder deep in a package and are documented only in their own help text. This page is the index.

The organizing question is **"what am I trying to do?"**, not "what package is it in". Every entry names the mechanism and the consequence, so you can tell from the table alone whether the tool is the one you want. Where two tools look interchangeable and are not, the difference is written down in [Reach for this, not that](#reach-for-this-not-that).

Companion documents: [Class_Map.md](Class_Map.md) is the inheritance and dependency view of the same code, [Architecture_Overview.md](Architecture_Overview.md) is the runtime flow, and the per-subsystem references under [documentation/](../README.md) are the exhaustive treatment of anything listed here.

## Table of contents

- [Trial values and randomization](#trial-values-and-randomization)
- [Trial selection and the trial table](#trial-selection-and-the-trial-table)
- [Outcome coding and per-trial data](#outcome-coding-and-per-trial-data)
- [The runtime: state, parameters, events](#the-runtime-state-parameters-events)
- [Protocols and phase files](#protocols-and-phase-files)
- [Hardware and parameters](#hardware-and-parameters)
- [Online and offline analysis](#online-and-offline-analysis)
- [Behavior GUI building blocks](#behavior-gui-building-blocks)
- [Subjects, projects, and session configuration](#subjects-projects-and-session-configuration)
- [Logging and diagnostics](#logging-and-diagnostics)
- [The stimgen seam](#the-stimgen-seam)
- [Teensy program model](#teensy-program-model)
- [General-purpose utilities](#general-purpose-utilities)
- [Reach for this, not that](#reach-for-this-not-that)

## Trial values and randomization

Anything that has to vary trial by trial — an ITI, a hold duration, a level, a stimulus identity — has a right answer here, and it is usually not `rand`.

| Tool | Use it for |
|---|---|
| [`epsych.BlockSequence`](../../obj/+epsych/@BlockSequence/BlockSequence.m) | A pregenerated, **block-randomized** list of values that the caller indexes by trial number. Every value appears its exact share within each block rather than merely on average, and because the caller owns the index the value for a trial can be re-read, rewound, or fast-forwarded and is always the same value. Optional `Repeats` (unequal but exact proportions), `MaxConsecutive`, `NoRepeatAcrossBlocks`, and `Jitter` — all off by default, because each distorts the sampling distribution. `Seed` resolves eagerly and never touches the global stream, so a session can be replayed. |
| [`hw.Parameter.isRandom`](../../obj/+hw/@Parameter/Parameter.m) | The cheap alternative: `set.Value` redraws `randi([Min Max])` on every dispatch. Memoryless, integer-only, and unbalanced over any finite session. Fine for a jitter nobody analyzes; wrong for a factor. |
| [`randGellerman`](../../helpers/randGellerman.m) | Two-alternative sequences obeying Gellermann's (1933) constraints — balanced, run-capped, no exploitable alternation. |
| [`FellowsSeq`](../../helpers/FellowsSeq.m) | Chance stimulus sequences per Fellows (1967), for discrimination tasks. Seed with `rng` first for repeatability. |
| [`RandomTrialSequence`](../../helpers/RandomTrialSequence.m) | Binary sequence with a maximum run length and a cap on cumulative drift. |
| [`findConsecutive`](../../helpers/findConsecutive.m) | First/last indices of runs of `true` in a logical vector, optionally forgiving *g* intervening zeros. The tool behind "three hits in a row" and "five aborts, stop the session" rules. |
| [`Viemeister`](../../helpers/Viemeister.m) | Modulation-depth to effective-power conversion for AM detection work. |

```matlab
% A block-randomized inter-trial interval, read by trial index
s = epsych.BlockSequence([500 1000 1500 2000], Label = "ITI");
iti = s.valueAt(TRIALS.TrialIndex);

% Unequal but exact proportions, a run cap, and jitter
s = epsych.BlockSequence([500 1000 1500 2000], Repeats = [2 2 2 1], ...
        MaxConsecutive = 2, Jitter = 50, ValueLimits = [250 Inf]);
```

> A parameter driven from a `BlockSequence` **must have `isRandom = false`**, or `set.Value` overwrites the drawn value on dispatch. Full treatment, including the mid-session edit rule and the step-size trap: [epsych_BlockSequence.md](../epsych/epsych_BlockSequence.md).

## Trial selection and the trial table

| Tool | Use it for |
|---|---|
| [`epsych.TrialSelector`](../../obj/+epsych/@TrialSelector/TrialSelector.m) | The abstract contract for deciding what runs next: `initialize(snapshot)`, `selectNext(TRIALS)`, `onRecompile(snapshot)`, and the optional `onComplete(trialID, data)` where adaptive policies live. Instantiate through `epsych.TrialSelector.create(selectorConfig)`. |
| [`epsych.DefaultTrialSelector`](../../obj/+epsych/@DefaultTrialSelector/DefaultTrialSelector.m) | The stock policy: pick from the least-used trials, break ties randomly. Read it first — it is the shortest complete implementation of the contract. |
| [`epsych.Runtime.compiledTrialColumns`](../../obj/+epsych/@Runtime/compiledTrialColumns.m) | The trial table plus the column map that names its columns. `writeparams`, `writeParamIdx`, `trials`, and `parameters` are only meaningful together; this is the one place that returns them consistently. |
| [`epsych.Runtime.dispatchNextTrial`](../../obj/+epsych/@Runtime/dispatchNextTrial.m) | Apply the selected trial's writable parameters, fire the reset and new-trial triggers, broadcast `NewTrial`. Call it if you are driving a session yourself instead of through the timer chain. |
| [`epsych.Runtime.resolveTriggerParameters`](../../obj/+epsych/@Runtime/resolveTriggerParameters.m) | Locate and cache the mandatory `NewTrial` / `ResetTrig` / `TrialComplete` triggers for one subject's box, erroring immediately when one is missing rather than at the first dispatch. |

Reference: [epsych_TrialSelector.md](../epsych/epsych_TrialSelector.md), [epsych_TrialLifecycle.md](../epsych/epsych_TrialLifecycle.md).

## Outcome coding and per-trial data

| Tool | Use it for |
|---|---|
| [`epsych.BitMask`](../../obj/+epsych/@BitMask/BitMask.m) | The `uint32` enumeration behind every response code: behavioral states, contingencies, trial types, choices, options. `Bits2Mask` builds a mask, `Mask2Bits` decodes one, and the `getResponses` / `getContingencies` / `getTrialTypes` / `getChoices` group accessors save you from hard-coding bit lists. Also carries the default plot colors, so a figure legend and a history table agree. |
| [`bitmaskGUI`](../../helpers/bitmaskGUI.m) | Build a mask interactively — check the flags, read the integer, click to copy it. Useful when writing a save function or a filter by hand. |
| [`epsych.TrialJournal`](../../obj/+epsych/@TrialJournal/TrialJournal.m) | Append-only, crash-safe `.epj` journal written per trial during a run: one length-prefixed record per named variable, flat ~2 ms per append regardless of session length. `ep_TimerFcn_Stop` merges it into the seed `.mat`; `epsych.TrialJournal.recover` rebuilds that artifact after a crash from an orphaned journal. |
| [`epsych.TrialsData`](../../obj/+epsych/TrialsData.m) | The `event.EventData` payload delivered with `NewData` / `NewTrial` — `Data`, `Subject`, `BoxID`. What your listener's second argument actually is. |
| [`epsych.eventModeChange`](../../obj/+epsych/eventModeChange.m) | The `ModeChange` payload: `NewMode`, typically an `hw.DeviceState`. |
| [`PRGMSTATE`](../../obj/PRGMSTATE.m) | Session state enumeration — `NOCONFIG`, `CONFIGLOADED`, `READY`, `RUNNING`, `POSTRUN`, `STOP`, `ERROR`. Top-level, not in a package. |
| [`hw.DeviceState`](../../obj/+hw/DeviceState.m) | Backend state enumeration — `Idle`, `Standby`, `Preview`, `Record`, `Stop`, `Pause`, `Error`, plus `isIdle`. |

```matlab
flags = [epsych.BitMask.Hit epsych.BitMask.Reward];
mask  = epsych.BitMask.Bits2Mask(uint32(flags));
[bits, activeFlags] = epsych.BitMask.Mask2Bits(mask);
```

Reference: [epsych_BitMask.md](../epsych/epsych_BitMask.md), [epsych_TrialJournal.md](../epsych/epsych_TrialJournal.md).

## The runtime: state, parameters, events

`epsych.Runtime` is the session's state container, and most paradigm code talks to it through four or five methods rather than by reaching into its properties.

| Tool | Use it for |
|---|---|
| [`epsych.Runtime`](../../obj/+epsych/@Runtime/Runtime.m) | The container itself: `TRIALS`, `HW` / `S` (interfaces), `EVENTS`, `TIMER`, `NSubjects`. It is a `dynamicprops` handle, so a paradigm may attach its own state to it. |
| [`Runtime.all_parameters`](../../obj/+epsych/@Runtime/all_parameters.m) | Every `hw.Parameter` across every registered interface, with switches for triggers and invisible parameters. The starting point for any generic GUI or logger. |
| [`Runtime.find_parameter`](../../obj/+epsych/@Runtime/find_parameter.m) | Parameters by name, optionally pre-filtered by interface class, interface type, or module — the lookup a behavior GUI does for each control it builds. |
| [`Runtime.filter_parameters`](../../obj/+epsych/@Runtime/filter_parameters.m) | Parameters whose *property* matches a value or pattern (all buffers, everything writable, everything on box 2). |
| [`epsych.EventHub`](../../obj/+epsych/@EventHub/EventHub.m) | The per-session broadcaster on `RUNTIME.EVENTS` carrying `NewData`, `NewTrial`, and `ModeChange`. Subscribe; do not poll. (Named `epsych.Helper` before 2026-08.) |
| [`Runtime.updateTrialsFromParameters`](../../obj/+epsych/@Runtime/updateTrialsFromParameters.m) | Push edited parameter values back into the writable columns of `TRIALS`, which is what a "commit" button ultimately does. |
| [`epsych.SelfTest`](../../obj/+epsych/@SelfTest/SelfTest.m) | Nine groups of real pre-flight checks against a loaded session — compile the protocols, exercise the selector, write and read back a data file, probe hardware — each returning a status and an actionable remedy. Headless; `gui.SelfTest` is the window. Mutating groups (hardware connect, behavior GUI launch, GUI state cycling) are opt-in. |

Reference: [epsych_Runtime.md](../epsych/epsych_Runtime.md), [Event_Notifications.md](../epsych/Event_Notifications.md), [RunExpt_SelfTest.md](RunExpt_SelfTest.md).

## Protocols and phase files

A protocol is the experiment's data model; a phase file is the same format holding one training stage's values. Both are `.eprot`.

| Tool | Use it for |
|---|---|
| [`epsych.Protocol`](../../obj/+epsych/@Protocol/Protocol.m) | Interfaces, parameters, options, compiled trials. `addInterface` / `addParameter` / `removeParameter`, `compile`, `validate`, `save` / `load`, `toJSON` / `fromJSON`. |
| `Protocol.listVersions` / `loadVersion` / `restoreVersion` / `compareVersions` | The version archive every `save` writes inside the `.eprot`. `compareVersions(fileA, vA, fileB, vB)` says what changed between two versions — a file and a version **per side**, so a protocol revised under a new name still compares. It reads the stored structs alone, never rebuilding the object graph, so a version naming a backend this installation cannot construct still compares; it never throws, because every caller is a dialog that has to say why. `gui.compareProtocolVersions` is the window over it. |
| [`Protocol.needsCompile`](../../obj/+epsych/@Protocol/needsCompile.m) | Whether the compiled trial table is stale — cheaper and more honest than recompiling defensively. |
| [`Protocol.estimateDuration`](../../obj/+epsych/@Protocol/estimateDuration.m) | Total session seconds from the compiled trials. `NaN` when compilation is incomplete. |
| [`Protocol.analyzeExpressions`](../../obj/+epsych/@Protocol/analyzeExpressions.m) | Static analysis of every parameter `Expression` without compiling or evaluating: dispatch ordering, dormancy, unresolvable references, cycles. |
| [`Protocol.dryRunExpressions`](../../obj/+epsych/@Protocol/dryRunExpressions.m) | Simulate *n* trials' worth of expression evaluation exactly as `dispatchNextTrial` would, against a simulated value store. No hardware, no mutation. |
| [`Protocol.sweepExpressions`](../../obj/+epsych/@Protocol/sweepExpressions.m) | Evaluate every expression over the **full cross-product** of its inputs using the real evaluator and `set.Value` clamping — the exhaustive version of the dry run. |
| [`Protocol.dependencyGraph`](../../obj/+epsych/@Protocol/dependencyGraph.m) | The parameter dependency graph as pure data (nodes, edges), so it can be inspected headlessly; the designer draws the same structure. |
| [`Protocol.versionOnDisk`](../../obj/+epsych/@Protocol/versionOnDisk.m) / [`versionNumber`](../../obj/+epsych/@Protocol/versionNumber.m) | Read a file's stored `protocolVersion` without rebuilding its object graph, and compare two version strings. Asked once per subject on every subject-list repaint, which is why it exists. |
| [`Runtime.phaseParameterData`](../../obj/+epsych/@Runtime/phaseParameterData.m) | The single chokepoint for reading a phase file: `.eprot`, `.prot`, or legacy JSON all reduce to one struct array of `hw.Parameter.toStruct` entries plus `ParentType`. Falls back to a full `Protocol.load` whenever the fast shape is not recognized. |
| [`Runtime.phaseCache`](../../obj/+epsych/@Runtime/phaseCache.m) | The session-lifetime memo behind it, keyed on path + mtime + size. `phaseCache('clear'\|'disable')` restores unmemoized behavior. |
| [`Runtime.readParameters`](../../obj/+epsych/@Runtime/readParameters.m) / [`writeParametersProtocol`](../../obj/+epsych/@Runtime/writeParametersProtocol.m) | Load a phase into the live session, or save the session's current values as a new phase file. |

Reference: [epsych_Protocol.md](../epsych/epsych_Protocol.md), [ProtocolDesigner.md](../design/ProtocolDesigner.md).

## Hardware and parameters

| Tool | Use it for |
|---|---|
| [`hw.Interface`](../../obj/+hw/@Interface/Interface.m) | The abstract backend contract — `connect`, `disconnect`, `get_parameter`, `set_parameter`, `trigger`, `setup_interface`, plus the `IsConnected` and `mode` properties. Also three connect-recovery hooks with safe defaults (`connectionRecoveryLabel`, `recoverConnection`, `canRunOffline`) that decide what the session offers an operator when a backend will not come up. |
| [`hw.Module`](../../obj/+hw/@Module/Module.m) | The parameter container: `add_parameter`, `writeParametersJSON` / `readParametersJSON`, `Fs`, `Info`. |
| [`hw.Parameter`](../../obj/+hw/@Parameter/Parameter.m) | One parameter with its metadata, bounds, callbacks, and dispatch policy (`UpdateEveryTrial`, `SetOnce`, `isRandom`, `Expression`). `toStruct` is what gets serialized into every protocol and phase file. |
| [`hw.Parameter.expressionSelectsIndex`](../../obj/+hw/@Parameter/Parameter.m) | The single predicate deciding whether an `Expression` result is a value or a **1-based index into `Values`** (the latter for `String` and `StimType` parameters). Anything reading expressions must ask it rather than re-deriving the rule. |
| [`hw.Software`](../../obj/+hw/@Software/Software.m) | The in-memory backend. Every protocol can be built, compiled, and run against it with nothing plugged in — the reason a laptop is a valid development rig. |
| [`hw.InterfaceSpec`](../../obj/+hw/InterfaceSpec.m) / [`hw.InterfaceSpecOption`](../../obj/+hw/InterfaceSpecOption.m) | The value objects a backend returns from `getCreationSpec()` to describe itself to the Protocol Designer: type, label, options, and the factory that builds it. |
| [`gui.selectSerialPort`](../../obj/+gui/selectSerialPort.m) | The modal port picker for a serial backend that will not connect. **Refresh** re-enumerates, so a device powered on while the dialog is open can be chosen; an optional `Probe` callback adds a detect button, which is the only thing that distinguishes a wrong port from a device that is off. Ports held by another process are listed but not selectable. |

> Adding a backend means edits at four hardcoded registry sites **outside** the class folder — there is no reflection. The checklist is in [hw_Interface_Tutorial.md](../hw/hw_Interface_Tutorial.md); omitting `Protocol.createInterfaceFromStruct_` fails silently, reloading saved protocols as `hw.Software` stubs.

## Online and offline analysis

Every class in this section works **online** (construct with a `Runtime`; it follows `NewData` events) and **offline** (construct with a saved `DATA` struct array; no listeners attached). That is the base-class contract, not a per-class feature.

| Tool | Use it for |
|---|---|
| [`psychophysics.Metrics`](../../obj/+psychophysics/Metrics.m) | The formulas themselves, with no state: d′, criterion, relative criterion, ln β, A′, B″, proportion correct, and the four named corrections for rates of exactly 0 or 1 — including the trial-count dependent log-linear and 1/(2N) rules. Needs no Statistics Toolbox, broadcasts, and propagates NaN rather than turning a missing rate into a bound. `fromCounts(nHit,nMiss,nFA,nCR)` returns the lot. `rateDenominator` holds the one judgement call in the denominators — aborts are excluded by default, and every class here takes the same `IncludeAborts` option. Call this rather than re-deriving a z-transform; everything below delegates to it. See [psychophysics_Metrics.md](../psychophysics/psychophysics_Metrics.md). |
| [`psychophysics.Psych`](../../obj/+psychophysics/Psych.m) | The abstract base: shared trial data, the `ExcludedTrials` mask, `StimulusTrialType`, `refresh`, and `NewData` propagation. Subclass it rather than writing a listener by hand. |
| [`psychophysics.SessionMetrics`](../../obj/+psychophysics/@SessionMetrics/SessionMetrics.m) | Session-level counts, outcome rates, d′ and criterion over a configurable trial window, computed from the decoded response bitmask — so it serves any paradigm that writes `RespCode`. The computation behind `gui.components.SessionPerformance`, and equally usable headlessly. |
| [`psychophysics.TrialWindow`](../../obj/+psychophysics/TrialWindow.m) | The immutable "which trials" value object: all, last *N*, first *N*, or an explicit range. `parse` accepts the shorthand — `"all"`, `50`, `[20 100]`, `"last 20"`, `"20-100"` — so a window can be written the way you would say it. |
| [`psychophysics.Detection`](../../obj/+psychophysics/@Detection/Detection.m) | Hit and false-alarm rates, d′, and bias **grouped by unique stimulus value** — the psychometric-function view of a detection task. `Hit_Rate` is `Hit/(Hit+Miss)` at each value and `FA_Rate` is `FA/(FA+CR)` over the session, both honoring `IncludeAborts`; `gui.components.SlidingWindowPerformancePlot` follows the same setting. Note `Hit_Rate` is deliberately *not* `[obj.Rate.Hit]`, which is the proportion of every trial at that value. |
| [`psychophysics.NAFC`](../../obj/+psychophysics/@NAFC/NAFC.m) | N-alternative forced choice: per-alternative choice functions, proportion correct against a 1/N chance level, the confusion matrix, and choice bias. Choices come from `Choice_*` bits or a named DATA field, the correct alternative from `TrialType`. It also defines the forced-choice bit encoding: `Choice_k` alone carries which alternative was chosen, `Hit` means that choice was correct and `Miss` means it was wrong, an early answer is an `Abort`, and a trial with no response carries no outcome bit at all (Undefined). `CorrectReject`/`FalseAlarm` are detection outcomes and are never set; `psychophysics.SessionMetrics` does not apply. Its plot (three switchable `PlotType`s) redraws itself on every refresh, and it is a `gui.PopOut` adopter. Embedded live in `examples/two_afc`. |
| [`psychophysics.Staircase`](../../obj/+psychophysics/@Staircase/Staircase.m) | Step direction, reversal detection, and threshold estimation for adaptive procedures. Also a `gui.PopOut` adopter, so it plots in a window of its own. |
| [`psychophysics.BestPEST`](../../obj/+psychophysics/@BestPEST/BestPEST.m) | Maximum-likelihood threshold seeking: grid MLE fit after each trial, next level placed at the current estimate, with a profile-likelihood confidence interval. |
| [`psychophysics.MLP`](../../obj/+psychophysics/@MLP/MLP.m) | Three-parameter Bayesian procedure over threshold, slope, and lapse rate, placing each trial at one of up to four sweet points. |
| [`gui.Helper`](../../obj/+gui/@Helper/Helper.m) | Table row highlighting and timed color changes. Its `dprime2AFC(HR)`, `criterion(HR,FR)` and `percent_correct(HR,FR)` now forward to `psychophysics.Metrics`, keeping their hard-coded `[0.01 0.99]` bounds; they remain because lab GUIs outside this repository inherit the mixin. Call `psychophysics.Metrics` directly in new code. |

```matlab
% Offline: the last 50 trials of a saved session
S = psychophysics.SessionMetrics(DATA, TrialWindow = "last 50");
disp(S.Results)
```

Reference: [psychophysics_SessionMetrics.md](../psychophysics/psychophysics_SessionMetrics.md).

## Behavior GUI building blocks

A paradigm GUI subclasses [`gui.BehaviorGUI`](../../obj/+gui/@BehaviorGUI/BehaviorGUI.m) and implements `build(fig)` — nothing else. The base class owns single-instance enforcement, figure creation with position persistence, event listeners, the teardown registry, and `Parameter_Update` wiring. Inside `build`, the `add*` methods are the intended vocabulary: each one constructs a component, registers it for teardown, and returns the handle.

| `build` helper | Creates |
|---|---|
| `addControl(parent, param, …)` | A `gui.components.Parameter_Control` bound to a parameter. **An unresolved name returns `[]` without error**, so one `build` serves protocols with differing parameter sets. |
| `addButton(parent, param, …)` | An auto-committing trigger button; a parameter whose name starts with `~` becomes a toggle. |
| `controlColumn(parent, Title=…)` | A titled panel wrapping a scrollable fixed-row-height grid, ready for a stack of `addControl` calls. |
| `addUpdateButton(parent)` | The commit button; its watch list is filled automatically after `build` with every non-trigger, non-autoCommit control. |
| `addMonitor(parent, params, …)` | A `gui.components.Parameter_Monitor`. Registered monitors stop polling when the session mode goes to Stop. |
| `addNextTrial(parent, …)` | The upcoming-trial display. |
| `addPerformance(parent, …)` | A `gui.components.SessionPerformance` computed through this GUI's psychophysics object when it has one, so trial-type conventions match. |
| `addSyringePump(parent, …)` | The `gui.components.SyringePump` panel over the session's `hw.NE1000` — or a standalone one when the protocol has no pump, so the GUI still opens. |
| `addScreenCapture(parent, …)` | The camera button that copies the whole window to the clipboard. |
| `addPopOutButton(parent, component, …)` | A button opening any `gui.PopOut` component in its own window. A non-poppable component is skipped with a message. |
| `addComponentToolbar(fig, …)` | The icon toolbar. Call it at the **top** of `build`: automatic entries are collected after `build` returns, so everything built later is still listed. |
| `register(comp, name)` | Put any component in the teardown registry — required for handle objects, whose listeners and timers outlive their graphics. |
| `defer(fcn)` | Queue a closure to run at the first `NewTrial`, when parameter values are real. |

Display components (all adopt `gui.PopOut` unless noted):

| Component | Shows |
|---|---|
| [`gui.components.History`](../../obj/+gui/@History/History.m) | Trial-by-trial table, rows colorable by decoded response bit. |
| [`gui.components.NextTrial`](../../obj/+gui/@NextTrial/NextTrial.m) | Parameters of the trial about to run, refreshed on every `NewTrial`. |
| [`gui.components.SessionPerformance`](../../obj/+gui/@SessionPerformance/SessionPerformance.m) | Counts, rates, d′, criterion, with the trial window on a right-click menu. |
| [`gui.components.ParameterScatter`](../../obj/+gui/@ParameterScatter/ParameterScatter.m) | Any per-trial parameter against any other, with an optional color-by parameter, all chosen from dropdowns at runtime. |
| [`gui.components.PsychPlot`](../../obj/+gui/@PsychPlot/PsychPlot.m) | Online psychometric summary (d′, hit rate, FA rate, bias) driven by a psychophysics object's own `NewData`. |
| [`gui.components.OnlinePlot`](../../obj/+gui/@OnlinePlot/OnlinePlot.m) | Real-time multi-trace hardware activity for one box, with time window and trial-locked modes. |
| [`gui.components.SlidingWindowPerformancePlot`](../../obj/+gui/@SlidingWindowPerformancePlot/SlidingWindowPerformancePlot.m) | Performance metrics over a moving trial window. |
| [`gui.components.Performance`](../../obj/+gui/@Performance/Performance.m) | Summary table of performance metrics from a linked psychophysics object. |
| [`gui.components.Parameter_Monitor`](../../obj/+gui/@Parameter_Monitor/Parameter_Monitor.m) | Polled current values of an array of parameters. |
| [`gui.components.SessionClock`](../../obj/+gui/@SessionClock/SessionClock.m) | Up to four live readouts: since last trial, since first trial, since session start, wall clock. |
| [`gui.components.ElapsedTrialTimer`](../../obj/+gui/@ElapsedTrialTimer/ElapsedTrialTimer.m) | Time since the last completed trial; usable headlessly by reading `ElapsedTime`. |
| [`gui.components.ModeIndicator`](../../obj/+gui/@ModeIndicator/ModeIndicator.m) | Lamp and label reflecting the current `hw.DeviceState`. |
| [`gui.components.StatusBar`](../../obj/+gui/@StatusBar/StatusBar.m) | Footer message line, green for success and red for errors; double-click copies the text. |

Infrastructure and design-time tools:

| Tool | Use it for |
|---|---|
| [`gui.PopOut`](../../obj/+gui/@PopOut/PopOut.m) | The mixin that gives a component its own window. A pop-out is a **second instance** over the same data source with its own graphics, listeners, and preference key, so it can never disturb the embedded one. Adopting takes three steps: inherit, implement `createPopOut_`, implement `popOutHostContainer_`. |
| [`gui.components.ComponentToolbar`](../../obj/+gui/@ComponentToolbar/ComponentToolbar.m) | One tool per display. **Lazy** entries declared with `addLazyComponent(name, factory, …)` are built on first click, which is how a paradigm offers a display without spending a polling timer or listeners on it up front. |
| [`gui.components.Parameter_Control`](../../obj/+gui/Parameter_Control.m) | The bound editor itself: edit field, range pair, dropdown, checkbox, button, or `'auto'`. |
| [`gui.components.Parameter_Update`](../../obj/+gui/Parameter_Update.m) | The commit button controller — enables itself when any watched editor is dirty; Ctrl-click discards. |
| [`gui.ParameterDebugger`](../../obj/+gui/@ParameterDebugger/ParameterDebugger.m) | Every parameter a protocol defines, readable and writable by hand. **It never polls** — reads happen only on demand — which is what makes it safe beside a running experiment. Cell color *is* the read report. |
| [`gui.ParameterTracker`](../../obj/+gui/@ParameterTracker/ParameterTracker.m) | The same parameters *against time* — scalar values on one live plot, in a window that owns its timer, its rate (0.1–20 Hz), and a Pause button. This is where the polling the debugger refuses to do actually lives, which is why it is a separate window rather than a debugger tab. A failed or non-scalar read is `NaN` (an honest break in the line) and is logged once per parameter, not once per sample. |
| [`gui.BehaviorBuilder`](../../obj/+gui/@BehaviorBuilder/BehaviorBuilder.m) | Design-time generator for `BehaviorGUI` subclasses: drag regions on a canvas, export a subclass that calls only the documented `add*` DSL. The headless statics (`specNew`, `specValidate`, `writeCode`) are testable on their own. |
| [`gui.BasicGUI`](../../obj/+gui/@BasicGUI/BasicGUI.m) | A tabbed GUI built automatically from any protocol — one tab per interface, one panel per module. The zero-effort GUI for prototyping. |
| [`gui.components.ScreenCapture`](../../obj/+gui/@ScreenCapture/ScreenCapture.m) | Copy the whole window — controls and plots alike — to the clipboard. Renders offscreen, so an obscured window still copies. |
| [`gui.toolbarIcon`](../../obj/+gui/toolbarIcon.m) | The 16×16 glyphs, drawn as pixel art so the toolbox ships no image files. `uibutton`'s `Icon` accepts only four built-in names, so every other glyph comes from here. |
| [`gui.GenericTimer`](../../obj/+gui/GenericTimer.m) | Timer creation, lookup, and start/stop lifecycle tied to a figure — instead of a bare `timer` that outlives its GUI. |
| [`gui.components.FilenameValidator`](../../obj/+gui/@FilenameValidator/FilenameValidator.m) | Edit field that enforces `.mat`, rejects invalid characters, and warns on an existing file. |
| [`showGridBorders`](../../helpers/showGridBorders.m) | Draw and label every cell of a `uigridlayout` while you are fighting a layout. Debug only — it adds child labels. |
| [`findFigure`](../../helpers/findFigure.m) | Find a figure by tag, creating it if absent. Keeps a repeatedly-opened window from spawning duplicates. |

Reference: [gui_BehaviorGUI.md](../gui/gui_BehaviorGUI.md), [gui_PopOut.md](../gui/gui_PopOut.md), [gui_ComponentToolbar.md](../gui/gui_ComponentToolbar.md), [gui_BehaviorBuilder.md](../gui/gui_BehaviorBuilder.md), and the template in [examples/customgui/](../../examples/customgui/).

## Subjects, projects, and session configuration

| Tool | Use it for |
|---|---|
| [`epsych.SubjectRoster`](../../obj/+epsych/@SubjectRoster/SubjectRoster.m) | The shared, file-backed roster of subjects organized by project (`.esub`). Every mutation goes through a reload-if-stale → apply → atomic-write cycle, which is what lets two rigs share one file on a network drive. `assignToSession` is the all-or-nothing commit into `RunExpt.CONFIG`; `ReplaceExisting=true` makes the batch the session's whole subject list, which is what the manager's button asks for. |
| `SubjectRoster.protocolStatus` / `updateProtocol` / `revertProtocol` | Protocol version tracking. Because `Protocol.save` overwrites an `.eprot` in place, the roster is the only thing that can notice a protocol edited between sessions: `current \| outdated \| pinned \| differs \| unknown \| missing \| none`. Revert restores the pointer and version, and gets the **content** back either by rewriting the file (`RestoreContent`) or by **holding** just that subject on the archived version, which `assignToSession` then loads for it. |
| `SubjectRoster.configuredFile` / `setConfiguredFile` | Where the roster lives. There is **no default location and no fallback**: until an operator names a file the roster is unbound, and `mutate_` throws rather than reporting a silent success. |
| [`epsych.Subject`](../../obj/+epsych/@Subject/Subject.m) / [`epsych.DefaultSubject`](../../obj/+epsych/@DefaultSubject/DefaultSubject.m) | The subject record — `BoxID`, `Name`, `Sex`, `Species`, plus `Weight` and `Notes`. `fromStruct` / `toStruct` for serialization. Roster records carry no BoxID; `toSubject` materializes one at assignment time. |
| [`gui.SubjectManager`](../../obj/+gui/@SubjectManager/SubjectManager.m) | The Subjects & Projects window, and the operator's only path to putting subjects in a session. |

Reference: [epsych_SubjectRoster.md](../epsych/epsych_SubjectRoster.md), [gui_SubjectManager.md](../gui/gui_SubjectManager.md).

## Logging and diagnostics

| Tool | Use it for |
|---|---|
| [`vprintf`](../../helpers/vprintf.m) | Every message EPsych prints. `vprintf(level, msg, …)`, or `vprintf(level, 1, msg)` for red. Levels: `-1` log only, `0` critical, `1` info, `2` debug, `3` verbose, `4` trace. **Never end a message with `\n`.** With values the message is a format string; with no values it is literal text — which is what lets `ME.message` and Windows paths survive intact. |
| [`visenabled`](../../helpers/visenabled.m) | The gate alone, for guarding a log argument that is genuinely expensive to build. `vprintf`'s own gate already makes an unwanted message cost microseconds, so use this only around real work. |
| [`eplog.isEnabled`](../../obj/+eplog/isEnabled.m) | The gate itself, per destination: `isEnabled(level,'console'\|'log'\|'any')`. The console (`GVerbosity`, default 1) and the error log (`GLogVerbosity`, default `Inf`) are decoupled — a quiet command window no longer costs the record. |
| [`eplog.Level`](../../obj/+eplog/Level.m) | Named levels — `LogOnly`, `Critical`, `Info`, `Debug`, `Verbose` — usable anywhere a number is accepted. |
| [`eplog.Logger`](../../obj/+eplog/@Logger/Logger.m) | The session singleton behind `vprintf`. `instance()`, `emit`, `flush`, `addSink`, and `LogFile` — **the** way to name the current log file. Never rebuild that path by hand; call `flush()` first if something is about to open it. |
| [`eplog.setLogDir`](../../obj/+eplog/setLogDir.m) | Point the daily logs somewhere else — a rig whose repository sits on a read-only or synced share. Persists as a preference and re-points the live logger immediately. Unlike the rest of the package it *does* throw, because it is configuration rather than logging. |
| [`eplog.formatException`](../../obj/+eplog/formatException.m) | Render an `MException` — or a `lasterror`-style struct such as `RUNTIME.ERROR` — as one record, preserving the catch site as the caller. This is what `catch ME; vprintf(0,1,ME); end` calls. |
| [`EPsychInfo`](../../helpers/@EPsychInfo/EPsychInfo.m) | Version, license, git checksum, commit timestamp, latest tag, the pinned stimgen checksum, and a `diagnostics` struct of host and software environment. What saved session metadata records, and what a bug report should include. |
| [`epsych_path`](../../epsych_path.m) | The toolbox root, resolved from `which`. Build paths from it rather than from `pwd`. |

## The stimgen seam

`obj/stimgen/` is a **git submodule** with no dependency on EPsych. Never put an `epsych.*` or `hw.*` reference inside it — these three classes are why.

| Tool | Use it for |
|---|---|
| [`stimbridge.RuntimeHost`](../../obj/+stimbridge/RuntimeHost.m) | Implements `stimgen.HardwareHost` over `epsych.Runtime` / `epsych.Protocol`, so stimgen GUIs drive EPsych hardware without naming an EPsych type. |
| [`stimbridge.InterfaceAdapter`](../../obj/+stimbridge/InterfaceAdapter.m) | Implements `stimgen.calibration.HwAdapter` over an `hw.Interface`. Resolves its five required parameters at construction and errors immediately if any is absent; discovers `Fs` from the first module reporting a device rate. |
| [`stimbridge.LogBridge`](../../obj/+stimbridge/LogBridge.m) | Routes stimgen's messages into `eplog`, so a `StimPlayer` failure lands in the session log instead of `tempdir`. Installed by `epsych_startup`. |
| [`epsych.calibrate`](../../obj/+epsych/calibrate.m) | Launch the stimgen calibration GUI with the bridge already wired — with a protocol it loads, connects, and enters Preview first. |
| [`isConcreteStimType`](../../helpers/isConcreteStimType.m) | Whether a class name is an **instantiable** stimulus. `stimgen.StimType` is `Hidden`, so the obvious `superclasses` test returns false for every stimulus; this walks `meta.class` instead, and also covers an unchecked-out submodule. |

> A new method added to a `stimgen.*` abstract class must be **concrete with a safe default**, or the `stimbridge` subclass becomes unconstructable. `epsych.SelfTest` check A3 is the tripwire. Reference: [stimgen.md](../stimgen.md).

## Teensy program model

Design-time tooling that turns an operant paradigm into a state table the board executes, so the contingency lives in a file rather than in firmware. No GUI dependency, which is what makes it testable headlessly. 🚧 Under development.

| Tool | Use it for |
|---|---|
| [`teensy.Program`](../../obj/+teensy/@Program/Program.m) | The document: channels, variables, states, timers, counters. A handle class, so a rename cascades through every reference including nested condition operands. |
| [`teensy.Compiler`](../../obj/+teensy/@Compiler/Compiler.m) | Emit the wire records, and check the program against the firmware's fixed array sizes. |
| [`teensy.Simulator`](../../obj/+teensy/@Simulator/Simulator.m) | Reference implementation of the firmware's execution semantics — powers the designer's test bench, the headless tests, and the firmware author's spec. |
| [`teensy.Templates`](../../obj/+teensy/Templates.m) | Ready-made paradigms (Go/No-Go, 2AFC, fixed ratio, shaping, passive), each a complete valid program with its diagram laid out. Start here rather than from an empty canvas. |
| [`teensy.varRef`](../../obj/+teensy/varRef.m) / [`teensy.isVarRef`](../../obj/+teensy/isVarRef.m) | Build and test the `"@Name"` reference that points a numeric field at a `teensy.Variable`. The single place that decides whether a field holds a literal or a reference. |
| [`teensy.getFieldOr`](../../obj/+teensy/getFieldOr.m) | Read one field from a serialized struct with a default, so a file written before a field existed still loads. Every `fromStruct` in the package goes through it. |

```matlab
p = teensy.Templates.get("GoNoGoDetection");
teensy.TrialDesigner(p);
```

Reference: [teensy_TrialDesigner_UserGuide.md](../teensy/teensy_TrialDesigner_UserGuide.md), [hw_Teensy_Program_Protocol.md](../hw/hw_Teensy_Program_Protocol.md).

## General-purpose utilities

| Tool | Use it for |
|---|---|
| [`findincell`](../../helpers/findincell.m) | Indices of non-empty cells, where `cell2mat` cannot help. |
| [`timeout`](../../helpers/timeout.m) | A stateful guard for a loop that might not terminate: `timeout(10)` to arm, `while ~timeout` to spin, `if timeout` to report. |
| [`PhotodiodeMarker`](../../helpers/PhotodiodeMarker.m) | Prime the corner of a Psychtoolbox window for a photodiode sync marker, immediately before flipping. |
| [`gexf`](../../helpers/gexf.m) | Write an adjacency matrix as a GEXF graph for Gephi. |
| [`util.VideoConverter`](../../obj/+util/@VideoConverter/VideoConverter.m) | Batch ffmpeg transcoding as *tracked child processes* — true per-file progress, instant cancellation, optional N-way parallelism, and a MATLAB that does not freeze for the whole encode. Progress arrives as [`util.ProgressEventData`](../../obj/+util/ProgressEventData.m); [`gui.VideoConverterSetup`](../../obj/+gui/@VideoConverterSetup/VideoConverterSetup.m) is the front end. |
| [`hw.VlcRecorder`](../../obj/+hw/@VlcRecorder/VlcRecorder.m) / [`gui.VlcRecorderSetup`](../../obj/+gui/@VlcRecorderSetup/VlcRecorderSetup.m) | Webcam recording under session control, configured against a live preview with an interactive crop rectangle. |
| [`peripherals.NanoMotorControl`](../../obj/+peripherals/@NanoMotorControl/NanoMotorControl.m) | The Arduino Nano DM320T stepper controller (motorized commutator) over its ASCII serial protocol, with a GUI in `peripherals.NanoMotorControlGUI`. |
| [`peripherals.PumpCom`](../../obj/+peripherals/@PumpCom/PumpCom.m) | Direct serial control of a syringe pump outside the `hw` hierarchy. For a pump the protocol should drive, use [`hw.NE1000`](../../obj/+hw/@NE1000/NE1000.m) instead. |

## Reach for this, not that

The pairs that look interchangeable and are not. Each row is a mistake that has already been made.

| Want | Use | Not | Because |
|---|---|---|---|
| A trial-varying value that is balanced | `epsych.BlockSequence` | `hw.Parameter.isRandom` | `isRandom` redraws per dispatch: memoryless, integer-only, unbalanced over any finite session, and unrecoverable after a rewind. |
| To print anything | `vprintf` | `fprintf` | `fprintf` bypasses the verbosity gate and never reaches `.error_logs/`, which is the file that has to explain a failure afterwards. |
| The current log file | `eplog.Logger.instance().LogFile` | a rebuilt path | The directory is overridable per rig, and the file rotates daily. |
| Per-trial durability | `epsych.TrialJournal` | `save('-append')` | Append cost grows with file size (4.9 → 19.7 ms over 300 trials), and a crash mid-rewrite can lose the whole file rather than one record. |
| To know a trial finished | a listener on `RUNTIME.EVENTS` | a polling timer | Everything downstream of the runtime is event-driven; the timer callback is the only intended polling loop. |
| Session-level d′ and rates | `psychophysics.SessionMetrics` | `psychophysics.Detection` | `Detection` groups by unique stimulus value (a psychometric function); `SessionMetrics` collapses the session to the numbers on the status panel. |
| A window of trials | `psychophysics.TrialWindow` | index arithmetic | The window resolves against the analysis's own trial count, so it stays meaningful as the session grows. |
| To read a parameter beside a running session | `gui.ParameterDebugger` | `gui.components.Parameter_Monitor` | The debugger reads only on demand; the monitor polls, which is a cost you should choose deliberately. |
| To watch a parameter *change* | `gui.ParameterTracker` | pressing Read All repeatedly | Repeated reads give you the values but not when they arrived. The tracker stamps every sample with the clock, so a period the timer missed widens a gap instead of drifting the time axis. |
| A protocol's version | `epsych.Protocol.versionOnDisk` | `epsych.Protocol.load` | `load` rebuilds every interface, module, and parameter — far too expensive for a question asked once per subject per repaint. |
| A second view of a display | `gui.PopOut` | a new `figure` | A pop-out is a second instance with its own listeners and preferences, so closing or restyling it cannot disturb the embedded component. |
| To check a stimulus class is usable | `isConcreteStimType` | `ismember('stimgen.StimType', superclasses(…))` | `stimgen.StimType` is `Hidden`, so `superclasses` omits it and the test is false for every stimulus. |
| A phase file's parameters | `epsych.Runtime.phaseParameterData` | `epsych.Protocol.load` | The fast path reads the saved structs directly and is memoized; it falls back to `load` on its own when the shape is unfamiliar. |
| A pump the protocol drives | `hw.NE1000` | `peripherals.PumpCom` | `PumpCom` is a standalone controller outside the `hw` hierarchy — no protocol parameters, no trial dispatch. |
| A component destroyed with its GUI | `obj.register(comp)` | relying on the figure | Deleting a figure removes graphics only; a handle object's listeners and timers stay alive. |
| Confidence a session will run | `epsych.SelfTest` | a trial run | The self-test converts mid-session failures into pre-flight failures, each with a remedy. |

## Where the full reference lives

Everything here is a summary. The authoritative treatment of each subsystem is in [documentation/](../README.md): `epsych/` for the framework, `hw/` for backends and parameters, `gui/` for components, `psychophysics/` for analysis, `eplog/` for logging, `teensy/` for the program model, and the submodule's own documentation for stimulus generation. Each class's help text is the last word on its own arguments — `doc epsych.BlockSequence` and its neighbors are written to be read.
