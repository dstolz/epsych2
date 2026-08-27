# EPsych Documentation

Documentation for the EPsych toolbox, organized by audience. Start with the guides section if you run experiments; start with the developer reference if you modify or extend the software.

## Guides for experimenters

Setup and orientation:

- [Installation Guide](overviews/Installation_Guide.md) — MATLAB, TDT software, and first-run validation
- [Toolbox Overview](overviews/Toolbox_Overview.md) — which tools matter first and how they fit together

Worked example — a complete simulated detection task, from protocol design to
data analysis, runnable with no hardware
([examples/detection_task/](../examples/detection_task/)):

- [Detection Task Walkthrough](examples/Detection_Task_Walkthrough.md) — index and quick start
- [1 — Designing a protocol in code](examples/Detection_Task_1_Protocol.md) — conditions, pairing, expressions, triggers, compile/save
- [2 — Writing a custom trial selector](examples/Detection_Task_2_TrialSelector.md) — the `epsych.TrialSelector` contract and a Go/No-Go policy
- [3 — Building a behavior GUI](examples/Detection_Task_3_BehaviorGUI.md) — `gui.BehaviorGUI` hooks wired to live `psychophysics.Detection` analysis
- [4 — Running a session](examples/Detection_Task_4_Running.md) — the RunExpt path and the simulation driver, side by side
- [5 — Loading and analyzing saved data](examples/Detection_Task_5_Data.md) — session file layout, `epsych.BitMask` decoding, d', crash recovery

Daily workflow:

- [Protocol Designer User Guide](design/ProtocolDesigner_UserGuide.md) — building and compiling protocols (`.eprot` files)
- [Teensy Trial Designer](teensy/teensy_TrialDesigner_UserGuide.md) — building an operant paradigm as a state machine, testing it against a simulated subject, and uploading it to the board
- [RunExpt GUI Overview](overviews/RunExpt_GUI_Overview.md) — configuring subjects and running sessions
- [Subjects & Projects](gui/gui_SubjectManager.md) — organizing subjects by project and adding several to a session at once
- [Phase Selector](gui/PhaseSelector.md) — switching parameter sets between training stages
- [Staircase Training GUI](gui/StaircaseTraining.md) — step rules and bounds for progressive training
- [Parameter Debugger](gui/gui_ParameterDebugger.md) — reading and writing hardware parameters by hand when a paradigm misbehaves

Stimuli and calibration — these live in the `stimgen` submodule, which maintains
its own documentation set. Start at its index rather than at a link list here,
which would go stale every time the submodule is updated:

- [Stimulus Generation Overview](../obj/stimgen/documentation/stimgen_overview.md) — entry point for stimulus objects, playback, calibration, and file types
- [How EPsych integrates with stimgen](stimgen.md) — submodule contract and the `stimbridge` seam

## Developer reference

Architecture:

- [Architecture Overview](overviews/Architecture_Overview.md) — repository map and core runtime flow
- [Class Map](overviews/Class_Map.md) — inheritance and runtime dependency views
- [Programmer's Toolkit](overviews/Programmers_Toolkit.md) — catalog of the classes and functions worth knowing before writing your own, organized by task
- [Commit History Overview](overviews/CommitHistoryOverview.md) — how the codebase evolved

Experiment framework (`epsych`):

- [epsych.Protocol](epsych/epsych_Protocol.md) — protocol data model, compile, serialization
- [epsych.Runtime](epsych/epsych_Runtime.md) — session state, parameter queries, trial dispatch
- [Trial Lifecycle](epsych/epsych_TrialLifecycle.md) — a trial from dispatch to data save
- [epsych.TrialSelector](epsych/epsych_TrialSelector.md) — pluggable trial selection base class
- [epsych.BlockSequence](epsych/epsych_BlockSequence.md) — block-randomized per-trial values, indexed by the caller
- [epsych.SubjectRoster](epsych/epsych_SubjectRoster.md) — the shared subject/project roster, its file format, and the shared-file concurrency contract
- [Event Notifications](epsych/Event_Notifications.md) — `NewData` / `NewTrial` / `ModeChange` events
- [epsych.BitMask](epsych/epsych_BitMask.md) — response-code encoding and decoding
- [EPsychInfo](epsych/EPsychInfo.md) — version and repository metadata

Hardware layer (`hw`):

- [hw.Interface](hw/hw_Interface.md) — abstract backend contract and discovery helpers
- [hw.Interface Tutorial](hw/hw_Interface_Tutorial.md) — authoring a new hardware backend
- [hw.Module](hw/hw_Module.md) — parameter grouping and JSON serialization
- [hw.Parameter](hw/hw_Parameter.md) — parameter metadata, callbacks, expressions, per-trial dispatch flags
- [hw.Intan_RHX](hw/hw_Intan_RHX.md) — Intan RHX TCP backend (under development)
- [hw.VlcRecorder](hw/hw_VlcRecorder.md) — VLC webcam preview/recording backend
- [hw.Bpod](hw/hw_Bpod.md) — Bpod 0.5/0.6 state machine backend (under development)
- [hw.Teensy](hw/hw_Teensy.md) — Teensy 4.x USB-serial backend (under development)

Teensy trial programs (`teensy`) — building an operant paradigm as a state machine the board
executes, rather than as firmware:

- [Teensy Trial Designer user guide](teensy/teensy_TrialDesigner_UserGuide.md) — designing, simulating and uploading a paradigm
- [teensy program model](teensy/teensy_Program_Model.md) — the classes, validation, compiler and simulator
- [Teensy program wire protocol](hw/hw_Teensy_Program_Protocol.md) — the contract the firmware implements

Utilities (`util`):

- [util.VideoConverter](util/VideoConverter.md) — batch video format conversion via tracked ffmpeg processes, with true per-file progress, parallelism, and a GUI

GUI components (`gui`):

- [gui.components.Parameter_Control](gui/Parameter_Control.md) — binding a parameter to a UI widget
- [gui.components.Parameter_Update](gui/Parameter_Update.md) — commit button for staged parameter edits
- [gui.ParameterDebugger](gui/gui_ParameterDebugger.md) — read and write every parameter a protocol defines, on demand
- [gui.ParameterTracker](gui/gui_ParameterTracker.md) — plot scalar parameters against time, live
- [gui.components.History](gui/gui_History.md) — trial-by-trial history table
- [gui.SubjectManager](gui/gui_SubjectManager.md) — subjects by project, and the batch commit into a session
- [gui.BehaviorGUI](gui/gui_BehaviorGUI.md) — the base class a paradigm's own experiment GUI subclasses, and its component helpers
- [gui.BehaviorBuilder](gui/gui_BehaviorBuilder.md) — design-time builder that generates a `gui.BehaviorGUI` subclass from a protocol and a drag-and-drop layout
- [gui.components.ComponentToolbar](gui/gui_ComponentToolbar.md) — one toolbar opening each display in a window of its own, including displays the GUI does not host
- [gui.components.ScreenCapture](gui/gui_ScreenCapture.md) — camera button copying the whole window to the clipboard
- [gui.PopOut](gui/gui_PopOut.md) — the mixin that makes a display component poppable
- [gui.components.NextTrial](gui/gui_NextTrial.md) — upcoming-trial display driven by `NewTrial`
- [gui.components.SessionPerformance](gui/gui_SessionPerformance.md) — session summary: rates, counts, d'
- [gui.components.SyringePump](gui/gui_SyringePump.md) — operator panel for an `hw.NE1000` reward pump
- [gui.VlcRecorderSetup](gui/VlcRecorderSetup.md) — webcam preview UI for configuring VlcRecorder device/fps/resolution/crop
- [gui.VideoConverterSetup](util/VideoConverter.md) — batch video conversion UI (see util.VideoConverter)
- [eval_staircase_training_mode](gui/eval_staircase_training_mode.md) — training-mode toggle callback

Analysis (`psychophysics`):

- [psychophysics.Metrics](psychophysics/psychophysics_Metrics.md) — stateless signal-detection arithmetic (d', criterion, A', B'', and the corrections for rates of 0 and 1)
- [psychophysics.Psych](psychophysics/psychophysics_Psych.md) — analysis base class (online/offline)
- [psychophysics.SessionMetrics](psychophysics/psychophysics_SessionMetrics.md) — session counts, rates and sensitivity over a trial window
- [psychophysics.NAFC](psychophysics/psychophysics_NAFC.md) — N-alternative forced choice: choice functions, confusion matrix, choice bias
- [psychophysics.Staircase](psychophysics/psychophysics_Staircase.md) — reversals and threshold estimation
- [psychophysics.BestPEST](psychophysics/psychophysics_BestPEST.md) — maximum-likelihood threshold tracking
- [psychophysics.MLP](psychophysics/psychophysics_MLP.md) — Bayesian psychometric estimation
- [A' (nonparametric sensitivity)](psychophysics/psychophysics_APrime.md) — distribution-free companion to d'

Protocol design internals:

- [Protocol Designer (developer reference)](design/ProtocolDesigner.md)
- [Customized GUI Instructions](design/Customized_GUI_Instructions.md) — pattern for building task GUIs

Task-specific reference (`cl`):

- [cl_AppetitiveStimDetect](paradigms/cl_AppetitiveStimDetect.md) — appetitive detection trial selector
- [cl_SaveDataFcn](paradigms/cl_SaveDataFcn.md) — appetitive task save function

Peripherals and utilities:

- [peripherals.NanoMotorControl](peripherals/peripherals_NanoMotorControl.md) — commutator motor control
- [peripherals.PumpCom](peripherals/peripherals_PumpCom.md) — syringe pump serial interface
- [vprintf](helpers/helpers_vprintf.md) — verbosity-gated printing and logging, the API all EPsych code uses
- [granary](granary/granary_Logging.md) — the logger behind `vprintf`: levels, format policy, sinks, log file lifecycle
- [stimgen developer docs](../obj/stimgen/documentation/) — `StimType`, `StimPlay`, `StimCalibration`, and the calibration engine, maintained in the submodule

## Other resources

- Repository landing page: [../README.md](../README.md)
- Project wiki: <https://github.com/dstolz/epsych2/wiki>
