# epsych.Runtime

`epsych.Runtime` is the session-state container used during experiment execution. `epsych.RunExpt` creates a fresh instance on each Run/Preview and passes it to every timer callback, GUI, and analysis object.

This is a developer reference. For the operator's view of a session, see [../overviews/RunExpt_GUI_Overview.md](../overviews/RunExpt_GUI_Overview.md).

Source class:

- [obj/+epsych/@Runtime/Runtime.m](../../obj/+epsych/@Runtime/Runtime.m)

Primary method files:

- `all_parameters.m`, `find_parameter.m`, `filter_parameters.m` — parameter queries
- `dispatchNextTrial.m`, `resolveTriggerParameters.m` — trial dispatch
- `updateTrialsFromParameters.m` — trial-table sync
- `writeParametersProtocol.m`, `readParameters.m`, `phaseParameterData.m`, `phaseCache.m` — phase persistence (phases are protocol files)
- `writeParametersJSON.m`, `readParametersJSON.m`, `createTemplateJSON.m` — legacy JSON phase format

## Responsibilities

- connect and hold the hardware/software interfaces defined by the protocol
- store and expose runtime trial state (`TRIALS`)
- resolve and cache the required trigger parameters (`TRIGGERS`)
- provide cross-interface parameter query/filter utilities
- dispatch trial parameter values and triggers to hardware
- synchronize writable trial columns from live parameter values

## Core properties

| Property | Meaning |
| --- | --- |
| `Interfaces` | The `hw.Interface` array borrowed from the protocol. Assigning this property connects any disconnected interface and sets each interface's `Runtime` back-reference. |
| `Protocol` | The session `epsych.Protocol` whose `Interfaces` this runtime borrows (assigned by `RunExpt.ExptDispatch`). Because the parameter handles are shared, serializing it snapshots the live session — this is how `writeParametersProtocol` saves a phase. |
| `TRIALS` | Per-subject struct array of trial state (see below). The first assignment resolves the required triggers, dispatches trial #1 for each subject, caches `P`, and records `StartTime`; later assignments (e.g., mid-run syncs) do not re-trigger hardware. |
| `TRIGGERS` | Per-subject cached handles to the required trigger parameters `NewTrial`, `ResetTrig`, `TrialComplete`. |
| `P` | Cached struct of all parameters (keyed by `validName`), populated when `TRIALS` is first set. GUI components use this instead of repeating lookups. |
| `EVENTS` | `epsych.EventHub` event broadcaster (`NewData`, `NewTrial`, `ModeChange`). |
| `TIMER` | The MATLAB `PsychTimer` object. |
| `NSubjects` | Number of subjects (read-only; derived from `TRIALS`). |
| `isTest` | True for Preview runs; recorded into every trial's data. |
| `DataFile`, `TempDataDir`, `DefaultDataPath` | Crash-recovery file paths and default data directory. |
| `Journal` | Per-subject [`epsych.TrialJournal`](epsych_TrialJournal.md); the append-only file each completed trial is written to. |
| `StartTime` | Session start `datetime`. |

Note: `epsych.Runtime` subclasses `dynamicprops`, so some workflows attach extra properties at runtime — for example `readParameters` adds a `Phase` property that logs which phase files were loaded and when.

### Renamed properties (2026-08)

Three properties were renamed to say what they hold. The old names remain as hidden, silently forwarding aliases so paradigm code outside this repository — custom save functions, timer functions, box GUIs — keeps working; they will be removed once those folders have been migrated.

| Old name | New name | Why |
| --- | --- | --- |
| `HELPER` | `EVENTS` | The class it holds is now `epsych.EventHub` (was `epsych.Helper`, a name that said nothing and collided with the unrelated `gui.Helper`). |
| `CORE` | `TRIGGERS` | It holds the `REQUIRED_TRIGGERS` parameters; `CORE` in caps read like a constant. Its resolver is now `resolveTriggerParameters`. |
| `dfltDataPath` | `DefaultDataPath` | Same concept, same spelling as the `DefaultDataPath` project field that feeds it and the `RunExpt.DefaultDataPath` it is copied from. |

`psychophysics.Psych` and `psychophysics.Detection` renamed their `Helper` property to `Events` on the same terms — the psych object still exposes a read-only `Helper` alias, so `listener(pObj.Helper,'NewData',…)` in an existing GUI keeps working.

### Ownership of hardware interfaces

The Runtime *borrows* interfaces from the `epsych.Protocol`; it does not own them. On Stop the interfaces are returned to Idle but stay connected so the next run can reuse the connection (some backends, e.g. TDT RPcoX/zBus, cannot survive a delete/recreate cycle mid-session). Hardware is released when the RunExpt window closes.

### The TRIALS struct

Each `TRIALS(i)` element is built by `ep_TimerFcn_Start` and contains (selected fields):

| Field | Meaning |
| --- | --- |
| `parameters` | Compiled `hw.Parameter` array, one per trial-table column |
| `trials` | Cell matrix: rows = trial conditions, columns = parameter values |
| `writeparams` / `writeParamIdx` | Writable-parameter names and their column indices |
| | These four fields are only meaningful together and are installed together, by `epsych.Runtime.compiledTrialColumns(COMPILED)` — at session start and again after every safe-boundary recompile. Replacing `trials` without rebuilding the map leaves every by-name column lookup pointing at the wrong parameter, because a recompile that adds or removes a parameter (phase load, operator recompile, a selector that creates its own runtime parameters) shifts every column after the change. Regression test: `tmp/smoke_test_recompile_columns.m` |
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

This is how GUI edits (e.g., `gui.components.Parameter_Update` commits, phase loads) propagate into the trial table mid-run without recompiling the protocol.

## Trigger resolution and trial dispatch

### resolveTriggerParameters

Locates and caches the mandatory trigger parameters for one subject. The expected parameter names follow the pattern `x_<Trigger>_<BoxID>`:

- `x_NewTrial_<BoxID>`
- `x_ResetTrig_<BoxID>`
- `x_TrialComplete_<BoxID>`

An error is raised immediately if any required trigger is missing from the protocol, so include these in every protocol that runs through the standard timer functions.

`TrialComplete` is **polled**, so it has to hold a number the poll can test. `hw.Module.add_parameter` fills `Values`, not `Value`, so a trigger declared in code and never assigned reads back **empty** — and `if ~[]` is false, which used to complete a trial on every tick and run a whole session ballistically at the timer period. Two things now prevent that:

- `resolveTriggerParameters` seeds an empty **software** trigger to 0 as it caches it, logging that it did. Hardware-backed triggers are left alone: assigning `Value` there would write to the device.
- `ep_TimerFcn_RunTime` treats anything that is not a definite scalar number as "not yet" — empty, `NaN` (what a failed or write-only read returns), or a non-numeric reply never advances the trial.

Protocols should still seed their own triggers (`p = sw.add_parameter('x_TrialComplete_1', 0, isTrigger = true); p.Value = 0;`), as the shipped examples do; the runtime's seeding is a backstop for protocols already saved without it.

### dispatchNextTrial

Per subject, in order:

1. fire `TRIGGERS.ResetTrig` so hardware returns to a known state
2. write the selected trial row's values into the writable parameters — only parameters whose `Access` is not `'Read'` **and** whose `UpdateEveryTrial` flag is true are written. Parameters flagged `SetOnce` (the default for `Coefficient Buffer` types) join the very first dispatch of the session only, so their value reaches the hardware once and is then left alone; parameters with both flags false are never written by the per-trial dispatch
3. fire `TRIGGERS.NewTrial`
4. broadcast the `NewTrial` event with an `epsych.TrialsData` payload

## Phase persistence (phases are protocols)

Phases and protocols share one format: saving a phase serializes the session's `epsych.Protocol` to an `.eprot` file, and loading a phase reads a protocol file and applies its parameters to the live session.

```matlab
r.writeParametersProtocol('phase_A.eprot', 'Shaping stage'); % snapshot the session as a protocol
P = r.readParameters('phase_A.eprot');  % restore values; returns resolved hw.Parameter array
[pd, md] = epsych.Runtime.phaseParameterData('phase_A.eprot'); % inspect without applying
```

Because `Interfaces` are the protocol's own handles, `writeParametersProtocol` starts from the live parameter values, then reconciles the serialized snapshot with the session's effective values before writing: a deferred `gui.components.Parameter_Update` commit that only reached `TRIALS.trials` (dispatch copies it onto the parameter at the next boundary) is captured, and each single-level parameter's design-time `Values` list is refreshed to the effective value so the recompile a later phase load schedules reproduces the runtime edit instead of reverting it. Roved, expression-driven, randomized, trigger, read-only, and per-trial-managed (non-uniform trial-table column, e.g. a staircase) parameters keep their design state. The live protocol object is never mutated; the saved file records the source protocol's version and opens anywhere a protocol does, including `epsych.ProtocolDesigner`. `readParameters` matches each saved parameter to a live interface by `ParentType` and by `Name`, restores metadata, design-time `Values`, and `Value` (an `Expression` in the file, or preserved from the live parameter when the file has none, takes precedence over the saved literal), and skips entries with no live match.

Parameters holding **transient session-control state** are the exception: `hw.Parameter.isTransientControl` identifies triggers, plus writable `Boolean` parameters the trial dispatcher never refreshes (`UpdateEveryTrial == false` and `SetOnce == false`) — the operator's live toggles and momentary buttons. Their metadata and design-time `Values` are restored, but their value is left to the running session, because a phase file records whatever those buttons happened to be doing when it was saved: restoring one re-asserts a stale button press, and a phase saved with a "deliver trials" toggle active would start delivering trials on load. The `UpdateEveryTrial` term is what separates a control toggle from a genuine Boolean setting — a parameter the dispatcher does refresh is overwritten from the trial table on the next trial anyway, so its saved value is design state and restoring it is safe. Non-Boolean types are never transient, so a one-time numeric setup value still travels with the phase. The same predicate keeps `writeParametersProtocol` from promoting a button press into design-time `Values`.

When a session is running, `readParameters` also sets `TRIALS.RECOMPILE_REQUESTED` for subjects running the session protocol, so `ep_TimerFcn_RunTime` recompiles the protocol at the next safe trial boundary and regenerates `TRIALS.trials` from the loaded phase's design-time `Values` and `Expressions` — a phase load is a full protocol swap, not just a value patch. (Current values are still synced into the existing trial table immediately via `updateTrialsFromParameters`, covering trials dispatched before the boundary.)

These files back the **experiment phase** workflow: parameter sets saved per training phase and reloaded between blocks without restarting the session. `gui.components.PhaseSelector` provides the GUI for this (see [../gui/](../gui/)). Loaded phases are logged in the dynamic `Phase` property with a timestamp, source path, and `Source` tag (`"Protocol"` or `"JSON"`).

Legacy JSON snapshots written by `writeParametersJSON` remain loadable through the same `readParameters` path (`readParametersJSON` is now a back-compat wrapper), and `epsych.Runtime.createTemplateJSON` still writes a starter file for the JSON format.

### How a phase file is read

`phaseParameterData` is the single chokepoint every phase read goes through, and it does two things to keep a phase load off the operator's critical path.

**It reads the parameter structs directly.** An `.eprot` stores exactly `hw.Parameter.toStruct` output (see `epsych.Protocol.toStruct`), which is `phaseParameterData`'s own output contract — so when the file's shape is recognized in full, the structs are read straight out of the MAT file. `epsych.Protocol.load` remains the authority and the automatic fallback: it rebuilds every interface, module, parameter, and `stimgen` object, without connecting hardware, only for those objects to be serialized straight back to structs. The fast path is refused, and the fallback taken, unless the file carries `formatVersion == 1.0`, the full protocol metadata set, a non-empty `InterfaceData`, and every `toStruct` field on every parameter — so legacy files, files whose interfaces are recoverable only from `COMPILED.writeparams`, hand-built files, and any future format revision keep the old behavior. Pass `FastParse=false` to force the fallback. Where the two paths differ (an expression's `Value` is re-evaluated by the fallback, a random `Value` re-drawn, `'Read / Write'` normalized to `'Any'`, `lastUpdated` restamped) every consumer re-derives the field from the live parameter or overwrites it; `tmp/smoke_test_phase_fastparse.m` is the standing proof.

**It memoizes the result.** `epsych.Runtime.phaseCache` keys parses on the file's canonical path, modification time, and size, so a phase re-saved mid-session is re-parsed automatically. One preview-plus-Load in `gui.components.PhaseSelector` asks for the same file three times and browsing the dropdown asks once per selection; all of those now share one parse. The cache holds value data only — an entry whose `UserData` carries a handle is deliberately not cached — so a hit is indistinguishable from a fresh parse. It keeps the eight most recently used phases. `phaseCache('clear')`, `phaseCache('disable')`, and `clear functions` are the escape hatches; `phaseCache('stats')` reports hits and parses.

```matlab
epsych.Runtime.phaseCache('clear')                 % drop every cached parse
epsych.Runtime.phaseParameterData(f, UseCache=false, FastParse=false)  % force the original path
```

## Typical usage

Most code receives an already-initialized Runtime rather than building one. Interactive inspection from the base workspace (RunExpt: **Help → Diagnostics → Assign RUNTIME to Command Window**):

```matlab
p = RUNTIME.find_parameter('Depth');
p.Value = 0.5;

readables = RUNTIME.all_parameters(Access='Read', asStruct=true);
RUNTIME.updateTrialsFromParameters(RUNTIME.all_parameters(Access='All'));
```

## Related documentation

- [epsych_TrialLifecycle.md](epsych_TrialLifecycle.md) — how the Runtime drives a session trial by trial
- [epsych_Protocol.md](epsych_Protocol.md) — where interfaces and compiled trials come from
- [Event_Notifications.md](Event_Notifications.md) — the `EVENTS` event model
- [../hw/hw_Parameter.md](../hw/hw_Parameter.md) — parameter behavior, including `UpdateEveryTrial`
