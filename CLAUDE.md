# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**EPsych v2** is a MATLAB toolbox for designing and running behavioral experiments, with support for Tucker-Davis Technologies (TDT) hardware, electrophysiology recording, stimulus generation, and real-time analysis. The project combines legacy procedural code, GUIDE-era GUIs, and newer object-oriented runtime components—it is not a greenfield framework but an evolved, actively-used laboratory tool.

### Key Facts

- **Language**: MATLAB R2024b (supports R2014b+)
- **Available Toolboxes**: Audio, Curve Fitting, DSP System, Global Optimization, Image Acquisition, Image Processing, Optimization, Parallel Computing, Signal Processing, Statistics and Machine Learning
- **Architecture**: Mixed procedural/OOP with newer APIs in obj/+epsych/, obj/+hw/, obj/+stimgen/, obj/+gui/, obj/+psychophysics/
- **License**: GNU GPL v3.0
- **Author**: Daniel Stolzberg, PhD

## Quick Start Commands

### Setup

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

1. **Protocol Design**: User creates experiment via epsych.ProtocolDesigner GUI, defines hardware interfaces, parameters, and trial options, saves as .prot file
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
- **epsych.BitMask**: uint32 enumeration for trial outcomes
- **epsych.PRGMSTATE**: Session state enumeration

#### obj/+hw/ – Hardware Abstraction Layer
- **hw.Interface** (abstract base): Uniform API for all backends (connect, disconnect, get/set parameter, trigger)
- **hw.Module**: Parameter container
- **hw.Parameter**: Single parameter with validation and callbacks
- **Concrete Backends**:
  - hw.TDT_Synapse: TDT Synapse API backend
  - hw.TDT_RPcox: RPvds/RPco.x backend
  - hw.Intan_RHX: Intan RHX TCP interface
  - hw.Software: In-memory software backend
  - hw.VlcRecorder: VLC video recording control

#### obj/+stimgen/ – Stimulus Generation
- **stimgen.StimType** (abstract): Base for all stimuli
- **Stimulus Subclasses**: Tone, Noise, AMnoise, FMtone, SweptSine, ClickTrain
- **stimgen.StimPlayer**: Multi-stimulus manager
- **stimgen.StimCalibration**: Frequency response and SPL-to-voltage lookup

#### obj/+gui/ – Reusable GUI Components
- Real-time visualization: OnlinePlot, Performance, PsychPlot
- Session control: StaircaseTraining, StatusBar, Triggers
- Parameter control: Parameter_Control, Parameter_Monitor, Parameter_Update
- Utilities: ElapsedTrialTimer

#### obj/+psychophysics/ – Online & Offline Analysis
- **psychophysics.Psych** (abstract): Base for all analysis
- **psychophysics.Detection**: Hit rate, false alarm rate, d'
- **psychophysics.Staircase**: Reversal detection and threshold estimation
- **psychophysics.BestPEST**, **psychophysics.MLP**: Threshold-seeking algorithms

#### runtime/ – Execution Callbacks & Services
- **runtime/timerfcns/**: Timer lifecycle (Start, RunTime, Stop, Error)
- **runtime/savefcns/**: Data persistence
- **runtime/helpers/**: Per-trial logic
- **runtime/guis/**: Base GUI classes

#### TDTfun/ – Low-Level TDT Integration
- OpenDeveloper and RPco.x connection
- TDT device/tank metadata, tags, circuits
- TDT data file import (TDT2mat, SEV2mat)
- Synapse SDK

#### helpers/ – Shared Utilities
- **vprintf.m**: Verbosity-gated printing with automatic logging
- **EPsychInfo**: Version and git metadata
- **Trial sequence generators**: GellermannSeq, RandomTrialSequence, FellowsSeq
- **Analysis utilities**: dprime, shapedata_spikes, shapedata_wave
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
6. **Parameter Expressions**: Parameters can reference other parameters (e.g., Param.Prop or Module.Param.Prop)

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
  - Never add \n at end; vprintf adds it automatically
  - Examples: vprintf(0,1, 'Error: %s', msg); vprintf(2, 'Debug info')
  - Level -1 logs only; 0 = critical; 1 = info; 2 = debug; 3 = verbose
- vprintf automatically logs to .error_logs/ for debugging

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
Protocol and config files: .prot (protocol), .ecfg (config MAT files)

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

1. Create obj/+stimgen/YourStimulus.m inheriting from stimgen.StimType
2. Implement: IsMultiObj, CalibrationType, Normalization properties
3. Implement update_signal() to generate raw waveform
4. Define user-facing properties (e.g., Frequency, Depth)
5. Base class handles gating, normalization, calibration automatically
6. Test via stimgen.StimPlayer GUI

Reference: obj/+stimgen/Tone.m, obj/+stimgen/Noise.m

### Adding a New Online Analysis Tool

1. Create obj/+psychophysics/YourAnalyzer.m inheriting from psychophysics.Psych
2. Implement update(varargin) to process trial data
3. In epsych.RunExpt, wire listener via Runtime.HELPER.NewData event
4. Optional: Create GUI in obj/+gui/ to visualize results

Reference: obj/+psychophysics/@Detection/, obj/+gui/@OnlinePlot/

### Adding Experiment-Specific Behavior

1. Use cl/ directory as pattern for paradigm-specific code
2. Create custom GUIs and save functions
3. Subscribe to epsych.Helper events for trial and mode changes
4. Example: Custom epsych.TrialSelector for closed-loop

Reference: cl/cl_SaveDataFcn.m, design/ep_AddSubject.m

## Where to Look When Making Changes

- **Startup or runtime flow**: obj/+epsych/@RunExpt/, obj/+epsych/@Runtime/, runtime/timerfcns/
- **Protocol loading or compilation**: obj/+epsych/@Protocol/, obj/+epsych/@ProtocolDesigner/, design/
- **Hardware integration**: obj/+hw/@Interface/, concrete backends, TDTfun/
- **Stimulus generation**: obj/+stimgen/@StimType/, obj/+stimgen/@StimPlayer/
- **Online analysis**: obj/+psychophysics/Psych.m, obj/+gui/@OnlinePlot/
- **Session GUI**: obj/+epsych/@RunExpt/, obj/+gui/
- **New paradigm**: Use cl/ as pattern

## File & Folder Highlights

| Path | Purpose |
|------|---------|
| obj/+epsych/ | Experiment framework |
| obj/+hw/ | Hardware abstraction |
| obj/+stimgen/ | Stimulus generation |
| obj/+gui/ | GUI components |
| obj/+psychophysics/ | Analysis (Detection, Staircase, BestPEST, MLP) |
| obj/+peripherals/ | Motor control, pump communication |
| runtime/timerfcns/ | Timer callbacks |
| runtime/savefcns/ | Data saving |
| runtime/helpers/ | Per-trial helpers |
| TDTfun/ | Low-level TDT integration |
| design/ | Protocol design utilities |
| calibration/ | Calibration workflows |
| cl/ | Experiment-specific implementations |
| helpers/ | Shared utilities |
| documentation/ | User and developer docs |

## Important Git Practices

- Commit messages should reference the area changed
- Use feature branches for significant changes
- No force pushes to main/master without discussion
- Git hooks enforce clean history

## Documentation Resources

- **User setup**: documentation/overviews/Installation_Guide.md
- **Session walkthrough**: documentation/overviews/RunExpt_GUI_Overview.md
- **Runtime events**: documentation/epsych/Event_Notifications.md
- **Architecture**: documentation/overviews/Architecture_Overview.md
- **Class map**: documentation/overviews/Class_Map.md
- **Toolbox overview**: documentation/overviews/Toolbox_Overview.md
- **Full wiki**: https://github.com/dstolz/epsych2/wiki

## Repository Information

- **Latest commit**: EPsychInfo.commitTimestamp and EPsychInfo.chksum
- **Version**: EPsych v2, Data format v1.2
- **Author/Contact**: Daniel Stolzberg, PhD (daniel.stolzberg@gmail.com)
- **Repository**: https://github.com/dstolz/epsych2
