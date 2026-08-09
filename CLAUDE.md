# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**EPsych v2** is a MATLAB toolbox for designing and running behavioral experiments, with support for Tucker-Davis Technologies (TDT) hardware, electrophysiology recording, stimulus generation, and real-time analysis. The project combines legacy procedural code, GUIDE-era GUIs, and newer object-oriented runtime components—it is not a greenfield framework but an evolved, actively-used laboratory tool.

### Key Facts

- **Language**: MATLAB R2024b (supports R2014b+)
- **Available Toolboxes**: Audio, Curve Fitting, DSP System, Global Optimization, Image Acquisition, Image Processing, Optimization, Parallel Computing, Signal Processing, Statistics and Machine Learning
- **Architecture**: Mixed procedural/OOP with newer APIs in obj/+epsych/, obj/+hw/, obj/+gui/, obj/+psychophysics/, and the obj/stimgen/ submodule
- **License**: GNU GPL v3.0
- **Author**: Daniel Stolzberg, PhD

## Quick Start Commands

### Setup

```bash
# Clone with submodules (stimgen lives in a separate repo)
git clone --recurse-submodules https://github.com/dstolz/epsych2.git
# For an existing clone:
git submodule update --init --recursive
```

```matlab
% Add repository to MATLAB path (run once after opening MATLAB)
addpath('C:\path\to\epsych2')
epsych_startup
```

### Main Entry Points

```matlab
% Main session GUI
epsych.RunExpt

% Protocol design GUI
epsych.ProtocolDesigner

% Stimulus player
stimgen.StimPlayer

% Speaker calibration GUI, wired to EPsych hardware via stimbridge
epsych.calibrate

% View repository information
E = EPsychInfo;
disp(E.meta)
```

### Testing & Validation
EPsych does not have a formal automated test suite. Manual validation is performed via:
- **Smoke tests** in 	mp/ directory (e.g., smoke_test_stimplayer_standalone.m)
- Protocol validation through epsych.Protocol.validate() method
- Trial preview via RunExpt GUI's "View Trials" button before running experiments

## Architecture & Key Components

### High-Level Flow: From Protocol to Runtime

1. **Protocol Design**: User creates experiment via epsych.ProtocolDesigner GUI, defines hardware interfaces, parameters, and trial options, saves as .eprot file
2. **Configuration**: epsych.RunExpt loads protocol, adds subjects, selects hardware backend
3. **Runtime Setup**: epsych.Runtime creates hardware connections, compiles trials, initializes event system
4. **Execution**: MATLAB timer fires callbacks: ep_TimerFcn_Start -> ep_TimerFcn_RunTime (repeated) -> ep_TimerFcn_Stop
5. **Data Saving**: Configurable save function persists session data

### Core Classes & Their Roles

#### obj/+epsych/ – Experiment Framework
- **epsych.RunExpt** (440 lines): Main session GUI; manages CONFIG (subject/protocol), RUNTIME state, and program transitions
- **epsych.Runtime** (120+ lines): Central state container; holds HW interfaces, TRIALS, HELPER (event broadcaster), and TIMER
- **epsych.Protocol** (212 lines): Data model for experiment; owns hw.Interface objects, parameters, compiled trials
- **epsych.ProtocolDesigner** (326 lines): GUI for building protocols (~57 UI callbacks)
- **epsych.Helper**: Lightweight event broadcaster (NewData, NewTrial, ModeChange)
- **epsych.TrialSelector** (abstract): Pluggable trial selection
- **epsych.SelfTest**: Headless pre-flight diagnostics for a RunExpt session (9 check groups); GUI in obj/+gui/@SelfTest/
- **epsych.BitMask**: uint32 enumeration for trial outcomes
- **PRGMSTATE** (top-level class in obj/PRGMSTATE.m): Session state enumeration

#### obj/+hw/ – Hardware Abstraction Layer
- **hw.Interface** (abstract base): Uniform API for all backends (connect, disconnect, get/set parameter, trigger)
- **hw.Module**: Parameter container
- **hw.Parameter**: Single parameter with validation and callbacks
- **Concrete Backends**:
  - hw.TDT_Synapse: TDT Synapse API backend (under development)
  - hw.TDT_RPcox: RPvds/RPco.x backend
  - hw.Intan_RHX: Intan RHX TCP interface (under development)
  - hw.Teensy: Teensy 4.x USB-serial backend; firmware in firmware/EPsychTeensy/ (under development)
  - hw.Bpod: Bpod 0.5/0.6 state machine over USB serial. Speaks the Arduino
    firmware's byte protocol directly and never loads c:\src\Bpod, whose
    RunStateMatrix blocks; see documentation/hw/hw_Bpod.md (under development)
  - hw.Software: In-memory software backend
  - hw.VlcRecorder: VLC video recording control

Adding a backend requires edits in four hardcoded registry sites outside the
class folder (`getAvailableInterfaceSpecs`, `getInterfaceEditState`,
`Protocol.toStruct`, `Protocol.createInterfaceFromStruct_`) — there is no
reflection. See documentation/hw/hw_Interface_Tutorial.md
and the `hw.Teensy` commit for the full list; omitting
`Protocol.createInterfaceFromStruct_` in particular fails silently, reloading
saved protocols as `hw.Software` stubs.

#### obj/stimgen/ – Stimulus Generation (GIT SUBMODULE)
Separate repository: [dstolz/stimgen](https://github.com/dstolz/stimgen) — package is at `obj/stimgen/+stimgen/`.
Edits here belong to that repo, not epsych2; commit there and update the submodule pointer.
- **stimgen.StimType** (abstract): Base for all stimuli
- **Stimulus Subclasses**: not listed here — the set changes with the submodule.
  Use `stimgen.StimType.list` or `obj/stimgen/documentation/stimgen_StimTypes.md`.
- **stimgen.StimPlayer**: Multi-stimulus manager
- **stimgen.StimCalibration**: Frequency response and SPL-to-voltage lookup
- **stimgen.HardwareHost** (abstract): Contract EPsych implements for hardware access

stimgen has NO dependency on epsych2. Never add `epsych.*` or `hw.*` references
inside `obj/stimgen/` — route them through the bridge below.

stimgen is pinned to an exact commit and released independently, so do not
duplicate its class inventory, signal-pipeline details, or per-class docs in this
repository; link to the submodule's own documentation instead. `epsych.SelfTest`
check A3 verifies the pinned commit still satisfies the stimbridge contract, and
`EPsychInfo.stimgenChksum` records that commit in saved session metadata.
stimgen logs through its own `stimgen.util.vprintf` to
`fullfile(tempdir,'stimgen_error_logs')`, not to this repository's `.error_logs/`.

#### obj/+stimbridge/ – EPsych ↔ stimgen Seam
- **stimbridge.RuntimeHost**: Implements `stimgen.HardwareHost` over epsych.Runtime/Protocol
- **stimbridge.InterfaceAdapter**: Implements `stimgen.calibration.HwAdapter` over hw.Interface

#### obj/+gui/ – Reusable GUI Components
- **gui.BoxGUI** (abstract): base class for custom experiment (BoxFig) GUIs — owns lifecycle, event listeners, position prefs, component-registry teardown, and Parameter_Update wiring; subclasses implement build(fig) (see documentation/gui/gui_BoxGUI.md, template in examples/customgui/)
- Real-time visualization: OnlinePlot, Performance, PsychPlot, ParameterScatter (generic X/Y/color parameter scatter for custom GUIs)
- Session control: StaircaseTraining, StatusBar, Triggers
- Diagnostics: SelfTest (window for epsych.SelfTest; opened from RunExpt's Help menu)
- Parameter control: Parameter_Control, Parameter_Monitor, Parameter_Update
- Utilities: ElapsedTrialTimer

#### obj/+teensy/ – Teensy Trial Programs
Design-time tooling that turns an operant paradigm into a state table the Teensy executes, so
the contingency lives in a file rather than in firmware. No dependency on the GUI layer, which
is what makes the whole feature testable headlessly.
- **teensy.Program**: the document — channels, variables, states, timers, counters. Handle class;
  renames cascade through every reference, including nested condition operands.
- **teensy.Channel / State / Transition / Condition / Action / Variable / BoardProfile**: value
  classes. Value semantics make toStruct/fromStruct an exact round trip, which is what makes the
  designer's undo exact.
- **teensy.Compiler**: emits the wire records documented in
  documentation/hw/hw_Teensy_Program_Protocol.md, and checks the program against the firmware's
  fixed array sizes.
- **teensy.Simulator**: reference implementation of the firmware's execution semantics. Powers
  the designer's test bench, the headless tests, and tells the firmware author what to build.
- **teensy.Templates**: ready-made paradigms (Go/No-Go, 2AFC, fixed ratio, shaping, passive).
- **teensy.TrialDesigner**: the GUI (documentation/teensy/teensy_TrialDesigner_UserGuide.md).

Any numeric field may hold a literal or an "@Name" reference to a teensy.Variable; a reference
compiles to a constant-table index, which is how a protocol varies a duration per trial without
re-uploading the state table.

#### obj/+psychophysics/ – Online & Offline Analysis
- **psychophysics.Psych** (abstract): Base for all analysis
- **psychophysics.Detection**: Hit rate, false alarm rate, d'
- **psychophysics.Staircase**: Reversal detection and threshold estimation
- **psychophysics.BestPEST**, **psychophysics.MLP**: Threshold-seeking algorithms

#### runtime/ – Execution Callbacks & Services
- **runtime/timerfcns/**: Timer lifecycle (Start, RunTime, Stop, Error)
- **runtime/savefcns/**: Data persistence
- **runtime/guis/**: Base GUI classes

#### TDTfun/ – Low-Level TDT Integration
- RPco.x connection (TDTRP) and RPvds tag reading (ReadRPvdsTags)
- Synapse SDK (SynapseAPI/)

#### obj/+eplog/ – Logging
The machinery behind vprintf; almost nothing should call it directly.
- **eplog.isEnabled**: the verbosity gate, and the only interpreter of GVerbosity
- **eplog.Logger**: session singleton; builds one record per message and dispatches
  to its sinks. `instance()`, `emit`, `flush`, `addSink`, `LogFile`
- **eplog.sink.Console / TextFile / JsonLines**: destinations. FileSink owns the
  daily .error_logs file — rotation, flush, handle recovery, failure latching
- **eplog.format / formatException**: message text policy; an exception (or a
  lasterror/timer-event struct) becomes ONE record at the catch site
Nothing in the package throws: EPsych logs from inside catch blocks.
See documentation/eplog/eplog_Logging.md.

#### helpers/ – Shared Utilities
- **vprintf.m**: Verbosity-gated printing and logging; a façade over obj/+eplog/
- **visenabled.m**: The gate alone, for guarding expensive log arguments
- **EPsychInfo**: Version and git metadata
- **Trial sequence generators**: randGellerman, RandomTrialSequence, FellowsSeq
- **GUI helpers**: findFigure, figAlwaysOnTop

### Event System & Runtime Communication

The epsych.Helper event broadcaster is the primary communication channel:
- **NewData**: Fired when a trial completes; listeners update results
- **NewTrial**: Fired when a new trial begins
- **ModeChange**: Fired when session mode changes

Subscribers (e.g., psychophysics.Psych subclasses, gui.OnlinePlot) listen to these events and update state.

### Program State Machine

NOCONFIG -> CONFIGLOADED -> READY -> RUNNING -> POSTRUN -> STOP

ERROR is reachable from any state.

### Key Design Patterns

1. **Heterogeneous Hardware Abstraction**: All backends inherit from hw.Interface with common API
2. **Event-Driven Analysis**: GUIs subscribe to epsych.Helper events rather than polling
3. **Configuration Persistence**: Session configs saved as .ecfg MAT files
4. **Auto-Discovery**: Backends auto-discover modules/parameters on connect via setup_interface()
5. **Pluggable Trial Selection**: epsych.TrialSelector is abstract and customizable
6. **Parameter Expressions**: Parameters can reference other parameters (e.g., Param.Prop or Module.Param.Prop). On `String`/`StimType` parameters the result is a 1-based index into `Values` instead of the value itself — `hw.Parameter.expressionSelectsIndex` is the single predicate that decides which meaning applies

## Coding Conventions & Standards

### From .github/copilot-instructions.md

**MATLAB Syntax**
- Target MATLAB R2024b (baseline R2014b+)
- Use arguments syntax for functions with >2 parameters or when validation needed
- Do NOT use compiler directives (e.g., %#ok<AGROW>)

**Naming**
- PascalCase for components, interfaces, type aliases
- camelCase for variables, functions, methods
- Suffix private class members with underscore (_)
- ALL_CAPS for constants

**Messaging & Logging**
- Use vprintf(level, msg, ...) for all formatted messages instead of fprintf
  - Never add \n at end; each record is its own line and a trailing newline is stripped
  - Examples: vprintf(0,1, 'Error: %s', msg); vprintf(2, 'Debug info')
  - Level -1 logs only; 0 = critical; 1 = info; 2 = debug; 3 = verbose; 4 = trace
- Format policy: **with** values the message is a printf format string; **with no**
  values it is literal text. Pass runtime-built strings (ME.message, file paths,
  tool output) as the whole message so '%' and backslashes survive
- vprintf is a façade over obj/+eplog/, which logs to .error_logs/
- Never rebuild the log path by hand. `eplog.Logger.instance().LogFile` names the
  current file; call `flush()` first if something is about to read or open it
- Guard only genuinely expensive log arguments with `visenabled(level)`; vprintf's
  own gate already makes a suppressed message ~1 us

**Error Handling**
- Use try/catch sparingly, only for expected errors
- Do NOT check isprop or isfield before accessing properties/fields
- Log caught exceptions with: catch ME; vprintf(0,1,ME); end

**Commenting**
- Concise comments explaining *why*, not *what*
- Function syntax first, then description, parameters, return values
- Class comments include purpose, properties, methods, minimal usage examples
- Avoid redundant comments

### File Organization

Class files: One class per directory with @ prefix

```text
obj/+packagename/@ClassName/
  ClassName.m          % Constructor and main methods
  methodName.m         % Separate method files (optional)
```

Procedural functions: Loose .m files in appropriate subdirectories
Protocol and config files: .eprot (protocol; legacy .prot still loadable), .ecfg (config MAT files)

## Common Development Tasks

### Adding a New Hardware Backend

1. Create obj/+hw/@YourBackend/YourBackend.m inheriting from hw.Interface
2. Implement: setup_interface(), close_interface(), connect(), get_parameter(), set_parameter(), trigger()
3. Implement dependent property IsConnected
4. Create hw.Module objects and populate with hw.Parameter objects
5. Implement static getCreationSpec() returning hw.InterfaceSpec
6. Test with epsych.Protocol.addInterface()

Reference: obj/+hw/@TDT_Synapse/, obj/+hw/@Software/

### Adding a New Stimulus Type

1. Create obj/stimgen/+stimgen/YourStimulus.m inheriting from stimgen.StimType
2. Implement: IsMultiObj, CalibrationType, Normalization properties
3. Implement update_signal() to generate raw waveform
4. Define user-facing properties (e.g., Frequency, Depth)
5. Base class handles gating, normalization, calibration automatically
6. Test via stimgen.StimPlayer GUI

Reference: obj/stimgen/+stimgen/Tone.m, obj/stimgen/+stimgen/Noise.m

### Adding a New Online Analysis Tool

1. Create obj/+psychophysics/YourAnalyzer.m inheriting from psychophysics.Psych
2. Implement update(varargin) to process trial data
3. In epsych.RunExpt, wire listener via Runtime.HELPER.NewData event
4. Optional: Create GUI in obj/+gui/ to visualize results

Reference: obj/+psychophysics/@Detection/, obj/+gui/@OnlinePlot/

### Adding Experiment-Specific Behavior

1. Use cl/ directory as pattern for paradigm-specific code
2. Custom GUIs: subclass gui.BoxGUI (copy examples/customgui/ExampleBoxGUI.m); the base provides lifecycle, listeners, and teardown — the subclass only writes build(fig) and event hooks
3. Create custom save functions
4. Subscribe to epsych.Helper events for trial and mode changes (BoxGUI subclasses get onNewTrial/onNewData/onModeChange hooks instead)
5. Example: Custom epsych.TrialSelector for closed-loop

Reference: examples/customgui/, runtime/guis/@ep_GenericGUI/, cl/cl_SaveDataFcn.m, obj/+epsych/@DefaultSubject/

## Where to Look When Making Changes

- **Startup or runtime flow**: obj/+epsych/@RunExpt/, obj/+epsych/@Runtime/, runtime/timerfcns/
- **Protocol loading or compilation**: obj/+epsych/@Protocol/, obj/+epsych/@ProtocolDesigner/, design/
- **Hardware integration**: obj/+hw/@Interface/, concrete backends, TDTfun/
- **Stimulus generation**: obj/stimgen/+stimgen/@StimType/, obj/stimgen/+stimgen/@StimPlayer/ (submodule)
- **Online analysis**: obj/+psychophysics/Psych.m, obj/+gui/@OnlinePlot/
- **Session GUI**: obj/+epsych/@RunExpt/, obj/+gui/
- **New paradigm**: Use cl/ as pattern

## File & Folder Highlights

| Path | Purpose |
|------|---------|
| obj/+epsych/ | Experiment framework |
| obj/+hw/ | Hardware abstraction |
| obj/stimgen/ | Stimulus generation (git submodule: dstolz/stimgen) |
| obj/+stimbridge/ | EPsych-to-stimgen adapters |
| examples/stimgen/ | Demo protocol/config/TDT circuit assets |
| obj/+gui/ | GUI components |
| obj/+teensy/ | Teensy trial programs: state-machine model, compiler, simulator, TrialDesigner GUI |
| obj/+eplog/ | Logging: verbosity gate, record dispatcher, console/file/JSON sinks |
| obj/+psychophysics/ | Analysis (Detection, Staircase, BestPEST, MLP) |
| obj/+peripherals/ | Motor control, pump communication |
| firmware/ | Microcontroller firmware (EPsychTeensy) |
| runtime/timerfcns/ | Timer callbacks |
| runtime/savefcns/ | Data saving |
| TDTfun/ | Low-level TDT integration |
| design/ | Protocol design utilities |
| cl/ | Experiment-specific implementations |
| helpers/ | Shared utilities |
| documentation/ | User and developer docs |

## Important Git Practices

- Commit messages should reference the area changed
- Use feature branches for significant changes
- No force pushes to main/master without discussion
- `obj/stimgen` is a submodule pinned to `main`. Changes there are committed in
  the stimgen repo; bumping the pointer here is a separate, deliberate commit.

## Documentation Resources

- **User setup**: documentation/overviews/Installation_Guide.md
- **Session walkthrough**: documentation/overviews/RunExpt_GUI_Overview.md
- **Pre-flight self-test**: documentation/overviews/RunExpt_SelfTest.md
- **Runtime events**: documentation/epsych/Event_Notifications.md
- **Logging**: documentation/eplog/eplog_Logging.md, documentation/helpers/helpers_vprintf.md
- **Architecture**: documentation/overviews/Architecture_Overview.md
- **Class map**: documentation/overviews/Class_Map.md
- **Toolbox overview**: documentation/overviews/Toolbox_Overview.md
- **Full wiki**: https://github.com/dstolz/epsych2/wiki

## Repository Information

- **Latest commit**: EPsychInfo.commitTimestamp and EPsychInfo.chksum
- **Version**: EPsych v2, Data format v1.2
- **Author/Contact**: Daniel Stolzberg, PhD (daniel.stolzberg@gmail.com)
- **Repository**: https://github.com/dstolz/epsych2
