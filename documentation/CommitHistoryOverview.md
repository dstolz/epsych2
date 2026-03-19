# Commit History Overview

Period covered: 2019-05-14 through 2026-03-19

Only months with recorded commits are listed below.

## 2026

- March 2026, 178 commits. This was the largest modernization wave in the repository: RunExpt and related GUIs were pushed toward handle-based runtime state, recent-configuration support, richer version/history links, runtime filename updates, and cleaner parameter plumbing. Adaptive behavior expanded at the same time through randomizable response-window delays, stimulus-delay and pre-stimulus offset controls, ProgressiveTraining, and full Staircase training integration. Staircase itself saw repeated work on reversal detection, threshold estimation, plotting, BitMask-derived colors, and decibel conversion. Hardware support also broadened with VlcRecorder, multi-camera and frame-rate features, NanoMotorControl, and removal of deprecated webcam and figure-centric paths. Documentation and coding guidance accelerated sharply alongside the code changes.
- February 2026, 17 commits. Work centered on the new pellet-focused appetitive detection workflow: the GUI gained trial controls, sound settings, save-data dialogs, and better button and table presentation. Parameter_Monitor was introduced, Parameter gained trigger support, and trial-selection logic was refined for reminder trials, NO-GO handling, and false alarms.

## 2025

- December 2025, 34 commits. Stimulus-generation tooling became a major focus. The project added FMtone support, built StimGenInterface and StimGenInterface_Simple GUI flows, added serialization and structured save logic for stimulus objects, and improved stimulus-order logging. Calibration and signal plotting were revised repeatedly, with several commits explicitly noting that calibration still needed more work.
- November 2025, 27 commits. GUI operation and trial analysis were refined together. The appetitive GUI gained free-reward, manual-trial, and shape-trigger controls, sound-level editing, and more stable active-trial updates. In parallel, the repository added an interactive BitMask GUI, quick response-code/statistics recalculation, d-prime fixes, and stronger parameter-update and logging behavior.
- October 2025, 1 commit. A small cleanup pass improved performance-table formatting and readability.
- September 2025, 56 commits. This month introduced a major runtime architecture step through ep_RunExpt2, PRGMSTATE, and ModeChange events. File naming and save behavior were overhauled with FilenameValidator, DataFilename handling, and cl_SaveDataFcn. SlidingWindowPerformancePlot, BitMask-based trial typing, runtime diagnostics, and multiple GUI and performance cleanups all point to a strong shift toward explicit state management and cleaner experiment execution.
- August 2025, 4 commits. Follow-up cleanup focused on timer behavior, plotted-parameter reductions, and tightening ep_RunExpt guidance during the broader SynapseIntegration work.
- June 2025, 43 commits. Response-code handling was formalized around epsych.BitMask. Commits added enumerated BitMask support, response-code decoding, array processing, user-definable trial types, and Detect/trialIndex improvements, while also integrating SlidingWindowPerformancePlot into the GUI. This was the month where response classification and online performance analysis became much more systematic.
- May 2025, 12 commits. Early groundwork for later 2025 features landed here: verbosity controls, generalized Depth handling in trial selection, initial stimulus-detection and trial-decoding class work, and continued BitMask enumeration refinement.
- February 2025, 2 commits. A light maintenance month with small GUI and trial-selection information updates.
- January 2025, 17 commits. Hardware integration restarted in earnest. The repo added SynapseAPI-related work, moved TDT_RP functionality into TDTfun, combined pump controls, redirected test assets, updated test protocols, and began another round of plotting-performance and hardware-path cleanup.

## 2024

- December 2024, 8 commits. Parameter and GUI infrastructure was reorganized around a stronger Parameter and Parameter_Control model. The month added hardware-mode events and listeners, standardized parameter messaging, and moved Module behavior under Parameter, setting up the larger abstractions that followed.
- November 2024, 11 commits. The project made a clear turn toward hardware abstraction. Commits built a shell GUI compatible with the older workflow, improved hardware mode handling, added helper utilities, and pushed conversion work that was repeatedly marked as needing rig testing.

## 2023

- August 2023, 14 commits. Synapse integration became the dominant theme. The repository absorbed Melissa's Synapse code, added a Synapse prototype, started an object-oriented hardware interface, updated datetime handling, and made multiple small fixes while noting that much of the new path still needed testing.

## 2022

- September 2022, 5 commits. Work focused on RPvds-side utilities and trial buffering: AcqBuffer was added, useful RPvds macros were introduced, response-code updates were delayed until trial completion, and general buffer handling was adjusted.
- August 2022, 1 commit. MATLAB-controlled trials were updated so duration could be specified directly in samples.
- March 2022, 3 commits. Small fixes addressed WAV-file handling and buffer-structure edge cases.
- January 2022, 1 commit. Pump-rate return behavior was added or restored.

## 2021

- December 2021, 9 commits. Stimulus shaping and calibration details were refined, especially for click generation. The code added high-pass filtering, truncate-to-stimulus-length behavior, excitation-voltage support, and multiple revisions to time-vector and onset-delay handling.
- October 2021, 30 commits. Calibration infrastructure took shape rapidly. Commits built arbitrary-magnitude filters from calibration data, integrated calibration into stimgen.StimType, added save/load support, attached plotting listeners, and leaned on RPvds filtering. The repeated "needs testing" phrasing shows that this was an active build-out rather than a finished stabilization phase.
- September 2021, 24 commits. The stimulus-generation stack broadened around StimPlay, RPvds circuit control, calibration modules, buffer management, and early GUI work. Record buffers, double buffering, gating/windowing changes, and empty-protocol/trial-selection scaffolding all appeared during this month.
- August 2021, 25 commits. This was the first large stimgen month. The repo built out StimType classes, worked on stimgen GUI components, added AttackModNoise and audio playback, introduced envelope/ISI/repetition options, and made a series of runtime and GUI fixes to support the new stimulus path.
- January 2021, 3 commits. PumpCom was introduced and repository metadata/development-version information was updated.

## 2020

- December 2020, 5 commits. Control flow shifted incrementally from timer-driven behavior toward event triggers, while buffer data types were converted to single precision and low-value handling was corrected.
- November 2020, 2 commits. Trial timing was simplified so delay reset to zero before a trial started.
- October 2020, 5 commits. Runtime performance and buffering were tuned through finite-length buffers, display adjustments, and protocol metadata attached to runtime trials.
- September 2020, 21 commits. Psychophysics abstractions and online plotting expanded together. The code added new superclass work, a new psychophysics class, improved online plotting for multiple BitMask banks and Go/NoGo counts, introduced Fellows trial sequences, added a new RPvds BitMask macro, and tightened abort, inhibit, and trial-selection behavior.
- August 2020, 2 commits. README and startup/runtime behavior were lightly maintained, including buffer clearing and parameter-input ordering fixes.
- July 2020, 1 commit. Buffer clearing on startup was added, with a note that the change still needed real-world validation.
- February 2020, 8 commits. Early runtime and GUI mechanics were generalized: external trial-update control was added, activeTrials initialization was fixed, outputs were renamed, BusyMode was adjusted, and debug or user-specific code was trimmed back.

## 2019

- December 2019, 2 commits. Git-related error handling and small function cleanup improved robustness for users outside a git-managed checkout.
- November 2019, 1 commit. Root lookup was simplified by moving it from a private property to a static method.
- July 2019, 8 commits. Plotting and event behavior were refined through better timer configuration, corrected psych plot labeling and colors, relocated event broadcasts, Go/NoGo plot counters, and an added abort code.
- June 2019, 17 commits. The repository established the core Detection and Helper object model, event notifications for NewData and NewTrial, generic online plotting, GUI integration with psychophysics objects, new enumerations, and BitMask-backed response reporting. This month gave the project much of its early object and event structure.
- May 2019, 38 commits. The project was initially imported and rapidly shaped into an EPsych v1.1-style codebase. Core RPvds macros, design utilities, metadata/version-info features, parameter polling, common program-data access, calibration tooling, trial-history table fixes, compatibility updates, and early online-plot work all landed in quick succession.

## Overarching Trends

- The repository moved steadily from procedural and figure-centric workflows toward object-oriented, event-driven, and parameter-driven designs, especially in the GUI and runtime layers.
- Hardware support expanded in waves: RPvds infrastructure came first, then calibration-heavy stimulus support, then Synapse integration, and finally more general hardware abstractions and recorder/device-control classes.
- BitMask handling evolved from a supporting utility into a core representation for response decoding, trial classification, visualization, and GUI reporting.
- Adaptive training and online psychophysics became a central product direction over time, culminating in 2026 with ProgressiveTraining, Staircase training, richer response-window control, and better live performance displays.
- Documentation matured alongside the implementation. Early history is code-first and exploratory, while late 2025 and especially 2026 show deliberate efforts to document APIs, GUI patterns, coding conventions, and project history.
