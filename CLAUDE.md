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

#### Running MATLAB through the MCP server

The MathWorks `matlab-mcp-server` is registered for this project and is the preferred way to
lint and run code: it holds **one persistent MATLAB session**, so the engine starts once
(~7.5 s) instead of paying `matlab -batch`'s 20-60 s startup on every invocation. Tools:
`check_matlab_code` (Code Analyzer, read-only), `run_matlab_file`, `evaluate_matlab_code`,
`detect_matlab_toolboxes`, `run_matlab_test_file` (unused - there is no `matlab.unittest`
suite here). All tool arguments must be **absolute paths**.

`--initial-working-folder` is configured to the repo root but does **not** take effect - MATLAB
starts in whatever `userpath` is set to for the logged-in user (verified: `C:\Users\dstolz\My
Drive\temp_analysis` on this workstation, `C:\Users\caraslab\Documents\MATLAB` on the rig), the
same quirk that makes `-batch` ignore `-sd`. Never assume a relative path resolves or that the
fallback folder is the same on two machines: pass absolute `script_path`
values, and pass `project_path` to `evaluate_matlab_code` when the code needs the repo as cwd.
Repo scripts that bootstrap themselves off `mfilename` (as `tmp/smoke_test_*.m` do) are
unaffected.

Rules that matter:

- **One session is shared by every call, and concurrent calls interleave in it.** Two
  `run_matlab_file` calls issued together execute against the same base workspace. Run
  dependent checks one at a time.
- **Never `clear`, `close all`, or `delete(timerfindall)`** when the server is attached to a
  live session (`--matlab-session-mode=existing`) - it destroys running experiment state.
- **Restart the MATLAB session after any COM/ActiveX work.** MATLAB caches one COM wrapper
  class per CLSID per session, so an `actxcontrol` call poisons every later `actxserver` use
  of the same class. Each `-batch` exit used to reset that; a persistent session does not.
  This is the one hazard the persistent model adds.
- `actxcontrol` still hard-crashes MATLAB when there is no display, and the server runs
  `--matlab-display-mode=nodesktop`.
- `matlab -batch` remains the fallback when the server is unavailable, and is still required
  for `exportapp` GUI screenshot capture.

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
- **epsych.SubjectRoster**: shared, file-backed roster of subjects organized by
  project (many-to-many, with a per-project active/retired flag and per-membership
  protocol memory). Three flat arrays plus a join table in a `-mat` `.esub` file —
  MAT not JSON because `jsonencode(NaN)` would destroy the "not measured" `Weight`.
  A project also owns the **box GUI** its sessions launch (`BoxGUI`, applied to
  `RunExpt.FUNCS.BoxFig` by `assignToSession`): `''` inherits the session
  default, `BOXGUI_NONE` runs none, anything else is fevaled at run start. That
  field used to be Customize's "Box GUI Function" — a GUI belongs to a paradigm,
  not to a rig.
  A project also carries its own bookkeeping: `Investigator` and `IACUCProtocol`
  (recorded, never enforced), an `Archived` flag that hides the project from the
  manager's list without touching its subjects or their protocol memory, and
  `Links` — a `Label`/`URL` array for the study's notebook, sheet, or NAS folder.
  Link addresses go through `isSafeUrl`, which allows only `http`/`https`/
  `mailto`/`file` (plus local and UNC paths, normalized to `file:///`) and
  refuses everything else: a roster is a **shared** file, so `matlab:` in one
  would make an `.esub` executable on every rig that clicks it. Validation is on
  the way in only — `reload` deliberately does not validate, or one typo would
  make the roster unreadable for the lab — with `openLink` re-checking at the
  click. Adding a project field means `blankProject_` + `addProject` +
  `updateProject`'s field list (which coerces with `char(string(...))`, so a
  non-char field needs its own branch); `normalize_` handles old files, so
  **every default must mean what a file written before the field meant**.
  Roster records carry **no BoxID**: a box belongs to a session, so `toSubject`
  materializes an `epsych.Subject` at assignment time, which is why `epsych.Subject`
  needs no subclassing. Every mutation goes through `mutate_` (reload-if-stale →
  apply → atomic temp+`movefile` write), which is what lets two rigs share one file
  on a network drive. `assignToSession` is the batch commit into `RunExpt.CONFIG`,
  all-or-nothing on a bad protocol or box exhaustion. Renaming a subject is refused
  once `<DataPath>/<Name>/` exists, because nothing downstream knows about
  `NameHistory`.
  **Protocol versions**: a membership records `LastProtocolVersion` alongside the
  path, because `Protocol.save` overwrites an `.eprot` in place — the roster is the
  only thing that can notice a protocol edited between sessions. `protocolStatus`
  reports `current|outdated|differs|unknown|missing|none` (`outdated` = the file
  moved on; `differs` = not the project default), `updateProtocol` records the
  version now in the file, and `revertProtocol` restores an entry from
  `ProtocolHistory`. Revert restores the **pointer and version, never the bytes**
  of an overwritten file — `Recoverable` says which case it is, and revisions kept
  as separate files revert exactly. Version reads go through
  `epsych.Protocol.versionOnDisk`/`versionNumber`, shared with
  `RunExpt.UpdateSubjectList`; the two new fields are additive, so `FORMAT_VERSION`
  stays 1 (see documentation/epsych/epsych_SubjectRoster.md)
- **epsych.TrialJournal**: append-only, crash-safe `.epj` journal that per-trial data
  is written to during a run (flat ~2 ms, versus a `save('-append')` that grew to
  40 ms by trial 600). `ep_TimerFcn_Stop` merges it back into the seed `.mat`, so the
  recovery artifact keeps its `info + data_NNNN` layout; `TrialJournal.recover`
  rebuilds it after a crash. Durability is guarded by a hard-kill harness, not a
  throughput benchmark — run `tmp/crash_test_trialjournal.m` after any change to it
  (see documentation/epsych/epsych_TrialJournal.md)
- **Phase loading**: `Runtime.phaseParameterData` is the single chokepoint for reading a
  phase (.eprot) file. It reads the saved `hw.Parameter.toStruct` entries straight out of
  the MAT file — the file already holds exactly what it returns — and falls back to the
  full `epsych.Protocol.load` reconstruction whenever the shape is not recognized in full.
  Results are memoized by `Runtime.phaseCache` on path+mtime+size. Both are transparent:
  `FastParse=false`, `UseCache=false`, and `phaseCache('clear'|'disable')` restore the
  original behavior, and `tmp/smoke_test_phase_fastparse.m` is the standing equivalence proof
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
  - hw.NE1000: New Era NE-1000 syringe pump over RS-232 Basic-mode ASCII;
    drives the pump as a single-rate reward dispenser, not its Phase program.
    Its TTL Operational Trigger (pin 2) splits in two: the `TTLTrigger`
    enable is a parameter, a designer option, and an operator checkbox,
    while `TriggerMode` (default `LE`) is programmatic only — the mode
    follows the rig's wiring, not the operator. The configuration is
    asserted on every connect, since the pump remembers it through a power
    cycle (see documentation/hw/hw_NE1000.md) (under development)
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
Inside `obj/stimgen/` call `stimgen.util.vprintf`, never the bare `vprintf`.
It is bridged into this repository's logger at startup (see `stimbridge.LogBridge`
below), so those messages reach `.error_logs/` like everything else; without a
host it falls back to `fullfile(tempdir,'stimgen_error_logs')`.

#### obj/+stimbridge/ – EPsych ↔ stimgen Seam
- **stimbridge.RuntimeHost**: Implements `stimgen.HardwareHost` over epsych.Runtime/Protocol
- **stimbridge.InterfaceAdapter**: Implements `stimgen.calibration.HwAdapter` over hw.Interface
- **stimbridge.LogBridge**: Implements `stimgen.LogSink` over `eplog.Logger`, so stimgen's
  messages land in the session log attributed to their own call site. Installed by
  `epsych_startup`, guarded so a stimgen pinned before the seam still starts

All three contracts follow the same rule: a new method added to a `stimgen.*` abstract
class must be **concrete with a safe default**, or the `stimbridge` subclass becomes
unconstructable. `epsych.SelfTest` check A3 is the tripwire.

#### obj/+gui/ – Reusable GUI Components
- **gui.BoxGUI** (abstract): base class for custom experiment (BoxFig) GUIs — owns lifecycle, event listeners, position prefs, component-registry teardown, and Parameter_Update wiring; subclasses implement build(fig) (see documentation/gui/gui_BoxGUI.md, template in examples/customgui/)
- Real-time visualization: OnlinePlot, Performance, PsychPlot, ParameterScatter (generic X/Y/color parameter scatter for custom GUIs)
- **gui.SessionPerformance**: generic session summary panel (rates, counts, d'); computes through psychophysics.SessionMetrics and exposes the trial window both programmatically and on a right-click menu (documentation/gui/gui_SessionPerformance.md)
- **gui.NextTrial**: generic upcoming-trial display driven by NewTrial events
- **gui.SubjectManager**: the Subjects & Projects window, and the operator's only path to putting subjects in a session — the RunExpt `add_subject` toolbar button and the new Subjects menu (Ctrl+B) both open it. Projects are a `uilistbox`, subjects a `uitable` because each row carries its own box before commit; Protocol is read-only in the grid because `uitable`'s `ColumnFormat` is per-column, so a dropdown there could not offer per-row protocols. The project dialog is also where the **box GUI** is set (it moved here from Customize); its dropdown is fed by the box GUIs other projects in the roster use, not by the `RecentBoxFig` pref, so it works with no session open. All state lives in `epsych.SubjectRoster`; every callback ends in `refresh`. "New Subject..." routes through `RunExpt.dispatchAddSubjectFcn_` so a lab's custom `FUNCS.AddSubjectFcn` still applies. A **Version** column and a **Protocol** menu surface `SubjectRoster`'s version checking: the column shows the version each subject is *on* (bold orange when the file has been saved since), a collapsible banner over the table announces how many are behind and offers Update All, and right-click opens that row's protocol in `epsych.ProtocolDesigner`. "Update All in Project" deliberately covers retired and filtered-out members too. A project's **links** render under the summary as `uihyperlink`s whose `URL` is left EMPTY on purpose — the click routes through `SubjectRoster.openLink` so a stored address is re-checked before anything navigates, and a `file:` folder goes to the file manager rather than a browser. "Show archived projects" is the project-level counterpart of "Show retired", and the selected project is never hidden by it (documentation/gui/gui_SubjectManager.md)
- **gui.SyringePump**: operator panel for an `hw.NE1000` pump — dispensed-volume readout (4 Hz), COM port picker with auto-detect, syringe diameter, rate, infuse/withdraw, a TTL-trigger enable, and manual Start/Stop/Zero. Drives a protocol's pump, or one it constructs itself when the session has none, so the panel still opens with no hardware. Every part is individually hideable through `Sections`/`show`/`hide` or the right-click menu, and a hidden control still works (the menu can set it); operator-made changes — layout, port, units, values — persist by `PreferenceTag`, while programmatic ones do not. The value options carry no `arguments`-block defaults, which is what lets a saved configuration fill in for what the caller did not state. Rate and readout **units** are the operator's too, from the right-click Units menu (µL/mL per min/hr, mL/min by default): changing them converts `Rate` rather than reinterpreting it, puts the interface into the same units — so a protocol column that writes `Rate` means them as well — and is refused while the pump runs, because the pump rejects a units-bearing `RAT` mid-dispense and `hw.NE1000`'s bare-value fallback would land in the OLD units (`gui.BoxGUI.addSyringePump`; documentation/gui/gui_SyringePump.md)
- **gui.PopOut** (abstract mixin): adds the right-click "Open in Separate Window" item and the `popOut` method to a display component. A pop-out is a SECOND instance over the same data source with its own graphics, listeners, and preference key (`<hostTag>_<Class>_PopOut`), so it never disturbs the embedded one; adopters implement `createPopOut_` and `popOutHostContainer_`. Adopted by ParameterScatter, History, SessionPerformance, NextTrial, Parameter_Monitor, PsychPlot, and psychophysics.Staircase; `gui.BoxGUI.addPopOutButton` opens one from a button (documentation/gui/gui_PopOut.md)
- **gui.toolbarIcon**: the 16x16 glyphs for `uitoolbar` tools, drawn as pixel art
  (a string mask per row over a shared palette) so the toolbox ships no image
  files. `uitoolbar` does render in a `uifigure`, but `uibutton`/`uiimage` `Icon`
  accepts only four built-in names — `success`, `error`, `warning`, `info` — so
  every other glyph has to be drawn here or supplied as a file. Shared by
  `epsych.RunExpt` and `gui.SubjectManager`; a new tool adds a `case` to it
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
- **psychophysics.SessionMetrics**: Session-level counts, rates, d' and criterion over a
  `psychophysics.TrialWindow` (all trials, last N, first N, or an explicit range). The
  computation behind `gui.SessionPerformance`; also usable headlessly and offline
  (documentation/psychophysics/psychophysics_SessionMetrics.md)

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
  (console) and GLogVerbosity (error log, default Inf = log everything). It answers
  per destination — `isEnabled(level,'console'|'log'|'any')` — because the two are
  decoupled: a quiet command window no longer costs the record of what happened
- **eplog.Logger**: session singleton; builds one record per message and dispatches
  to its sinks. `instance()`, `emit`, `flush`, `addSink`, `LogFile`
- **eplog.sink.Console / TextFile / JsonLines**: destinations. Each applies its own
  level in `accepts(rec)` — the logger's gate only asks whether ANY destination
  wants the record. FileSink owns the daily .error_logs file — rotation, flush,
  handle recovery, failure latching
- **eplog.format / formatException**: message text policy; an exception (or a
  lasterror/timer-event struct) becomes ONE record at the catch site
- **eplog.callerFrame**: attributes a record to the code that logged it, by skipping
  logger frames by filename. Any new wrapper in the call chain must be added to its
  skip list or it silently claims every message routed through it
Nothing in the package throws: EPsych logs from inside catch blocks.
stimgen reaches this package through `stimbridge.LogBridge`, not by calling `vprintf`.
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
6. **Parameter Expressions**: Parameters can reference other parameters (e.g., Param.Prop or Module.Param.Prop). On `String`/`StimType` parameters the result is a 1-based index into `Values` instead of the value itself — `hw.Parameter.expressionSelectsIndex` is the single predicate that decides which meaning applies. A non-empty Expression is re-evaluated by `set.Value` on every dispatch, overriding the assigned value — so constants must live in `Values`, never as an Expression: the ProtocolDesigner converts literal-constant entries to fixed Values on edit and on load (see documentation/design/ProtocolDesigner.md, "Constants are values, not expressions")

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
- The console and the log have separate levels: GVerbosity gates the command window,
  GLogVerbosity gates the file and defaults to Inf, so EVERY message is logged
- Never rebuild the log path by hand. `eplog.Logger.instance().LogFile` names the
  current file; call `flush()` first if something is about to read or open it
- Guard only genuinely expensive log arguments with `visenabled(level)`; vprintf's
  own gate already makes a message no destination wants ~4 us. Note visenabled is
  true whenever the LOG wants the level, which by default is always

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
| obj/+stimbridge/ | EPsych-to-stimgen adapters (hardware host, calibration adapter, log bridge) |
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
