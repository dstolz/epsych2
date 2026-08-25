# Multi-Subject / Multi-Box Support: Evaluation & Restoration Plan

## Context

EPsych v1 ran several subjects simultaneously (one behavior box each, one shared timer loop). The v2 rewrite kept the multi-subject skeleton in the trial engine, but newer code has drifted toward single-subject assumptions. Goal: evaluate the current state and restore the ability to (a) load an individual protocol per subject/box, (b) run/stop boxes individually or together, and (c) support per-box sub-GUIs launched as needed.

## Evaluation: current state

### What still works (multi-subject aware)

- **Configuration layer**: `RunExpt.CONFIG` is a `(1,:)` per-subject struct array (`obj/+epsych/@RunExpt/RunExpt.m:22`). `AddSubject` supports up to 16 boxes with unique BoxIDs and a distinct protocol file per subject; `RemoveSubject`, `SortBoxes`, per-subject `EditProtocol`/`UpdateProtocol`/`ChangeProtocolFile` context actions all index the selected subject. The `.ecfg` save/load layer was removed 2026-08-19 (plans/remove-config-subsystem.md); sessions are assembled from the roster. SelfTest check D5 explicitly guards multi-subject CONFIG capacity.
- **Trial engine**: `ep_TimerFcn_Start` builds `TRIALS(i)` per subject (own selector, own temp data file, `BoxID`); `ep_TimerFcn_RunTime` loops `1:NSubjects` with per-subject trial-complete polling, data append, recompile, and selector calls. `Runtime.dispatchNextTrial(i)` / `resolveCoreParameters(i)` are per-subject; triggers resolve as `x_<Trigger>_<BoxID>`.
- **Events**: `epsych.TrialsData` carries `Subject` + `BoxID`, so listeners *can* filter. `gui.components.ParameterScatter` already filters by BoxID; `gui.components.OnlinePlot` and `gui.components.Triggers` take a BoxID argument.
- **Saving**: `ep_SaveDataFcn` loops subjects and saves one file per subject; `SessionDataFilename` is reserved per subject.

### What is broken (single-subject drift)

1. **CRITICAL — hardware comes only from subject 1's protocol** (`obj/+epsych/@RunExpt/ExptDispatch.m:80`): `RUNTIME.Interfaces = CONFIG(1).PROTOCOL.Interfaces`. Every subject's protocol is a separate `epsych.Protocol` object (even loading the same .eprot file), and `COMPILED.parameters` are `hw.Parameter` handles into *that protocol's own* interface copies. Only subject 1's copies get connected; subjects 2+ dispatch trial parameters into orphan objects whose backend `set_parameter` silently no-ops when `~IsConnected` (e.g. `obj/+hw/@TDT_RPcox/TDT_RPcox.m:469`). Net effect: subject 2+ hardware never receives per-trial parameter values — a silent failure.
2. **Run/stop is all-or-nothing**: one `PsychTimer`; the bottom bar is `Run / Preview / Pause / Stop` for the whole session (`obj/+epsych/@RunExpt/buildUI.m:124-169`). "Pause" is only a ModeChange broadcast — nothing gates trial dispatch per box. Any interface entering Idle auto-stops the *entire* session (`RunExpt.m:471-478`, `PsychTimerRunTime`).
3. **One BoxFig per session** (`obj/+epsych/@RunExpt/PsychTimerStart.m:17-29`): a single `feval(FUNCS.BoxFig, RUNTIME)`; no subject index passed. (Accepted: sub-GUIs are launched manually as needed.)
4. **`gui.BoxGUI` is a singleton per class** (`obj/+gui/@BoxGUI/BoxGUI.m:432-450`): `closeExistingInstance_` keys on `PreferenceTag` (defaults to the class name). (Accepted for now; out of scope.)
5. **`gui.components.Parameter_Update` is single-subject by admission** (`obj/+gui/Parameter_Update.m:161` — "CURRENTLY ONLY WORKS FOR SINGLE SUBJECT"): `R.TRIALS.trials` scalar dot-indexing errors on a TRIALS array. This is the commit path behind every BoxGUI "Update" button.
6. **`psychophysics.Psych` has no box filter** (`obj/+psychophysics/Psych.m:95-107`): `update_data` overwrites `DATA` on *every* NewData event, so a Detection/Staircase object for box 1 ingests box 2's trials — cross-contaminated analysis in any multi-box session.
7. **Trial data capture is unscoped** (`runtime/timerfcns/ep_TimerFcn_RunTime.m:40`): the comment claims Read parameters are "scoped to this subject's box" but `all_parameters` has no box filter — every subject's saved trial rows include every box's readouts.
8. **Backend constraints**: `hw.Bpod` hard-errors on `NSubjects > 1` and two Bpods per session is unsupported; `hw.Teensy` tracks `BoxIDs` (plural — closest to multi-box ready); `hw.TDT_RPcox` supports the v1-style `~<BoxID>` tag suffix convention (one circuit, many boxes).
9. **Minor**: phase save/load (`RUNTIME.Protocol`) snapshots subject 1's protocol only; webcam recording is named after subject 1's data file; `cl/@cl_AppetitiveDetection_GUI_B/eval_rwdelay_training_mode.m` is flagged single-subject.

### Verdict

The trial engine core retained v1's multi-subject looping and is largely sound. The breaks are concentrated in (a) hardware interface aggregation (item 1 — the showstopper), (b) the operator-facing layer (global run state, Parameter_Update), and (c) analysis-object event filtering.

## Recommended approach

Decisions: support **both** hardware topologies, with the abstraction declaring what each backend is capable of — single-connection hardware (TDT) serves all boxes from one connection and its circuit design must account for multiple subjects (`~BoxID` tags); multi-instance hardware (Teensy, Bpod) connects one device per box. **Per-box pause/stop within a running session** (not late-start). **No multi-box-GUI framework** — sub-GUIs are launched manually as needed/wanted; the plan only fixes the pieces those sub-GUIs depend on (Parameter_Update, Psych filtering).

### Phase A — Core correctness (prerequisite for everything else)

**A0. Declare connection capability on `hw.Interface`**
Add capability metadata each backend defines (constant properties or a `getConnectionCapability()` static): (1) **connection scope** — `Singleton` (one connection per system: `hw.TDT_RPcox`, `hw.TDT_Synapse`) vs. `PerDevice` (multiple simultaneous connections keyed by device identity, e.g. serial `Port`: `hw.Teensy`, `hw.Bpod`, `hw.Intan_RHX`); and (2) **boxes per connection** — multi-box (TDT circuit via `~BoxID` tags; Teensy via its `BoxIDs` list) vs. single-box (Bpod: one state machine). `hw.Software` is trivially multi-box. This makes the aggregation rule data-driven rather than special-cased.

**A1. Aggregate interfaces across all subjects' protocols** — `obj/+epsych/@RunExpt/ExptDispatch.m:75-102`
Replace `CONFIG(1).PROTOCOL.Interfaces` with a capability-driven union over all `CONFIG(i).PROTOCOL.Interfaces`:
- `Singleton` scope: exactly one instance of that class connects (first subject's); additional copies from other protocols are folded into it. Error if their configurations conflict (different circuit files/module specs) — the shared circuit must be designed for all boxes.
- `PerDevice` scope: dedupe by identity key (`Port`); each distinct device connects. Error if a single-box device (Bpod) is claimed by more than one subject's BoxID.
`RUNTIME.Protocol` stays subject 1's for phase saves (document as known limitation).

**A2. Remap every subject's compiled parameters onto the connected interface set** — `runtime/timerfcns/ep_TimerFcn_Start.m:28`
After building `T(i)`, re-resolve `T(i).parameters` by name against `RUNTIME.Interfaces`, generalizing the alias-matching already written in `obj/+epsych/@Protocol/resolveCompiledParameters_.m` (move/share the core as a reusable resolver on `epsych.Runtime`). **Hard-error on unresolved names** — the silent no-op write is exactly the failure being eliminated. Subject 1 resolves to identical handles, so single-subject behavior is unchanged.

**A3. Fix `gui.components.Parameter_Update` for TRIALS arrays** — `obj/+gui/Parameter_Update.m:152-189`
Add a `SubjectIdx` property (default 1); commit into `R.TRIALS(SubjectIdx).trials` / `.writeParamIdx`. Remove the single-subject caveat from documentation/gui/Parameter_Update.md. (Enables manually launched sub-GUIs to target a specific box.)

**A4. Box filter in `psychophysics.Psych`** — `obj/+psychophysics/Psych.m:95-107`
Add a `BoxID` property (empty = accept all, back-compat). Early-return in `update_data` when the event's BoxID doesn't match — same pattern as `obj/+gui/@ParameterScatter/ParameterScatter.m:234`. (Enables per-box analysis objects in manually launched sub-GUIs.)

**A5. Scope per-trial Read data to the subject's box** — `runtime/timerfcns/ep_TimerFcn_RunTime.m:40`
Add a `BoxID` option to `epsych.Runtime.all_parameters`: keep unsuffixed (global) parameters plus those whose `~N` name suffix matches; makes the existing comment true.

### Phase B — Per-box run control

**B1. Per-subject run state**: add `TRIALS(i).RunState` (Running/Paused/Stopped enum) initialized in `ep_TimerFcn_Start`; `ep_TimerFcn_RunTime` skips non-Running subjects at the top of the loop. Pause = finish in-flight trial, no next dispatch; Resume = dispatch pending trial; Stop = finalize that box's data (DATA stays in place for session-end save) and notify listeners.

**B2. RunExpt per-box controls**: subject-list context menu gains Pause/Resume/Stop-this-box (new `PauseSubject/ResumeSubject/StopSubject(idx)` methods on RunExpt); add a per-box state column to the subject list. Global Run/Preview/Pause/Stop buttons keep operating on all boxes. Broadcast per-box mode changes (add BoxID to `epsych.eventModeChange`) so per-box GUIs can react.

**B3. Scope the auto-stop**: `RunExpt.m:471-478` (`PsychTimerRunTime`) currently stops the whole session when any interface goes Idle. Map interfaces to boxes via each subject's `CORE(i)` trigger parameters' parent interface; an Idle interface stops only its boxes; the session stops when all boxes are stopped.

### Phase C — Backends, tests, docs

- **hw.Bpod**: change `prepareRecording`'s `NSubjects > 1` hard error to a per-box check (error only if more than one subject maps to *this* Bpod's `BoxID`); with A0/A1, one-Bpod-per-box on distinct COM ports becomes the supported path. Verify trigger naming (`x_*_<BoxID>`) stays disjoint per instance.
- **Smoke test** `tmp/smoke_test_multibox.m` (headless, `hw.Software` backends, pattern of existing `tmp/smoke_test_*.m`): 2 subjects, 2 protocols; assert (1) each subject's dispatch handles live on the connected interface set, (2) per-subject DATA isolation, (3) Parameter_Update commits to subject 2's trial table, (4) Psych BoxID filtering, (5) stopping box 1 leaves box 2 running and its data intact.
- **SelfTest**: new check — every subject's compiled write parameters resolve against the session interface set (this would have caught the A1/A2 defect).
- **Docs**: update `documentation/epsych/epsych_TrialLifecycle.md`, `epsych_Runtime.md`, `documentation/gui/Parameter_Update.md`, `documentation/overviews/RunExpt_GUI_Overview.md`, and `documentation/hw/hw_Interface_Tutorial.md` (document the new connection-capability contract for backend authors).

## Critical files

- `obj/+hw/@Interface/Interface.m` + concrete backends — connection-capability declaration (A0)
- `obj/+epsych/@RunExpt/ExptDispatch.m` — capability-driven interface aggregation (A1); auto-stop scoping lives in `PsychTimerRunTime` in `RunExpt.m` (B3)
- `runtime/timerfcns/ep_TimerFcn_Start.m` — parameter remap (A2), RunState init (B1)
- `runtime/timerfcns/ep_TimerFcn_RunTime.m` — RunState gating (B1), box-scoped data (A5)
- `obj/+epsych/@Runtime/Runtime.m` + `all_parameters.m` — name resolver (A2) + BoxID filtering (A5)
- `obj/+gui/Parameter_Update.m` — SubjectIdx commit (A3)
- `obj/+psychophysics/Psych.m` — BoxID filter (A4)
- `obj/+epsych/@RunExpt/buildUI.m`, `UpdateSubjectList.m` — per-box run controls in the subject list (B2)
- `obj/+hw/@Bpod/` — per-box multi-subject check (C)

## Verification

1. `tmp/smoke_test_multibox.m` headlessly (`matlab -batch`) — the five assertions above.
2. Existing smoke tests in `tmp/` still pass (single-subject regression: A2 must resolve subject 1 to identical handles; A1 must reproduce today's behavior for one subject).
3. Manual: RunExpt session with 2 software-backend subjects, distinct protocols → Preview; confirm independent per-box pause/stop from the subject list, and two data files each containing only its own box's fields. Manually launch a sub-GUI (e.g. `ep_GenericGUI`) and a `gui.components.ParameterScatter` bound to box 2; confirm correct per-box updates.
4. `epsych.SelfTest` on the 2-subject session — new resolver check passes; D5 passes.

## Sequencing

Phase A first (correctness; everything else depends on the remap). Phase B follows A. Phase C lands with each phase (smoke test alongside A, Bpod change with A1, docs at the end).

## Explicitly out of scope (per user direction)

- No multi-box-GUI framework: `gui.BoxGUI` stays single-instance and RunExpt keeps launching one session BoxFig. Per-box sub-GUIs are launched manually as needed; A3/A4 make that workable.
