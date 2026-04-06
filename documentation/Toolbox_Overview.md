# EPsych Toolbox Overview

This document is a concise orientation guide for users who are new to EPsych and want to know which tools matter first.

## What EPsych provides

EPsych is a MATLAB toolbox for designing and running behavioral experiments, especially in TDT-based lab environments. In practice, the repository combines:

- protocol design tools
- a session runtime GUI
- hardware integration layers
- calibration utilities
- closed-loop task support
- general helper functions and support classes

The toolbox is broad, so the most useful way to approach it is by workflow rather than by folder.

## Start here

For most new users, the first three tools to learn are:

1. `epsych_startup`
   - Adds the repository and its visible subfolders to the MATLAB path.
   - Run this once after opening MATLAB.
2. `ep_ExperimentDesign`
   - Main protocol authoring GUI.
   - Use this to create or edit a `*.prot` experiment definition.
3. `epsych.RunExpt`
   - Main session GUI for loading subjects, selecting protocols, previewing trials, and running a session.

Typical first-run sequence:

```matlab
addpath('C:\path\to\epsych2')
epsych_startup
ep_ExperimentDesign
epsych.RunExpt
```

## Major tools by task

| Task | Main tool(s) | What they are for |
| --- | --- | --- |
| Set up MATLAB path | `epsych_startup`, `epsych_path` | Locate the toolbox and add EPsych folders to the MATLAB path. |
| Design a protocol | `ep_ExperimentDesign`, `ep_AddTrial`, `ep_struct2protocol` | Build or edit experiment structure and save it as a protocol file. |
| Compile or inspect protocols | `ep_CompileProtocol`, `ep_CompiledProtocolTrials` | Turn protocol definitions into runtime-ready trial structures and preview them. |
| Run an experiment | `epsych.RunExpt` | Configure subjects, associate protocol files, preview sessions, and run or record experiments. |
| Add subject/session metadata | `ep_AddSubject` | Collect subject information for a RunExpt session. Usually launched from the runtime GUI. |
| Calibrate outputs | `Calibrate`, `ep_CalibrationUtil`, `ep_PostCalibrationUtil` | Support hardware or stimulus calibration workflows before experiments are run. |
| Work with hardware backends | `obj/+hw/`, `TDTfun/` | Provide TDT-facing interfaces and lower-level hardware utilities used by runtime code. |
| Run closed-loop paradigms | `cl/` tools and GUIs | Task-specific closed-loop trial selection, GUIs, and saving behavior for specialized workflows. |
| Use common utilities | `helpers/` | Shared functions for logging, GUI support, timing, randomization, analysis helpers, and small utilities used across the toolbox. |

## What each major area means

### `design/`

This is the protocol-building side of EPsych. If you are deciding trial structure, parameter values, or protocol options, this is usually where you start.

Most important files for new users:

- `ep_ExperimentDesign.m`
- `ep_CompileProtocol.m`
- `ep_CompiledProtocolTrials.m`

### `obj/+epsych/`

This is the newer object-oriented EPsych runtime layer. The most important entry point here is `epsych.RunExpt`, which is the main GUI most users interact with during an experiment.

### `runtime/`

This folder contains the machinery used after a session starts, such as timer callbacks, save functions, helper routines, and runtime state updates. Most users do not start here, but this area matters when customizing behavior.

### `obj/+hw/` and `TDTfun/`

These folders handle hardware communication. If you need to understand how EPsych talks to TDT systems, or you are adapting EPsych to a specific hardware path, this is the relevant layer.

### `calibration/`

Use these tools when stimulus levels, speakers, or other outputs need to be calibrated before running experiments.

### `cl/`

This area contains specialized closed-loop experiment components. New users can ignore it initially unless they are working with an existing closed-loop paradigm.

### `helpers/`

This is a shared utility layer. It includes small functions and support classes used throughout the toolbox. It is useful once you begin extending or debugging EPsych internals.

## Recommended path for a new user

If you are trying to get productive quickly, use this order:

1. Read [Installation_Guide.md](Installation_Guide.md).
2. Run `epsych_startup` in MATLAB.
3. Open `ep_ExperimentDesign` and inspect or create a protocol.
4. Launch `epsych.RunExpt`.
5. Add a subject, attach a protocol, and use trial preview before running hardware.
6. Read [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md) once the GUI is open.

## Which document to read next

- For setup and prerequisites: [Installation_Guide.md](Installation_Guide.md)
- For running sessions: [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md)
- For runtime and analysis events: [Event_Notifications.md](Event_Notifications.md)
- For internals and code structure: [Architecture_Overview.md](Architecture_Overview.md)

## Short version

If you only remember one workflow, remember this:

- `epsych_startup` prepares MATLAB
- `ep_ExperimentDesign` prepares the protocol
- `epsych.RunExpt` runs the session

Everything else in the repository mainly supports one of those three stages.
