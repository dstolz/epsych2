# Commit History Overview

Period covered: 2026-01-01 through 2026-03-19

## Summary

- January 2026: no commits found.
- February 2026: 17 commits, centered on new GUI features, parameter monitoring, training controls, and trial-selection logic.
- March 2026: 168 commits, dominated by RunExpt/runtime refactoring, substantial Staircase work, recording and hardware integration, and extensive documentation updates.

## February 2026

- Added the pellet appetitive-detection GUI, including trial controls, sound settings, and a modal save-data workflow.
- Introduced parameter-monitoring support in the GUI, including a monitor table, total-pellet display, trigger handling, and richer Parameter_Control behavior.
- Added variable response-window delay support and training UI, then evolved that flow into ProgressiveTrainingGUI.
- Added an appetitive stimulus-detection trial-selection routine and refined NO-GO handling, false-alarm logic, depth constraints, and probability normalization.
- Improved GUI usability and presentation, including button styling, sound-level editors, and modal layout cleanup.

## March 2026

- Reworked the RunExpt/runtime architecture with a newer RunExpt flow, broader runtime-handle propagation, recent-configuration management, and runtime filename updates.
- Expanded adaptive timing and training behavior through response-window randomization, evaluator functions, stimulus-delay controls, pre-stimulus offset support, and staircase-training mode.
- Integrated Staircase behavior more deeply into GUI and trial execution.
- Overhauled Staircase internals with repeated fixes to reversal detection and threshold calculation, decibel conversion support, improved listeners/history handling, and major plot-management upgrades.
- Added recent Staircase visualization improvements, including BitMask-based color defaults, response-code color mapping, and context-menu plot interactions.
- Updated appetitive and aversive GUIs to use newer psychophysics objects and improved performance reporting, including clearer abort/performance metrics and layout cleanup.
- Added recording and hardware capabilities, including VlcRecorder, multi-camera VLC support with frame-rate control, and NanoMotorControl/NanoMotorControlGUI.
- Removed deprecated recording paths and older figure-based/runtime code, including the standalone WebcamRecorder path and obsolete GUI artifacts.
- Expanded documentation substantially across Staircase, BitMask, vprintf, RunExpt GUI behavior, custom GUI construction, Parameter classes, and related infrastructure.

## Major Themes

- Modernization of psychophysics workflows, especially adaptive Staircase analysis and training.
- Migration toward parameter-driven GUI behavior and clearer runtime state management.
- Stronger support for adaptive timing, randomized response windows, and training-specific interaction modes.
- Broader device integration for video recording and motor control.
- Ongoing cleanup of deprecated code paired with a large documentation push.