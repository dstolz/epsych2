# epsych.RunExpt GUI overview

![epsych.RunExpt main window with the subject table, bottom control bar (Run/Preview/Pause/Stop), and right-side action buttons](images/RunExpt.png)

This document is a practical guide to using the `epsych.RunExpt` session GUI to configure subjects, load and save session configurations, and run (or preview) behavioral experiments. It is written for experiment operators. If you need to change how the session controller works internally, start with [Architecture_Overview.md](Architecture_Overview.md) and the class source in [obj/+epsych/@RunExpt/](../../obj/+epsych/@RunExpt/).

The window above is shown before any subjects are added; see [Main window layout](#3-main-window-layout) for what each area does once a session is configured.

## Table of contents

- [1) Launching the GUI](#1-launching-the-gui)
- [2) Quick-start workflow](#2-quick-start-workflow)
- [3) Main window layout](#3-main-window-layout)
- [4) Working with protocols](#4-working-with-protocols)
- [5) Running, pausing, stopping, and saving data](#5-running-pausing-stopping-and-saving-data)
- [6) Config files (`*.ecfg`)](#6-config-files-ecfg)
- [7) Customization](#7-customization)
- [8) Menus reference](#8-menus-reference)
- [9) Keyboard shortcuts](#9-keyboard-shortcuts)
- [10) Notes and common gotchas](#10-notes-and-common-gotchas)
- [Related documentation](#related-documentation)

## 1) Launching the GUI

In MATLAB, run:

```matlab
epsych.RunExpt
```

Optional: load a saved configuration immediately:

```matlab
epsych.RunExpt("C:\path\to\mySession.ecfg")
```

Optional: load a configuration and start the run in one step:

```matlab
epsych.RunExpt("C:\path\to\mySession.ecfg", Run=true)
```

Notes:

- Only one RunExpt window is kept open at a time. If one already exists, calling `epsych.RunExpt` brings it to the foreground and reuses it.
- Closing the window while an experiment is running will prompt you and will stop the experiment if you proceed.

## 2) Quick-start workflow

A typical session looks like this:

1. (If needed) Build and save a protocol (`*.eprot`) using the [Protocol Designer](../design/ProtocolDesigner_UserGuide.md).
2. Launch the GUI: `epsych.RunExpt`.
3. (Recommended) Set a default data directory: **Customize → Customize... → Data Path**.
4. Add one or more subjects:
   - Click **Add Subject**.
   - Fill in subject information (including BoxID).
   - Choose the subject's protocol file when prompted (`*.eprot`).
5. (Optional) Sanity check the protocol/trials:
   - Select a subject row.
   - Click **View Trials** to preview compiled trials.
6. Start the session:
   - Click **Preview** for a dry-run mode (data marked as test), or **Run** to record.
7. During the session:
   - Use **Pause** if needed.
   - Use **Stop** to end the session.
8. After stopping:
   - Click **Save Data** and save each subject's data file.
9. (Optional) Save your session configuration for reuse:
   - **Config → Save Config...**

## 3) Main window layout

### 3.1 Subject table (left)

The main table shows one row per configured subject, with columns:

- **BoxID**: behavioral box identifier.
- **Name**: subject name (must be unique within the session).
- **Protocol**: the protocol filename associated with that subject. Subjects whose loaded protocol is older than the version saved on disk are flagged so you know an update is available.

Selecting a row prints the selected subject's details to the MATLAB command window. Right-clicking a row opens the protocol context menu (see [Working with protocols](#4-working-with-protocols)).

### 3.2 Bottom control bar

- **Record video** (checkbox): when checked, clicking **Run** also starts a webcam recording via VLC for the duration of the session; unchecked by default. The setting persists across sessions. Preview never records. See [5.1](#51-what-happens-when-you-click-run--preview) and [7) Customization](#7-customization).
- **LIVE VIEW - NOT RECORDING** (amber text): shown only while a live webcam view is open (**View → Live Webcam View (No Recording)**). It is a reminder that the VLC window on screen is *not* being saved to disk.
- **Run**: starts the experiment in Record mode.
- **Preview**: starts the experiment in Preview mode; data are marked as a test run.
- **Pause**: requests a pause via the runtime ModeChange event.
- **Stop**: stops the timers, signals Stop mode, and transitions the GUI to a post-run state.

### 3.3 Right-side action buttons

- **Add Subject**: launches the configured add-subject dialog, then prompts you to select the subject's `*.eprot` protocol.
- **Remove Subject**: removes the selected subject (or clears the session if there is only one subject).
- **Edit Protocol**: opens the selected subject's protocol in the Protocol Designer.
- **View Trials**: previews compiled trials for the selected subject.
- **Save Data**: invokes the configured saving function to write data to disk (enabled after Stop or on Error).

## 4) Working with protocols

Right-click a subject row for these protocol actions:

- **Edit Protocol...**: opens the protocol file in the Protocol Designer.
- **Update to Latest Version**: reloads the subject's protocol from its file on disk. Use this after saving edits in the Protocol Designer so the session uses the latest version. The GUI tells you whether the subject was already up to date.
- **Change Protocol File...**: assigns a different `*.eprot` file to the selected subject.

Protocols are validated when loaded and again when you press **Run**/**Preview**. Validation errors are reported before the session starts; protocols that need compilation are compiled automatically at start.

## 5) Running, pausing, stopping, and saving data

If you need the underlying event model for GUI updates or runtime hooks, see [../epsych/Event_Notifications.md](../epsych/Event_Notifications.md).

### 5.1 What happens when you click Run / Preview

When you click **Run** or **Preview**, RunExpt:

- Raises MATLAB process priority (Windows) to reduce timing jitter.
- Resets the session runtime (a fresh `epsych.Runtime`).
- Validates each subject's protocol and compiles it if needed.
- Connects the hardware interfaces defined in the protocol (TDT, Intan, software, etc.). Hardware connections persist between runs within the same session, so a rerun does not reconnect from scratch.
- Creates a temporary data directory (a `DATA` folder next to the repository) with one crash-recovery `.mat` file per subject.
- Creates the trial timer (`PsychTimer`, default period 0.01 s; configurable via **Customize**).
- Sets the hardware mode to Record or Preview and starts the timer.
- Launches the behavior GUI (Box GUI function) if one is configured.

### 5.2 Pause

**Pause** signals a pause via the runtime's ModeChange event. The exact behavior depends on your hardware and runtime listeners.

### 5.3 Stop

**Stop**:

- Signals Stop via ModeChange, then returns the hardware to Idle.
- Stops and deletes the session timers.
- Enables **Save Data** and re-enables **Run**/**Preview**.

The hardware connection itself stays open so you can run again without reconnecting; it is released when you close the RunExpt window.

### 5.4 Save Data

After **Stop** (or if a timer error occurs), click **Save Data**.

By default, `ep_SaveDataFcn(RUNTIME)` prompts once per subject for an output `.mat` file and saves that subject's trial data.

During the session, each trial is also appended to a per-subject crash-recovery file (`RUNTIME_DATA_<name>_Box_<nn>_<timestamp>.mat`) in the temporary data directory, so at most the in-progress trial is lost if the computer fails mid-session.

## 6) Config files (`*.ecfg`)

RunExpt session configurations are stored in MAT-files with the extension `*.ecfg`. A saved config includes:

- the subject list and protocol associations
- the configured callback function names (saving function, add-subject function, timer callbacks)
- EPsych version metadata for reproducibility

### 6.1 Loading, refreshing, and saving

- **Config → Load Config...** loads a `*.ecfg` file.
- **Config → Refresh Config** reloads the currently loaded config file from disk — useful when the config or its protocols were changed outside the GUI.
- **Config → Save Config...** saves the current configuration.
- Recently used configs appear in the **Config** menu for one-click reloading.

### 6.2 Browsing configs

- **Config → Browse Configs...** opens a browser that recursively lists `*.ecfg` files under a chosen root folder.
- The root folder is set in **Customize → Customize... → Config Browser Root**.

## 7) Customization

All customization lives in a single dialog: **Customize → Customize...**. Values are stored in MATLAB preferences and are also saved/restored with `*.ecfg` files.

| Setting | Purpose | Default |
| --- | --- | --- |
| Saving Function | Called to save data after Stop/Error. Signature: `SavingFcn(RUNTIME)` (1 input, 0 outputs). | `ep_SaveDataFcn` |
| Box GUI Function | Launches a per-session behavior/performance GUI when the run starts. Signature: `BoxFig(RUNTIME)`. | `ep_GenericGUI` |
| Add Subject Function | Dialog used by **Add Subject**. | `epsych.DefaultSubject.open` |
| Data Path | Default root folder used to suggest data filenames. | current directory |
| Config Browser Root | Folder scanned by **Config → Browse Configs...**. | — |
| Video Recording Path | Root folder for webcam recordings made with the **Record video** checkbox. Files are saved to `<root>\<subject>\<subject>_<yyMMddTHHmmss>.ts`. Leave empty to fall back to the Data Path. | — |
| Intan Recording Path | Root folder for Intan RHX recordings when an `hw.Intan_RHX` interface is in the protocol. Files save under `<root>\<subject>\` named after the data file (RHX appends its own `_<timestamp>`). **Must contain no spaces.** Leave empty to fall back to the Data Path. | — |
| Intan Settings File | RHX `.xml` settings file loaded when the Intan interface connects. **Must contain no spaces.** Leave empty to load none. | — |
| Timer Period (s) | PsychTimer callback period (0.001–1 s). | 0.01 |

If the Box GUI function is empty or disabled, the session can still run; you just will not get a live performance GUI.

The webcam device itself (camera, frame rate, resolution, crop) is configured separately in **View → Webcam Recorder Setup...**.

The Intan Recording Path and Settings File are stored in the `ep_RunExpt_Intan` preference group (per machine, like the webcam settings) and are applied to every `hw.Intan_RHX` interface at run time. RHX names its files with a mandatory `_<timestamp>` suffix, so the Intan `.rhd`/`.rhs`, the behavioral `.mat`, and the webcam `.ts` are paired by shared filename prefix rather than exact equality.

## 8) Menus reference

- **Config**: Browse Configs..., Load Config..., Refresh Config, Save Config..., recent configs list.
- **Customize**: Customize... (all settings above).
- **View**: Always On Top, Commutator GUI (opens the motorized commutator control; see [../peripherals/peripherals_NanoMotorControl.md](../peripherals/peripherals_NanoMotorControl.md)), Webcam Recorder Setup... (camera, frame rate, resolution, crop; see [../gui/VlcRecorderSetup.md](../gui/VlcRecorderSetup.md)), Live Webcam View (No Recording).
  - **Live Webcam View (No Recording)** opens a VLC window showing the camera with the same device, frame rate, resolution, and crop a recording would use, but writes nothing to disk — useful for aiming the camera or checking on a subject between runs. The VLC window carries a yellow **LIVE VIEW - NOT RECORDING** overlay and window title, and the bottom control bar shows a matching amber banner. Select it again to close the view.
  - The item is disabled while a session is RUNNING, because opening or closing the view restarts VLC and would stall the trial loop. A view opened before **Run** stays open through a session; if that session is recording, the recording takes over the camera and the live view closes.
- **Help**:
  - Version Info — toolbox version, git commit, and links.
  - Open Current Error Log — opens today's EPsych error log file.
  - Assign RUNTIME to Command Window — exports the live `RUNTIME` object to the base workspace for inspection (enabled while hardware is active).
  - Verbosity... — sets how much detail EPsych prints to the command window.
  - GitHub Repository / Documentation / Commit History Overview — online resources.

## 9) Keyboard shortcuts

In the RunExpt figure:

- `Ctrl+0` … `Ctrl+4` set the global message verbosity level.
- Menu accelerators are shown next to each menu item (for example `Ctrl+U` opens the Customize dialog).

## 10) Notes and common gotchas

- **Button enabling/disabling is state-driven**: Add/Remove/Edit actions are disabled while the experiment is running.
- **Subject names must be unique** within a session; adding a duplicate name will be rejected.
- **Data saving is intentionally post-run** by default: the Save Data button is enabled after Stop (and on Error).
- **Hardware comes from the protocol**: which backend is used (TDT Synapse, TDT RPvds, Intan, software-only) is defined in the protocol file, not chosen in RunExpt. If hardware fails to connect, check the protocol's interface configuration and the device, then try again.
- **Protocol edits are not picked up automatically**: after editing a protocol in the Protocol Designer, use **Update to Latest Version** (or **Config → Refresh Config**) so the session loads the new version.
- **Closing the GUI stops the session**: closing while running prompts first, then stops the timers, releases the hardware, and cleans up.

## Related documentation

- [../design/ProtocolDesigner_UserGuide.md](../design/ProtocolDesigner_UserGuide.md) — building the protocols this GUI runs
- [../epsych/Event_Notifications.md](../epsych/Event_Notifications.md) — runtime event model (for GUI/analysis developers)
- [Architecture_Overview.md](Architecture_Overview.md) — internals (for developers)
