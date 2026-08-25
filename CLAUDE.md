# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**EPsych v2** is a MATLAB toolbox for designing and running behavioral experiments, with support for Tucker-Davis Technologies (TDT) hardware, electrophysiology recording, stimulus generation, and real-time analysis. The project combines legacy procedural code, GUIDE-era GUIs, and newer object-oriented runtime components—it is not a greenfield framework but an evolved, actively-used laboratory tool.

### Key Facts

- **Language**: MATLAB R2024b (supports R2014b+)
- **Available Toolboxes**: Audio, Curve Fitting, DSP System, Global Optimization, Image Acquisition, Image Processing, Optimization, Parallel Computing, Signal Processing, Statistics and Machine Learning
- **Architecture**: Mixed procedural/OOP with newer APIs in obj/+epsych/, obj/+hw/, obj/+gui/, obj/+psychophysics/, and the obj/stimgen/ submodule
- **License**: GNU GPL v3.0
- **Author**: Daniel Stolzberg, PhD

## Quick Start Commands

### Setup

```bash
# Clone with submodules (stimgen lives in a separate repo)
git clone --recurse-submodules https://github.com/dstolz/epsych2.git
# For an existing clone:
git submodule update --init --recursive
```

```matlab
% Add repository to MATLAB path (run once after opening MATLAB)
addpath('C:\path\to\epsych2')
epsych_startup
```

### Main Entry Points

```matlab
% Main session GUI
epsych.RunExpt

% Protocol design GUI
epsych.ProtocolDesigner

% Stimulus player
stimgen.StimPlayer

% Speaker calibration GUI, wired to EPsych hardware via stimbridge
epsych.calibrate

% View repository information
E = EPsychInfo;
disp(E.meta)
```

### Testing & Validation
EPsych does not have a formal automated test suite. Manual validation is performed via:
- **Smoke tests** in 	mp/ directory (e.g., smoke_test_stimplayer_standalone.m)
- Protocol validation through epsych.Protocol.validate() method
- Trial preview via RunExpt GUI's "View Trials" button before running experiments

#### Running MATLAB through the MCP server

The MathWorks `matlab-mcp-server` is registered for this project and is the preferred way to
lint and run code: it holds **one persistent MATLAB session**, so the engine starts once
(~7.5 s) instead of paying `matlab -batch`'s 20-60 s startup on every invocation. Tools:
`check_matlab_code` (Code Analyzer, read-only), `run_matlab_file`, `evaluate_matlab_code`,
`detect_matlab_toolboxes`, `run_matlab_test_file` (unused - there is no `matlab.unittest`
suite here). All tool arguments must be **absolute paths**.

`--initial-working-folder` is configured to the repo root but does **not** take effect - MATLAB
starts in whatever `userpath` is set to for the logged-in user (verified: `C:\Users\dstolz\My
Drive\temp_analysis` on this workstation, `C:\Users\caraslab\Documents\MATLAB` on the rig), the
same quirk that makes `-batch` ignore `-sd`. Never assume a relative path resolves or that the
fallback folder is the same on two machines: pass absolute `script_path`
values, and pass `project_path` to `evaluate_matlab_code` when the code needs the repo as cwd.
Repo scripts that bootstrap themselves off `mfilename` (as `tmp/smoke_test_*.m` do) are
unaffected.

Rules that matter:

- **One session is shared by every call, and concurrent calls interleave in it.** Two
  `run_matlab_file` calls issued together execute against the same base workspace. Run
  dependent checks one at a time.
- **Never `clear`, `close all`, or `delete(timerfindall)`** when the server is attached to a
  live session (`--matlab-session-mode=existing`) - it destroys running experiment state.
- **Restart the MATLAB session after any COM/ActiveX work.** MATLAB caches one COM wrapper
  class per CLSID per session, so an `actxcontrol` call poisons every later `actxserver` use
  of the same class. Each `-batch` exit used to reset that; a persistent session does not.
  This is the one hazard the persistent model adds.
- `actxcontrol` still hard-crashes MATLAB when there is no display, and the server runs
  `--matlab-display-mode=nodesktop`.
- `matlab -batch` remains the fallback when the server is unavailable, and is still required
  for `exportapp` GUI screenshot capture.

## Architecture & Key Components

### High-Level Flow: From Protocol to Runtime

1. **Protocol Design**: User creates experiment via epsych.ProtocolDesigner GUI, defines hardware interfaces, parameters, and trial options, saves as .eprot file
2. **Session assembly**: epsych.RunExpt commits subjects from the roster; each membership carries its protocol, box memory, and session settings
3. **Runtime Setup**: epsych.Runtime creates hardware connections, compiles trials, initializes event system
4. **Execution**: MATLAB timer fires callbacks: ep_TimerFcn_Start -> ep_TimerFcn_RunTime (repeated) -> ep_TimerFcn_Stop
5. **Data Saving**: Configurable save function persists session data

### Core Classes & Their Roles

#### obj/+epsych/ – Experiment Framework
- **epsych.RunExpt** (440 lines): Main session GUI; manages CONFIG (subject/protocol), RUNTIME state, and program transitions
- **epsych.Runtime** (120+ lines): Central state container; holds HW interfaces, TRIALS, EVENTS (event broadcaster), and TIMER
- **epsych.Protocol** (212 lines): Data model for experiment; owns hw.Interface objects, parameters, compiled trials
- **epsych.ProtocolDesigner** (326 lines): GUI for building protocols (~57 UI callbacks)
- **epsych.EventHub**: Lightweight event broadcaster (NewData, NewTrial, ModeChange)
- **epsych.TrialSelector** (abstract): Pluggable trial selection
- **epsych.BlockSequence**: block-randomized value sequence a trial selector indexes by
  trial number — an ITI, a hold duration, a level — where `hw.Parameter.isRandom` would
  redraw `randi([Min Max])` per dispatch, unbalanced and unrecoverable. A block is a
  shuffled permutation of `Values` with optional integer `Repeats`; `MaxConsecutive`,
  `NoRepeatAcrossBlocks`, and `Jitter` are all off by default because each distorts the
  sampling distribution and must be asked for. The **caller owns the index**, so the class
  holds no cursor and a rewind is exact: extension only ever appends, and jitter is baked
  at generation rather than drawn at read. Two things a reader would otherwise re-derive:
  a mid-session edit to `Values` **freezes what was already delivered** and regenerates
  only from the next whole block (a partial block is abandoned rather than spliced, since
  half-old/half-new would break balance silently), and a parameter driven from a
  BlockSequence **must have `isRandom = false`** or `set.Value` overwrites the drawn value
  on dispatch. `Seed` resolves eagerly and never touches the global stream, so it can be
  recorded and replayed. Its first consumer is `cl_AppetitiveStimDetect`'s
  stimulus delay, which is also where the practical traps are written down:
  the list ends live on `StimDelayList.Min/.Max` but the STEP needs its own
  parameter (`hw.Parameter` clamps `Value` into `[Min Max]` and
  `gui.Parameter_Control` limits the edit field to the same range, so a 250 ms
  step in a 1000-4000 ms list silently becomes 1000); a repeat-on-abort is a
  held index rather than a stashed value; and anything ELSE that drives the
  same parameter — `gui.StaircaseTraining` in training mode — has to make the
  sequence stand down, since suspending `isRandom` does not stop a selector
  (see documentation/epsych/epsych_BlockSequence.md,
  documentation/paradigms/cl_AppetitiveStimDetect.md)
- **epsych.SelfTest**: Headless pre-flight diagnostics for a RunExpt session (9 check groups); GUI in obj/+gui/@SelfTest/
- **epsych.BitMask**: uint32 enumeration for trial outcomes
- **epsych.SubjectRoster**: shared, file-backed roster of subjects organized by
  project (many-to-many, with a per-project active/retired flag and per-membership
  protocol memory). Three flat arrays plus a join table in a `-mat` `.esub` file —
  MAT not JSON because `jsonencode(NaN)` would destroy the "not measured" `Weight`.
  **There is no default file location and no fallback.** `configuredFile`
  returns `''` until an operator names one, and a roster with no path is
  *unbound*: empty, `IsBound` false, `IsWritable` false, and `mutate_` throws
  `epsych:SubjectRoster:NoFile` — it throws rather than returning false because
  the CRUD methods mint an ID and report success without consulting that return.
  Until 2026-08-14 it fell back to `<prefdir>/epsych/subjects.esub`, which put a
  lab's only copy somewhere release-specific (silently empty after a MATLAB
  upgrade) that nobody chose. `setConfiguredFile` validates at the
  moment of choosing (absolute-izes, refuses a folder, appends `.esub`, makes
  the parent) rather than at the first save.
  The **MEMBERSHIP carries the session settings a paradigm decides**
  (`SESSION_FIELDS`: `DefaultDataPath`, `SavingFcn`, `BehaviorGUI`,
  `TimerPeriod`, the four `Timer*Fcn` PsychTimer callbacks, and the recording
  roots): selecting a subject selects all config required to run it. The
  project's Session Defaults are a **template**, stamped verbatim at `assign`
  (and in `copyProject`'s member copies — from the NEW project's template,
  never the source memberships); later template edits reach existing members
  only through `reapplyTemplate`, and one subject diverges with
  `updateMembership`. `assignToSession` resolves the planned subjects'
  memberships before any side effect and **refuses the batch when they
  disagree** on a session-level field (`report.aborted` + machine-readable
  `report.mismatch`; the manager's Settings column shows `template`/`edited`
  so the refusal is predictable). The agreed membership lands on the session:
  `BehaviorGUI` → `FUNCS.BehaviorGUI`, `SavingFcn` → `FUNCS.SavingFcn`,
  `Timer*Fcn` → `FUNCS.TIMERfcn.*`, `TimerPeriod` → `FUNCS.TimerPeriod`,
  `DefaultDataPath` → `RunExpt.DefaultDataPath`, and the recording roots →
  `RunExpt.PATHS` (a session-level struct seeded from the `ep_RunExpt_Video`/
  `ep_RunExpt_Intan` prefs, which exists so a study can override a recording
  root for ONE session — the readers used to `getpref` at the point of use).
  Two rules: **empty means inherit the BUILT-IN default** (`NaN` for
  `TimerPeriod`; there is no rig-pref floor under the callbacks anymore —
  `GetDefaultFuncs` returns literals, and only `AddSubjectFcn` keeps a pref),
  which is the only reading an older roster can have, and **nothing is written
  back to the preferences** — closing the session persists nothing.
  `BehaviorGUI` has a third state: `BEHAVIORGUI_NONE` runs no GUI. These fields were
  RunExpt's Customize dialog until they moved here; what stayed there describes
  the machine (log path/viewer, roster file, add-subject
  function, the rig's default data path). The dialogs (shared grid:
  `gui.SubjectManager.sessionDefaultsGrid_`, `ProjectDlg_*` vs `MembershipDlg_*`
  tags) fill every session default in before the operator sees it — from a
  per-field MRU under `ep_RunExpt_Subjects/Recent<Field>`, else the built-in —
  and refuse a blank one, so "empty" in practice means an old roster or a
  scripted project. When two memberships must converge, the fixes are the
  Subject menu's Session Settings... and the Project menu's Re-apply Project
  Template to Checked.
  A project also carries its own bookkeeping: `Investigator` and `IACUCProtocol`
  (recorded, never enforced), an `Archived` flag that hides the project from the
  manager's list without touching its subjects or their protocol memory, and
  `Links` — a `Label`/`URL` array for the study's notebook, sheet, or NAS folder.
  Link addresses go through `isSafeUrl`, which allows only `http`/`https`/
  `mailto`/`file` (plus local and UNC paths, normalized to `file:///`) and
  refuses everything else: a roster is a **shared** file, so `matlab:` in one
  would make an `.esub` executable on every rig that clicks it. Validation is on
  the way in only — `reload` deliberately does not validate, or one typo would
  make the roster unreadable for the lab — with `openLink` re-checking at the
  click. Adding a project field means `blankProject_` + `addProject` +
  `updateProject`'s field list (which coerces with `char(string(...))`, so a
  non-char field needs its own branch) + `copyProject`'s carry list;
  `normalize_` handles old files, so
  **every default must mean what a file written before the field meant**.
  `copyProject` clones a project's whole configuration for the study that
  follows it, delegating every validation to `addProject` rather than
  re-implementing it. Its override options carry **no `arguments` defaults**,
  so "not stated" (follow the source) stays distinguishable from "stated as
  empty" — that is what lets the GUI show the copy in the edit dialog first.
  Three deliberate exclusions: `Archived` (a copy is made to start work),
  subjects unless `IncludeSubjects` (a new cohort and a second phase want
  opposite things), and `ProtocolHistory` even when `CopyProtocolMemory` is on
  (a membership created a moment ago has no way it was). Retired members stay
  behind unless `IncludeRetired`. The project is written first and the
  memberships second, so an interrupted copy leaves an empty project — the
  recoverable half, since "Add to Project" can finish it.
  Roster records carry **no BoxID**: a box belongs to a session, so `toSubject`
  materializes an `epsych.Subject` at assignment time, which is why `epsych.Subject`
  needs no subclassing. Every mutation goes through `mutate_` (reload-if-stale →
  apply → atomic temp+`movefile` write), which is what lets two rigs share one file
  on a network drive. `assignToSession` is the batch commit into `RunExpt.CONFIG`,
  all-or-nothing on a bad protocol or box exhaustion. `ReplaceExisting` (which the
  manager's button passes, and a script does not) makes the batch the session's
  WHOLE subject list: the clear happens after every refusal check and after every
  protocol has loaded, so an aborted batch leaves the session intact, and the
  outgoing subjects' boxes and names are not "taken" — otherwise re-ticking an
  animal already in the session would skip as a duplicate and commit nothing.
  `epsych.RunExpt.ClearConfig` moved out of the private block into the
  `?epsych.SubjectRoster` one for it. Renaming a subject is refused
  once `<DataPath>/<Name>/` exists, because nothing downstream knows about
  `NameHistory`.
  **Protocol versions**: a membership records `LastProtocolVersion` alongside the
  path, because a subject carries no version of its own — the roster is the only
  thing that can notice a protocol edited between sessions. `protocolStatus`
  reports `current|outdated|pinned|differs|unknown|missing|none` (`outdated` =
  the file moved on; `differs` = not the project default), `updateProtocol`
  records the version now in the file, and `revertProtocol` restores an entry from
  `ProtocolHistory`. Every `Protocol.save` archives the version it replaces
  INSIDE the `.eprot` (four MAT variables: `protocol` unchanged, `history`,
  `historyIndex`, `historyFormat`; `epsych.Protocol.writeProtocolFile` is the
  one writer, atomic, shared with phase saves so they cannot drop the archive;
  `listVersions`/`hasVersion`/`loadVersion`/`restoreVersion` read it), so revert
  reports `Source = disk|archive|none`: `disk` re-points exactly, `archive`
  restores bytes too when asked (`RestoreContent=true`, exact mode, default OFF
  because the file is shared — `OthersOnFile` says who else it changes), `none`
  = a file last saved pre-archiving, pointer-and-version only.
  An `archive` revert that does NOT rewrite the file **pins** the membership
  (`ProtocolPinned`), and `assignToSession` then loads that version out of the
  archive (`loadVersion`) instead of the file's content — so the subject runs
  what was restored while the shared file keeps serving everyone else. That is
  what makes such a revert mean anything: before it, the session loaded the file
  and `rememberProtocol` wrote the file's version straight back over the revert,
  so ADDING THE SUBJECT TO A SESSION SILENTLY UNDID IT. Three rules keep it
  coherent — a pin is set only where the file disagrees and the content is still
  reachable; `rememberProtocol` clears it whenever the file or version it records
  differs from what is on record (honouring a hold hands back the pinned version,
  so only a move forward ends it); and a hold whose version has left the archive
  ABORTS the batch rather than quietly running the file. `pinned` is kept out of
  `IsOutdated`, the manager's banner, and Update All — it is deliberate, not a
  problem — and `RunExpt.UpdateSubjectList` infers it with no new CONFIG field
  (`Protocol.load` always yields current content, so loaded ≠ disk but present in
  the archive can only be a honoured hold), showing `vN (held)` unflagged. Version reads go
  through `epsych.Protocol.versionOnDisk`/`versionNumber`, shared with
  `RunExpt.UpdateSubjectList` — both selectively load the one MAT variable, as
  does the phase fast parse, so the archive costs readers nothing; minting
  reconciles with the disk (`max(memory, disk) + 1`) so two stale objects
  cannot coin one version for different content. **What changed** between two
  versions is `epsych.Protocol.compareVersions`/`diffStructs`, reading the stored
  `toStruct` payloads and never rebuilding the object graph — cheap enough for a
  dialog's selection change, and able to compare a version naming a backend class
  this installation cannot construct. It takes a file AND a version PER SIDE, so
  a subject's history compares across the two FILES a protocol revised under a
  new name leaves behind. `lastModified` is excluded (every save rewrites it, so
  it would appear in every comparison saying nothing) and `protocolVersion`
  always is (it is the identity of the sides, not a difference between them);
  matching is by name, so a rename reads as one add and one remove, because
  nothing in the file records otherwise. It never throws — every caller is a
  dialog that has to say why instead. `gui.compareProtocolVersions` is the one
  window over it, modal because both callers (the designer's Version History,
  the Subjects window's Revert Protocol) open it from a modal dialog of their
  own, where an ordinary window would be stranded behind its parent.
  Roster fields stay additive,
  so `FORMAT_VERSION` stays 1; standing proof
  `tmp/smoke_test_protocol_versioning.m`
  (see documentation/epsych/epsych_SubjectRoster.md,
  documentation/epsych/epsych_Protocol.md)
- **epsych.TrialJournal**: append-only, crash-safe `.epj` journal that per-trial data
  is written to during a run (flat ~2 ms, versus a `save('-append')` that grew to
  40 ms by trial 600). `ep_TimerFcn_Stop` merges it back into the seed `.mat`, so the
  recovery artifact keeps its `info + data_NNNN` layout; `TrialJournal.recover`
  rebuilds it after a crash. Durability is guarded by a hard-kill harness, not a
  throughput benchmark — run `tmp/crash_test_trialjournal.m` after any change to it
  (see documentation/epsych/epsych_TrialJournal.md)
- **epsych.SessionNotes**: the operator's typed notes for one session, always
  present as `RUNTIME.NOTES` so no caller has to test for it. A note is one line
  stamped with the COMPLETED trial count (0 before the first trial, and the
  furthest-along subject for a session-wide note on a multi-box rig) — the trial
  index is the axis the data is already on, where a wall clock has to be
  reconciled with the session's start first. Notes are session-wide by default
  (one behavior GUI per session, not per subject) and written into every
  subject's file; `Subject=i` tags one animal and is then filtered into that
  file alone. Two things make them durable, and neither costs a saving function
  an edit: `epsych.SessionSnapshot.withNotes` — called by `forSubject`, NOT by
  `capture`, since notes are typed long after the start-of-session snapshot is
  frozen — folds `Notes`/`NotesText`/`NotesEdited` into the `Info` every saving
  function already writes; and every commit rewrites the WHOLE log into each
  subject's journal under one record name (`notes`), which the journal reader
  resolves last-wins, so a crash leaves the newest complete log rather than
  fragments. **Hand-edited text wins**: `setText` stores the operator's text
  verbatim and re-parses `Records` from it, a line whose stamp is gone parsing
  as `Trial = NaN` rather than being dropped, and `NotesEdited` is what tells a
  later reader which of the two is the operator's own. `fromSnapshot` rebuilds
  a store from a saved file for `epsych.ReviewSession`, deliberately unbound to
  a runtime — a review has no journal to write and no trial to stamp with
  (see documentation/gui/gui_Notes.md)
- **epsych.ReviewSession** + **epsych.SessionSnapshot** + **hw.Replay**: offline
  session review — reopen a finished session in the paradigm's own
  `gui.BehaviorGUI`, every display showing what it showed when the session ended,
  with a `gui.ReviewTransport` scrubber. **No display component was modified**,
  because three things already held: `epsych.EventHub` declares its events
  `NotifyAccess = 'public'`; every consumer takes the WHOLE `DATA` array out of the
  payload and recomputes (`Psych.update_data` assigns `obj.DATA = event.Data.DATA`),
  so one notify carrying `Data(1:k)` is worth k notifies and seeking BACKWARD costs
  what seeking forward costs; and `gui.Parameter_Control` already greys out on an
  interface `mode` of `Idle`. The runtime is therefore a REAL `epsych.Runtime` with a
  real `EventHub`, not a fake — required rather than tidy, since
  `psychophysics.Detection` is not a `Psych` subclass and has no struct-source path.
  Things a reader would otherwise re-derive: `hw.Replay` reports
  `IsConnected = true` **on purpose**, because `get.Value` short-circuits to the
  cached DESIGN-TIME value for an `hw.Software` parent or a disconnected one, and
  reporting connected is what routes the read into `get_parameter`; it never assigns
  `Value` (that would run `randomize_value`/`Expression`/`clamp_value_` over the very
  numbers being reviewed, and throw on a read-only parameter), so its design-time
  fallback is read from the struct — asking the parameter would recurse; the
  interfaces go `Standby → Idle` only AFTER `build` returns, since `mode` is
  `AbortSet` and a control built at `Idle` would never see the transition; and
  `Runtime.ReviewMode` suppresses the one-shot dispatch in `set.TRIALS`, which would
  otherwise write every parameter and fire the hardware triggers. The constructor
  runs `seek(NumTrials, Notify=false)` **before** launching the GUI, because two
  components read state at construction rather than waiting for an event:
  `gui.Parameter_Control` seats once and then waits for a `PostSet` a review never
  fires (so it must seat from the trial the session ENDED on, not the design-time
  value), and `gui.NextTrial.seedFromRuntime_` indexes the trial table with
  `NextTrialID` — empty there yields zero elements and throws. Monitors and the
  debugger poll, so those DO follow the scrubber; the controls deliberately do not. Every window a
  review opens **anchors it** in appdata (`epsych_ReviewSession`) — load-bearing,
  not tidiness: the no-output call ends in `clear obj`, and an unanchored handle
  object is deleted the moment the constructor returns, closing the windows it
  just opened (it survived by accident only while a transport was open). The snapshot is
  captured by `ep_TimerFcn_Start` (so the crash-recovery file is reviewable too) onto
  `TRIALS(i).SessionInfo`, and **any** saving function writes it with one line —
  `Info = epsych.SessionSnapshot.forSubject(RUNTIME,i)`. It **blanks buffer
  CONTENTS** (`Buffer`/`Coefficient Buffer`), keeping the metadata: `toStruct`
  serializes `Values` AND `Value`, and one 131072-sample calibration buffer measured
  245x the whole rest of the protocol — 16 MB into every session `.mat` and every
  `.epj` info record. Nothing is lost that a review can show, which is why
  `gui.ParameterDebugger` already refuses to read those two types. A file with no snapshot still
  opens: `addControl` already skips parameters it cannot resolve, so the data
  displays work and the controls are absent (`IsDegraded` says so). A GUI that DRIVES
  the rig must stand down on `gui.BehaviorGUI.ReviewMode` — the base class cannot
  tell display from contingency (see documentation/epsych/epsych_ReviewSession.md)
- **Phase loading**: `Runtime.phaseParameterData` is the single chokepoint for reading a
  phase (.eprot) file. It reads the saved `hw.Parameter.toStruct` entries straight out of
  the MAT file — the file already holds exactly what it returns — and falls back to the
  full `epsych.Protocol.load` reconstruction whenever the shape is not recognized in full.
  Results are memoized by `Runtime.phaseCache` on path+mtime+size. Both are transparent:
  `FastParse=false`, `UseCache=false`, and `phaseCache('clear'|'disable')` restore the
  original behavior, and `tmp/smoke_test_phase_fastparse.m` is the standing equivalence proof
- **PRGMSTATE** (top-level class in obj/PRGMSTATE.m): Session state enumeration

#### obj/+hw/ – Hardware Abstraction Layer
- **hw.Interface** (abstract base): Uniform API for all backends (connect, disconnect, get/set parameter, trigger).
  A failed connect at session start is not automatically fatal: three concrete
  hooks with safe defaults — `connectionRecoveryLabel` (`''` = offer nothing,
  so it doubles as the capability query), `recoverConnection`, `canRunOffline`
  — decide what `RunExpt.connectInterfaces_` may put to the operator. Accepting
  "continue without it" sets `RunOffline`, and `Runtime.Interfaces` then skips
  connect and assert but **keeps the interface in the array**: removing it would
  take its parameters out of `dispatchNextTrial` and `readParameters`. The flag
  is cleared every connect pass, so the choice lasts one run. Only override
  `canRunOffline` for a peripheral whose absence is visible (the reward pump),
  never for the interface making the stimulus or taking the data
- **hw.Module**: Parameter container
- **hw.Parameter**: Single parameter with validation and callbacks
- **Concrete Backends**:
  - hw.TDT_Synapse: TDT Synapse API backend (under development)
  - hw.TDT_RPcox: RPvds/RPco.x backend
  - hw.Intan_RHX: Intan RHX TCP interface (under development)
  - hw.Teensy: Teensy 4.x USB-serial backend; firmware in firmware/EPsychTeensy/ (under development)
  - hw.Bpod: Bpod 0.5/0.6 state machine over USB serial. Speaks the Arduino
    firmware's byte protocol directly and never loads c:\src\Bpod, whose
    RunStateMatrix blocks; see documentation/hw/hw_Bpod.md (under development)
  - hw.NE1000: New Era NE-1000 syringe pump over RS-232 Basic-mode ASCII;
    drives the pump as a single-rate reward dispenser, not its Phase program.
    Its TTL Operational Trigger (pin 2) splits in two: the `TTLTrigger`
    enable is a parameter, a designer option, and an operator checkbox,
    while `TriggerMode` (default `LE`) is programmatic only — the mode
    follows the rig's wiring, not the operator. The configuration is
    asserted on every connect, since the pump remembers it through a power
    cycle. The only backend so far to implement the connect-recovery hooks:
    a pump that is off or on a renumbered COM port gets the operator a port
    picker instead of ending the run, and may be left offline for one session
    (its transactions no-op while disconnected, so trial dispatch is inert
    rather than broken). Picking a port by hand clears `AutoDetect`, or the
    connect-time rescan could pick a different pump in a daisy chain
    (see documentation/hw/hw_NE1000.md) (under development)
  - hw.Software: In-memory software backend
  - hw.Replay: read-only backend answering parameter reads from a saved
    session record, for `epsych.ReviewSession`. Deliberately absent from the
    four registry sites below — it is built from a session snapshot, never
    saved into an `.eprot`, and must not be offerable in ProtocolDesigner
  - hw.VlcRecorder: VLC video recording control

Adding a backend requires edits in four hardcoded registry sites outside the
class folder (`getAvailableInterfaceSpecs`, `getInterfaceEditState`,
`Protocol.toStruct`, `Protocol.createInterfaceFromStruct_`) — there is no
reflection. See documentation/hw/hw_Interface_Tutorial.md
and the `hw.Teensy` commit for the full list; omitting
`Protocol.createInterfaceFromStruct_` in particular fails silently, reloading
saved protocols as `hw.Software` stubs.

#### obj/stimgen/ – Stimulus Generation (GIT SUBMODULE)
Separate repository: [dstolz/stimgen](https://github.com/dstolz/stimgen) — package is at `obj/stimgen/+stimgen/`.
Edits here belong to that repo, not epsych2; commit there and update the submodule pointer.
- **stimgen.StimType** (abstract): Base for all stimuli
- **Stimulus Subclasses**: not listed here — the set changes with the submodule.
  Use `stimgen.StimType.list` or `obj/stimgen/documentation/stimgen_StimTypes.md`.
- **stimgen.StimPlayer**: Multi-stimulus manager
- **stimgen.StimCalibration**: Frequency response and SPL-to-voltage lookup
- **stimgen.HardwareHost** (abstract): Contract EPsych implements for hardware access

stimgen has NO dependency on epsych2. Never add `epsych.*` or `hw.*` references
inside `obj/stimgen/` — route them through the bridge below.

stimgen is pinned to an exact commit and released independently, so do not
duplicate its class inventory, signal-pipeline details, or per-class docs in this
repository; link to the submodule's own documentation instead. `epsych.SelfTest`
check A3 verifies the pinned commit still satisfies the stimbridge contract, and
`EPsychInfo.stimgenChksum` records that commit in saved session metadata.
Inside `obj/stimgen/` call `stimgen.util.vprintf`, never the bare `vprintf`.
It is bridged into this repository's logger at startup (see `stimbridge.LogBridge`
below), so those messages reach `.error_logs/` like everything else; without a
host it falls back to `fullfile(tempdir,'stimgen_error_logs')`.

#### obj/+stimbridge/ – EPsych ↔ stimgen Seam
- **stimbridge.RuntimeHost**: Implements `stimgen.HardwareHost` over epsych.Runtime/Protocol
- **stimbridge.InterfaceAdapter**: Implements `stimgen.calibration.HwAdapter` over hw.Interface
- **stimbridge.LogBridge**: Implements `stimgen.LogSink` over `eplog.Logger`, so stimgen's
  messages land in the session log attributed to their own call site. Installed by
  `epsych_startup`, guarded so a stimgen pinned before the seam still starts

All three contracts follow the same rule: a new method added to a `stimgen.*` abstract
class must be **concrete with a safe default**, or the `stimbridge` subclass becomes
unconstructable. `epsych.SelfTest` check A3 is the tripwire.

#### obj/+gui/ – Reusable GUI Components
- **gui.BehaviorGUI** (abstract): base class for a paradigm's own experiment GUI, launched once per session as `feval(FUNCS.BehaviorGUI, RUNTIME)` — owns lifecycle, event listeners, position prefs, component-registry teardown, and Parameter_Update wiring; subclasses implement build(fig) (see documentation/gui/gui_BehaviorGUI.md, template in examples/customgui/).
  The `add*` helpers are the documented way to reach every reusable
  component, and each registers what it builds for teardown. A helper whose
  component needs something the session does not have returns `[]` and logs
  at debug level rather than throwing — the same tolerance `addControl` has
  for an unresolved parameter name, and what keeps `epsych.SelfTest` check
  I6 (open against a runtime with no interfaces) passing. `addHistory`,
  `addScatter`, `addPsychPlot`, `addStaircasePlot`, `addSessionClock`,
  `addTrialTimer`, `addModeIndicator` and `addSessionGate` were added
  2026-08-22 for components that already existed but had no entry point;
  before that a paradigm constructed them by hand and remembered to
  `register` and `attachRuntime` itself, which the BehaviorBuilder's
  emitters had to open-code
- **gui.BehaviorBuilder**: design-time builder that generates BehaviorGUI subclasses
  for naive users — load a protocol, pick components from a palette, drag snap-to-grid
  regions on an `images.roi.Rectangle` canvas, and export. The design round-trips
  through an `.eblt` JSON spec (NaN forbidden so `jsonencode` is exact; protocol
  reduced to a `ParameterSnapshot`, never serialized objects, which is what makes a
  moved protocol a degraded mode instead of a dead spec). Generated `build()` calls
  only the documented `add*` helper DSL plus guarded `obj.register(...)` natives, and
  never emits lifecycle code, so output survives SelfTest I6 like a hand-written
  subclass; duplicate component classes get explicit PreferenceTags. The spec model
  and codegen are headless statics (`specNew`/`specValidate`/`saveSpecFile`/
  `writeCode`); `tmp/smoke_test_behaviorbuilder.m` is the standing check. Adding a
  palette component = one `componentCatalog.m` row + one emitter branch in
  `generateCode.m` (documentation/gui/gui_BehaviorBuilder.md)
- Real-time visualization: Performance, PsychPlot, ParameterScatter (generic X/Y/color parameter scatter for custom GUIs)
- **gui.OnlinePlot**: the live multi-trace view of one box's hardware —
  parameters, or the bits of an RPvds bitmask bank, sampled on a timer
  against a scrolling (or trial-locked) time axis
  (`gui.BehaviorGUI.addOnlinePlot`). Reads are **batched per interface**,
  not per trace: `hw.Parameter.get.Value` costs an `isprop` probe plus an
  `IsConnected` probe before the value, and on `hw.TDT_RPcox` that
  connection probe is a `GetStatus` COM call per module, so an N-trace plot
  paid 2N round trips a tick where N+1 would do. Every backend but
  `hw.Software` and `hw.VlcRecorder` takes a whole `hw.Parameter` array in
  one `get_parameter` (`hw.Teensy` and `hw.Bpod` serve it from a single
  snapshot); a backend that refuses the array is demoted to per-parameter
  polling ONCE rather than failing a call every tick, and write-only,
  `StimType` and `hw.Software` parameters never join a batch because
  `get.Value` is where they are correctly served. Which traces, in what
  order, and how they look are settable BOTH from code (`setWatched`,
  `setTraceOrder`, `setTraceColor`, the aesthetic properties) and by the
  operator (right-click: Select Traces..., Reorder Traces..., palette, line
  width, per-trace colour) — the menu items call the public setters, so
  nothing the operator can do is out of a script's reach. The arrangement
  PERSISTS by `PreferenceTag`, with two rules that keep it from fighting the
  paradigm: order and per-trace style are always re-applied and are matched
  by trace NAME (so a colour follows its signal through a reorder or a
  protocol edit), while the trace SELECTION is re-applied only when the
  operator chose it by hand — a `source` passed to the constructor is what
  `build()` asked for. A `gui.PopOut` adopter, and the pop-out is a fully
  independent instance (own timer, read plan, buffers, preference key),
  which is the point: the usual reason to pop one out is to watch a
  DIFFERENT set of traces large. Four things a reader would otherwise
  re-derive: the ring is sized from the time window and timer period (a
  fixed 1000 samples is 50 s at the bitmask period, so a wider window drew a
  plot that stopped part way back); trial markers are recycled from a
  bounded pool, since one line plus one text per onset left ~900 of each on
  the axes after an hour, all re-rendered by every `drawnow`; a `Text`
  `Position` is plain numeric even on a duration ruler, and the trial-number
  labels used to be drawn above the y limit where nothing could see them;
  and `reorderTraces` may use no nested functions, because a nested callback
  handle keeps its parent workspace — and the `onCleanup` in it that deletes
  the window — alive for as long as the figure holds it, so CANCELLING the
  dialog leaked an invisible modal window and the next one blocked in
  `uiwait` forever (documentation/gui/gui_OnlinePlot.md)
- **gui.SessionPerformance**: generic session summary panel (rates, counts, d'); computes through psychophysics.SessionMetrics and exposes the trial window both programmatically and on a right-click menu (documentation/gui/gui_SessionPerformance.md)
- **gui.NextTrial**: generic upcoming-trial display driven by NewTrial events
- **gui.ReviewTransport**: the trial scrubber for an `epsych.ReviewSession` —
  slider, step, play/pause, rate, and elapsed-time readout. Its OWN window, not a
  strip added to the behavior GUI, because that layout belongs to the paradigm's
  `build` and the base class offers no seam for inserting into it; keeping it
  separate is also why a paradigm needs to know nothing about review to be
  reviewable. Marked with `gui.PopOut.markStandaloneWindow`, so it gets "Keep
  Window on Top" and remembers being pinned. The slider commits on RELEASE
  (`ValueChangedFcn`), since each seek re-notifies every display and each
  recomputes the whole session from the DATA array. Closing it closes only the
  transport (`R.showTransport()` brings it back); closing the BEHAVIOR GUI takes
  it with them, since there is then nothing to scrub. Two controls at the right
  are not transport at all: a `gui.ScreenCapture` aimed at the **behavior GUI**
  rather than at this window (a picture of a scrubber is no use in a notebook,
  and the reason the transport has its own window is to stay out of the
  paradigm's layout — screenshots included), and an **On Top** state button, so
  a review stays readable while the operator works in another application. The
  slider row is 56 px because a `uislider`'s tick labels hang BELOW its track
  and ran into the buttons at the 32 px an ordinary control gets; a remembered
  window position is floored at `DEFAULT_SIZE` for the same reason
- **gui.SubjectManager**: the Subjects & Projects window, and the operator's only path to putting subjects in a session — the RunExpt `add_subject` toolbar button and the new Subjects menu (Ctrl+B) both open it. **Add Checked to Session** REPLACES the session's subject list rather than appending to it (`assignToSession`'s `ReplaceExisting`) — what is ticked is the operator's answer to "who is running", and a leftover animal would keep dispatching trials in its box; the displaced names go in the commit report, and the button and its tool say so in a tooltip. Projects are a `uilistbox`, subjects a `uitable` because each row carries its own box before commit; Protocol is read-only in the grid because `uitable`'s `ColumnFormat` is per-column, so a dropdown there could not offer per-row protocols. **Copy...** (also `Project > Copy Project...` and a two-folders tool) starts a study's next phase from one that already works: it asks the subjects question FIRST in a `uiconfirm` — with subjects, or settings only, skipped entirely for a project with no active members — because that is the one thing the edit dialog cannot show, then opens the ordinary dialog titled `Copy Project` on a non-colliding `(copy)` name, so nothing is written until OK. Copied subjects stay in the source too (membership is many-to-many); the roster's `IncludeRetired`/`CopyProtocolMemory` are script-only. The project dialog has two tabs: **Project** (identity, links, archived) and **Session Defaults**, which is where the settings that moved off Customize are set — protocol, data path, saving function, behavior GUI, timer period, video and Intan paths. Nothing there opens blank: each field is seeded from its MRU (`ep_RunExpt_Subjects/Recent<Field>`, written only on OK) and then the machine pref, and OK refuses a blank one; `DefaultProtocol` and `IntanSettingsFile` are the two deliberate exceptions. The behavior GUI dropdown is fed by the behavior GUIs other projects in the roster use, not by the `RecentBehaviorGUI` pref, so it works with no session open. All state lives in `epsych.SubjectRoster`; every callback ends in `refresh`. On a rig with no roster file chosen the window opens *unbound* — header `Roster: (no file chosen)`, an explanation where the table goes, and everything off EXCEPT New Project / New Subject / Import, because clicking one of those three is how `ensureRoster_` asks for the file. That prompt loops with two exits (name a file, or close the window): "carry on without one" is never offered, since it would mean filling in a record with nowhere to save it. Browsing never prompts. A configured path whose FOLDER is gone (share moved, drive unmounted, temp dir cleaned up) is treated the same way and marked `(folder not found)` — otherwise it is indistinguishable from a fresh empty roster, and `saveAtomic_` would re-create that dead folder and save into it. The header shows the FULL path plus a Change... button, redundantly with the toolbar tool and File menu, because an icon-only toolbar is no help to someone whose roster is not where they expected. "New Subject..." routes through `RunExpt.dispatchAddSubjectFcn_` so a lab's custom `FUNCS.AddSubjectFcn` still applies. A **Version** column and a **Protocol** menu surface `SubjectRoster`'s version checking: the column shows the version each subject is *on* (bold orange when the file has been saved since), a collapsible banner over the table announces how many are behind and offers Update All, and right-click opens that row's protocol in `epsych.ProtocolDesigner`. "Update All in Project" deliberately covers filtered-out members, but RETIRED members are outside the version workflow entirely: they are skipped by every update, left out of the banner, the tooltip, and Check Protocol Versions, and their Version cell is greyed rather than flagged. A finished animal's recorded protocol is the record of what it ran, and no session will follow to make a newer version true. A project's **links** render under the summary as `uihyperlink`s whose `URL` is left EMPTY on purpose — the click routes through `SubjectRoster.openLink` so a stored address is re-checked before anything navigates, and a `file:` folder goes to the file manager rather than a browser. "Show archived projects" is the project-level counterpart of "Show retired", and the selected project is never hidden by it (documentation/gui/gui_SubjectManager.md)
- **gui.SyringePump**: operator panel for an `hw.NE1000` pump — dispensed-volume readout (4 Hz), COM port picker with auto-detect, syringe diameter, rate, infuse/withdraw, a TTL-trigger enable, and manual Start/Stop/Zero. Drives a protocol's pump, or one it constructs itself when the session has none, so the panel still opens with no hardware. Every part is individually hideable through `Sections`/`show`/`hide` or the right-click menu, and a hidden control still works (the menu can set it); operator-made changes — layout, port, units, values — persist by `PreferenceTag`, while programmatic ones do not. The value options carry no `arguments`-block defaults, which is what lets a saved configuration fill in for what the caller did not state. Rate and readout **units** are the operator's too, from the right-click Units menu (µL/mL per min/hr, mL/min by default): changing them converts `Rate` rather than reinterpreting it, puts the interface into the same units — so a protocol column that writes `Rate` means them as well — and is refused while the pump runs, because the pump rejects a units-bearing `RAT` mid-dispense and `hw.NE1000`'s bare-value fallback would land in the OLD units (`gui.BehaviorGUI.addSyringePump`; documentation/gui/gui_SyringePump.md)
- **gui.Notes**: the operator's note pad — one entry line (Enter or the button
  beside it commits), above it a log of everything typed, each line stamped with
  the trial (`[T042 00:17:05] ear plug slipped`). It STORES NOTHING: every note
  goes to `epsych.SessionNotes` (normally `RUNTIME.NOTES`), which is what puts
  it in the data file and the journal, so any number of instances — an embedded
  panel, its pop-out, a second GUI — are views over one log kept in step by
  `NotesChanged`. Two forms, and the second is why the pop-out machinery is load
  bearing rather than a nicety: `ButtonOnly=true`
  (`gui.BehaviorGUI.addNotesButton`) builds a single button whose click is
  `popOut()`, so a GUI with no room for a log gets the notes in a window that
  remembers its position, pins on top, raises instead of duplicating, and closes
  with its host — all from `gui.PopOut`, with `createPopOut_` returning a full
  panel over the same store. The log box is a `uitextarea` filling whatever row
  the host layout gives it (no size option, by design) and is **read-only until
  the right-click Editable is ticked**, remembered per host GUI; an edit then
  makes that text authoritative (see `epsych.SessionNotes`). `TimeStamp`
  (`elapsed` default, `clock`, `none`) and `Subject` are programmatic only — the
  stamp is the paradigm's decision, not the operator's. In `ReviewMode` the
  entry row is disabled and Editable is refused: what a review shows is the
  record the file was saved with. On `gui.BehaviorBuilder`'s palette under
  Add-ons, where the ButtonOnly form is the one case that CLEARS a region's
  pop-out flag in `normalizeRegion_` — that button already opens the window a
  pop-out button would (documentation/gui/gui_Notes.md)
- **gui.KeyBindings**: the keyboard-command processor a behavior GUI owns
  (`obj.Keys`), and the answer to a figure having exactly ONE
  `WindowKeyPressFcn` slot that three parties used to claim by assignment —
  `gui.Parameter_Update` outright, `gui.RegenerateTrial` by chaining and
  re-installing on every ModeChange, and the subclass itself. Last write won,
  silently: `TwoAFCBehaviorGUI` wired its arrow keys and then called
  `addUpdateButton`, so the keys its own tooltips advertised were dead. The
  class **owns both slots** rather than using `addlistener` — listeners
  compose, but that leaves the slots a live clobber surface with no defined
  order, and owning it is what lets `claimFigure` (called by the base AFTER
  `build`) notice a foreign claim and chain it for unbound keys instead of
  throwing it away. Bindings are **code, never operator preference**: nothing
  is persisted, there is no rebinding UI, and `showHelp` (Ctrl+Shift+?, F1) is
  the only place the set is visible. A chord is the WHOLE modifier set
  (`ctrl+shift+r` does not fire `ctrl+r`), normalized to one canonical
  spelling with the aliases the older handlers each special-cased
  (`command`→ctrl, `numpadN`→N, `?`→slash); a **duplicate errors** rather than
  warning, since a collision in code is a paradigm bug that should not leave
  one command quietly dead. Four things a reader would otherwise re-derive: a
  bare modifier press is STATE and is never looked up as a chord, or holding
  Ctrl to arm something would also fire whatever `ctrl` was bound to;
  `CurrentModifiers`/`ModifiersChanged` is what `gui.Parameter_Update` and
  `gui.RegenerateTrial` now read through an optional `KeySource`, so both keep
  their whole hook machinery for STANDALONE windows and neither needs it
  inside a GUI (`smoke_test_regenerate_trial` is unchanged and still green);
  dispatch is **suppressed in a review** unless a binding asks for
  `EnableInReview`, defence in depth over the components' own gates; and a
  binding with an `Owner` dies with that component. The helpers that ship a
  default chord are `addUpdateButton` (Ctrl+Enter, via a new `commitPending`
  that is inert when nothing is pending), `addScreenCapture` (Ctrl+Shift+C)
  and `addNotes`/`addNotesButton` (Ctrl+Shift+N), each dropped with
  `KeyBinding='none'`; `addSessionGate`, `addSyringePump` and
  `addRegenerateTrial` deliberately have NONE, since those start a session,
  move a syringe, or interrupt the trial in progress — the regenerate hold
  gesture IS its key handling. Two limits are documented rather than fixed: a
  uifigure delivers no window key event while an edit field has focus (which
  is also what stops a shortcut firing mid-note), and a modifier released
  while another window has focus corrects itself only at the next keystroke.
  Standing proof `tmp/smoke_test_keybindings.m`, whose group 11 is the
  regression itself — a key bound before `addUpdateButton` still firing after
  it (documentation/gui/gui_KeyBindings.md)
- **gui.RegenerateTrial**: a button that re-arms the trial the rig is holding
  (`gui.BehaviorGUI.addRegenerateTrial`). One press is
  `epsych.Runtime.dispatchNextTrial` — the same call the trial loop makes at
  every boundary — so `set.Value` redraws every `isRandom` parameter and
  re-evaluates every `Expression`, and a mid-trial edit reaches the hardware
  without waiting for the next trial. The button is **dead until
  Ctrl+Alt+Shift are all held** and dies again as one is released — the
  combination `gui.Parameter_Update` already uses held-while-clicking, so the
  gesture is not new to an operator. The gate is re-checked inside
  `regenerate` and not only in the button's `Enable`, so a script or a stale
  enable state fails closed. Inside a behavior GUI the modifiers now arrive
  from `gui.KeyBindings` through a `KeySource` and none of what follows
  applies; the hook machinery remains for a STANDALONE window, where a figure
  has ONE `WindowKeyPressFcn` and `Parameter_Update` claims it outright, so
  this component CHAINS (wrapped in try/catch — `Parameter_Update`'s own handler
  throws until its `watchedHandles` are wired at the end of `build`) and
  RE-INSTALLS on the first `ModeChange`, which is the first moment every
  component has had its turn. `isInstalled_` tests `~isempty(hook)` before
  `isequal`, because `isequal('',[])` is TRUE in MATLAB — an `isequal`-only
  test reports the hook as installed on the bare figure every first install
  starts from, so nothing was ever wired and the button could never arm.
  **Once armed it interrupts the trial in progress
  and asks nothing further**: the component cannot tell an ITI from an animal
  part way through a response, the reset and new-trial triggers go out
  either way, and since a `DATA` record is assembled at completion the trial
  is recorded with the LAST dispatch's values. `TrialIndex` deliberately
  does not move — one trial, one record, so a session never counts trials
  the subject never saw — which is exactly why nothing downstream can see it
  happened, and why every press is written into `RUNTIME.NOTES` tagged with
  the box. It does **not** re-run the trial selector: selecting is where a
  paradigm's state moves (a staircase steps, a catch hazard climbs, a queued
  reminder is consumed), so redrawing a delay must not advance the schedule;
  `Reselect=true` asks for that and is safe only because every
  `epsych.TrialSelector` already tolerates being called twice for one trial.
  The enable state FOLLOWS `ModeChange` rather than being read at
  construction, since a behavior GUI is built from the PsychTimer `StartFcn`
  before `RunExpt` broadcasts the mode; a review never arms it. Kept off the
  `gui.BehaviorBuilder` palette on purpose — that builder is for operators
  assembling a GUI without writing code, who should not get this button by
  accident. Used by `cl_AppetitiveDetection_BehaviorGUI`, last in the
  trigger row and set apart from it; standing proof
  `tmp/smoke_test_regenerate_trial.m`
  (documentation/gui/gui_RegenerateTrial.md)
- **gui.ScreenCapture**: camera button that copies a picture of the whole window
  — controls and plots alike — to the system clipboard, for pasting into a
  notebook entry (`gui.BehaviorGUI.addScreenCapture`). `exportapp` is the
  capture because it is the only one that includes UI components, and it
  renders offscreen, so an obscured window still copies; the image reaches the
  clipboard through .NET because MATLAB's `clipboard()` is text-only, which is
  what makes the full-window form Windows-only (elsewhere it falls back to
  `copygraphics` and logs which happened). The glyph comes from
  `gui.toolbarIcon("camera")`, since `uibutton`'s `Icon` accepts only four
  built-in names — the confirmation flash after a copy is the one place those
  are used (documentation/gui/gui_ScreenCapture.md)
- **gui.SessionGate**: the "Begin Experiment" button for a rig that must not
  start dispatching the moment the session does — the syringe line purged,
  the animal placed. It comes in TWO HALVES in two places, which is the
  thing to know: `gui.BehaviorGUI.addSessionGate` puts the button in
  `build`, and `waitForSessionGate` in the SUBCLASS CONSTRUCTOR is what
  actually holds the session; the wait cannot live in `build`, which runs
  from inside the base constructor before the window is shown. Blocking
  works at all because `RunExpt` builds the behavior GUI from the
  PsychTimer's `StartFcn` and a timer will not fire its `TimerFcn` during
  another of its own callbacks, so the trial loop is held without the
  runtime knowing a gate exists. It `pause`s rather than spins, since
  priming the line through `gui.SyringePump`'s manual controls is most of
  what the operator does during the hold. Pressing it RETIRES the button
  into a status line (`Experiment Running`/`Preview Running`/`Session
  Complete`) rather than removing it, which would reflow the layout, or
  merely greying it, which could not tell a preview from a record — and
  Preview is tested alongside Record everywhere because it is a distinct
  `hw.DeviceState` and is not `isIdle`. `attachRuntime` catches up when a
  run starts without a press, so a script never leaves an armed button in
  front of a running loop; an idle mode arriving BEFORE anything ran leaves
  it armed, since that is a session waiting rather than one that finished.
  Never in a review — blocking would hang `epsych.ReviewSession` inside
  `feval`. Extracted from `examples/syringepump/PumpBehaviorGUI`, which now
  uses it (documentation/gui/gui_SessionGate.md)
- **gui.PopOut** (abstract mixin): adds the right-click "Open in Separate Window" item and the `popOut` method to a display component. A pop-out is a SECOND instance over the same data source with its own graphics, listeners, and preference key (`<hostTag>_<Class>_PopOut`), so it never disturbs the embedded one; adopters implement `createPopOut_` and `popOutHostContainer_`. Adopted by ParameterScatter, History, SessionPerformance, NextTrial, Parameter_Monitor, SyringePump, PsychPlot, OnlinePlot, and psychophysics.Staircase; `gui.BehaviorGUI.addPopOutButton` opens one from a button, `gui.ComponentToolbar` puts them all on one toolbar. A second item, **Keep Window on Top**, pins the window (`WindowStyle='alwaysontop'`) so a display stays readable while the operator works in another application, and is remembered with the window position. It appears only in a window holding ONE component — a pop-out, or one `ComponentToolbar` opened for a lazy entry, marked as such by `gui.PopOut.markStandaloneWindow` before the component is built — never on the embedded copy, whose window belongs to the behavior GUI and everything else on it. A `PopOutStateChanged` event says when a window opened or closed — NOT when one is merely raised, and not during the host's own destruction, which is what keeps closing a GUI from reading as the operator closing its windows — and is what `gui.BehaviorGUI`'s `RestorePopOuts` listens to: with it on, the GUI remembers WHICH displays were open (`OpenPopOuts` under its own `PreferenceTag`, rewritten at each change rather than at teardown, so a killed MATLAB still remembers) and reopens them at construction. It records only the list; how each window looks — position, font, columns, pinned — was already the component's own pop-out preference key, which is why "restore the configuration" needed no new persistence. Two decisions: an identity is the component-toolbar label (register name, else the class name spaced out, uniquified by registration order), so `register(comp, name)` is what pins it when a GUI holds two of a class; and an entry this GUI cannot resolve is skipped but KEPT in the list — a protocol showing fewer displays than another must not erase the fuller layout (documentation/gui/gui_PopOut.md)
- **gui.ComponentToolbar**: the optional icon toolbar a behavior GUI adds with
  `addComponentToolbar` — one tool per display, opening it in a window of its
  own. Two kinds of entry, differing in who owns the window: **automatic**
  entries are the registered `gui.PopOut` components, whose windows stay
  theirs, and are collected AFTER `build` returns (not when the toolbar is
  made) so a GUI can ask for the toolbar on its first line and still list
  everything built after; **lazy** entries are declared with
  `addLazyComponent(name, factory, ...)` for displays the GUI does not show at
  all, and the toolbar owns those windows — the factory runs on first click,
  which is the whole point, since constructing a Parameter_Monitor starts a
  polling timer and a ParameterScatter attaches listeners. Closing a lazy
  window deletes the component; clicking again builds a fresh one, so a
  component that remembers itself by `PreferenceTag` reopens as it was.
  `Style="toggle"` shows which windows are open and decides from
  `hasPopOut`/window validity rather than from the button state the click just
  set, so a window opened from a right-click menu — which the toolbar is never
  told about — still closes on ONE click. Tool labels come from `register`'s
  long-unused `name` argument, else the class name split at camelCase
  (documentation/gui/gui_ComponentToolbar.md)
- **gui.selectSerialPort**: the modal port picker RunExpt offers when a serial
  backend will not connect. **Refresh** re-enumerates rather than reusing the
  list the session started with — a device powered on while the dialog is open
  is the case it exists for — and an optional `Probe` callback adds a detect
  button (`hw.NE1000.findPumpPort`), which is the only thing that tells a wrong
  port from a device that is off. Ports held by another process are listed but
  not selectable, because a pump held open by a stale MATLAB is a likely reason
  for the failure and hiding it would make the port look missing. Every widget
  write after an enumeration or probe re-checks `isvalid(fig)`: `serialportlist`
  and the probe yield, so a rig's timers (gui.SyringePump polls at 4 Hz) can
  close the dialog mid-scan
- **gui.compareProtocolVersions**: the modal window showing what differs between
  two protocol versions — a filtered table over `epsych.Protocol.compareVersions`
  with a Copy Report button for a notebook entry. Shared by the designer's
  Version History and the Subjects window's Revert Protocol; see the version
  comparison notes under `epsych.SubjectRoster` above
- **gui.toolbarIcon**: the 16x16 glyphs for `uitoolbar` tools, drawn as pixel art
  (a string mask per row over a shared palette) so the toolbox ships no image
  files. `uitoolbar` does render in a `uifigure`, but `uibutton`/`uiimage` `Icon`
  accepts only four built-in names — `success`, `error`, `warning`, `info` — so
  every other glyph has to be drawn here or supplied as a file. Shared by
  `epsych.RunExpt`, `gui.SubjectManager`, and `gui.ComponentToolbar`; a new tool
  adds a `case` to it. The component-toolbar section is the one place a MISSING
  case is not an error: those names are computed from a class name
  (`gui.Parameter_Monitor` → `parametermonitor`) and `gui.ComponentToolbar`
  falls back to the generic `component` glyph, so a new `gui.PopOut` adopter
  works before anyone draws for it
- Session control: StaircaseTraining, StatusBar, Triggers
- **gui.ParameterDebugger**: the other window on RunExpt's Help menu (Ctrl+E) — every
  hw.Parameter a protocol defines, in one table, readable and writable by hand. It
  **never polls**: a read happens only on a double-click, Read Selected, or Read All
  (F5), which is what makes it safe to leave open beside a running experiment;
  `gui.Parameter_Monitor` is the polling display when you want one. Colour on the
  Value cell IS the read report — green read, blue written-and-confirmed, amber
  written-but-reads-back-different (clamping, an `Expression`, a coarse device — not
  an error), red threw, grey unreadable, uncoloured never asked. Read All skips
  write-only parameters (`get.Value` logs a critical record and returns NaN for them)
  and `Buffer`/`Coefficient Buffer` (megabytes off the device) — naming one always
  reads it. Typed values go through `str2num` behind a numeric-literal regexp, because
  this window points at live hardware and a cell that could `eval` anything would be a
  trap. Every write is followed by a read-back, since on a real backend that is the
  only proof it landed. Sources come from `CONFIG(i).PROTOCOL.Interfaces`, not
  RUNTIME, so it works before a run; `(offline)` on a timestamp means the backend was
  never asked. The Find box filters **as you type** (`ValueChanging`, not on Enter),
  which is affordable precisely because filtering touches only handles already in
  memory; a Regex tick makes it a pattern, and a half-typed one (`Freq[`) leaves the
  list alone rather than emptying it, since MATLAB's `regexp` accepts those silently
  and only `patternIncomplete_` notices. A filter change CARRIES the read report over
  (matched on the parameter handle — same object, same evidence) while a rebuild still
  starts clean, and Esc clears the box before it closes the window. Sorting and column
  rearranging are on: safe only because every callback uses the DATA index uitable
  reports (`Selection`, `evt.Indices`, `InteractionInformation.Row`), never the
  `Display*` one a header click reorders (documentation/gui/gui_ParameterDebugger.md)
- **gui.ParameterTracker**: the live plot the debugger opens with Track Selected
  (Ctrl+T) — scalar parameters against seconds since tracking started, one colour
  each. It is where the polling the debugger refuses to do actually lives: its own
  window, its own timer, an operator-set rate (0.1-20 Hz, default 5), and a Pause
  button, so bus traffic is something visibly turned on. Samples are stamped with
  the clock rather than the sample index, so a period the timer misses widens a gap
  instead of drifting the time axis; a failed or non-scalar read is NaN and is logged
  once per parameter (again only if the message changes), or a disconnected rig writes
  five records a second. A parameter added mid-run gets NaN for what it missed rather
  than invented history, and removing one takes its samples with it
  (documentation/gui/gui_ParameterTracker.md)
- Diagnostics: SelfTest (window for epsych.SelfTest; opened from RunExpt's Help menu)
- Parameter control: Parameter_Control, Parameter_Monitor, Parameter_Update.
  `Parameter_Control` seats its widget ONCE at construction and then waits for a
  `PostSet`, so whatever it seats from is what it shows until the parameter is
  written. `initialWidgetValue_` clamps that seed into the field's own `Limits`:
  a stored value outside the parameter's bounds is not a corrupt file but a
  routine one — `hw.Parameter` clamps on write and not on read, so a backend
  read-back, a protocol saved while a device reported 0, or a `Min`/`Max` edited
  after the value was set all produce one (`cl_AppetitiveDetection`'s `StimDelay`
  ships `Value = 0` with `Min = 400`). `uieditfield` rejects it outright, and one
  such parameter used to abort the whole `build`, taking every control after it.
  Only the WIDGET is clamped; the parameter is left alone.
  Enable is the AND of TWO INDEPENDENT GATES kept in separate fields: the
  interface `mode` (dead while the hardware is idle) and a dependency gate
  set by `EnabledBy=`/`DisabledBy=` (a governing checkbox), or by hand with
  `setEnabled`. They must stay apart, or ungating a control would light it up
  over an idle rig and starting the rig would light up a gated one. Gating
  covers `widgets()` AND `h_label` (a `range` owns two entry fields, and a
  greyed field beside a black label reads as an oversight) and re-applies
  from `runPostUpdateFcn` — which is shared by the operator and external-write
  paths, so a phase load moves the greying with it — rather than from
  `PostUpdateFcn`, a single slot a paradigm may already be using.
  `cl_AppetitiveDetection_BehaviorGUI` predates this and still greys three
  control groups by hand
- Utilities: ElapsedTrialTimer

#### obj/+teensy/ – Teensy Trial Programs
Design-time tooling that turns an operant paradigm into a state table the Teensy executes, so
the contingency lives in a file rather than in firmware. No dependency on the GUI layer, which
is what makes the whole feature testable headlessly.
- **teensy.Program**: the document — channels, variables, states, timers, counters. Handle class;
  renames cascade through every reference, including nested condition operands.
- **teensy.Channel / State / Transition / Condition / Action / Variable / BoardProfile**: value
  classes. Value semantics make toStruct/fromStruct an exact round trip, which is what makes the
  designer's undo exact.
- **teensy.Compiler**: emits the wire records documented in
  documentation/hw/hw_Teensy_Program_Protocol.md, and checks the program against the firmware's
  fixed array sizes.
- **teensy.Simulator**: reference implementation of the firmware's execution semantics. Powers
  the designer's test bench, the headless tests, and tells the firmware author what to build.
- **teensy.Templates**: ready-made paradigms (Go/No-Go, 2AFC, fixed ratio, shaping, passive).
- **teensy.TrialDesigner**: the GUI (documentation/teensy/teensy_TrialDesigner_UserGuide.md).

Any numeric field may hold a literal or an "@Name" reference to a teensy.Variable; a reference
compiles to a constant-table index, which is how a protocol varies a duration per trial without
re-uploading the state table.

#### obj/+psychophysics/ – Online & Offline Analysis
- **psychophysics.Metrics**: the signal-detection formulas, with no state — d',
  criterion, relative criterion, ln β, A', B'', proportion correct, and the
  z-transform under them. Static only and not constructible; it never touches
  `epsych.BitMask`, `DATA`, or `RUNTIME`, so it is testable with four integers,
  and **classification deliberately stays with `Psych`** — turning response codes
  into counts needs the trial window, the exclusion mask, and an aborts policy,
  which are properties of a session rather than arithmetic. `fromCounts` is the
  seam. Three things a reader would otherwise re-derive: `z` is built on
  `erfcinv`, so d' no longer needs the Statistics Toolbox (and the smoke test
  scans the source to keep it that way); the correction for rates of 0 and 1 is
  **named at every call** — `"none"`, `"clamp"` (default `[0.01 0.99]`),
  `"halfcell"`, `"loglinear"` — and the two trial-count dependent modes **error**
  rather than falling back to a clamp, since a silent fallback is exactly how the
  toolbox came to have three correction defaults nobody chose; and NaN propagates
  instead of becoming a bound, because MATLAB's `min`/`max` drop NaN, so the
  obvious `max(min(p,hi),lo)` turned "no catch trials" into "99% false alarms"
  (three call sites carried a workaround for that and a fourth did not). The
  method is `z`, never `norminv`: an unqualified `norminv(p)` inside a classdef
  resolves to the toolbox function rather than to the static, which is the only
  reason the `Detection.norminv` it replaced ever worked. Aborts are the one
  judgement call in the denominators, and `rateDenominator` is the single place
  it lives: **excluded by default** (an abort is a lapse of engagement, not a
  wrong answer), with an `IncludeAborts` option on `fromCounts`,
  `SessionMetrics`, and `Detection` — `gui.SlidingWindowPerformancePlot`
  follows its analysis object. Before 2026-08-19 the toolbox disagreed with
  itself here: `SessionMetrics` excluded aborts while `Detection.Hit_Rate`, the
  sliding-window plot, and the offline examples divided by EVERY trial at a
  stimulus value, so one session gave two different d'. `Detection.Hit_Rate` is
  therefore no longer `[obj.Rate.Hit]` — `Rate` stays the proportion of all
  trials at a value. `Detection.d_prime`/
  `bias`/`a_prime`/`norminv` and `gui.Helper.dprime2AFC`/`criterion`/
  `percent_correct` are forwarders kept because they are public API and an
  inherited mixin (see documentation/psychophysics/psychophysics_Metrics.md)
- **psychophysics.Psych** (abstract): Base for all analysis
- **psychophysics.Detection**: Hit rate, false alarm rate, d', grouped by unique
  stimulus value; its four statics forward to `psychophysics.Metrics`, A'. It owns the
  signal-detection arithmetic every other component reuses (`d_prime`, `bias`,
  `a_prime`). **A'** is the nonparametric sensitivity index (Grier 1971): chance
  0.5, defined at rates of 0 and 1, so unlike d' it takes NO `infCorrection` —
  clamping the rates would only bias it toward chance, which is why the clamp is
  passed to `d_prime`/`bias` and withheld from `a_prime` at every call site.
  Exposed as `Detection.APrime` (per stimulus value),
  `SessionMetrics.Results.APrime`, and a plot type on `gui.PsychPlot` (`APrime`)
  and `gui.SlidingWindowPerformancePlot` (`aPrime`); shown by default nowhere,
  since `defaultMetrics` and the default plot types are unchanged
  (documentation/psychophysics/psychophysics_APrime.md)
- **psychophysics.NAFC**: N-alternative forced choice — choice functions, proportion
  correct vs a 1/N chance level, confusion matrix, choice bias — with customizable,
  self-refreshing plotting (three PlotTypes, right-click switchable, gui.PopOut).
  Choices come from Choice_* bits or a named DATA field, the correct alternative from
  TrialType (field or bits); embedded live in examples/two_afc.
  It also **defines the forced-choice bit encoding**, which is not the detection
  one: every alternative is a response, so no outcome name may carry the side.
  `Choice_k` is the only bit saying which alternative was chosen and is set on
  exactly the answered trials; `Hit` means that choice was correct and `Miss`
  means the subject chose and chose wrong; `Abort` is a response that arrived
  BEFORE the response window; and a trial with no response carries no outcome
  bit at all — **Undefined**, whose absence is what distinguishes it from Miss.
  `CorrectReject`/`FalseAlarm` name what a subject does when there is nothing to
  respond to and are never set in an N-AFC; `Reward`/`Punish` are the paradigm's
  contingency rather than scoring, and may be omitted. `TrialType_k` is the
  trial's CATEGORY (stimulus, catch, remind, ...) — the bit fallback for the
  correct alternative works only where the category IS the correct alternative
  (examples/two_afc's left-target/right-target trials), which is why anything
  else must name a `CorrectField`. Three consequences a reader would otherwise
  re-derive: correctness is computed from choice vs correct alternative and
  **never** from the outcome bits, which is what lets NAFC score a rig that
  wrote only `Choice_*` (`teensy.Templates.twoAFC_`, whose condition language
  has no variable comparison, so the board cannot know); `NumAborted` counts the
  Abort bit while `NumNoResponse` counts the rest of the unanswered trials, so
  the two failure modes stay separable; and **psychophysics.SessionMetrics does
  not apply** — its hit/false-alarm/d'/criterion model assumes a stimulus/catch
  split a forced choice does not have, which is why TwoAFCBehaviorGUI has no
  gui.SessionPerformance panel
  (documentation/psychophysics/psychophysics_NAFC.md)
- **psychophysics.Staircase**: Reversal detection and threshold estimation
- **psychophysics.BestPEST**, **psychophysics.MLP**: Threshold-seeking algorithms
- **psychophysics.SessionMetrics**: Session-level counts, rates, d', A' and criterion over a
  `psychophysics.TrialWindow` (all trials, last N, first N, or an explicit range). The
  computation behind `gui.SessionPerformance`; also usable headlessly and offline
  (documentation/psychophysics/psychophysics_SessionMetrics.md)

#### runtime/ – Execution Callbacks & Services
- **runtime/timerfcns/**: Timer lifecycle (Start, RunTime, Stop, Error)
- **runtime/savefcns/**: Data persistence
- **runtime/guis/**: Base GUI classes

#### TDTfun/ – Low-Level TDT Integration
- RPco.x connection (TDTRP) and RPvds tag reading (ReadRPvdsTags)
- Synapse SDK (SynapseAPI/)

#### obj/+eplog/ – Logging
The machinery behind vprintf; almost nothing should call it directly.
- **eplog.isEnabled**: the verbosity gate, and the only interpreter of GVerbosity
  (console) and GLogVerbosity (error log, default Inf = log everything). It answers
  per destination — `isEnabled(level,'console'|'log'|'any')` — because the two are
  decoupled: a quiet command window no longer costs the record of what happened
- **eplog.Logger**: session singleton; builds one record per message and dispatches
  to its sinks. `instance()`, `emit`, `flush`, `addSink`, `LogFile`
- **eplog.sink.Console / TextFile / JsonLines**: destinations. Each applies its own
  level in `accepts(rec)` — the logger's gate only asks whether ANY destination
  wants the record. FileSink owns the daily .error_logs file — rotation, flush,
  handle recovery, failure latching
- **eplog.format / formatException**: message text policy; an exception (or a
  lasterror/timer-event struct) becomes ONE record at the catch site
- **eplog.callerFrame**: attributes a record to the code that logged it, by skipping
  logger frames by filename. Any new wrapper in the call chain must be added to its
  skip list or it silently claims every message routed through it
Nothing in the package throws: EPsych logs from inside catch blocks.
stimgen reaches this package through `stimbridge.LogBridge`, not by calling `vprintf`.
See documentation/eplog/eplog_Logging.md.

#### helpers/ – Shared Utilities
- **vprintf.m**: Verbosity-gated printing and logging; a façade over obj/+eplog/
- **visenabled.m**: The gate alone, for guarding expensive log arguments
- **EPsychInfo**: Version and git metadata
- **Trial sequence generators**: randGellerman, RandomTrialSequence, FellowsSeq
- **GUI helpers**: findFigure

### Event System & Runtime Communication

The epsych.EventHub event broadcaster is the primary communication channel:
- **NewData**: Fired when a trial completes; listeners update results
- **NewTrial**: Fired when a new trial begins
- **ModeChange**: Fired when session mode changes

Subscribers (e.g., psychophysics.Psych subclasses, gui.OnlinePlot) listen to these events and update state.

### Program State Machine

NOCONFIG -> CONFIGLOADED -> READY -> RUNNING -> POSTRUN -> STOP

ERROR is reachable from any state.

### Key Design Patterns

1. **Heterogeneous Hardware Abstraction**: All backends inherit from hw.Interface with common API
2. **Event-Driven Analysis**: GUIs subscribe to epsych.EventHub events rather than polling
3. **Roster-backed sessions**: the .esub subject roster is the persistent session configuration; a subject's membership carries everything a session needs (there is no .ecfg config file)
4. **Auto-Discovery**: Backends auto-discover modules/parameters on connect via setup_interface()
5. **Pluggable Trial Selection**: epsych.TrialSelector is abstract and customizable
6. **Parameter Expressions**: Parameters can reference other parameters (e.g., Param.Prop or Module.Param.Prop). On `String`/`StimType` parameters the result is a 1-based index into `Values` instead of the value itself — `hw.Parameter.expressionSelectsIndex` is the single predicate that decides which meaning applies. A non-empty Expression is re-evaluated by `set.Value` on every dispatch, overriding the assigned value — so constants must live in `Values`, never as an Expression: the ProtocolDesigner converts literal-constant entries to fixed Values on edit and on load (see documentation/design/ProtocolDesigner.md, "Constants are values, not expressions")

## Coding Conventions & Standards

### From .github/copilot-instructions.md

**MATLAB Syntax**
- Target MATLAB R2024b (baseline R2014b+)
- Use arguments syntax for functions with >2 parameters or when validation needed
- Do NOT use compiler directives (e.g., %#ok<AGROW>)

**Naming**
- PascalCase for components, interfaces, type aliases
- camelCase for variables, functions, methods
- Suffix private class members with underscore (_)
- ALL_CAPS for constants

**Messaging & Logging**
- Use vprintf(level, msg, ...) for all formatted messages instead of fprintf
  - Never add \n at end; each record is its own line and a trailing newline is stripped
  - Examples: vprintf(0,1, 'Error: %s', msg); vprintf(2, 'Debug info')
  - Level -1 logs only; 0 = critical; 1 = info; 2 = debug; 3 = verbose; 4 = trace
- Format policy: **with** values the message is a printf format string; **with no**
  values it is literal text. Pass runtime-built strings (ME.message, file paths,
  tool output) as the whole message so '%' and backslashes survive
- vprintf is a façade over obj/+eplog/, which logs to .error_logs/
- The console and the log have separate levels: GVerbosity gates the command window,
  GLogVerbosity gates the file and defaults to Inf, so EVERY message is logged
- Never rebuild the log path by hand. `eplog.Logger.instance().LogFile` names the
  current file; call `flush()` first if something is about to read or open it
- Guard only genuinely expensive log arguments with `visenabled(level)`; vprintf's
  own gate already makes a message no destination wants ~4 us. Note visenabled is
  true whenever the LOG wants the level, which by default is always

**Error Handling**
- Use try/catch sparingly, only for expected errors
- Do NOT check isprop or isfield before accessing properties/fields
- Log caught exceptions with: catch ME; vprintf(0,1,ME); end

**Commenting**
- Concise comments explaining *why*, not *what*
- Function syntax first, then description, parameters, return values
- Class comments include purpose, properties, methods, minimal usage examples
- Avoid redundant comments

### File Organization

Class files: One class per directory with @ prefix

```text
obj/+packagename/@ClassName/
  ClassName.m          % Constructor and main methods
  methodName.m         % Separate method files (optional)
```

Procedural functions: Loose .m files in appropriate subdirectories
Protocol files: .eprot (a MAT file holding a `protocol` struct)

## Common Development Tasks

### Adding a New Hardware Backend

1. Create obj/+hw/@YourBackend/YourBackend.m inheriting from hw.Interface
2. Implement: setup_interface(), close_interface(), connect(), get_parameter(), set_parameter(), trigger()
3. Implement dependent property IsConnected
4. Create hw.Module objects and populate with hw.Parameter objects
5. Implement static getCreationSpec() returning hw.InterfaceSpec
6. Test with epsych.Protocol.addInterface()

Reference: obj/+hw/@TDT_Synapse/, obj/+hw/@Software/

### Adding a New Stimulus Type

1. Create obj/stimgen/+stimgen/YourStimulus.m inheriting from stimgen.StimType
2. Implement: IsMultiObj, CalibrationType, Normalization properties
3. Implement update_signal() to generate raw waveform
4. Define user-facing properties (e.g., Frequency, Depth)
5. Base class handles gating, normalization, calibration automatically
6. Test via stimgen.StimPlayer GUI

Reference: obj/stimgen/+stimgen/Tone.m, obj/stimgen/+stimgen/Noise.m

### Adding a New Online Analysis Tool

1. Create obj/+psychophysics/YourAnalyzer.m inheriting from psychophysics.Psych
2. Implement update(varargin) to process trial data
3. In epsych.RunExpt, wire listener via Runtime.EVENTS.NewData event
4. Optional: Create GUI in obj/+gui/ to visualize results

Reference: obj/+psychophysics/@Detection/, obj/+gui/@OnlinePlot/

### Adding Experiment-Specific Behavior

1. Use paradigms/ directory as pattern for paradigm-specific code
2. Custom GUIs: subclass gui.BehaviorGUI (copy examples/customgui/ExampleBehaviorGUI.m); the base provides lifecycle, listeners, and teardown — the subclass only writes build(fig) and event hooks. For a starting point without hand-writing code, `gui.BehaviorBuilder` generates one from a protocol + drag-and-drop layout
3. Create custom save functions
4. Subscribe to epsych.EventHub events for trial and mode changes (BehaviorGUI subclasses get onNewTrial/onNewData/onModeChange hooks instead)
5. Example: Custom epsych.TrialSelector for closed-loop

Reference: examples/customgui/, runtime/guis/@ep_GenericGUI/, paradigms/cl_SaveDataFcn.m, obj/+epsych/@DefaultSubject/

## Where to Look When Making Changes

- **Startup or runtime flow**: obj/+epsych/@RunExpt/, obj/+epsych/@Runtime/, runtime/timerfcns/
- **Protocol loading or compilation**: obj/+epsych/@Protocol/, obj/+epsych/@ProtocolDesigner/
- **Hardware integration**: obj/+hw/@Interface/, concrete backends, TDTfun/
- **Stimulus generation**: obj/stimgen/+stimgen/@StimType/, obj/stimgen/+stimgen/@StimPlayer/ (submodule)
- **Online analysis**: obj/+psychophysics/Psych.m, obj/+gui/@OnlinePlot/
- **Session GUI**: obj/+epsych/@RunExpt/, obj/+gui/
- **New paradigm**: Use paradigms/ as pattern

## File & Folder Highlights

| Path | Purpose |
|------|---------|
| obj/+epsych/ | Experiment framework |
| obj/+hw/ | Hardware abstraction |
| obj/stimgen/ | Stimulus generation (git submodule: dstolz/stimgen) |
| obj/+stimbridge/ | EPsych-to-stimgen adapters (hardware host, calibration adapter, log bridge) |
| examples/stimgen/ | Demo protocol/config/TDT circuit assets |
| obj/+gui/ | GUI components |
| obj/+teensy/ | Teensy trial programs: state-machine model, compiler, simulator, TrialDesigner GUI |
| obj/+eplog/ | Logging: verbosity gate, record dispatcher, console/file/JSON sinks |
| obj/+psychophysics/ | Analysis (Detection, Staircase, BestPEST, MLP) |
| obj/+peripherals/ | Motor control, pump communication |
| firmware/ | Microcontroller firmware (EPsychTeensy) |
| runtime/timerfcns/ | Timer callbacks |
| runtime/savefcns/ | Data saving |
| TDTfun/ | Low-level TDT integration |
| paradigms/ | Experiment-specific implementations (one lab's paradigms; `cl_*` function names unchanged) |
| helpers/ | Shared utilities |
| documentation/ | User and developer docs |

## Important Git Practices

- Commit messages should reference the area changed
- Use feature branches for significant changes
- No force pushes to main/master without discussion
- `obj/stimgen` is a submodule pinned to `main`. Changes there are committed in
  the stimgen repo; bumping the pointer here is a separate, deliberate commit.

## Documentation Resources

- **User setup**: documentation/overviews/Installation_Guide.md
- **Session walkthrough**: documentation/overviews/RunExpt_GUI_Overview.md
- **Pre-flight self-test**: documentation/overviews/RunExpt_SelfTest.md
- **Runtime events**: documentation/epsych/Event_Notifications.md
- **Offline session review**: documentation/epsych/epsych_ReviewSession.md
- **Logging**: documentation/eplog/eplog_Logging.md, documentation/helpers/helpers_vprintf.md
- **Architecture**: documentation/overviews/Architecture_Overview.md
- **Class map**: documentation/overviews/Class_Map.md
- **Toolbox overview**: documentation/overviews/Toolbox_Overview.md
- **Full wiki**: https://github.com/dstolz/epsych2/wiki

## Repository Information

- **Latest commit**: EPsychInfo.commitTimestamp and EPsychInfo.chksum
- **Version**: EPsych v2, Data format v1.2
- **Author/Contact**: Daniel Stolzberg, PhD (daniel.stolzberg@gmail.com)
- **Repository**: https://github.com/dstolz/epsych2
