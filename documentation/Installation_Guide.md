# EPsych Installation Guide

This document covers practical setup for running EPsych on a Windows MATLAB workstation with optional TDT hardware and webcam support.

## Overview

An EPsych installation has four layers:

1. MATLAB itself
2. The EPsych repository on the MATLAB path
3. TDT software components appropriate for your experiment
4. Optional toolbox or hardware dependencies such as camera capture

## Supported baseline

- MATLAB R2014b or newer
- Recommended MATLAB release: R2018b or later
- Historical development has been done on MATLAB 2024b

## Choose your experiment mode

Before installing TDT components, decide which path you actually need.

### Behavioral experiments without electrophysiology

Install:

- `TDT ActiveX Controls`

Typical use case:

- behavioral control with TDT-connected hardware but without an OpenEx electrophysiology pipeline

### Electrophysiology experiments with OpenEx

Install:

- `TDT OpenEx`
- `TDT OpenDeveloper Controls`

Typical use case:

- EPsych coordinates with an OpenEx experiment and interacts through the OpenDeveloper ActiveX interface

### RPvds-based workflows without OpenEx

You still need a working MATLAB-to-TDT ActiveX path so EPsych can talk to RPco.x devices and load RPvds circuits.

Typical use case:

- direct control of RPvds-based modules without a Synapse or OpenEx runtime in front of them

## Install EPsych

1. Clone or copy the repository to a stable local folder.
2. Open MATLAB.
3. Add the repository root to the MATLAB path.
4. Run the EPsych startup helper.

Example:

```matlab
addpath('C:\path\to\epsych2')
epsych_startup
```

What `epsych_startup` does:

- finds the repository root
- rebuilds the EPsych path entries
- adds visible subdirectories to the MATLAB path
- optionally prints the EPsych banner

## First-run validation

After installation, validate the MATLAB-side setup in this order.

### Step 1: confirm startup runs

Run:

```matlab
epsych_startup
```

Expected result:

- the path is configured without errors
- EPsych functions become discoverable in MATLAB

### Step 2: open the main runtime GUI

Run:

```matlab
epsych.RunExpt
```

Expected result:

- the main session window opens
- menus and buttons render correctly

If this works, EPsych itself is available in MATLAB even if hardware is not connected yet.

### Step 3: open the protocol designer

Open one of the design tools from MATLAB, for example:

```matlab
ep_ExperimentDesign
```

Expected result:

- the experiment design GUI opens
- you can create or inspect a protocol file

## Recommended setup sequence for a new lab machine

1. Install MATLAB and confirm it launches cleanly.
2. Install the TDT software required by your workflow.
3. Clone the EPsych repository.
4. Run `epsych_startup`.
5. Open `epsych.RunExpt`.
6. Open the protocol designer.
7. Only after the MATLAB-side flow is stable, connect and test TDT hardware.

This order matters because it separates MATLAB path problems from hardware or driver problems.

## Legacy installation notes

The repository still includes historical setup notes in `Notes_on_Installation.txt`.

Those notes are mainly relevant if:

- you are maintaining an older Windows MATLAB environment
- you need to rebuild older MEX components
- you are dealing with legacy dependencies such as Microsoft SDK 7.1

In modern setups, start with the normal MATLAB path configuration first and only fall back to those notes if a specific component fails.

## Common setup issues

### MATLAB cannot find EPsych functions

Likely causes:

- the repository root was not added to the MATLAB path
- `epsych_startup` was not run
- the repository was moved after path setup

What to do:

1. Add the repository root again with `addpath(...)`
2. Re-run `epsych_startup`
3. Verify `which epsych_startup` and `which epsych.RunExpt`

### The GUI opens, but hardware control does not work

Likely causes:

- missing TDT software components
- ActiveX registration or connectivity issues
- mismatch between experiment mode and installed TDT software

What to do:

1. Confirm whether your protocol expects OpenEx or a direct RPvds workflow
2. Confirm the required TDT software is installed
3. Test the TDT side independently before debugging EPsych runtime behavior

### Older MATLAB setup requires extra build tools

Likely cause:

- a legacy MEX dependency was never built for the local machine

What to do:

1. Review `Notes_on_Installation.txt`
2. Configure `mex -setup`
3. Build only the specific missing component rather than changing unrelated parts of the environment

## Next documents to read

- Runtime walkthrough: [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md)
- Architecture overview: [Architecture_Overview.md](Architecture_Overview.md)
