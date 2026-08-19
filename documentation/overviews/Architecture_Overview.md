# EPsych Architecture Overview

This document is a high-level map of the EPsych repository for developers who need to understand where functionality lives and how the major pieces relate to each other. If you only want to run experiments, read [Toolbox_Overview.md](Toolbox_Overview.md) instead.

## Design goals reflected in the codebase

EPsych is not a greenfield framework with a single centralized abstraction. It is a working laboratory toolbox that combines:

- object-oriented runtime, hardware, and GUI components
- procedural MATLAB code and figure-based GUIs
- TDT ActiveX integration utilities
- experiment-specific helper functions and utilities

That mixed structure is the key architectural fact to understand before making changes.

> 🔑 **The OOP layer is the extension surface; the procedural layer is load-bearing.** `hw.Interface`, `epsych.TrialSelector`, `psychophysics.Psych`, and `gui.BehaviorGUI` are where new work belongs. A new paradigm should reach the runtime through events rather than by editing `runtime/timerfcns/`.

## Top-level layout

### `obj/+epsych/`

Newer object-oriented EPsych APIs and runtime entry points live here.

| Class | Purpose |
|---|---|
| `epsych.RunExpt` | Main session GUI and experiment controller |
| `epsych.Runtime` | Central runtime state container (`Interfaces`, `TRIALS`, `TRIGGERS`, `TIMER`, `EVENTS`) |
| `epsych.Protocol` | Protocol data model — owns `hw.Interface` objects, parameters, compiled trials; serialized to `.eprot` files |
| `epsych.ProtocolDesigner` | GUI for building and editing protocol files |
| `epsych.EventHub` | Event broadcaster (`NewData`, `NewTrial`, `ModeChange` events) |
| `epsych.BitMask` | `uint32` enumeration for encoding trial outcomes (Hit, Miss, CR, FA, ...) |
| `epsych.TrialSelector` | Abstract base for pluggable trial selection strategies |
| `epsych.DefaultTrialSelector` | Built-in balancing selector (least-used trial, random tie-break) |
| `epsych.Subject` / `epsych.DefaultSubject` | Abstract subject definition and default implementation with a built-in entry dialog |
| `epsych.TrialsData` | Event payload for `NewData` / `NewTrial` |
| `epsych.eventModeChange` | Event payload for `ModeChange` |

`PRGMSTATE` (the session state enumeration) is a top-level class in `obj/PRGMSTATE.m`, not part of the `epsych` package.

Detailed references: [../epsych/](../epsych/)

### `obj/+hw/`

Hardware abstraction classes live here. All concrete interfaces inherit from `hw.Interface`, which defines a uniform API for connecting, reading, writing, and triggering.

| Class | Purpose |
|---|---|
| `hw.Interface` | Abstract base: `connect`, `get_parameter`, `set_parameter`, `trigger`, parameter discovery helpers |
| `hw.Module` | Parameter container associated with a named hardware module |
| `hw.Parameter` | Single named parameter with value getter/setter, bounds, expressions, and callback chain |
| `hw.TDT_Synapse` | TDT Synapse API backend; auto-discovers gizmo parameters on connect (under development) |
| `hw.TDT_RPcox` | RPvds/RPco.x backend; auto-discovers circuit tags on connect |
| `hw.Intan_RHX` | Intan RHX TCP backend (under development) |
| `hw.Software` | In-memory software backend for MATLAB-side parameters |
| `hw.VlcRecorder` | Controls a VLC process for webcam preview/recording |
| `hw.DeviceState` | Enumeration of device states (`Idle`, `Preview`, `Record`, ...) |
| `hw.InterfaceSpec` / `hw.InterfaceSpecOption` | Creation specs that let `ProtocolDesigner` build interface-creation dialogs generically |

Each concrete backend implements `setup_interface()` to auto-discover its modules and parameters, and a static `getCreationSpec()` so the Protocol Designer can construct it from user input.

Detailed references: [../hw/](../hw/)

### `obj/+gui/`

Reusable GUI components live here. These are generally instantiated by `RunExpt`, task GUIs, or experiment-specific workflows.

Key components: `gui.OnlinePlot`, `gui.Performance`, `gui.PsychPlot`, `gui.SlidingWindowPerformancePlot`, `gui.History`, `gui.StaircaseTraining`, `gui.PhaseSelector` (JSON parameter phase switching), `gui.ModeIndicator`, `gui.StatusBar`, `gui.Triggers`, `gui.ElapsedTrialTimer`, `gui.FilenameValidator`, `gui.BasicGUI`, parameter widgets `Parameter_Control`, `Parameter_Monitor`, `Parameter_Update`, and the standalone `gui.ParameterDebugger` window (every protocol parameter, read and written on demand).

Detailed references: [../gui/](../gui/)

### `obj/stimgen/` (submodule)

Stimulus generation, playback, and calibration. This is a **git submodule**
pointing at <https://github.com/dstolz/stimgen>; the package itself is at
`obj/stimgen/+stimgen/`. Run `git submodule update --init --recursive` after
cloning. See [stimgen.md](../stimgen.md) for the integration contract.

`stimgen` has no dependency on EPsych. EPsych implements its two abstract
integration classes in `obj/+stimbridge/` (see below).

> ⚠️ **Nothing inside `obj/stimgen/` may name an EPsych type.** The package must stay usable standalone, so every `epsych.*` / `hw.*` reference belongs in `obj/+stimbridge/`. Edits under `obj/stimgen/` are commits in the *stimgen* repository; bumping the pointer here is separate and deliberate.

| Class | Purpose |
|---|---|
| `stimgen.StimType` | Abstract base; defines the signal processing pipeline and variant (vectorized property) selection |
| `stimgen.StimPlay` | Wraps a `StimType` with repetition tracking and selection order |
| `stimgen.StimPlayer` | Standalone stimulus-bank editor and playback tool |
| `stimgen.StimCalibration` | Headless calibration wrapper held by `StimType`; the GUI is `stimgen.calibration.CalibrationGui` |
| `stimgen.calibration.*` | Calibration package: `Engine` (core algorithm), `CalibrationGui`, and hardware adapters (`HwAdapter`, `WindowsSoundCardAdapter`) |
| `stimgen.HardwareHost` | Abstract contract EPsych implements to give stimgen GUIs hardware access |

The concrete stimulus classes are deliberately not listed here — the set changes
with the submodule, independently of this repository. `stimgen` maintains its own
index at [../../obj/stimgen/documentation/stimgen_StimTypes.md](../../obj/stimgen/documentation/stimgen_StimTypes.md),
and `stimgen.StimType.list` enumerates whatever the pinned commit provides.

### `obj/+stimbridge/`

The seam between EPsych and the `stimgen` submodule. These are the only classes
that translate between the two; nothing inside `stimgen` names an EPsych type.

| Class | Purpose |
|---|---|
| `stimbridge.RuntimeHost` | Implements `stimgen.HardwareHost` over `epsych.Runtime`/`epsych.Protocol`: protocol loading, connect/release, device mode, parameter lookup, and calibration-adapter selection |
| `stimbridge.InterfaceAdapter` | Implements `stimgen.calibration.HwAdapter` over an `hw.Interface` (TDT and similar), resolving the buffer/trigger tags used for play-and-record |

The signal processing pipeline applied by `StimType` on every update is:

```
update_signal()   ← implemented by each subclass
  → apply_normalization()  scale to [-1, 1]
  → apply_calibration()    SPL → voltage via lookup table and EQ filter
  → apply_gate()           cosine-squared onset/offset window
  → Signal property        final waveform
```

Calibration precedes gating because `apply_calibration` renormalizes before
scaling to the lookup-table voltage, which would undo an earlier ramp. This order
is owned by `stimgen`; treat its documentation as authoritative.

Detailed references: [../../obj/stimgen/documentation/stimgen_overview.md](../../obj/stimgen/documentation/stimgen_overview.md)

### `obj/+psychophysics/`

Online and offline analysis classes live here.

| Class | Purpose |
|---|---|
| `psychophysics.Psych` | Abstract base; subscribes to `Runtime.EVENTS.NewData` for online analysis or accepts saved DATA offline |
| `psychophysics.Detection` | Hit rate, false alarm rate, d' (signal detection theory) |
| `psychophysics.Staircase` | Reversal detection and threshold estimation |
| `psychophysics.BestPEST` | Maximum-likelihood threshold tracking (Best PEST) |
| `psychophysics.MLP` | Bayesian maximum-likelihood psychometric estimation with sweet-point placement |

Detailed references: [../psychophysics/](../psychophysics/)

### `obj/+peripherals/`

Peripheral hardware interfaces that do not fit the core `hw` hierarchy: `peripherals.PumpCom` (syringe pump), `peripherals.NanoMotorControl` and `peripherals.NanoMotorControlGUI` (motorized commutator).

Detailed references: [../peripherals/](../peripherals/)

### `obj/+eplog/`

The logger behind `vprintf`. `eplog.isEnabled` gates on two globals — `GVerbosity` for the command window, `GLogVerbosity` (default `Inf`, everything) for the error log — and each sink applies the one for its own destination, so quieting the console never quiets the log. `eplog.Logger` builds one record per message and dispatches it to its sinks (`eplog.sink.Console`, `eplog.sink.TextFile`, and the opt-in `eplog.sink.JsonLines`). It owns the daily `.error_logs` file: rotation, flushing, handle recovery, and failure latching. Nothing in the package throws, because EPsych logs from inside `catch` blocks.

Almost all code should call `vprintf` rather than this package directly. Detailed reference: [../eplog/eplog_Logging.md](../eplog/eplog_Logging.md)

### `runtime/`

Runtime execution callbacks, timer lifecycle functions, save functions, and experiment services live here. This area activates once a session is running.

| Path | Responsibility |
|---|---|
| `runtime/timerfcns/` | Timer lifecycle: `ep_TimerFcn_Start`, `ep_TimerFcn_RunTime`, `ep_TimerFcn_Stop`, `ep_TimerFcn_Error` |
| `runtime/savefcns/` | Data saving callbacks (`ep_SaveDataFcn`) invoked at session end |
| `runtime/guis/` | Base GUI classes (`ep_GenericGUI`) |

### `TDTfun/`

Low-level TDT integration utilities live here. This directory is a utility layer beneath the higher-level `hw` abstractions.

Contents:

- `TDTRP.m` — RPco.x connection wrapper used by `hw.TDT_RPcox`
- `ReadRPvdsTags.m` — RPvds circuit parameter-tag reader
- `SynapseAPI/` — the Synapse SDK used by `hw.TDT_Synapse`

### `helpers/`

General utilities and support classes used across the codebase live here.

Notable items:

- `vprintf.m` — verbosity-gated formatted printing with automatic logging; used in place of `fprintf` throughout ([../helpers/helpers_vprintf.md](../helpers/helpers_vprintf.md)). A façade over the `eplog` package ([../eplog/eplog_Logging.md](../eplog/eplog_Logging.md)), which owns formatting, the daily log file and its destinations
- `visenabled.m` — the verbosity gate on its own, for guarding log arguments that are expensive to build
- `EPsychInfo` class — version and git metadata ([../epsych/EPsychInfo.md](../epsych/EPsychInfo.md))
- `randGellerman.m`, `RandomTrialSequence.m`, `FellowsSeq.m` — trial sequence generators
- `findFigure.m`, `showGridBorders.m` — GUI helpers

### `paradigms/`

Experiment-specific implementations for the appetitive detection paradigm (`cl_AppetitiveDetection_GUI_B`, `cl_AppetitiveStimDetect`, `cl_SaveDataFcn`). This is the reference example for paradigm-specific code that extends the core runtime without modifying it. See [../paradigms/](../paradigms/).

### `documentation/`

Human-facing documentation lives here, organized by subsystem under `documentation/<subsystem>/`. The index is [../README.md](../README.md).

---

## Core runtime flow

At a high level, a typical EPsych session looks like this:

1. A protocol is created or edited using `epsych.ProtocolDesigner` and saved as an `.eprot` file.
2. `epsych.RunExpt` loads the session configuration (subjects + protocols).
3. On Run/Preview, protocols are validated and compiled, and a fresh `epsych.Runtime` is created.
4. The hardware interfaces owned by the protocol are connected (`Runtime.Interfaces` setter) and remain connected across reruns within the session.
5. A MATLAB timer starts; `ep_TimerFcn_Start` fires once to build `RUNTIME.TRIALS`, resolve the required trigger parameters (`TRIGGERS`), and dispatch the first trial; then `ep_TimerFcn_RunTime` fires on each tick.
6. Each tick polls the `TrialComplete` trigger; when a trial completes, data is collected and appended to the crash-recovery file, the trial selector picks the next trial, and `Runtime.dispatchNextTrial` writes parameters and fires hardware triggers.
7. GUIs and analysis objects react to `NewTrial` / `NewData` / `ModeChange` events on `RUNTIME.EVENTS` rather than polling.
8. On Stop, `ep_TimerFcn_Stop` returns hardware to Idle and data is saved via the configured save function.

> 🔑 **Everything downstream of the runtime is event-driven, not polled.** GUIs and analysis objects subscribe to `NewTrial` / `NewData` / `ModeChange` on `RUNTIME.EVENTS`. The only real polling loop is the timer callback itself.

For the full trial-level walkthrough, see [../epsych/epsych_TrialLifecycle.md](../epsych/epsych_TrialLifecycle.md).

### Program state machine

Session state is tracked with the top-level `PRGMSTATE` enumeration:

```
ERROR ← NOCONFIG → CONFIGLOADED → READY → RUNNING → POSTRUN → STOP
```

### Timer callback chain

```
ep_TimerFcn_Start   → build TRIALS, create selectors, resolve required triggers, dispatch first trial
ep_TimerFcn_RunTime → poll TrialComplete, save data, select next trial, dispatchNextTrial
ep_TimerFcn_Stop    → set interfaces Idle, broadcast ModeChange, tear down EVENTS
ep_TimerFcn_Error   → handle timer errors, preserve data
```

The callback names are configurable per session (RunExpt **Customize** dialog), so paradigms can substitute their own timer functions.

---

## Hardware path selection

The codebase supports multiple hardware backends through a common `hw.Interface` API. Which backends are used is defined in the protocol: `epsych.Protocol.Interfaces` holds the configured `hw.Interface` objects, and `epsych.Runtime` connects them at run start. The choice of backend is transparent to most of the runtime.

| Backend | Use case | Key support code | Status |
|---|---|---|---|
| `hw.TDT_Synapse` | TDT Synapse experiments | `TDTfun/SynapseAPI/` | under development |
| `hw.TDT_RPcox` | Direct RPvds circuit control | `TDTRP`, `TDTfun/` | — |
| `hw.Intan_RHX` | Intan RHX electrophysiology over TCP | — | under development |
| `hw.Software` | In-memory parameters; design-time store and hardware-free testing | — | — |
| `hw.VlcRecorder` | Webcam preview/recording via VLC | — | — |

Code that reads or writes parameters should always go through `hw.Interface` / `hw.Parameter` methods (or the `Runtime.find_parameter` / `Runtime.all_parameters` helpers) rather than calling backend-specific APIs directly.

> ⚠️ **Never call a backend-specific API directly.** Every read and write goes through `hw.Interface` / `hw.Parameter` (or the `Runtime.find_parameter` / `Runtime.all_parameters` helpers) — that indirection is exactly what makes the backend choice transparent to the rest of the runtime.

---

## Protocol model

`epsych.Protocol` is the central data model for an experiment.

A protocol captures:

- `Interfaces` — the `hw.Interface` objects (always at least one `hw.Software` design-time parameter store)
- `Options` — trial selector class (`trialFunc`), `compileAtRuntime`, `IncludeWAVBuffers`, `ConnectionType`
- `COMPILED` — the compiled trial table (`parameters`, `trials`, `writeparams`, `ntrials`) produced by `compile()`
- `meta` — format version, EPsych version, and a `protocolVersion` string incremented on each save (used by RunExpt to flag out-of-date subjects)

Parameters carry design-time trial levels in `hw.Parameter.Values`; `compile()` expands the cross-product of unpaired parameter levels (paired parameters advance together) into the trials matrix. Several parts of the codebase depend on the compiled structure being stable — changes to protocol fields or the compile output format have wide impact.

> ⚠️ **`COMPILED`'s field set and column order are a repository-wide contract.** The timer functions, the parameter widgets, the mid-session recompile path, and paradigm code all map names to columns through it. Changing its shape is a breaking change, not a refactor.

See [../epsych/epsych_Protocol.md](../epsych/epsych_Protocol.md).

---

## Psychophysics and analysis model

`psychophysics.Psych` and its subclasses operate in two modes:

- **Online**: construct with a `Runtime`; the object subscribes to `EVENTS.NewData` and updates results trial-by-trial.
- **Offline**: construct with a saved per-trial `DATA` struct array to compute results post-hoc.

See [../psychophysics/psychophysics_Psych.md](../psychophysics/psychophysics_Psych.md).

---

## Practical guidance for contributors

### If you are changing experiment startup or runtime behavior

Look first at:

- [obj/+epsych/@RunExpt/RunExpt.m](../../obj/+epsych/@RunExpt/RunExpt.m) (especially `ExptDispatch.m`)
- [obj/+epsych/@Runtime/Runtime.m](../../obj/+epsych/@Runtime/Runtime.m)
- [runtime/timerfcns/](../../runtime/timerfcns/)

### If you are changing protocol loading or compilation

Look first at:

- [obj/+epsych/@Protocol/Protocol.m](../../obj/+epsych/@Protocol/Protocol.m) (`compile_internal.m`, `validate_internal.m`, `toStruct.m`/`fromStruct.m`)
- [obj/+epsych/@ProtocolDesigner/ProtocolDesigner.m](../../obj/+epsych/@ProtocolDesigner/ProtocolDesigner.m)

### If you are changing hardware integration

Look first at:

- [obj/+hw/@Interface/Interface.m](../../obj/+hw/@Interface/Interface.m)
- The concrete interface for your backend (`TDT_RPcox`, `TDT_Synapse`, `Intan_RHX`, `VlcRecorder`)
- [TDTfun/](../../TDTfun/)
- Tutorial: [../hw/hw_Interface_Tutorial.md](../hw/hw_Interface_Tutorial.md)

### If you are changing stimulus generation

Look first at:

Stimulus generation lives in the `stimgen` submodule, so changes there are
committed to <https://github.com/dstolz/stimgen> and picked up here by updating
the submodule pointer:

- [obj/stimgen/+stimgen/@StimType/StimType.m](../../obj/stimgen/+stimgen/@StimType/StimType.m)
- [obj/stimgen/+stimgen/@StimPlayer/StimPlayer.m](../../obj/stimgen/+stimgen/@StimPlayer/StimPlayer.m)
- [obj/stimgen/+stimgen/+calibration/](../../obj/stimgen/+stimgen/+calibration/)
- EPsych-side integration: [obj/+stimbridge/](../../obj/+stimbridge/)

### If you are changing online analysis or psychophysics

Look first at:

- [obj/+psychophysics/Psych.m](../../obj/+psychophysics/Psych.m)
- [obj/+gui/@OnlinePlot/OnlinePlot.m](../../obj/+gui/@OnlinePlot/OnlinePlot.m)
- [obj/+gui/@Performance/Performance.m](../../obj/+gui/@Performance/Performance.m)

### If you are changing session GUI behavior

Look first at:

- [obj/+epsych/@RunExpt/RunExpt.m](../../obj/+epsych/@RunExpt/RunExpt.m) (`buildUI.m`, `UpdateGUIstate.m`)
- [obj/+gui/](../../obj/+gui/)

### If you are adding a new paradigm

Use the `paradigms/` directory as a pattern. Create paradigm-specific GUIs, trial selectors, and save functions that hook into the runtime event system (`epsych.EventHub`) and the save-function callback without modifying core runtime files. See [../design/Customized_GUI_Instructions.md](../design/Customized_GUI_Instructions.md).

---

## Documentation map

- Documentation index: [../README.md](../README.md)
- User setup guide: [Installation_Guide.md](Installation_Guide.md)
- Session walkthrough: [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md)
- Trial lifecycle: [../epsych/epsych_TrialLifecycle.md](../epsych/epsych_TrialLifecycle.md)
- Runtime event reference: [../epsych/Event_Notifications.md](../epsych/Event_Notifications.md)
- Class and dependency maps: [Class_Map.md](Class_Map.md)
- General repository landing page: [../../README.md](../../README.md)
