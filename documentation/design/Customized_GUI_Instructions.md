# Customized GUI Instructions (EPsych / Caras Lab style)

![Small example task GUI built from the components described in this guide: Trial Controls (gui.Parameter_Control), Phase Selector (gui.PhaseSelector), and a Commit Changes button (gui.Parameter_Update) with a pending edit highlighted](images/CustomGUIDemo.png)

This document describes a *general* pattern for building custom MATLAB GUIs that interface with EPsych-style experiments. It uses the class `cl_AppetitiveDetection_GUI_B` and its GUI builder `create_gui.m` as a concrete reference, but the ideas apply broadly to other tasks (appetitive/aversive, staircase, go/no-go, training modes, etc.).

The screenshot above is a minimal example assembled from the same building blocks `create_gui.m` uses: a `gui.Parameter_Control` bound to a real `hw.Parameter` (with the "SoundLevel" field showing a pending edit in green), a `gui.PhaseSelector`, and a `gui.Parameter_Update` commit button. It is not `cl_AppetitiveDetection_GUI_B` itself — that production GUI is larger — but it demonstrates the same wiring pattern described in [Section 3](#3-wiring-parameters-to-ui-controls) and [Section 5](#5-common-gui-helper-classes-you-may-use).

## Overview (start here)

If you are new to MATLAB GUIs, the main idea is simple: **the experiment already has “knobs” (parameters) and “signals” (state/events)**, and your GUI is just a clean way to *edit* the knobs and *display* the signals.

In EPsych code you will have a runtime object (`epsych.Runtime`, often abbreviated **`R`**) that gives you access to:

* **Parameters (`R.find_parameter`, `R.all_parameters`, `R.P`)**: values that map to device settings/state (timing, triggers, amplitudes) and software-side values that live only in the session (training flags, derived settings, GUI-only config that should still be logged). Hardware-backed and software-backed parameters share the same `hw.Parameter` interface, so GUI code can treat them uniformly.
* **Trial logic (`R.TRIALS`)**: what trial is next, what happened on the last trial, and "force" flags for training/testing.
* **Event sources (`R.HELPER`, task helpers)**: events like *NewTrial*, *NewData*, *ModeChange* that let the GUI update without constant polling (see [../epsych/Event_Notifications.md](../epsych/Event_Notifications.md)).


### A practical mental model

* **Parameters** are shared “handles” that both the runtime and GUI can read/write.
* **Controls** (buttons/edit fields) write to parameters.
* **Monitors** (tables/text labels/plots) read parameters or respond to events.
* **Listeners** keep the GUI responsive without high CPU usage.

A typical EPsych GUI follows this workflow:

1. **Pick what the GUI needs to control vs. monitor.**

   * *Control* = user-editable settings (e.g., ITI duration, enable/disable trial delivery).
   * *Monitor* = read-only live values (e.g., trial outcome codes, latencies, counters).
2. **Find the parameter handles by name.**

   * Existing parameters: `p = R.find_parameter('Name');` or grab everything at once with `P = R.all_parameters(asStruct=true, includeTriggers=true);`
   * New software parameters: locate the software interface and add one, e.g. `sw = R.Interfaces(arrayfun(@(x) isa(x,'hw.Software'), R.Interfaces)); p = sw.add_parameter('Name', defaultValue);`
3. **Build the layout first (usually with `uigridlayout`).**

   * Make panels for logical blocks (Trial Controls, Sound Controls, Performance, etc.).
   * Use scrollable containers for long parameter lists.
4. **Create controls using helper wrappers (recommended).**

   * Use `gui.Parameter_Control` to bind a parameter to a widget (toggle, edit field, dropdown, momentary button).
   * Use `gui.Parameter_Update` if you want a deliberate “Apply/Commit” step.
5. **Update displays using either monitors or events.**

   * Use `gui.Parameter_Monitor` for read-only live tables or graphical dashboards (lamps/labels/gauges).
   * Prefer `addlistener(...)` callbacks for “once-per-trial” updates (plots, summaries, previews).
6. **Clean up on close.**

   * Delete listeners, timers, helper objects, and any secondary figures you created.

### Common beginner mistakes to avoid

* **Not storing handles/objects** (wrappers/listeners can be garbage-collected if you don’t keep them on `obj`).
* **Over-polling** (very fast timers make GUIs sluggish; prefer event-driven updates when possible).
* **Mixing trial-engine logic into UI callbacks** (UI should *request* actions; the runtime should *execute* them).
* **Forgetting cleanup** (timers/listeners left running after the GUI closes cause hard-to-debug behavior).

For a first pass, read Sections **1–4** in order. Sections **6–9** are the main “make it robust” material once you have something working.

## 0) The fast path: subclass `gui.BoxGUI`

Most of the plumbing this guide explains — single-instance enforcement, figure creation with saved window position, the three event listeners, cleanup of listeners/timers/components on close, and wiring `gui.Parameter_Update` to your controls — is provided by the base class **`gui.BoxGUI`**. A new task GUI only needs:

1. A constructor that forwards the runtime: `obj@gui.BoxGUI(RUNTIME, Name='My Task')`
2. A protected `build(fig)` method that lays out the window using one-line helpers: `addButton`, `addControl`, `controlColumn`, `addUpdateButton`, `addMonitor`, and `register` for any other component
3. Optional hooks: `createPsych`, `onNewTrial`, `onNewData`, `onModeChange`, `onFirstTrial`

Start by copying [examples/customgui/ExampleBoxGUI.m](../../examples/customgui/ExampleBoxGUI.m) (launchable without hardware via `examples/customgui/run_example.m`) and see [../gui/gui_BoxGUI.md](../gui/gui_BoxGUI.md) for the full API. `ep_GenericGUI`, the default box GUI, is itself a small `gui.BoxGUI` subclass and a good second reference.

The remaining sections explain the concepts underneath (parameters, controls, monitors, events, layout). They still apply inside `build()` — and to the pre-BoxGUI hand-rolled pattern that `cl_AppetitiveDetection_GUI_B` uses, which is worth understanding but no longer the recommended starting point.

## Table of contents

* [0) The fast path: subclass gui.BoxGUI](#0-the-fast-path-subclass-guiboxgui)
* [1) Recommended architecture](#1-recommended-architecture)
* [2) Finding parameters (hardware + software)](#2-finding-parameters-hardware--software)
* [3) Wiring parameters to UI controls](#3-wiring-parameters-to-ui-controls)
* [4) Monitoring experiment state in the GUI](#4-monitoring-experiment-state-in-the-gui)
* [5) Common GUI helper classes you may use](#5-common-gui-helper-classes-you-may-use)
* [6) Layout strategies for a responsive MATLAB GUI](#6-layout-strategies-for-a-responsive-matlab-gui)
* [7) Updating plots and tables efficiently](#7-updating-plots-and-tables-efficiently)
* [8) Safe interaction patterns (training modes, forcing trials)](#8-safe-interaction-patterns-training-modes-forcing-trials)
* [9) Suggested development workflow](#9-suggested-development-workflow)
* [10) Minimal skeleton](#10-minimal-skeleton)

## 1) Recommended architecture

### 1.1 Use a class as the GUI “controller”

A common, robust pattern is:

* A `handle` class owns the GUI figure and all UI components.
* The class stores references to:

  * the runtime/experiment object (`RUNTIME`, often abbreviated `R`)
  * parameter handles (hardware + software)
  * plot/table helper objects
  * event listeners
* The GUI layout is built in a dedicated method (often `create_gui`) so the constructor stays small.

In `cl_AppetitiveDetection_GUI_B`:

* `RUNTIME` holds the `epsych.Runtime` that exposes the interfaces (`R.Interfaces`), parameter lookups (`R.find_parameter`, `R.all_parameters`, `R.P`), trial logic (`R.TRIALS`), and helper/event sources (`R.HELPER`).
* `create_gui(obj)` is implemented as a method and is placed in a separate file under the class folder (`@cl_AppetitiveDetection_GUI_B/create_gui.m`). This is a good MATLAB convention for keeping large GUI code maintainable.

### 1.2 Constructor responsibilities

The constructor should typically:

1. Store the runtime handle (`obj.RUNTIME = RUNTIME`).
2. Enforce “single instance” rules if needed (optional).
3. Instantiate task/psychophysics objects used by the GUI.
4. Call `obj.create_gui()`.

Keep side-effects minimal; avoid starting timers or long-running processes inside the constructor unless you also carefully clean them up in the destructor.

> With `gui.BoxGUI`, all of this is the base constructor's job: it stores the runtime, replaces an existing instance, calls your `createPsych` hook, and then your `build(fig)` method.

### 1.3 Destructor responsibilities (cleanup)

Custom GUIs often create listeners, timers, and secondary figures. Always clean these up so closing the GUI doesn’t leave background objects running.

Typical cleanup items:

* Delete listener handles created with `addlistener`.
* Delete UI component handles (or store them in a container and delete the container).
* Close/delete any secondary figures.
* Stop/delete timers created for GUI polling (if you created them).

In `cl_AppetitiveDetection_GUI_B/delete`:

* `obj.hl_NewTrial`, `obj.hl_NewData`, `obj.hl_ModeChange` are disabled and deleted.
* `obj.guiHandles` (all UI objects under the figure) are deleted.
* A timer cleanup is performed via `timerfindall("Tag","GUIGenericTimer")`.

> With `gui.BoxGUI`, no destructor is needed: everything created through the `add*` helpers or `register()` is deleted automatically when the window closes. Deleting a figure by itself only removes graphics — component handle objects and their listeners/timers survive — which is exactly the leak the registry prevents.

## 2) Finding parameters (hardware + software)

A GUI typically binds controls and monitors to parameters. In EPsych code, parameters are discovered by name through the runtime, which searches every registered interface (hardware and software alike).

### 2.1 Looking up parameters: `R.find_parameter` and `R.all_parameters`

Common usage patterns:

* `p = R.find_parameter('ITIDur');`
* `p = R.find_parameter('~TrialDelivery', includeInvisible=true);`
* `P = R.all_parameters(asStruct=true, includeTriggers=true);` then `P.ITIDur`, `P.Depth`, ... — this is the pattern the reference GUI (`cl_AppetitiveDetection_GUI_B/create_gui.m`) uses to fetch everything in one call.
* `RUNTIME.P` is a runtime-cached struct of all parameters (keyed by `validName`), populated at run start — prefer it over repeated lookups in hot paths.

Notes:

* Names can be short (`'Param'`) or qualified (`'Module.Param'`) when the same name exists on multiple modules.
* Use `includeInvisible=true` for internal/advanced parameters (often prefixed with `~`, `_`, or `!`).
* Pass `silenceParameterNotFound=true` to make optional parameters safe:

  * Example: `p = R.find_parameter('dBSPL', silenceParameterNotFound=true);`
  * If `p` is empty, simply skip creating that UI control.

### 2.2 Software parameters

Software parameters do *not* exist on a hardware device, but are exposed through the same `hw.Parameter` abstraction. This shared interface lets you write common GUI and runtime code that treats hardware and software parameters uniformly.

Software parameters often represent derived settings, training modes, module configuration, or GUI-only/session-level values. They live on the protocol's `hw.Software` interface. To add one at run time:

```matlab
sw = R.Interfaces(arrayfun(@(x) isa(x,'hw.Software'), R.Interfaces));
p = sw.add_parameter('MinDepth', 0.001);
```

General guidance:

* Prefer defining software parameters in the protocol (Protocol Designer) so they persist, serialize, and appear in trial data automatically.
* Use `add_parameter` at run time only for GUI-session values that do not belong in the protocol.
* Use `R.find_parameter(...)` when the parameter already exists and you just need the handle.

### 2.3 Setting parameter metadata for UI and validation

Before binding a parameter to a UI control, you can configure:

* Units: `p.Unit = 'ms';`
* Range limits: `p.Min = 100; p.Max = 10000;`
* Special behavior (example pattern): `p.isRandom = true;`

These settings help:

* constrain edit fields
* inform labels
* keep hardware-safe bounds

## 3) Wiring parameters to UI controls

### 3.1 `gui.Parameter_Control` for user-editable controls

`gui.Parameter_Control` is a central convenience wrapper that creates an appropriate UI widget and binds it to a parameter.

Common patterns from `create_gui.m`:

* Momentary button:

  * `gui.Parameter_Control(parentLayout, p, Type='momentary', autoCommit=true)`
* Toggle button:

  * `gui.Parameter_Control(parentLayout, p, Type='toggle', autoCommit=true)`
* Numeric edit field:

  * `gui.Parameter_Control(parentLayout, p, Type='editfield')`
* Dropdown:

  * `gui.Parameter_Control(parentLayout, p, Type='dropdown')`

Guidance:

* Use `autoCommit=true` for actions that should be applied immediately (e.g., hardware triggers like dropping a pellet).
* Use a manual “commit” mechanism (see `gui.Parameter_Update`) when you want a deliberate apply step.
* Store the returned object somewhere stable (e.g., in `obj.hButtons` or a list) if you need to update styles, enable/disable it, or read state later.

### 3.2 Post-update hooks: `PostUpdateFcn`

Some tasks need extra logic to run after a parameter changes.

Pattern:

* `p.PostUpdateFcn = @YourClass.someCallback;`
* `p.PostUpdateFcnArgs = {R};`

In `create_gui.m`, toggles such as “Shape” and “Reminder” attach to `cl_AppetitiveDetection_GUI_B.trigger_Shape` and `trigger_ReminderTrial`.

Use this approach when:

* you must coordinate with other parameters
* you must enforce state constraints (e.g., block reminder trials while “Deliver Trials” is active)
* you need to trigger trial-level behavior (`R.TRIALS.FORCE_TRIAL = true`)

### 3.3 Evaluators: `EvaluatorFcn` for dependent parameters

Sometimes a UI control should *validate* or *propagate changes* to other parameters.

Pattern — assign an evaluator to the GUI control wrapper. The callback is invoked as `[value,success] = EvaluatorFcn(hControl, event, Parameter, extraArgs...)`:

* `h.EvaluatorFcn = @gui.eval_dependent_parameter_randomization;`
* `h.EvaluatorArgs = {pMin, pMax, pTarget};`

(`gui.eval_dependent_parameter_randomization` and `gui.eval_staircase_training_mode` are ready-made evaluators used by the reference GUI; write your own with the same signature for task-specific rules.)

This is useful when:

* two UI fields represent a min/max pair
* changing one field must update the valid range of another field
* a derived parameter (e.g., randomized delay) must be kept consistent

### 3.4 Styling: accessing underlying UI handles

Many wrapper objects store the underlying UI control handle (often via a property like `h.h_uiobj`).

In `create_gui.m`, the GUI collects the underlying handles to apply consistent font settings:

* build a list of underlying handles
* call `set(handle, ...)` for font size/weight and enabling

This avoids repeating formatting for every control.

## 4) Monitoring experiment state in the GUI

### 4.1 `gui.Parameter_Monitor` for read-only live displays

Use `gui.Parameter_Monitor` when you want parameters that update continuously (e.g., trial state, latencies, response codes). It offers a sortable live table (`type="table"`, the default), a graphical dashboard (`type="graphical"`) with lamps for boolean state, value labels, and gauges, or a plain text block (`type="text"`). See [../gui/Parameter_Monitor.md](../gui/Parameter_Monitor.md) for the full option set.

Pattern:

* `p = R.find_parameter({...}, includeInvisible=true);`
* `obj.ParameterMonitor = gui.Parameter_Monitor(parentPanel, p, pollPeriod=0.1);`

Graphical dashboard variant (lamps for binary state monitors):

* `gui.Parameter_Monitor(parentPanel, p, pollPeriod=0.1, type="graphical", Styles=struct(InTrial="lamp", Platform="lamp"))`

Notes:

* Polling frequency (`pollPeriod`) trades responsiveness vs. hardware-read load; rendering itself is cheap because the display only redraws values that actually changed.
* For long sessions or weaker machines, consider slower polling or event-driven updates if available.
* Monitors clean themselves up (timer included) when their display is destroyed with the hosting figure; deleting them earlier (e.g., on a Stop state, see `onModeChange`) simply freezes the display sooner.

### 4.2 Event listeners: `addlistener` to update UI on trial events

Polling isn’t always necessary. EPsych runtimes often emit events.

Pattern from `create_gui.m`:

* `obj.hl_NewTrial = addlistener(R.HELPER, 'NewTrial', @(src,ev) obj.update_NextTrial(src,ev));`
* `obj.hl_NewData  = addlistener(obj.Psych.Helper,'NewData', @(src,ev) obj.update_NewData(src,ev));`
* `obj.hl_ModeChange = addlistener(R.HELPER,'ModeChange', @(src,ev) obj.onModeChange(src,ev));`

Guidance:

* Prefer event-driven updates for:

  * “Next Trial” previews
  * performance summaries
  * plots updated once per trial
* Keep listener callbacks short and robust (defensive `try` blocks only where failure is expected).

## 5) Common GUI helper classes you may use

The example GUI uses several helper classes that encapsulate common UI elements:

* `gui.Parameter_Control`: user-editable parameter widgets
* `gui.Parameter_Monitor`: read-only monitoring table or graphical dashboard ([../gui/Parameter_Monitor.md](../gui/Parameter_Monitor.md))
* `gui.Parameter_Update`: a unified “Update Parameters”/commit mechanism ([../gui/Parameter_Update.md](../gui/Parameter_Update.md))
* `gui.PhaseSelector`: dropdown for loading/saving named parameter sets (JSON phase files) between training blocks
* `gui.FilenameValidator`: file naming / data filename UX
* `gui.ElapsedTrialTimer`: elapsed-time display driven by trial events
* `psychophysics.Staircase` plotting (`Plot`): online staircase visualization
* `gui.History`: response history table ([../gui/gui_History.md](../gui/gui_History.md))

General advice:

* Use these helpers rather than re-implementing low-level `uicontrol` logic.
* Store each helper object on `obj` so it isn’t garbage-collected.
* Ensure helper objects are deleted/cleaned up in the GUI destructor.

## 6) Layout strategies for a responsive MATLAB GUI

### 6.1 Prefer `uigridlayout` over hard-coded pixel positioning

The example GUI builds a main grid:

* `layoutMain = uigridlayout(fig, [11, 7]);`
* Uses explicit `RowHeight` and `ColumnWidth` (mix of fixed values and `'1x'` for flexible expansion)

This makes the GUI more robust to resizing and differing display setups.

### 6.2 Use nested layouts for logical sections

A scalable strategy is:

* One top-level grid for global structure
* Nested grids for groups (buttons, controls, plots)
* Panels (`uipanel`) to create visual separation and titles

In `create_gui.m`:

* A nested grid for control buttons (`layoutButtons`)
* Panels for “Trial Controls”, “Sound Controls”, “Filename”, “Next Trial”, “Session Performance”, “Response History”

### 6.3 Make long parameter sections scrollable

Parameter lists tend to grow.

Use:

* `layoutControls.Scrollable = "on";`

This keeps the GUI compact while allowing additional controls without breaking layout.

### 6.4 Tagging and later lookup

For UI components that are updated frequently, you can:

* assign a `Tag`
* retrieve the handle later with `findobj`

Example pattern:

* `tablePreview.Tag = 'tblPreview';`
* In `update_NextTrial`, locate it once (using a `persistent` handle cache) and then update `h.Data`.

This avoids storing *every* handle as a property, while still allowing robust updates.

## 7) Updating plots and tables efficiently

### 7.1 Minimize high-frequency redraw in `uifigure`

If you need very fast plotting, legacy `figure` can be faster than `uifigure` in some workflows.

The example includes `create_onlineplot` that creates a separate `figure` for online plotting.

General strategy:

* Keep heavy plots isolated.
* Update plots on trial boundaries (events) rather than continuously.
* Prefer incremental updates (append points) over full redraws.

### 7.2 Compute session summary metrics on events

In `update_NewData`, performance metrics (hit/abort rate) are updated after new trial data.

Best practices:

* compute summary metrics on discrete updates (e.g., per trial)
* update a label or summary panel
* keep formatting consistent and readable (font size, alignment)

## 8) Safe interaction patterns (training modes, forcing trials)

GUIs often provide “manual overrides” or training toggles. Use guarded logic:

* check constraints (e.g., block Reminder trials if auto-delivery is active)
* reset the control state if an action is rejected
* keep trial logic and UI logic separated:

  * UI initiates an action (set a parameter or flag)
  * the runtime/trial engine executes the action

Example patterns:

* “Reminder” sets `R.TRIALS.FORCE_TRIAL = true` after validation.
* “Shape” temporarily sets stimulus depth to 100% and then restores.

## 9) Suggested development workflow

1. Start with a minimal `uifigure` + `uigridlayout` skeleton.

* During layout development, temporarily call `showGridBorders(layoutHandle)` (e.g., `showGridBorders(layoutMain)`) to visualize grid cell boundaries and quickly spot mis-assigned `Layout.Row`/`Layout.Column` settings. Disable/remove this once the layout is finalized.

1. Add parameter controls using `gui.Parameter_Control` for the most important parameters.
1. Add a `gui.Parameter_Update` commit button if you want batch updates.
1. Add monitoring using `gui.Parameter_Monitor` and/or event listeners.
1. Add plots (e.g., `S.Plot(ax)` on a `psychophysics.Staircase`) once the basics are stable.
1. Audit cleanup (listeners/timers/figures) and verify closing the GUI leaves no background processes.

## 10) Minimal skeleton

The recommended skeleton is a `gui.BoxGUI` subclass — copy [examples/customgui/ExampleBoxGUI.m](../../examples/customgui/ExampleBoxGUI.m) and adapt:

* `classdef YourGui < gui.BoxGUI`

  * `constructor`: forward the runtime — `obj@gui.BoxGUI(RUNTIME, Name='Your Task')`
  * `createPsych` (optional): return a psychophysics object; NewData then arrives *after* it has processed each trial
  * `build(fig)`:

    * create the main `uigridlayout` and panels for grouped controls
    * `obj.addButton(...)` for triggers/toggles, `obj.addControl(...)` for editable parameters (names that are missing from the loaded protocol are skipped), `obj.addUpdateButton(...)` to commit them
    * `obj.addMonitor(...)` for read-only live values
    * `obj.register(...)` for any other component (`gui.ParameterScatter`, `gui.History`, `gui.PhaseSelector`, ...)
  * hooks `onNewTrial` / `onNewData` / `onModeChange` / `onFirstTrial` for per-trial displays

No properties for listeners, no destructor, no `closeGUI`: the base class owns the lifecycle. See [../gui/gui_BoxGUI.md](../gui/gui_BoxGUI.md) for the full API.

Writing the same structure by hand as a plain `handle` class (own figure, own listeners, own destructor — the pattern `cl_AppetitiveDetection_GUI_B` predates BoxGUI with) still works and follows the concepts in Sections 1–9, but is only worth the extra ~200 lines when a GUI cannot inherit from `gui.BoxGUI` for some reason.
