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
- Current development is done on MATLAB R2024b

## Choose your experiment mode

Before installing TDT components, decide which path you actually need.

> 🔑 **Choose the experiment mode before installing anything from TDT.** Behavioral-only rigs need TDT ActiveX Controls; OpenEx workflows need TDT OpenEx *plus* OpenDeveloper Controls. Installing the wrong set is the usual cause of "the GUI opens but hardware control does not work". With no TDT hardware, skip this section entirely.

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

1. Clone the repository **with submodules** to a stable local folder.
2. Clone **`granary`**, the logging package, beside it.
3. Open MATLAB.
4. Add the repository root to the MATLAB path.
5. Run the EPsych startup helper.

EPsych depends on two other repositories, and they are attached differently.
[`stimgen`](https://github.com/dstolz/stimgen), the stimulus-generation package,
is a git submodule at `obj/stimgen/`, so the clone must include it:

```bash
git clone --recurse-submodules https://github.com/dstolz/epsych2.git
```

If you already cloned without `--recurse-submodules`, or you copied the folder
rather than cloning it, fetch the submodule before continuing:

```bash
cd epsych2
git submodule update --init --recursive
```

[`granary`](https://github.com/dstolz/granary), the logging package, is **not** a
submodule — it is a standalone library, so clone it separately. The simplest
place is beside the EPsych checkout, which is where `epsych_startup` looks:

```bash
git clone https://github.com/dstolz/granary.git
```

That gives you `C:\src\epsych2` and `C:\src\granary` side by side. To keep it
somewhere else, say so once and EPsych will remember:

```matlab
setpref('EPsych','GranaryPath','D:\shared\granary')   % the folder holding +granary
```

Unlike the submodule, this failure is **loud**: `vprintf` is a thin facade over
`granary.printf`, so nothing in the toolbox can log without it and
`epsych_startup` stops with clone instructions rather than starting.

Then, in MATLAB:

```matlab
addpath('C:\path\to\epsych2')
epsych_startup
```

`epsych_startup` locates `granary` and verifies the submodule is present,
printing an actionable message for each. Do not skip the stimgen warning:
without it, protocols containing stimulus parameters load with silently
degraded values instead of failing outright. See [stimgen.md](../stimgen.md)
and [granary_Logging.md](../granary/granary_Logging.md).

> ⚠️ **The submodule failure is silent, not loud.** Without `stimgen`, nothing errors when a protocol loads — the stimulus values are simply wrong. Heed `epsych_startup`'s warning and run `git submodule update --init --recursive`.

What `epsych_startup` does:

- finds the repository root — the folder holding the copy of `epsych_startup.m`
  that was actually called, not whichever one `which` happens to answer with
- removes every EPsych checkout already on the MATLAB path, including stale
  entries for folders that no longer exist
- adds visible subdirectories to the MATLAB path (a folder whose name starts
  with `.` is skipped, along with everything below it)
- optionally prints the EPsych banner

### Working from a git worktree

`git worktree add` makes a second checkout of this repository, and both trees
define the same classes. `epsych_startup` leaves exactly **one** checkout on the
path: run it from the tree you want, and the other is removed and reported.

> ⚠️ **`epsych_startup` leaves exactly one checkout on the path.** Two worktrees define the same classes, so running it from one evicts the other and reports it. MATLAB still holds the evicted tree's class definitions and live objects in memory — `clear classes` or restart before starting a session — and `git worktree add` does not populate submodules.

Two things do not follow automatically:

- MATLAB keeps class definitions and live objects from the evicted tree in
  memory. Run `clear classes`, or restart MATLAB, before starting a session.
- `git worktree add` does not populate submodules. Run
  `git submodule update --init --recursive` inside the new worktree, or
  `epsych_startup` will report `obj/stimgen` as unavailable.

The worktree may live anywhere, including under a dotted directory — only the
part of a folder *below* the repository root is tested for the leading period.

## First-run validation

After installation, validate the MATLAB-side setup in this order.

> 🔑 **Validate MATLAB-side before connecting hardware.** Every GUI opens and every protocol compiles with no hardware attached. Working in this order means a failure in the steps below is a path problem and a failure afterwards is a hardware problem — never both at once.

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
epsych.ProtocolDesigner
```

Expected result:

- the protocol designer GUI opens
- you can create or inspect a protocol (`.eprot`) file

## Recommended setup sequence for a new lab machine

1. Install MATLAB and confirm it launches cleanly.
2. Install the TDT software required by your workflow.
3. Clone the EPsych repository with `--recurse-submodules`.
4. Run `epsych_startup`.
5. Open `epsych.RunExpt`.
6. Open `epsych.ProtocolDesigner`.
7. Only after the MATLAB-side flow is stable, connect and test TDT hardware.

This order matters because it separates MATLAB path problems from hardware or driver problems.

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

### A MEX component is missing

Likely cause:

- a MEX dependency was never built for the local machine

What to do:

1. Configure `mex -setup`
2. Build only the specific missing component rather than changing unrelated parts of the environment

## Next documents to read

- Toolbox orientation: [Toolbox_Overview.md](Toolbox_Overview.md)
- Session walkthrough: [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md)
- Protocol design: [../design/ProtocolDesigner_UserGuide.md](../design/ProtocolDesigner_UserGuide.md)

