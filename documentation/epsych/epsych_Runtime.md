# epsych.Runtime

`epsych.Runtime` is the session-state container used during experiment execution. `epsych.RunExpt` creates a fresh instance on each Run/Preview and passes it to every timer callback, GUI, and analysis object.

This is a developer reference. For the operator's view of a session, see [../overviews/RunExpt_GUI_Overview.md](../overviews/RunExpt_GUI_Overview.md).

Source class:

- [obj/+epsych/@Runtime/Runtime.m](../../obj/+epsych/@Runtime/Runtime.m)

Primary method files:

- `all_parameters.m`, `find_parameter.m`, `filter_parameters.m` — parameter queries
- `dispatchNextTrial.m`, `resolveCoreParameters.m` — trial dispatch
- `updateTrialsFromParameters.m` — trial-table sync
- `writeParametersProtocol.m`, `readParameters.m`, `phaseParameterData.m` — phase persistence (phases are protocol files)
- `writeParametersJSON.m`, `readParametersJSON.m`, `createTemplateJSON.m` — legacy JSON phase format

## Responsibilities

- connect and hold the hardware/software interfaces defined by the protocol
- store and expose runtime trial state (`TRIALS`)
- resolve and cache the required trigger parameters (`CORE`)
- provide cross-interface parameter query/filter utilities
- dispatch trial parameter values and triggers to hardware
- synchronize writable trial columns from live parameter values

## Core properties

| Property | Meaning |
| --- | --- |
| `Interfaces` | The `hw.Interface` array borrowed from the protocol. Assigning this property connects any disconnected interface and sets each interface's `Runtime` back-reference. |
| `Protocol` | The session `epsych.Protocol` whose `Interfaces` this runtime borrows (assigned by `RunExpt.ExptDispatch`). Because the parameter handles are shared, serializing it snapshots the live session — this is how `writeParametersProtocol` saves a phase. |
| `TRIALS` | Per-subject struct array of trial state (see below). The first assignment resolves `CORE` triggers, dispatches trial #1 for each subject, caches `P`, and records `StartTime`; later assignments (e.g., mid-run syncs) do not re-trigger hardware. |
| `CORE` | Per-subject cached handles to the required trigger parameters `NewTrial`, `ResetTrig`, `TrialComplete`. |
| `P` | Cached struct of all parameters (keyed by `validName`), populated when `TRIALS` is first set. GUI components use this instead of repeating lookups. |
| `HELPER` | `epsych.Helper` event broadcaster (`NewData`, `NewTrial`, `ModeChange`). |
| `TIMER` | The MATLAB `PsychTimer` object. |
| `NSubjects` | Number of subjects (read-only; derived from `TRIALS`). |
| `isTest` | True for Preview runs; recorded into every trial's data. |
| `DataFile`, `TempDataDir`, `dfltDataPath` | Crash-recovery file paths and default data directory. |
| `StartTime` | Session start `datetime`. |

Note: `epsych.Runtime` subclasses `dynamicprops`, so some workflows attach extra properties at runtime — for example `readParameters` adds a `Phase` property that logs which phase files were loaded and when.

### Ownership of hardware interfaces

The Runtime *borrows* interfaces from the `epsych.Protocol`; it does not own them. On Stop the interfaces are returned to Idle but stay connected so the next run can reuse the connection (some backends, e.g. TDT RPcoX/zBus, cannot survive a delete/recreate cycle mid-session). Hardware is released when the RunExpt window closes.

### The TRIALS struct

Each `TRIALS(i)` element is built by `ep_TimerFcn_Start` and contains (selected fields):

| Field | Meaning |
| --- | --- |
| `parameters` | Compiled `hw.Parameter` array, one per trial-table column |
| `trials` | Cell matrix: rows = trial conditions, columns = parameter values |
| `writeparams` / `writeParamIdx` | Writable-parameter names and their column indices |
| `selector` | `epsych.TrialSelector` instance for this subject |
| `TrialIndex` / `NextTrialID` | Completed-trial counter and next trial row |
| `DATA` | Struct array of per-trial response data |
| `FORCE_TRIAL` / `RECOMPILE_REQUESTED` | Operator override flags |
| `Subject`, `BoxID`, `DataFilename` | Subject metadata and output file |

See [epsych_TrialLifecycle.md](epsych_TrialLifecycle.md) for how these fields are used across a session.

## Parameter query APIs

### all_parameters

```matlab
P = r.all_parameters(...
    includeInvisible=false, includeTriggers=false, includeArray=true, ...
    Access='Read', Interface={}, asStruct=false, valueOnly=false);
```

- Concatenates parameters from every interface (optionally restricted to specific interface classes via `Interface`).
- `Access` filters by access mode; the default is `'Read'` — pass `'All'` for no filtering.
- `asStruct=true` returns a struct keyed by each parameter's `validName`.
- `valueOnly=true` returns values instead of `hw.Parameter` handles (used by `ep_TimerFcn_RunTime` to snapshot trial data).

### find_parameter

```matlab
P = r.find_parameter(name, includeInvisible=false, includeTriggers=false, ...
    silenceParameterNotFound=false);
```

Resolves one or more names (short `'Param'` or qualified `'Module.Param'`) to `hw.Parameter` handles, preserving the requested order. Set `silenceParameterNotFound=true` to make optional parameters safe to probe.

### filter_parameters

```matlab
P = r.filter_parameters(propertyName, propertyValue, testFcn=@isequal, ...
    includeInvisible=false, includeTriggers=false);
```

Returns parameters whose property values satisfy `testFcn` (e.g., `@contains`, `@startsWith`).

## Trial sync API

### updateTrialsFromParameters

```matlab
r.updateTrialsFromParameters(parameters);
```

- Uses `TRIALS.writeparams` to decide which incoming parameters are writable.
- Uses `TRIALS.writeParamIdx` to map parameter names to compiled trial columns.
- Writes current parameter values into every row of the corresponding `TRIALS.trials` column.

This is how GUI edits (e.g., `gui.Parameter_Update` commits, phase loads) propagate into the trial table mid-run without recompiling the protocol.

## Trigger resolution and trial dispatch

### resolveCoreParameters

Locates and caches the mandatory trigger parameters for one subject. The expected parameter names follow the pattern `x_<Trigger>_<BoxID>`:

- `x_NewTrial_<BoxID>`
- `x_ResetTrig_<BoxID>`
- `x_TrialComplete_<BoxID>`

An error is raised immediately if any required trigger is missing from the protocol, so include these in every protocol that runs through the standard timer functions.

### dispatchNextTrial

Per subject, in order:

1. fire `CORE.ResetTrig` so hardware returns to a known state
2. write the selected trial row's values into the writable parameters — only parameters whose `Access` is not `'Read'` **and** whose `UpdateEveryTrial` flag is true are written; parameters with `UpdateEveryTrial = false` are set once and left unchanged across trials
3. fire `CORE.NewTrial`
4. broadcast the `NewTrial` event with an `epsych.TrialsData` payload

## Phase persistence (phases are protocols)

Phases and protocols share one format: saving a phase serializes the session's `epsych.Protocol` to an `.eprot` file, and loading a phase reads a protocol file and applies its parameters to the live session.

```matlab
r.writeParametersProtocol('phase_A.eprot', 'Shaping stage'); % snapshot the session as a protocol
P = r.readParameters('phase_A.eprot');  % restore values; returns resolved hw.Parameter array
[pd, md] = epsych.Runtime.phaseParameterData('phase_A.eprot'); % inspect without applying
```

Because `Interfaces` are the protocol's own handles, `writeParametersProtocol` starts from the live parameter values, then reconciles the serialized snapshot with the session's effective values before writing: a deferred `gui.Parameter_Update` commit that only reached `TRIALS.trials` (dispatch copies it onto the parameter at the next boundary) is captured, and each single-level parameter's design-time `Values` list is refreshed to the effective value so the recompile a later phase load schedules reproduces the runtime edit instead of reverting it. Roved, expression-driven, randomized, trigger, read-only, and per-trial-managed (non-uniform trial-table column, e.g. a staircase) parameters keep their design state. The live protocol object is never mutated; the saved file records the source protocol's version and opens anywhere a protocol does, including `epsych.ProtocolDesigner`. `readParameters` matches each saved parameter to a live interface by `ParentType` and by `Name`, restores metadata, design-time `Values`, and `Value` (an `Expression` in the file, or preserved from the live parameter when the file has none, takes precedence over the saved literal), and skips entries with no live match.

When a session is running, `readParameters` also sets `TRIALS.RECOMPILE_REQUESTED` for subjects running the session protocol, so `ep_TimerFcn_RunTime` recompiles the protocol at the next safe trial boundary and regenerates `TRIALS.trials` from the loaded phase's design-time `Values` and `Expressions` — a phase load is a full protocol swap, not just a value patch. (Current values are still synced into the existing trial table immediately via `updateTrialsFromParameters`, covering trials dispatched before the boundary.)

These files back the **experiment phase** workflow: parameter sets saved per training phase and reloaded between blocks without restarting the session. `gui.PhaseSelector` provides the GUI for this (see [../gui/](../gui/)). Loaded phases are logged in the dynamic `Phase` property with a timestamp, source path, and `Source` tag (`"Protocol"` or `"JSON"`).

Legacy JSON snapshots written by `writeParametersJSON` remain loadable through the same `readParameters` path (`readParametersJSON` is now a back-compat wrapper), and `epsych.Runtime.createTemplateJSON` still writes a starter file for the JSON format.

## Typical usage

Most code receives an already-initialized Runtime rather than building one. Interactive inspection from the base workspace (RunExpt: **Help → Assign RUNTIME to Command Window**):

```matlab
p = RUNTIME.find_parameter('Depth');
p.Value = 0.5;

readables = RUNTIME.all_parameters(Access='Read', asStruct=true);
RUNTIME.updateTrialsFromParameters(RUNTIME.all_parameters(Access='All'));
```

## Related documentation

- [epsych_TrialLifecycle.md](epsych_TrialLifecycle.md) — how the Runtime drives a session trial by trial
- [epsych_Protocol.md](epsych_Protocol.md) — where interfaces and compiled trials come from
- [Event_Notifications.md](Event_Notifications.md) — the `HELPER` event model
- [../hw/hw_Parameter.md](../hw/hw_Parameter.md) — parameter behavior, including `UpdateEveryTrial`
