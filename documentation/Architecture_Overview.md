# EPsych Architecture Overview

This document is a high-level map of the EPsych repository for developers and advanced users who need to understand where functionality lives and how the major pieces relate to each other.

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

- `epsych.RunExpt`: the main session GUI/controller used to configure and run experiments
- `epsych.Runtime`: the central runtime state container used while a session is active
- additional object-oriented utilities that are gradually replacing older procedural flows

### `obj/+hw/`

Hardware abstraction classes live here.

Two important runtime paths are visible in the current code:

- `hw.TDT_Synapse`: interface for Synapse-backed workflows
- `hw.TDT_RPcox`: interface for RPvds/RPco.x-backed workflows

This separation matters because the same high-level EPsych session flow may initialize different hardware backends depending on what is available and how the protocol is configured.

### `design/`

Experiment and protocol authoring tools live here.

Key responsibilities:

- defining protocol structure
- configuring module aliases and hardware mappings
- setting options such as trial selection, connection type, and OpenEx usage
- compiling or preparing protocol definitions for runtime use

Examples:

- `ep_ExperimentDesign.m`
- `ep_CompileProtocol.m`
- `ep_struct2protocol.m`

### `runtime/`

Runtime execution helpers, callbacks, timer support, save functions, and experiment services live here.

This area is responsible for work that happens once a session is running, such as:

- timer-driven updates
- data collection helpers
- hardware initialization helpers
- runtime save and cleanup logic
- trial selection and per-trial bookkeeping

- `runtime/savefcns/`
- `runtime/timerfcns/`

### `TDTfun/`

Low-level or lower-level TDT integration utilities live here.

This directory contains helpers for:

- connecting to OpenDeveloper and RPco.x interfaces
- reading TDT device and tank metadata
- working with tags, RPvds circuits, and TDT-specific file structures

Think of this area as a utility layer beneath the higher-level runtime and hardware abstractions.

### `obj/+utils/` and `obj/+peripherals/`

General utilities and support classes now live in `obj/+utils/` (for general-purpose functions and classes) and `obj/+peripherals/` (for hardware-related helpers).

This includes:

- formatting and logging helpers such as `utils.vprintf`
- GUI helpers
- utility functions used across many parts of the codebase
- support classes such as recorder-related helpers

### `calibration/`

Calibration GUIs and calibration-related workflows live here.

This area matters when protocols or stimulus generation depend on calibrated hardware or output levels.

### `documentation/`

Human-facing documentation lives here.

Use this directory for:

- user walkthroughs
- focused feature notes
- developer-facing overviews such as this document

## Core runtime flow

At a high level, a typical EPsych session looks like this:

1. A protocol is created or edited in `design/` and saved as a `.prot` file.
2. `epsych.RunExpt` loads session configuration and selected protocols.
3. `epsych.Runtime` is created or reset to hold session state.
4. EPsych decides which hardware path to use.
5. Hardware is initialized through object-oriented wrappers and TDT utilities.
6. A MATLAB timer is started to drive runtime callbacks.
7. Runtime helpers update parameters, collect data, and respond to state changes.
8. The session stops, cleanup runs, and data is saved.

## Hardware path selection

The codebase currently reflects multiple hardware execution paths.

### OpenEx or Synapse-style path

In newer object-oriented runtime code, the session checks whether Synapse is running and may choose a Synapse-backed interface.

Relevant components:

- `hw.TDT_Synapse`
- OpenDeveloper-related helpers in `TDTfun/`

### Direct RPvds path

If Synapse is not in use, the runtime can initialize RPvds modules directly through the RPco.x path.

Relevant components:

- `hw.TDT_RPcox`
- `TDTRP`
- `TDT_SetupRP`

The practical implication is that protocol metadata and runtime assumptions must stay compatible with both higher-level experiment logic and the underlying hardware access path.

## Protocol model

Protocols are a central abstraction in EPsych.

In practice, a protocol captures:

- experiment modules and aliases
- parameter values and trial definitions
- runtime options such as connection type and OpenEx usage
- references to RPvds files or buffers
- trial selection and compile-time behavior

Several parts of the codebase depend on protocol structures being stable, so changes to protocol fields tend to have wide impact.

## Why the code feels mixed

There are two simultaneous modernization pressures visible in the repository:

1. preserve compatibility with older experiments, GUIs, and TDT workflows
2. move core behavior into more maintainable object-oriented code

As a result, a change that looks local may still have to preserve expectations from:

- older `.prot` files
- GUIDE-generated GUIs
- callback-by-name configuration patterns
- legacy ActiveX behavior

When editing the code, assume compatibility constraints are real unless verified otherwise.

## Practical guidance for contributors

### If you are changing experiment startup or runtime behavior

Look first at:

- `obj/+epsych/@RunExpt/`
- `obj/+epsych/Runtime.m`
- `runtime/timerfcns/`

### If you are changing protocol loading or compilation

Look first at:

- `design/ep_ExperimentDesign.m`
- `design/ep_CompileProtocol.m`
- `design/ep_struct2protocol.m`

### If you are changing hardware integration

Look first at:

- `obj/+hw/`
- `TDTfun/`
- any runtime helper that prepares DA or RP interfaces

### If you are changing session GUI behavior

Look first at:

- `obj/+epsych/@RunExpt/`
- any related helper GUIs in `design/` or previously in `helpers/` (now in `obj/+utils/`)

## Documentation map

- User setup guide: [Installation_Guide.md](Installation_Guide.md)
- Session walkthrough: [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md)
- General repository landing page: [../README.md](../README.md)
