# Customized GUI Instructions (EPsych / Caras Lab style)

This document describes a *general* pattern for building custom MATLAB GUIs that interface with EPsych-style experiments. It uses the class `cl_AppetitiveDetection_GUI_B` and its GUI builder `create_gui.m` as a concrete reference, but the ideas apply broadly to other tasks (appetitive/aversive, staircase, go/no-go, training modes, etc.).

## Table of contents

- [1) Recommended architecture](#1-recommended-architecture)
- [2) Finding parameters (hardware + software)](#2-finding-parameters-hardware--software)
- [3) Wiring parameters to UI controls](#3-wiring-parameters-to-ui-controls)
- [4) Monitoring experiment state in the GUI](#4-monitoring-experiment-state-in-the-gui)
- [5) Common GUI helper classes you may use](#5-common-gui-helper-classes-you-may-use)
- [6) Layout strategies for a responsive MATLAB GUI](#6-layout-strategies-for-a-responsive-matlab-gui)
- [7) Updating plots and tables efficiently](#7-updating-plots-and-tables-efficiently)
- [8) Safe interaction patterns (training modes, forcing trials)](#8-safe-interaction-patterns-training-modes-forcing-trials)
- [9) Suggested development workflow](#9-suggested-development-workflow)
- [10) Minimal skeleton (conceptual)](#10-minimal-skeleton-conceptual)

## 1) Recommended architecture

### 1.1 Use a class as the GUI “controller”
A common, robust pattern is:

- A `handle` class owns the GUI figure and all UI components.
- The class stores references to:
  - the runtime/experiment object (`RUNTIME`, often abbreviated `R`)
  - parameter handles (hardware + software)
  - plot/table helper objects
  - event listeners
- The GUI layout is built in a dedicated method (often `create_gui`) so the constructor stays small.

In `cl_AppetitiveDetection_GUI_B`:

- `RUNTIME` holds the object that exposes hardware (`R.HW`), session/module (`R.S`), trial logic (`R.TRIALS`), and helper/event sources (`R.HELPER`).
- `create_gui(obj)` is implemented as a method and is placed in a separate file under the class folder (`@cl_AppetitiveDetection_GUI_B/create_gui.m`). This is a good MATLAB convention for keeping large GUI code maintainable.

### 1.2 Constructor responsibilities
The constructor should typically:

1. Store the runtime handle (`obj.RUNTIME = RUNTIME`).
2. Enforce “single instance” rules if needed (optional).
3. Instantiate task/psychophysics objects used by the GUI.
4. Call `obj.create_gui()`.

Keep side-effects minimal; avoid starting timers or long-running processes inside the constructor unless you also carefully clean them up in the destructor.

### 1.3 Destructor responsibilities (cleanup)
Custom GUIs often create listeners, timers, and secondary figures. Always clean these up so closing the GUI doesn’t leave background objects running.

Typical cleanup items:

- Delete listener handles created with `addlistener`.
- Delete UI component handles (or store them in a container and delete the container).
- Close/delete any secondary figures.
- Stop/delete timers created for GUI polling (if you created them).

In `cl_AppetitiveDetection_GUI_B/delete`:

- `obj.hl_NewTrial`, `obj.hl_NewData`, `obj.hl_ModeChange` are disabled and deleted.
- `obj.guiHandles` (all UI objects under the figure) are deleted.
- A timer cleanup is performed via `timerfindall("Tag","GUIGenericTimer")`.

## 2) Finding parameters (hardware + software)

A GUI typically binds controls and monitors to parameters. In EPsych-style code, parameters are usually discovered by name.

### 2.1 Hardware parameters: `HW.find_parameter`
Hardware parameters tend to represent device settings and current state.

Common usage pattern:

- `p = R.HW.find_parameter('ITIDur');`
- `p = R.HW.find_parameter('~TrialDelivery', includeInvisible=true);`

Notes:

- Use `includeInvisible=true` for internal/advanced parameters (often prefixed with `~` or `!`).
- Some calls pass `silenceParameterNotFound=true` to make optional parameters safe:
  - Example: `p = R.HW.find_parameter('dBSPL', silenceParameterNotFound=true);`
  - If `p` is empty, simply skip creating that UI control.

### 2.2 Software parameters: `S.find_parameter` or `S.Module.add_parameter`
`S` is best thought of as **Software parameters**: parameters that do *not* exist on the hardware device, but are exposed through the same parameter-handle interface/abstraction as hardware parameters. This shared interface lets you write common GUI and runtime code that can treat hardware and software parameters uniformly.

Software parameters often represent derived settings, training modes, module configuration, or GUI-only/session-level values.

You’ll commonly see:

- `p = R.S.Module.add_parameter('MinDepth', 0.001);`
- `p = R.S.Module.add_parameter('RespWinDelayMin', pRWDelay.Min);`

General guidance:

- Use `add_parameter` when you want a configurable software parameter that lives with the module/session and should persist or be logged.
- Use `S.find_parameter(...)` (if available in your runtime) when the software parameter already exists and you just need the handle.

### 2.3 Setting parameter metadata for UI and validation
Before binding a parameter to a UI control, you can configure:

- Units: `p.Unit = 'ms';`
- Range limits: `p.Min = 100; p.Max = 10000;`
- Special behavior (example pattern): `p.isRandom = true;`

These settings help:

- constrain edit fields
- inform labels
- keep hardware-safe bounds

## 3) Wiring parameters to UI controls

### 3.1 `gui.Parameter_Control` for user-editable controls
`gui.Parameter_Control` is a central convenience wrapper that creates an appropriate UI widget and binds it to a parameter.

Common patterns from `create_gui.m`:

- Momentary button:
  - `gui.Parameter_Control(parentLayout, p, Type='momentary', autoCommit=true)`
- Toggle button:
  - `gui.Parameter_Control(parentLayout, p, Type='toggle', autoCommit=true)`
- Numeric edit field:
  - `gui.Parameter_Control(parentLayout, p, Type='editfield')`
- Dropdown:
  - `gui.Parameter_Control(parentLayout, p, Type='dropdown')`

Guidance:

- Use `autoCommit=true` for actions that should be applied immediately (e.g., hardware triggers like dropping a pellet).
- Use a manual “commit” mechanism (see `gui.Parameter_Update`) when you want a deliberate apply step.
- Store the returned object somewhere stable (e.g., in `obj.hButtons` or a list) if you need to update styles, enable/disable it, or read state later.

### 3.2 Post-update hooks: `PostUpdateFcn`
Some tasks need extra logic to run after a parameter changes.

Pattern:

- `p.PostUpdateFcn = @YourClass.someCallback;`
- `p.PostUpdateFcnArgs = {R};`

In `create_gui.m`, toggles such as “Shape” and “Reminder” attach to `cl_AppetitiveDetection_GUI_B.trigger_Shape` and `trigger_ReminderTrial`.

Use this approach when:

- you must coordinate with other parameters
- you must enforce state constraints (e.g., block reminder trials while “Deliver Trials” is active)
- you need to trigger trial-level behavior (`R.TRIALS.FORCE_TRIAL = true`)

### 3.3 Evaluators: `EvaluatorFcn` for dependent parameters
Sometimes a UI control should *validate* or *propagate changes* to other parameters.

Pattern (as used for response-window delay randomization):

- Assign an evaluator to the GUI control wrapper:
  - `h.EvaluatorFcn = @obj.eval_rwdelay_randomization;`
  - `h.EvaluatorArgs = {[pMin pMax pRWDelay]};`

This is useful when:

- two UI fields represent a min/max pair
- changing one field must update the valid range of another field
- a derived parameter (e.g., randomized delay) must be kept consistent

### 3.4 Styling: accessing underlying UI handles
Many wrapper objects store the underlying UI control handle (often via a property like `h.h_uiobj`).

In `create_gui.m`, the GUI collects the underlying handles to apply consistent font settings:

- build a list of underlying handles
- call `set(handle, ...)` for font size/weight and enabling

This avoids repeating formatting for every control.

## 4) Monitoring experiment state in the GUI

### 4.1 `gui.Parameter_Monitor` for read-only live tables
Use `gui.Parameter_Monitor` when you want a table of parameters that update continuously (e.g., trial state, latencies, response codes).

Pattern:

- `p = R.HW.find_parameter({...}, includeInvisible=true);`
- `obj.ParameterMonitorTable = gui.Parameter_Monitor(parentPanel, p, pollPeriod=0.1);`

Notes:

- Polling frequency (`pollPeriod`) trades responsiveness vs. CPU load.
- For long sessions or weaker machines, consider slower polling or event-driven updates if available.
- If the experiment enters a Stop state, it can be appropriate to delete monitors (see `onModeChange`).

### 4.2 Event listeners: `addlistener` to update UI on trial events
Polling isn’t always necessary. EPsych runtimes often emit events.

Pattern from `create_gui.m`:

- `obj.hl_NewTrial = addlistener(R.HELPER, 'NewTrial', @(src,ev) obj.update_NextTrial(src,ev));`
- `obj.hl_NewData  = addlistener(obj.Psych.Helper,'NewData', @(src,ev) obj.update_NewData(src,ev));`
- `obj.hl_ModeChange = addlistener(R.HELPER,'ModeChange', @(src,ev) obj.onModeChange(src,ev));`

Guidance:

- Prefer event-driven updates for:
  - “Next Trial” previews
  - performance summaries
  - plots updated once per trial
- Keep listener callbacks short and robust (defensive `try` blocks only where failure is expected).

## 5) Common GUI helper classes you may use

The example GUI uses several helper classes that encapsulate common UI elements:

- `gui.Parameter_Control`: user-editable parameter widgets
- `gui.Parameter_Monitor`: read-only monitoring table
- `gui.Parameter_Update`: a unified “Update Parameters”/commit mechanism
- `gui.FilenameValidator`: file naming / data filename UX
- `gui.StaircaseHistoryPlot`: online staircase visualization
- `gui.History`: response history table

General advice:

- Use these helpers rather than re-implementing low-level `uicontrol` logic.
- Store each helper object on `obj` so it isn’t garbage-collected.
- Ensure helper objects are deleted/cleaned up in the GUI destructor.

## 6) Layout strategies for a responsive MATLAB GUI

### 6.1 Prefer `uigridlayout` over hard-coded pixel positioning
The example GUI builds a main grid:

- `layoutMain = uigridlayout(fig, [11, 7]);`
- Uses explicit `RowHeight` and `ColumnWidth` (mix of fixed values and `'1x'` for flexible expansion)

This makes the GUI more robust to resizing and differing display setups.

### 6.2 Use nested layouts for logical sections
A scalable strategy is:

- One top-level grid for global structure
- Nested grids for groups (buttons, controls, plots)
- Panels (`uipanel`) to create visual separation and titles

In `create_gui.m`:

- A nested grid for control buttons (`buttonLayout`)
- Panels for “Trial Controls”, “Sound Controls”, “Filename”, “Next Trial”, “Session Performance”, “Response History”

### 6.3 Make long parameter sections scrollable
Parameter lists tend to grow.

Use:

- `layoutTrialControls.Scrollable = "on";`
- `layoutSoundControls.Scrollable = "on";`

This keeps the GUI compact while allowing additional controls without breaking layout.

### 6.4 Use a small helper for consistent panel layout
The example defines a local helper function `simple_layout(p)` that creates a 1x1 grid with zero padding.

This is a good practice for:

- consistent spacing
- reducing repeated layout boilerplate

### 6.5 Tagging and later lookup
For UI components that are updated frequently, you can:

- assign a `Tag`
- retrieve the handle later with `findobj`

Example pattern:

- `tableNextTrial.Tag = 'tblNextTrial';`
- In `update_NextTrial`, locate it once (using a `persistent` handle cache) and then update `h.Data`.

This avoids storing *every* handle as a property, while still allowing robust updates.

## 7) Updating plots and tables efficiently

### 7.1 Minimize high-frequency redraw in `uifigure`
If you need very fast plotting, legacy `figure` can be faster than `uifigure` in some workflows.

The example includes `create_onlineplot` that creates a separate `figure` for online plotting.

General strategy:

- Keep heavy plots isolated.
- Update plots on trial boundaries (events) rather than continuously.
- Prefer incremental updates (append points) over full redraws.

### 7.2 Compute session summary metrics on events
In `update_NewData`, performance metrics (hit/abort rate) are updated after new trial data.

Best practices:

- compute summary metrics on discrete updates (e.g., per trial)
- update a label or summary panel
- keep formatting consistent and readable (font size, alignment)

## 8) Safe interaction patterns (training modes, forcing trials)

GUIs often provide “manual overrides” or training toggles. Use guarded logic:

- check constraints (e.g., block Reminder trials if auto-delivery is active)
- reset the control state if an action is rejected
- keep trial logic and UI logic separated:
  - UI initiates an action (set a parameter or flag)
  - the runtime/trial engine executes the action

Example patterns:

- “Reminder” sets `R.TRIALS.FORCE_TRIAL = true` after validation.
- “Shape” temporarily sets stimulus depth to 100% and then restores.

## 9) Suggested development workflow

1. Start with a minimal `uifigure` + `uigridlayout` skeleton.
  - During layout development, temporarily call `showGridBorders(layoutHandle)` (e.g., `showGridBorders(layoutMain)`) to visualize grid cell boundaries and quickly spot mis-assigned `Layout.Row`/`Layout.Column` settings. Disable/remove this once the layout is finalized.
2. Add parameter controls using `gui.Parameter_Control` for the most important parameters.
3. Add a `gui.Parameter_Update` commit button if you want batch updates.
4. Add monitoring using `gui.Parameter_Monitor` and/or event listeners.
5. Add plots (`gui.StaircaseHistoryPlot`, etc.) once the basics are stable.
6. Audit cleanup (listeners/timers/figures) and verify closing the GUI leaves no background processes.

## 10) Minimal skeleton (conceptual)

Below is a conceptual outline (not copied verbatim) that captures the overall structure:

- `classdef YourGui < handle`
  - `properties` for runtime handle, figure handles, helper objects, listeners
  - `constructor`:
    - store runtime
    - create or locate task objects
    - call `create_gui`
  - `create_gui`:
    - create `uifigure` and main `uigridlayout`
    - add panels for grouped controls
    - use `R.HW.find_parameter` and `R.S.find_parameter`/`add_parameter` to collect hardware + software parameters
    - create controls with `gui.Parameter_Control`
    - create monitors with `gui.Parameter_Monitor`
    - register `addlistener` callbacks for trial events
  - `delete`:
    - delete listeners
    - delete helper objects
    - close figures

If you follow this pattern, your GUI stays modular, responsive, and consistent with other EPsych GUIs.
