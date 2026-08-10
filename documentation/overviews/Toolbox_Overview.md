# EPsych Toolbox Overview

This document is a concise orientation guide for users who are new to EPsych and want to know which tools matter first. It is written for people who run experiments; if you plan to modify or extend the software itself, read [Architecture_Overview.md](Architecture_Overview.md) instead.

## What EPsych provides

EPsych is a MATLAB toolbox for designing and running behavioral experiments, especially in TDT-based lab environments. In practice, the repository combines:

- protocol design tools
- a session runtime GUI
- hardware integration layers
- stimulus generation and calibration utilities
- closed-loop task support
- general helper functions and support classes

The toolbox is broad, so the most useful way to approach it is by workflow rather than by folder.

## Start here

For most new users, the first three tools to learn are:

1. `epsych_startup`
   - Adds the repository and its visible subfolders to the MATLAB path.
   - Run this once after opening MATLAB.
2. `epsych.ProtocolDesigner`
   - Main protocol authoring GUI.
   - Use this to create or edit protocol (`.eprot`) files.
   - See [../design/ProtocolDesigner_UserGuide.md](../design/ProtocolDesigner_UserGuide.md).
3. `epsych.RunExpt`
   - Main session GUI for loading subjects, selecting protocols, previewing trials, and running a session.
   - See [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md).

Typical first-run sequence:

```matlab
addpath('C:\path\to\epsych2')
epsych_startup
epsych.ProtocolDesigner
epsych.RunExpt
```

## Major tools by task

| Task | Main tool(s) | What they are for |
| --- | --- | --- |
| Set up MATLAB path | `epsych_startup` | Locate the toolbox and add EPsych folders to the MATLAB path. |
| Design a protocol | `epsych.ProtocolDesigner` | Build or edit experiment structure, parameters, and options, then save it as an `.eprot` protocol file. |
| Compile or inspect protocols | ProtocolDesigner's **Compile Protocol** / **Compiled Preview** | Turn protocol definitions into runtime-ready trial lists and preview them before running. |
| Run an experiment | `epsych.RunExpt` | Configure subjects, associate protocol files, preview trials, and run or record experiments. |
| Add subject/session metadata | **Add Subject** button in RunExpt | Collect subject information for a session. Uses a built-in dialog by default; labs can substitute their own. |
| Preview or play stimuli | `stimgen.StimPlayer` | Build a bank of stimuli, preview them through the speakers, and optionally play them through hardware. |
| Calibrate sound output | `epsych.calibrate` (or RunExpt's **Utilities > Calibration GUI...**) | Open the stimgen calibration GUI already wired to EPsych hardware; measure and save speaker calibration so requested dB SPL levels map to correct output voltages. See [../../obj/stimgen/documentation/stimgen_calibration.md](../../obj/stimgen/documentation/stimgen_calibration.md). |
| Adjust parameters between sessions | Phase files and the phase selector in task GUIs | Save and reload named parameter sets (JSON) so training phases can be switched without editing the protocol. |
| Use common utilities | `helpers/` | Shared functions for logging, GUI support, timing, randomization, and analysis used across the toolbox. |

## What each major area means

### Protocol design (`epsych.ProtocolDesigner`)

This is the protocol-building side of EPsych. If you are deciding trial structure, parameter values, or protocol options, this is where you start. Protocols are saved as `.eprot` files that `epsych.RunExpt` loads at session time.

### Session control (`epsych.RunExpt`)

The main GUI most users interact with during an experiment. It manages subjects, protocols, and session state, and starts and stops the experiment. Saved session configurations use `.ecfg` files so a full setup can be reloaded in one step.

### Stimulus tools (`stimgen`)

Stimulus objects (tones, noise, clicks, and more), a stimulus bank player, and speaker calibration tools. Most users will only need `stimgen.StimPlayer` and the calibration GUI. See [../../obj/stimgen/documentation/stimgen_overview.md](../../obj/stimgen/documentation/stimgen_overview.md).

`stimgen` is a separate repository ([dstolz/stimgen](https://github.com/dstolz/stimgen)) attached here as a git submodule at `obj/stimgen/`. Clone with `--recurse-submodules`, or run `git submodule update --init --recursive` in an existing clone. See [../stimgen.md](../stimgen.md).

### Hardware layers (`obj/+hw/` and `TDTfun/`)

These folders handle hardware communication (TDT Synapse, TDT RPvds, Intan RHX, Teensy, Bpod, webcam recording, and a software-only test backend). As a user you normally do not touch this layer directly — the protocol file records which hardware your experiment uses. The TDT Synapse, Intan RHX, Teensy, and Bpod backends are under development.

### Task-specific code (`cl/`)

Contains specialized experiment implementations, such as the appetitive detection task, with their own GUIs and trial selection logic. New users can ignore it unless they are running one of these paradigms.

### Utilities (`helpers/`)

A shared utility layer of small functions and support classes used throughout the toolbox. It becomes relevant once you begin extending or debugging EPsych.

## Recommended path for a new user

If you are trying to get productive quickly, use this order:

1. Read [Installation_Guide.md](Installation_Guide.md).
2. Run `epsych_startup` in MATLAB.
3. Open `epsych.ProtocolDesigner` and inspect or create a protocol.
4. Launch `epsych.RunExpt`.
5. Add a subject, attach a protocol, and use **View Trials** to preview trials before running hardware.
6. Read [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md) once the GUI is open.

## Which document to read next

- For setup and prerequisites: [Installation_Guide.md](Installation_Guide.md)
- For running sessions: [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md)
- For designing protocols: [../design/ProtocolDesigner_UserGuide.md](../design/ProtocolDesigner_UserGuide.md)
- For stimulus generation and calibration: [../../obj/stimgen/documentation/stimgen_overview.md](../../obj/stimgen/documentation/stimgen_overview.md)
- For internals and code structure (developers): [Architecture_Overview.md](Architecture_Overview.md)

## Short version

If you only remember one workflow, remember this:

- `epsych_startup` prepares MATLAB
- `epsych.ProtocolDesigner` prepares the protocol
- `epsych.RunExpt` runs the session

Everything else in the repository mainly supports one of those three stages.
