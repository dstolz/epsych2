# EPsych Architecture Overview

This document is a high-level map of the EPsych repository for developers and advanced users who need to understand where functionality lives and how the major pieces relate to each other.

_Please note that I am actively working on improving the organizational structure and readability of the code._

## Design goals reflected in the codebase

EPsych is not a greenfield framework with a single centralized abstraction. It is an evolved toolbox that combines:

- legacy procedural MATLAB code
- GUIDE-era GUIs
- TDT ActiveX integration utilities
- newer object-oriented runtime components
- experiment-specific helper functions and utilities

That mixed structure is the key architectural fact to understand before making changes.

## Top-level layout

### `obj/+epsych/`

Newer object-oriented EPsych APIs and runtime entry points live here.

Important pieces include:

| Class | Purpose |
|---|---|
| `epsych.RunExpt` | Main session GUI and experiment controller |
| `epsych.Runtime` | Central runtime state container (`HW`, `TRIALS`, `TIMER`, `HELPER`) |
| `epsych.Protocol` | Protocol data model — holds interfaces, parameters, compiled trials |
| `epsych.ProtocolDesigner` | GUI for building and editing protocol files (~57 UI callback methods) |
| `epsych.Helper` | Event broadcaster (`NewData`, `NewTrial`, `ModeChange` events) |
| `epsych.BitMask` | `uint32` enumeration for encoding trial outcomes (Hit, Miss, CR, FA) |
| `epsych.TrialSelector` | Abstract base for pluggable trial selection strategies |
| `epsych.DefaultTrialSelector` | Concrete serial/random trial selector |
| `epsych.PumpCom` | Syringe pump communication |
| `epsych.PRGMSTATE` | Enumeration of program states (`NOCONFIG`, `READY`, `RUNNING`, etc.) |

### `obj/+hw/`

Hardware abstraction classes live here. All concrete interfaces inherit from `hw.Interface`, which defines a uniform API for connecting, reading, writing, and triggering.

| Class | Purpose |
|---|---|
| `hw.Interface` | Abstract base: `connect`, `disconnect`, `get_parameter`, `set_parameter`, `trigger` |
| `hw.Module` | Parameter container associated with a named hardware module |
| `hw.Parameter` | Single named parameter with value getter/setter and callback chain |
| `hw.TDT_Synapse` | TDT Synapse API backend; auto-discovers gizmo parameters on connect |
| `hw.TDT_RPcox` | RPvds/RPco.x backend; auto-discovers circuit tags on connect |
| `hw.Intan_RHX` | Intan RHX TCP backend |
| `hw.Software` | In-memory software backend for Matlab code parameters |
| `hw.VlcRecorder` | Controls a VLC process for video recording |
| `hw.DeviceState` | Enumeration of device states (`Idle`, `Preview`, `Record`, etc.) |

Hardware interfaces follow a lifecycle: **Offline → Connect → Runtime → Disconnect**. `setup_interface()` in each concrete class auto-discovers modules and parameters at connect time.

### `obj/+gui/`

Reusable GUI components live here. These are generally instantiated by `RunExpt` or experiment-specific workflows.

Key components include `gui.OnlinePlot`, `gui.Performance`, `gui.PsychPlot`, `gui.StaircaseTraining`, `gui.StatusBar`, `gui.Triggers`, and helpers such as `Parameter_Control`, `Parameter_Monitor`, and `Parameter_Update`.

### `obj/+stimgen/`

Stimulus generation and playback classes live here.

| Class | Purpose |
|---|---|
| `stimgen.StimType` | Abstract base; defines the signal processing pipeline |
| `stimgen.Tone` | Pure sine wave |
| `stimgen.Noise` | Band-limited Gaussian noise |
| `stimgen.AMnoise` | Amplitude-modulated noise |
| `stimgen.FMtone` | Frequency-modulated tone |
| `stimgen.ClickTrain` | Impulse train |
| `stimgen.SweptSine` | Logarithmic chirp |
| `stimgen.StimPlay` | Wraps `StimType` with repetition tracking and selection order |
| `stimgen.StimPlayer` | Multi-stimulus playback manager with UI, ISI control, and buffer writing |
| `stimgen.StimCalibration` | Calibration workflow and SPL-to-voltage lookup tables |

The signal processing pipeline applied by `StimType` on every update is:

```
update_signal()   ← implemented by each subclass
  → apply_gate()           cosine-squared onset/offset window
  → apply_normalization()  scale to [-1, 1]
  → apply_calibration()    SPL → voltage via lookup table and EQ filter
  → Signal property        final waveform
```

### `obj/+psychophysics/`

Online and offline analysis classes live here.

| Class | Purpose |
|---|---|
| `psychophysics.Psych` | Abstract base; can subscribe to `Runtime.HELPER.NewData` for online analysis |
| `psychophysics.Detection` | Hit rate, false alarm rate, d' (signal detection theory) |
| `psychophysics.Staircase` | Reversal detection and threshold estimation |

### `obj/+peripherals/`

Peripheral hardware interfaces (motor control, pump communication) that do not fit the core `hw` hierarchy live here.

### `design/`

Experiment and protocol authoring tools live here. This directory contains a mix of legacy GUIDE GUIs and support utilities.

Key files:

- `ep_ExperimentDesign.m` — Legacy protocol design GUI
- `ep_CompileProtocol.m` — Legacy protocol compilation (functionality now also in `epsych.Protocol.compile`)
- `ep_struct2protocol.m` — Convert struct to protocol format
- `prot2Protocol.m` — Migrate legacy protocol files to the new `epsych.Protocol` format
- `ep_BitmaskGen.m` — Bitmask definition editor

### `runtime/`

Runtime execution callbacks, timer lifecycle functions, save functions, and experiment services live here. This area activates once a session is running.

Subdirectory responsibilities:

| Path | Responsibility |
|---|---|
| `runtime/timerfcns/` | Timer lifecycle: `Start`, `RunTime`, `Stop`, `Error` callbacks |
| `runtime/savefcns/` | Data saving callbacks invoked at session end |
| `runtime/helpers/` | Per-trial helpers such as `SelectTrial` |
| `runtime/guis/` | Base GUI classes (`ep_GenericGUI`, `ep_GenericGUITimer`) |
| `runtime/ephys/` | Electrophysiology GUI (`ep_EPhys`) |
| `runtime/trial_selection/` | Standalone trial selection functions |

### `TDTfun/`

Low-level TDT integration utilities live here. This directory is a utility layer beneath the higher-level `hw` abstractions.

Responsibilities include:

- Connecting to OpenDeveloper and RPco.x interfaces
- Reading TDT device and tank metadata
- Working with tags, RPvds circuits, and TDT-specific file structures
- Importing TDT data files (`TDT2mat`, `SEV2mat`)

The `SynapseAPI/` subdirectory contains the Synapse SDK used by `hw.TDT_Synapse`.

### `helpers/`

General utilities and support classes used across the codebase live here.

Notable items:

- `vprintf.m` — Verbosity-gated formatted printing; used in place of `fprintf` throughout
- `EPsychInfo` class — Version and path information
- `dprime.m` — Signal detection d′ calculation
- `GellermannSeq.m`, `RandomTrialSequence.m`, `FellowsSeq.m` — Trial sequence generators
- `ParseVarargin.m` — Name-value pair parsing
- `shapedata_spikes.m`, `shapedata_wave.m` — Neural data processing utilities

### `calibration/`

Calibration GUIs and calibration-related workflows live here. This area matters when protocols or stimulus generation depend on calibrated hardware output levels. `stimgen.StimCalibration` (in `obj/+stimgen/`) provides the object-oriented calibration API; the tools here provide the measurement GUIs.

### `cl/`

Experiment-specific implementations for conditional learning paradigms live here (`cl_AppetitiveDetection_GUI_B`, `cl_AppetitiveStimDetect`). This is an example of paradigm-specific code that extends the core runtime without modifying it.

### `documentation/`

Human-facing documentation lives here, organized by subsystem under `documentation/<subsystem>/`. Developer-facing overviews live in `documentation/overviews/`.

---

## Core runtime flow

At a high level, a typical EPsych session looks like this:

1. A protocol is created or edited using `epsych.ProtocolDesigner` and saved as a `.prot` file.
2. `epsych.RunExpt` loads the session configuration and selected protocol.
3. `epsych.Runtime` is created to hold live session state (`HW`, `TRIALS`, `TIMER`, `HELPER`).
4. EPsych selects a hardware backend based on what is available and how the protocol is configured.
5. Each `hw.Interface` calls `setup_interface()` to auto-discover its modules and parameters.
6. A MATLAB timer is started; `ep_TimerFcn_Start` fires once, then `ep_TimerFcn_RunTime` fires on each tick.
7. Runtime helpers dispatch trials, update parameters, collect data, and respond to state changes via events on `epsych.Helper`.
8. The session stops, `ep_TimerFcn_Stop` fires, cleanup runs, and data is saved via the configured save function.

### Program state machine

Session state is tracked in `epsych.PRGMSTATE`:

```
ERROR ← NOCONFIG → CONFIGLOADED → READY → RUNNING → POSTRUN → STOP
```

### Timer callback chain

```
ep_TimerFcn_Start   → initialize hardware, select first trial
ep_TimerFcn_RunTime → check TrialComplete, dispatchNextTrial, log data
ep_TimerFcn_Stop    → cleanup, invoke save function
ep_TimerFcn_Error   → handle timer errors gracefully
```

---

## Hardware path selection

The codebase supports multiple hardware backends through a common `hw.Interface` API. The choice of backend is transparent to most of the runtime.

### TDT Synapse path

Used when TDT Synapse is running. The interface auto-discovers gizmo parameters via the Synapse API.

Relevant components:

- `hw.TDT_Synapse`
- `TDTfun/SynapseAPI/`
- `TDTfun/ReadSynapseTags.m`

### TDT RPvds path

Used when Synapse is not available. The interface connects directly to RPco.x and reads parameter tags from the RPvds circuit.

Relevant components:

- `hw.TDT_RPcox`
- `TDTRP`
- `TDTfun/TDT_SetupRP.m`
- `TDTfun/ReadRPvdsTags.m`

### Intan RHX path

Used for Intan-based electrophysiology recording. The interface communicates over TCP.

Relevant components:

- `hw.Intan_RHX`

### Software (testing) path

An in-memory backend that requires no physical hardware. Useful for development and testing.

Relevant components:

- `hw.Software`

The practical implication is that protocol metadata and runtime logic must remain compatible with whichever backend is active. Code that reads or writes parameters should always go through `hw.Interface` methods rather than calling backend-specific APIs directly.

---

## Protocol model

`epsych.Protocol` is the central data model for an experiment.

A protocol captures:

- `Interfaces` — list of `hw.Interface` objects (hardware connections)
- `Options` — trial selection strategy, connection type, save behavior
- Compiled trials — a table of all parameter combinations after `compile()` runs
- Subject metadata

The `epsych.ProtocolDesigner` GUI provides a full UI for building and editing protocols. The legacy `design/` utilities (`ep_CompileProtocol`, `ep_struct2protocol`, `prot2Protocol`) remain available for backward compatibility.

Several parts of the codebase depend on the protocol structure being stable. Changes to protocol fields or the compile output format tend to have wide impact.

---

## Stimulus generation model

`stimgen.StimType` is the abstract base for all stimuli. Subclasses implement `update_signal()` to produce a raw waveform; the base class then applies gating, normalization, and calibration automatically.

`stimgen.StimPlayer` manages a bank of stimuli, handles inter-stimulus intervals, writes buffers to hardware, and fires playback triggers. It is the primary interface between the stimulus generation layer and the hardware layer during runtime.

`stimgen.StimCalibration` stores frequency response data and provides `compute_adjusted_voltage()` for converting target SPL values to output voltages on a calibrated transducer.

---

## Psychophysics and analysis model

`psychophysics.Psych` and its subclasses can operate in two modes:

- **Online**: subscribes to `Runtime.HELPER.NewData` events and updates results trial-by-trial during a live session.
- **Offline**: accepts a saved data structure and computes results post-hoc.

`psychophysics.Detection` provides hit rate, false alarm rate, sensitivity, specificity, and d′. `psychophysics.Staircase` tracks reversal counts and estimates threshold.

---

## Practical guidance for contributors

### If you are changing experiment startup or runtime behavior

Look first at:

- [obj/+epsych/@RunExpt/RunExpt.m](../../obj/+epsych/@RunExpt/RunExpt.m)
- [obj/+epsych/@Runtime/Runtime.m](../../obj/+epsych/@Runtime/Runtime.m)
- [runtime/timerfcns/](../../runtime/timerfcns/)
- [runtime/helpers/](../../runtime/helpers/)

### If you are changing protocol loading or compilation

Look first at:

- [obj/+epsych/@ProtocolDesigner/ProtocolDesigner.m](../../obj/+epsych/@ProtocolDesigner/ProtocolDesigner.m)
- [obj/+epsych/@Protocol/Protocol.m](../../obj/+epsych/@Protocol/Protocol.m)
- [design/ep_CompileProtocol.m](../../design/ep_CompileProtocol.m)
- [design/ep_struct2protocol.m](../../design/ep_struct2protocol.m)

### If you are changing hardware integration

Look first at:

- [obj/+hw/@Interface/Interface.m](../../obj/+hw/@Interface/Interface.m)
- The concrete interface for your backend (`TDT_RPcox`, `TDT_Synapse`, `Intan_RHX`)
- [TDTfun/](../../TDTfun/)

### If you are changing stimulus generation

Look first at:

- [obj/+stimgen/@StimType/StimType.m](../../obj/+stimgen/@StimType/StimType.m)
- [obj/+stimgen/@StimPlayer/StimPlayer.m](../../obj/+stimgen/@StimPlayer/StimPlayer.m)
- [obj/+stimgen/@StimCalibration/StimCalibration.m](../../obj/+stimgen/@StimCalibration/StimCalibration.m)

### If you are changing online analysis or psychophysics

Look first at:

- [obj/+psychophysics/Psych.m](../../obj/+psychophysics/Psych.m)
- [obj/+gui/@OnlinePlot/OnlinePlot.m](../../obj/+gui/@OnlinePlot/OnlinePlot.m)
- [obj/+gui/@Performance/Performance.m](../../obj/+gui/@Performance/Performance.m)

### If you are changing session GUI behavior

Look first at:

- [obj/+epsych/@RunExpt/RunExpt.m](../../obj/+epsych/@RunExpt/RunExpt.m)
- [obj/+gui/](../../obj/+gui/)

### If you are adding a new paradigm

Use the `cl/` directory as a pattern. Create paradigm-specific GUIs and save functions that hook into the runtime event system (`epsych.Helper`) and the save function callback without modifying core runtime files.

---

## Documentation map

- User setup guide: [Installation_Guide.md](Installation_Guide.md)
- Session walkthrough: [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md)
- Runtime event reference: [../epsych/Event_Notifications.md](../epsych/Event_Notifications.md)
- Class and dependency maps: [Class_Map.md](Class_Map.md)
- General repository landing page: [../../README.md](../../README.md)

