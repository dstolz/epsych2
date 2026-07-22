# EPsych Documentation

Documentation for the EPsych toolbox, organized by audience. Start with the guides section if you run experiments; start with the developer reference if you modify or extend the software.

## Guides for experimenters

Setup and orientation:

- [Installation Guide](overviews/Installation_Guide.md) — MATLAB, TDT software, and first-run validation
- [Toolbox Overview](overviews/Toolbox_Overview.md) — which tools matter first and how they fit together

Daily workflow:

- [Protocol Designer User Guide](design/ProtocolDesigner_UserGuide.md) — building and compiling protocols (`.eprot` files)
- [RunExpt GUI Overview](overviews/RunExpt_GUI_Overview.md) — configuring subjects and running sessions
- [Phase Selector](gui/PhaseSelector.md) — switching parameter sets between training stages
- [Staircase Training GUI](gui/StaircaseTraining.md) — step rules and bounds for progressive training

Stimuli and calibration:

- [Stimulus Generation Overview](../obj/stimgen/documentation/stimgen_overview.md) — stimulus objects, playback, and file types
- [StimPlayer](../obj/stimgen/documentation/stimgen_StimPlayer.md) — stimulus bank editor and player
- [Speaker Calibration](../obj/stimgen/documentation/stimgen_calibration.md) — concepts and step-by-step GUI walkthrough
- [Calibration GUI Reference](../obj/stimgen/documentation/stimgen_CalibrationGui.md)
- [Swept-Sine Calibration](../obj/stimgen/documentation/stimgen_SweptSineCalibration.md)

## Developer reference

Architecture:

- [Architecture Overview](overviews/Architecture_Overview.md) — repository map and core runtime flow
- [Class Map](overviews/Class_Map.md) — inheritance and runtime dependency views
- [Commit History Overview](overviews/CommitHistoryOverview.md) — how the codebase evolved

Experiment framework (`epsych`):

- [epsych.Protocol](epsych/epsych_Protocol.md) — protocol data model, compile, serialization
- [epsych.Runtime](epsych/epsych_Runtime.md) — session state, parameter queries, trial dispatch
- [Trial Lifecycle](epsych/epsych_TrialLifecycle.md) — a trial from dispatch to data save
- [epsych.TrialSelector](epsych/epsych_TrialSelector.md) — pluggable trial selection base class
- [Event Notifications](epsych/Event_Notifications.md) — `NewData` / `NewTrial` / `ModeChange` events
- [epsych.BitMask](epsych/epsych_BitMask.md) — response-code encoding and decoding
- [EPsychInfo](epsych/EPsychInfo.md) — version and repository metadata

Hardware layer (`hw`):

- [hw.Interface](hw/hw_Interface.md) — abstract backend contract and discovery helpers
- [hw.Interface Tutorial](hw/hw_Interface_Tutorial.md) — authoring a new hardware backend
- [hw.Module](hw/hw_Module.md) — parameter grouping and JSON serialization
- [hw.Parameter](hw/hw_Parameter.md) — parameter metadata, callbacks, expressions, per-trial dispatch flags
- [hw.Intan_RHX](hw/hw_Intan_RHX.md) — Intan RHX TCP backend
- [hw.VlcRecorder](hw/hw_VlcRecorder.md) — VLC webcam preview/recording backend

Utilities (`util`):

- [util.VideoConverter](util/VideoConverter.md) — batch video format conversion via tracked ffmpeg processes, with true per-file progress, parallelism, and a GUI

GUI components (`gui`):

- [gui.Parameter_Control](gui/Parameter_Control.md) — binding a parameter to a UI widget
- [gui.Parameter_Update](gui/Parameter_Update.md) — commit button for staged parameter edits
- [gui.History](gui/gui_History.md) — trial-by-trial history table
- [gui.VlcRecorderSetup](gui/VlcRecorderSetup.md) — webcam preview UI for configuring VlcRecorder device/fps/resolution/crop
- [gui.VideoConverterSetup](util/VideoConverter.md) — batch video conversion UI (see util.VideoConverter)
- [eval_staircase_training_mode](gui/eval_staircase_training_mode.md) — training-mode toggle callback

Analysis (`psychophysics`):

- [psychophysics.Psych](psychophysics/psychophysics_Psych.md) — analysis base class (online/offline)
- [psychophysics.Staircase](psychophysics/psychophysics_Staircase.md) — reversals and threshold estimation
- [psychophysics.BestPEST](psychophysics/psychophysics_BestPEST.md) — maximum-likelihood threshold tracking
- [psychophysics.MLP](psychophysics/psychophysics_MLP.md) — Bayesian psychometric estimation

Protocol design internals:

- [Protocol Designer (developer reference)](design/ProtocolDesigner.md)
- [Customized GUI Instructions](design/Customized_GUI_Instructions.md) — pattern for building task GUIs

Task-specific reference (`cl`):

- [cl_AppetitiveStimDetect](cl/cl_AppetitiveStimDetect.md) — appetitive detection trial selector
- [cl_SaveDataFcn](cl/cl_SaveDataFcn.md) — appetitive task save function

Peripherals and utilities:

- [peripherals.NanoMotorControl](peripherals/peripherals_NanoMotorControl.md) — commutator motor control
- [peripherals.PumpCom](peripherals/peripherals_PumpCom.md) — syringe pump serial interface
- [vprintf](helpers/helpers_vprintf.md) — verbosity-gated printing and logging
- [stimgen.StimType](../obj/stimgen/documentation/stimgen_StimType.md) — stimulus base class and variant selection
- [stimgen.StimPlay](../obj/stimgen/documentation/stimgen_StimPlay.md) — repetition/selection wrapper
- [stimgen.StimCalibration](../obj/stimgen/documentation/stimgen_StimCalibration.md) — calibration wrapper used by stimuli

## Other resources

- Repository landing page: [../README.md](../README.md)
- Project wiki: <https://github.com/dstolz/epsych2/wiki>
