# epsych.RunExpt GUI overview

![epsych.RunExpt main window with the toolbar, subject table, and bottom control bar (Run/Preview/Pause/Stop)](images/RunExpt.png)

This document is a practical guide to using the `epsych.RunExpt` session GUI to assemble a session from the subject roster and run (or preview) behavioral experiments. It is written for experiment operators. If you need to change how the session controller works internally, start with [Architecture_Overview.md](Architecture_Overview.md) and the class source in [obj/+epsych/@RunExpt/](../../obj/+epsych/@RunExpt/).

The window above shows a session with two subjects assigned to boxes 1 and 2; see [Main window layout](#3-main-window-layout) for what each area does.

## Table of contents

- [1) Launching the GUI](#1-launching-the-gui)
- [2) Quick-start workflow](#2-quick-start-workflow)
- [3) Main window layout](#3-main-window-layout)
- [4) Working with protocols](#4-working-with-protocols)
- [5) Running, pausing, stopping, and saving data](#5-running-pausing-stopping-and-saving-data)
- [6) Customization](#6-customization)
- [7) Menus reference](#7-menus-reference)
- [8) Keyboard shortcuts](#8-keyboard-shortcuts)
- [9) Notes and common gotchas](#9-notes-and-common-gotchas)
- [Related documentation](#related-documentation)

## 1) Launching the GUI

In MATLAB, run:

```matlab
epsych.RunExpt
```

Optional: assemble the whole session from a roster project — its subjects, each one's protocol and box, and the session settings each membership carries:

```matlab
epsych.RunExpt("Aversive Detection")
```

Optional: name the subjects and start the run in one step:

```matlab
epsych.RunExpt("Aversive Detection", Subjects=["M1","M2"], Run=true)
```

Notes:

- Only one RunExpt window is kept open at a time. If one already exists, calling `epsych.RunExpt` brings it to the foreground and reuses it.
- Closing the window while an experiment is running will prompt you and will stop the experiment if you proceed.

## 2) Quick-start workflow

A typical session looks like this:

1. (If needed) Build and save a protocol (`*.eprot`) using the [Protocol Designer](../design/ProtocolDesigner_UserGuide.md).
2. Launch the GUI: `epsych.RunExpt`.
3. (Recommended) Set a default data directory: **Customize → Customize... → Data Save Path** for the rig, or per study in **Edit Project → Session Defaults**.
4. Add one or more subjects:
   - Click the **Subjects** toolbar button (or **Subjects → Subjects & Projects...**, Ctrl+B).
   - Pick a project on the left, tick the animals running today, and press **Add Checked to Session**. Each one gets a free box and the protocol it last ran.
   - For an animal that is not in the roster yet, use **New Subject...** in the same window; it opens the usual subject dialog and files the animal into the selected project.
   - See [Subjects & Projects](../gui/gui_SubjectManager.md) for the full window.
5. (Optional) Sanity check the protocol/trials:
   - Right-click the subject row and choose **View Trials** to preview compiled trials.
6. Start the session:
   - Click **Preview** for a dry-run mode (data marked as test), or **Run** to record.
7. During the session:
   - Use **Pause** if needed.
   - Use **Stop** to end the session.
8. After stopping:
   - Click the **Save Data** toolbar button and save each subject's data file.

There is nothing to save at the end: the roster already holds everything a session needs, so tomorrow's session is the same ticks in **Subjects & Projects** — or one `epsych.RunExpt("<project>")` call.

## 3) Main window layout

### 3.1 Subject table (left)

The main table shows one row per configured subject, with columns:

- **BoxID**: behavioral box identifier.
- **Name**: subject name (must be unique within the session).
- **Protocol**: the protocol filename associated with that subject. Subjects whose loaded protocol is older than the version saved on disk are flagged so you know an update is available.

Selecting a row prints the selected subject's details to the MATLAB command window. Right-clicking a row opens the protocol context menu (see [Working with protocols](#4-working-with-protocols)).

### 3.2 Toolbar

A toolbar under the menu bar gives one-click access to the most common menu actions. Hover any tool for its tooltip. From left to right:

- **Subjects** (person beside a list): opens the [Subjects & Projects](../gui/gui_SubjectManager.md) window, where you pick several animals at once and commit them to the session — same as **Subjects → Subjects & Projects...** (Ctrl+B). Available in every state, including during a run; it is the commit action inside it that refuses while a session is running.
- **Remove Subject** (person with a red minus): removes the selected subject (or clears the session if there is only one subject).
- **Reload Protocols** (circular arrow): reloads every subject's protocol from its `.eprot` on disk — same as **Subjects → Reload All Protocols from Disk** (Ctrl+R). The one-click "everyone onto the freshly saved file" after editing in the Protocol Designer.
- **Save Data** (arrow into a tray): invokes the configured saving function to write data to disk. Enabled only after **Stop**, or on an error.
- **Customize** (gear): opens the Customize Settings dialog — same as **Customize → Customize...** (Ctrl+U).
- **Protocol Designer** (document with pencil): opens the Protocol Designer — same as **Utilities → Protocol Designer...** (Ctrl+P).
- **Live View** (eye, toggle): opens or closes the display-only camera view described in [7) Menus reference](#7-menus-reference) — same as **Utilities → Video → Live Webcam View (No Recording)**. The tool stays pressed while a view is open. Usable during a session as well as between runs; it still refuses while a recording is in progress, because that recording's VLC window already shows the live stream.
- **Record video** (red dot, toggle): when pressed, clicking **Run** also starts a webcam recording via VLC for the duration of the session; released by default. The setting persists across sessions. Preview never records. **Toggling it during a running session takes effect immediately** — pressing it starts recording from that moment, releasing it stops and finalizes the file. See [5.1](#51-what-happens-when-you-click-run--preview) and [6) Customization](#6-customization).
- **Always On Top** (pushpin, toggle): keeps the session window above all other windows — same as **View → Always On Top** (Ctrl+T). The toggle and the menu item's check mark stay in sync whichever one you use.
- **Wiki** (open book): opens the EPsych wiki in your web browser.

The subject tools are disabled while a session is RUNNING, matching their menu items; **Save Data** is enabled only after Stop (or on Error). The two webcam toggles stay available in every state, including RUNNING — each one restarts VLC, which stalls the trial loop for about a second, so use them between trials where the timing matters.

### 3.3 Bottom control bar

- **Run**: starts the experiment in Record mode.
- **Preview**: starts the experiment in Preview mode; data are marked as a test run.
- **Pause**: requests a pause via the runtime ModeChange event.
- **Stop**: stops the timers, signals Stop mode, and transitions the GUI to a post-run state.

### 3.4 Status bar

A single-line status bar spans the bottom of the window, below the control bar. It reports what the program is doing and what normally comes next — subjects added or removed, protocol compilation, hardware connection, session start/stop, data saving, and webcam recording or live view. Messages are green; anything that failed is red. Double-click the status bar to copy its current text to the clipboard.

The state of the session itself is announced whenever it changes (Ready, Session running, Preview running, Session stopped, Session ended with an error); a message posted by a specific action stays up until the state changes again.

- **LIVE VIEW - NOT RECORDING** (amber text, right end of the status bar): shown only while a live webcam view is open (via either the toolbar's **Live View** toggle or **Utilities → Video → Live Webcam View (No Recording)**). It is a reminder that the VLC window on screen is *not* being saved to disk.

Custom behavior GUIs, saving functions, and trial selectors can post their own messages with `RunExpt.setStatus(message)` or `RunExpt.setStatus(message, nextStep)`.

## 4) Working with protocols

Right-click a subject row for these actions:

- **Edit Protocol...**: opens the protocol file in the Protocol Designer.
- **Update to Latest Version**: reloads the subject's protocol from its file on disk. Use this after saving edits in the Protocol Designer so the session uses the latest version. The GUI tells you whether the subject was already up to date.
- **Change Protocol File...**: assigns a different `*.eprot` file to the selected subject.
- **View Trials**: previews the compiled trials for the selected subject.
- **Edit Subject Details...**: edits the selected subject in place, mirroring changes back to the roster.
- **Show in Subject Manager**: opens the roster window with that subject selected.

Protocols are validated when loaded and again when you press **Run**/**Preview**. Validation errors are reported before the session starts; protocols that need compilation are compiled automatically at start.

> ⚠️ **Protocol edits are not picked up automatically.** The session holds the copy it loaded. After saving in the Protocol Designer, use **Update to Latest Version** on the row, or **Subjects → Reload All Protocols from Disk** (Ctrl+R) — the **Version** column flags stale rows but will not reload them for you.

## 5) Running, pausing, stopping, and saving data

If you need the underlying event model for GUI updates or runtime hooks, see [../epsych/Event_Notifications.md](../epsych/Event_Notifications.md).

### 5.1 What happens when you click Run / Preview

When you click **Run** or **Preview**, RunExpt:

- Raises MATLAB process priority (Windows) to reduce timing jitter.
- Resets the session runtime (a fresh `epsych.Runtime`).
- Validates each subject's protocol and compiles it if needed.
- Connects the hardware interfaces defined in the protocol (TDT, Intan, software, etc.). Hardware connections persist between runs within the same session, so a rerun does not reconnect from scratch.
- Creates a temporary data directory (a `DATA` folder next to the repository) with one crash-recovery `.mat` file per subject.
- Creates the trial timer (`PsychTimer`, default period 0.01 s; set per subject in **Session Settings...** (template: **Edit Project → Session Defaults**)).
- Sets the hardware mode to Record or Preview and starts the timer.
- Launches the behavior GUI if one is configured — the behavior GUI the committed subjects' memberships name (see **Subjects & Projects**), or the built-in `ep_GenericGUI` when none named one.

#### When an interface will not connect

A device that is switched off, unplugged, or on a COM port that renumbered no
longer ends the command outright. RunExpt reports the failure and asks what to
do, offering only what that backend actually supports:

- **Select Serial Port...** — for serial devices (currently the NE-1000 pump).
  Opens a picker listing every port with its availability, plus:
  - **Refresh**, which re-scans, so a device you power on or plug in *while the
    dialog is open* appears without restarting anything;
  - **Find Pump**, which queries each available port and selects the one the
    device answers on — this is what tells "wrong port" apart from "device is
    off". Choosing a port by hand also turns **Auto Detect** off for the
    session, so your choice is not overridden at connect.
- **Retry** — for anything you fixed at the rig itself (cable, power, a program
  holding the port open).
- **Continue Without It** — only for peripherals a session can run without
  (the reward pump). The run proceeds normally, but that device accepts no
  commands for its duration and reports its last known values. The choice
  lasts one run: the next Run/Preview tries to connect it again.
- **Cancel** — abandons the command, disconnecting anything it had already
  connected so the rig is not left half-live.

The port you choose here applies to the session, not to the protocol file. Fix
the port in **ProtocolDesigner** to make it stick.

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

By default, `ep_SaveDataFcn(RUNTIME)` saves each subject's trial data without prompting, to the filename the session is already carrying (`RUNTIME.TRIALS(i).DataFilename` — the name seeded at **Run** and edited during the session by the behavior GUI's filename field, `gui.FilenameValidator`). Missing folders are created, and a `.mat` extension is added if the name lacks one.

Each save is reported in the command window with the full path as a hyperlink; clicking it loads that file into a base workspace variable named after the subject (`Data_<Subject>`), so the session's data is one click away from the prompt. A **Preview** run writes no data file — the filename field says as much while the preview runs — and a subject with no completed trials is skipped. If a save fails, the message names the crash-recovery `.mat` in the temporary data directory, which already holds every completed trial.


> 🔑 **Trials are journalled as they complete — a crash costs at most the trial in progress.** The `.epj` is merged into the `.mat` at **Stop**; after a crash, `epsych.TrialJournal.recover` does the merge. **Save Data** is still what produces the final file, and it only enables after **Stop**.

During the session, each trial is also appended to a per-subject crash-recovery journal (`RUNTIME_DATA_<name>_Box_<nn>_<timestamp>.epj`) in the temporary data directory, so at most the in-progress trial is lost if the computer fails mid-session. The journal is merged into the matching `.mat` when the session stops; after a crash, `epsych.TrialJournal.recover` does the same. See [epsych.TrialJournal](../epsych/epsych_TrialJournal.md).

## 6) Customization

Settings are split by **what owns them**. This dialog — **Customize → Customize...** — holds what describes *this machine*; everything a *paradigm* decides rides each subject's roster **membership**, stamped from the project's **Session Defaults (template)** when the subject joins, and is applied to the session when subjects are added — so a rig alternating between two studies follows the animals it is running rather than needing to be re-pointed by hand between sessions.

> 🔑 **Settings are split by who owns them: the rig or the paradigm.** **Customize** describes *this machine*. The **membership** carries what the paradigm decides — stamped from the project template, edited per subject with **Session Settings...** — and applies it when its subject is added. Two invariants hold on the membership side: an empty field inherits the built-in default, and nothing is written back to the machine's preferences.

### 6.1 Machine settings — Customize → Customize...

Values are stored in MATLAB preferences.

| Setting | Purpose | Default |
| --- | --- | --- |
| Add Subject Function | Dialog used by **New Subject...** and **Edit Subject Details...**. | `epsych.DefaultSubject.open` |
| Data Save Path | The rig's default data root: used when no membership overrides it, and the value a new project starts from. | current directory |
| Error Log Path | Directory the daily EPsych error log is written to. **Must be an absolute path.** Leave empty for the default. | `<EPsych root>\.error_logs` |
| Error Log Viewer | Application used by **Help → Open Current Error Log (External Viewer)**. Leave empty for the platform default. | `notepad.exe` (Windows) |
| Subject Roster File | The `.esub` roster behind **Subjects & Projects**. Put it on a shared drive and point every rig at it to share one roster. **There is no default:** left empty, Subjects & Projects asks for a location before it saves anything. | — |

The Functions and Paths tabs each keep a grey line where the moved fields were, naming where they went.

### 6.2 Session settings — the membership, and its project template

Each of these is applied to the live session by `epsych.SubjectRoster.assignToSession`, from the committed subjects' memberships, and only when the membership names it: an empty field means "inherit the built-in default". Templates and memberships written through the manager's dialogs are never partly empty — every field arrives pre-filled and OK refuses blanks — so an empty field in practice means a roster written by a script or before these fields existed. Nothing here is written back to the machine's preferences, and a multi-subject commit is refused when the checked memberships disagree (see [Subjects & Projects](../gui/gui_SubjectManager.md#add-checked-to-session)).

| Setting | Purpose | Built-in default |
| --- | --- | --- |
| Default Protocol | (Template only.) `.eprot` applied to a member with no protocol of its own. The one field that may stay empty: a study often exists before its protocol does. | — |
| Data Save Path | Root this subject's data is written under, `<path>\<subject>\`. | the rig's Data Save Path |
| Saving Function | Called to save data after Stop/Error. Signature: `SavingFcn(RUNTIME)` (1 input, 0 outputs). | `ep_SaveDataFcn` |
| Behavior GUI | Behavior GUI launched at run start, `feval(BehaviorGUI, RUNTIME)`. `(none)` runs none; `(built-in default)` inherits. | `ep_GenericGUI` |
| Timer Period (s) | PsychTimer callback period (0.001–1 s). | 0.01 |
| Timer Start/RunTime/Stop/Error Fcn | The PsychTimer lifecycle callbacks — the trial loop itself. A lab's custom loop names them on the template so the paradigm travels with the study. | `ep_TimerFcn_*` |
| Video Recording Path | Root for webcam recordings made with the **Record video** toolbar toggle. Files are saved to `<root>\<subject>\<subject>_<yyMMddTHHmmss>.ts`, named after the behavioral data file whether the recording starts with the run or is switched on mid-session. Stopping and restarting recording within one session appends `-2`, `-3`, … to the later segments so nothing is overwritten. Falls back to the Data Save Path when unset. | — |
| Intan Recording Path | Root for Intan RHX recordings when an `hw.Intan_RHX` interface is in the protocol. Files save under `<root>\<subject>\` named after the data file (RHX appends its own `_<timestamp>`). **Must contain no spaces.** Falls back to the Data Save Path when unset. | — |
| Intan Settings File | RHX `.xml` settings file loaded when the Intan interface connects. **Must contain no spaces.** A protocol that names its own wins over this; leave empty to load none. | — |

A membership can set no behavior GUI at all (`(none)`); the session still runs, you just will not get a live performance GUI.

The webcam device itself (camera, frame rate, resolution, crop) is configured separately in **Utilities → Video → Webcam Recorder Setup...**.

The recording paths in force for a session live on `RunExpt.PATHS`, seeded from the per-machine `ep_RunExpt_Video` / `ep_RunExpt_Intan` preference groups and overwritten by the committed memberships. They are applied to every `hw.Intan_RHX` interface at run time. RHX names its files with a mandatory `_<timestamp>` suffix, so the Intan `.rhd`/`.rhs`, the behavioral `.mat`, and the webcam `.ts` are paired by shared filename prefix rather than exact equality.

## 7) Menus reference

- **Subjects**: everything about who is in the session and who exists in the lab.
  - Subjects & Projects... (`Ctrl+B`) — the [subject manager](../gui/gui_SubjectManager.md). Available in every state, including during a run, so an animal's notes stay readable mid-session.
  - Remove Selected Subject — takes the selected row out of the session; the roster is untouched.
  - Reload All Protocols from Disk (`Ctrl+R`) — reloads every subject's protocol object from its `.eprot`, reporting how many were updated, already latest, or failed.
  - Roster File... — chooses the `.esub` roster this rig uses. Point several rigs at one file on a shared drive to share a roster. There is no default location and no fallback: until this is answered once — here, or when Subjects & Projects asks at the first project — the rig has no roster.
- **Customize**: Customize... (the machine settings in [6.1](#61-machine-settings--customize--customize)).
- **Utilities**: the standalone tools that ship with the toolbox, opened from the session window instead of the command line. Each opens its own window with its own lifecycle; RunExpt keeps no handle on it, and a tool that fails to open reports on the status bar rather than interrupting the session.
  - **Designers...** (submenu) — the tools for authoring, rather than just running, an experiment:
    - Protocol Designer... (`Ctrl+P`) — opens an empty designer for building a new protocol (`epsych.ProtocolDesigner`). To edit the protocol a subject is already using, right-click that subject instead (see [Working with protocols](#4-working-with-protocols)). See [../design/ProtocolDesigner_UserGuide.md](../design/ProtocolDesigner_UserGuide.md).
    - Teensy Trial Designer... — builds and simulates the state table a Teensy board executes (`teensy.TrialDesigner`); see [../teensy/teensy_TrialDesigner_UserGuide.md](../teensy/teensy_TrialDesigner_UserGuide.md).
    - Behavior GUI Builder... — generates a `gui.BehaviorGUI` subclass from a loaded protocol by dragging components onto a snap-to-grid canvas, for building a custom session GUI without hand-writing MATLAB (`gui.BehaviorBuilder`); see [../gui/gui_BehaviorBuilder.md](../gui/gui_BehaviorBuilder.md).
  - Stimulus Player... — builds a bank of stimuli and previews them through the sound card (`stimgen.StimPlayer`). It opens offline, unattached to the session's hardware.
  - Stimulus Inspector... — examines a single stimulus waveform and spectrum (`stimgen.StimInspector`).
  - Calibration GUI... — the speaker calibration GUI wired to EPsych hardware via `epsych.calibrate`; disabled while a session is RUNNING because calibration drives the hardware into Preview. See [../../obj/stimgen/documentation/stimgen_calibration.md](../../obj/stimgen/documentation/stimgen_calibration.md).
  - **Peripherals...** (submenu) — peripheral hardware GUIs that aren't video:
    - Commutator GUI (`Ctrl+G`) — motorized commutator control; see [../peripherals/peripherals_NanoMotorControl.md](../peripherals/peripherals_NanoMotorControl.md).
  - **Video** (submenu) — everything that touches the camera or its recordings:
    - Webcam Recorder Setup... (`Ctrl+W`) — camera, frame rate, resolution, crop; see [../gui/VlcRecorderSetup.md](../gui/VlcRecorderSetup.md).
    - **Live Webcam View (No Recording)** opens a VLC window showing the camera with the same device, frame rate, resolution, and crop a recording would use, but writes nothing to disk — useful for aiming the camera or checking on a subject. The VLC window carries a yellow **LIVE VIEW - NOT RECORDING** overlay and window title, and the status bar shows a matching amber banner at its right end. Select it again to close the view.
      - The item is available during a session as well as between runs. Opening or closing the view restarts VLC, which stalls the trial loop for about a second (up to eight when closing), so prefer to do it between trials. A view opened before **Run** stays open through a session; if that session is recording, the recording takes over the camera and the live view closes. The item refuses while a recording is in progress, since that recording's own window already shows the stream.
    - **Batch Video Converter...** — converts recordings already on disk to another format with ffmpeg (`util.VideoConverter` through `gui.VideoConverterSetup`). It opens on the session's **Video Recording Path** — the membership's, else this machine's (the Data Save Path when neither is set) with the file pattern set to the `.ts` files the recorder writes; both, and every encoding option, are editable in the window. The converter only reads and writes files, so it stays available while a session is running — though an encode competes with the session for CPU. See [../util/VideoConverter.md](../util/VideoConverter.md).
- **View**:
  - Always On Top (also available as the pushpin toolbar toggle).
  - Version Info (`Ctrl+I`) — toolbox version, git commit, and links. A **Worktree** row appears when the session is running from a git worktree rather than the main checkout; the worktree name is also appended to the window title, in brackets, and saved with the session metadata.
- **Help**:
  - Open Current Error Log — flushes the logger and opens today's EPsych error log file, creating it if nothing has been logged yet. The file opens through the operating system's `.txt` association.
  - Open Current Error Log (External Viewer) — the same file, handed to the application named in **Customize → Paths → Error Log Viewer** (`notepad.exe` by default on Windows). Use this on machines where MATLAB owns the `.txt` association and the item above would put the log in the MATLAB editor. The log's location follows **Customize → Paths → Error Log Path**.
  - Run Self-Test... (`Ctrl+D`) — pre-flight checks against the loaded session: protocol compilation, required trigger parameters, trial selection, data paths, hardware, and GUI wiring. Each check reports pass/fail with what to do about it. See [RunExpt_SelfTest.md](RunExpt_SelfTest.md).
  - Parameter Debugger... (`Ctrl+E`) — every parameter the loaded protocol defines, in one table, with a Read All button, a per-parameter read on double-clicking its name, and an editable Value column for the writable ones. Colour on the value says whether the read came back, whether a write was confirmed, and whether the backend was even connected. Like the self-test it stays available while a session is running, and it reads nothing on its own, so having it open changes nothing. See [../gui/gui_ParameterDebugger.md](../gui/gui_ParameterDebugger.md).
  - Assign RUNTIME to Command Window — exports the live `RUNTIME` object to the base workspace for inspection (enabled while hardware is active).
  - Verbosity... — sets how much detail EPsych prints to the command window. Everything at or below the chosen level is also written to the daily log; see [../eplog/eplog_Logging.md](../eplog/eplog_Logging.md).
  - **Example Experiments** (submenu) — one item per walkthrough under [../../examples/](../../examples/): **Your First Experiment...** and **Two-AFC Task...**. Each opens that walkthrough's wiki page in the default browser, the same way **Documentation** does; the page's Quick Start section holds the MATLAB commands that actually run it. The menu deliberately links rather than launches, because running an example starts an interactive session — you are the subject, clicking through trials — rather than opening a self-contained window.
  - GitHub Repository / Documentation / Commit History Overview — online resources.
  - Report an Issue on GitHub... — composes a bug report for the repository's issue tracker and shows it for review before anything opens. The version, commit, MATLAB release, host, and this session's state, subjects, interfaces, and callbacks are filled in for you, along with the tail of the day's error log; both sections are editable and the log excerpt can be dropped entirely, because the tracker is public and a log line can name a subject or a data path. Pressing **Open Issue** opens GitHub's bug-report form with those sections already filled in, puts the full log on the clipboard, and shows the log file in the file browser so it can be dragged onto the issue as an attachment. See [../epsych/RunExpt_ReportIssue.md](../epsych/RunExpt_ReportIssue.md).
  - Request a Feature on GitHub... — opens the repository's feature-request form in the default browser. No preview, because the only thing prefilled is a version line: the version, commit, and MATLAB release, with none of the session's paths, subject names, or log lines. Requests about stimulus generation belong in [dstolz/stimgen](https://github.com/dstolz/stimgen/issues) instead, whose code is a pinned submodule here.

## 8) Keyboard shortcuts

In the RunExpt figure:

- `Ctrl+0` … `Ctrl+4` set the global message verbosity level.
- Menu accelerators are shown next to each menu item (for example `Ctrl+U` opens the Customize dialog).

## 9) Notes and common gotchas

> ⚠️ **The four that bite most often:** protocol edits are not reloaded automatically; **Save Data** enables only after **Stop**; the hardware backend comes from the protocol, not from this window; and closing the GUI mid-run stops the session. **Help → Run Self-Test...** catches most of them before a session starts.

- **Button enabling/disabling is state-driven**: Add/Remove/Edit actions are disabled while the experiment is running.
- **Subject names must be unique** within a session; adding a duplicate name will be rejected.
- **Data saving is intentionally post-run** by default: the Save Data button is enabled after Stop (and on Error).
- **Hardware comes from the protocol**: which backend is used (TDT Synapse, TDT RPvds, Intan, software-only) is defined in the protocol file, not chosen in RunExpt. If hardware fails to connect, check the protocol's interface configuration and the device, then try again.
- **Protocol edits are not picked up automatically**: after editing a protocol in the Protocol Designer, use **Update to Latest Version** on the row (or **Subjects → Reload All Protocols from Disk**, Ctrl+R) so the session loads the new version.
- **Closing the GUI stops the session**: closing while running prompts first, then stops the timers, releases the hardware, and cleans up.
- **Check before you run**: **Help → Run Self-Test...** catches most of the above — a missing protocol trigger, an unwritable data path, a stale protocol version — before a session starts rather than partway through one.

## Related documentation

- [RunExpt_SelfTest.md](RunExpt_SelfTest.md) — pre-flight checks for a session
- [../design/ProtocolDesigner_UserGuide.md](../design/ProtocolDesigner_UserGuide.md) — building the protocols this GUI runs
- [../epsych/Event_Notifications.md](../epsych/Event_Notifications.md) — runtime event model (for GUI/analysis developers)
- [Architecture_Overview.md](Architecture_Overview.md) — internals (for developers)
