# epsych.RunExpt GUI overview

This document is a practical overview of how to use the `epsych.RunExpt` session GUI to configure subjects, load/save session configurations, and run (or preview) behavioral/electrophysiology experiments.

## Table of contents

- [1) Launching the GUI](#1-launching-the-gui)
- [2) Quick-start workflow](#2-quick-start-workflow)
- [3) Main window layout](#3-main-window-layout)
- [4) Running, pausing, stopping, and saving data](#4-running-pausing-stopping-and-saving-data)
- [5) Config files (`*.config`)](#5-config-files-config)
- [6) Customization (menus + callback function signatures)](#6-customization-menus--callback-function-signatures)
- [7) Keyboard shortcuts](#7-keyboard-shortcuts)
- [8) Notes and common gotchas](#8-notes-and-common-gotchas)

## 1) Launching the GUI

In MATLAB, run:

```matlab
epsych.RunExpt
```

Optional: load a saved configuration immediately:

```matlab
epsych.RunExpt("C:\path\to\mySession.config")
```

Notes:

- Only one RunExpt window is kept open at a time. If one already exists, calling `epsych.RunExpt` will bring it to the foreground and reuse it.
- Closing the window while an experiment is running will prompt you and will stop the experiment if you proceed.

## 2) Quick-start workflow

A typical session looks like this:

1. (If needed) Build and save a protocol (`*.prot`) using the experiment designer.
   - The RunExpt GUI can open the designer for an existing protocol via **Edit Protocol**.
2. Launch the GUI: `epsych.RunExpt`.
3. (Recommended) Set a default data directory:
   - **Customize → Define Save path...**
4. Add one or more subjects:
   - Click **Add Subject**.
   - Fill in subject information (including BoxID).
   - Choose the subject’s protocol file when prompted (`*.prot`).
5. (Optional) Sanity check the protocol/trials:
   - Select a subject row.
   - Click **View Trials** to preview compiled trials.
6. Start the session:
   - Click **Preview** for a dry-run mode, or **Run** to record.
7. During the session:
   - Use **Pause** if needed.
   - Use **Stop** to end the session.
8. After stopping:
   - Click **Save Data** and save each subject’s data file.
9. (Optional) Save your session configuration for reuse:
   - **Config → Save Config...**

## 3) Main window layout

### 3.1 Subject table (left)

The main table shows one row per configured subject, with columns:

- **BoxID**: behavioral box identifier.
- **Name**: subject name (must be unique within the session).
- **Protocol**: the protocol filename (without path) associated with that subject.

Selecting a row prints the selected subject’s struct to the MATLAB command window.

### 3.2 Bottom control bar

Buttons at the bottom:

- **Run**: starts an experiment in “Record” mode.
- **Preview**: starts an experiment in “Preview” mode.
- **Pause**: requests a pause via the runtime ModeChange event.
- **Stop**: stops timers, signals Stop mode, and transitions the GUI to a post-run state.

### 3.3 Right-side action buttons

- **Add Subject**: launches the configured Add-Subject dialog/function, then prompts you to select a `*.prot` protocol.
- **Remove Subject**: removes the selected subject (or clears the session if there is only one subject).
- **Edit Protocol**: opens the selected `*.prot` in the experiment design editor.
- **View Trials**: previews compiled trials for the selected subject (truncated preview).
- **Save Data**: invokes the configured saving function to write data to disk (enabled after Stop or on Error).

## 4) Running, pausing, stopping, and saving data

If you need the underlying event model for GUI updates or runtime hooks, see [Event_Notifications.md](Event_Notifications.md).

### 4.1 What happens when you click Run / Preview

When you click **Run** or **Preview**, RunExpt:

- Raises MATLAB process priority (Windows) to reduce timing jitter.
- Resets the session runtime (`RUNTIME = epsych.Runtime`).
- Loads each subject’s `protocol` from the `*.prot` file.
- Ensures a trial selection function exists (uses `DefaultTrialSelectFcn` if protocol specifies `< default >`).
- Initializes hardware based on whether Synapse is running:
  - If `Synapse.exe` is detected, it uses `hw.TDT_Synapse()`.
  - Otherwise it uses `hw.TDT_RPcox(...)` constructed from protocol modules.
- Creates a high-frequency MATLAB timer (`PsychTimer`, period 0.01 s).
- Sets the hardware mode to `Record` or `Preview` (depending on what you clicked).
- Starts the timer.

### 4.2 Pause

**Pause** signals a pause via the runtime’s ModeChange event. The exact behavior depends on your hardware/runtime listeners.

### 4.3 Stop

**Stop**:

- Signals Stop via ModeChange.
- Stops and deletes the `BoxTimer` (if present) and the `PsychTimer`.
- Enables **Save Data** and returns **Run**/**Preview** availability.

### 4.4 Save Data

After **Stop** (or if a timer error occurs), click **Save Data**.

By default, `ep_SaveDataFcn(RUNTIME)` prompts once per subject for an output `.mat` file and saves the per-subject `Data` struct array.

The runtime also maintains a temporary runtime file per subject during the session (intended as a crash-recovery aid). The precise location/name is determined by the active timer Start callback.

## 5) Config files (`*.config`)

RunExpt session configurations are stored in MAT-files with the extension `*.config`. A saved config includes:

- `config`: the subject list and protocol associations (the RunExpt `CONFIG` struct array).
- `funcs`: the configured callback function names (saving function, add-subject function, timer callback names, etc.).
- `meta`: EPsych version metadata (via `EPsychInfo`) for reproducibility.

### 5.1 Loading and saving

- **Config → Load Config...** loads a `*.config` file.
- **Config → Save Config...** saves the current configuration.

### 5.2 Browsing configs

- **Config → Browse Configs...** opens a modal config browser that recursively lists `*.config` files under a chosen root folder.
- **Customize → Define Config Browser Root...** sets that root folder (stored in MATLAB preferences).

## 6) Customization (menus + callback function signatures)

Most customization is done by setting function names via the **Customize** menu. These values are stored in MATLAB preferences and also saved/restored when you save/load `*.config` files.

### 6.1 Saving function

Menu:

- **Customize → Define Saving Function...**

Expected signature:

```matlab
SavingFcn(RUNTIME)
```

Constraints enforced by the GUI:

- Must take exactly 1 input.
- Must return 0 outputs.

Default: `ep_SaveDataFcn`.

### 6.2 Add-subject function

Menu:

- **Customize → Define Add Subject Function...**

Expected signature:

```matlab
S = AddSubjectFcn(S, boxids)
```

Where:

- `S` is an input struct (possibly empty) and output subject struct.
- `boxids` is the set of currently-available box IDs (typically 1–16 excluding IDs already in use).

Default: `ep_AddSubject`.

### 6.3 Behavior GUI (per-box performance GUI)

Menu:

- **Customize → Define Box GUI Function...**

Expected signature:

```matlab
BoxFig(RUNTIME)
```

Default: `ep_GenericGUI`.

Notes:

- If the Box GUI function is empty/disabled, the session can still run; you just won’t get a live performance GUI.
- After a successful launch, **View → Launch Behavior GUI** is enabled.

### 6.4 Default data directory

Menu:

- **Customize → Define Save path...**

This sets the default root folder used to pre-fill suggested data filenames during the run (stored as the `RunExpt` preference `DataPath`).

## 7) Keyboard shortcuts

In the RunExpt figure:

- `Ctrl+0` … `Ctrl+4` sets the global verbosity level.

## 8) Notes and common gotchas

- **Buttons enabling/disabling is state-driven**: Add/Remove/Edit actions are disabled while the experiment is running.
- **Subject names must be unique** within a session; adding a duplicate name will be rejected.
- **Data saving is intentionally “post-run”** by default: the Save Data button is enabled after Stop (and on Error).
- **Synapse detection is process-based**: the GUI checks whether `Synapse.exe` appears in the Windows task list. If your Synapse setup differs, hardware selection may not match expectations.
- **Closing the GUI stops the session**: closing while running prompts first, then stops timers and cleans up.

## Related documentation

- [Event_Notifications.md](Event_Notifications.md)
- [Architecture_Overview.md](Architecture_Overview.md)
