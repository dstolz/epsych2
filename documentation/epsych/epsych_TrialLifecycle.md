# Trial Lifecycle Overview

**Subsystem:** `epsych` runtime  
**Related files:**
- [`obj/+epsych/@Runtime/Runtime.m`](../../obj/+epsych/@Runtime/Runtime.m)
- [`runtime/timerfcns/ep_TimerFcn_Start.m`](../../runtime/timerfcns/ep_TimerFcn_Start.m)
- [`runtime/timerfcns/ep_TimerFcn_RunTime.m`](../../runtime/timerfcns/ep_TimerFcn_RunTime.m)
- [`runtime/timerfcns/ep_TimerFcn_Stop.m`](../../runtime/timerfcns/ep_TimerFcn_Stop.m)
- [`obj/+epsych/@TrialSelector/TrialSelector.m`](../../obj/+epsych/@TrialSelector/TrialSelector.m)
- [`obj/+epsych/@DefaultTrialSelector/DefaultTrialSelector.m`](../../obj/+epsych/@DefaultTrialSelector/DefaultTrialSelector.m)
- [`obj/+hw/@Parameter/Parameter.m`](../../obj/+hw/@Parameter/Parameter.m)

---

## Overview

EPsych runs experiments as a continuous loop of discrete **trials**. Each trial corresponds to one row in the compiled trials matrix, representing a unique combination of stimulus parameters. A MATLAB timer fires repeatedly throughout the session; each tick of that timer is the engine that detects trial completion, saves data, selects the next trial, and dispatches parameters to hardware.

This document describes the full lifecycle of a single trial — from session startup through completion — and explains how parameters flow between the protocol definition, runtime state, and hardware/software interfaces.

---

## Key Data Structures

### `RUNTIME.TRIALS(i)`

The central per-subject state struct. Important fields:

| Field | Description |
|---|---|
| `parameters` | Array of `hw.Parameter` objects, one per protocol column |
| `trials` | Cell matrix: rows = unique trial conditions, columns = parameter values |
| `selector` | `epsych.TrialSelector` instance responsible for choosing the next row |
| `TrialIndex` | Incrementing counter of completed trials (1-based) |
| `NextTrialID` | Row index into `trials` that will be dispatched on the next tick |
| `DATA` | Struct array accumulating response data, one entry per completed trial |
| `FORCE_TRIAL` | Flag: skip waiting for hardware completion and advance immediately |
| `RECOMPILE_REQUESTED` | Flag: operator has requested a protocol recompile at the next trial boundary |
| `Subject` | Subject metadata struct |
| `BoxID` | Hardware box identifier for this subject |

### `RUNTIME.CORE(i)`

Cached handles to the three mandatory hardware trigger parameters for subject `i`:

| Field | Purpose |
|---|---|
| `NewTrial` | Pulse sent to hardware to signal a new trial has started |
| `ResetTrig` | Pulse sent before writing parameters to reset hardware state |
| `TrialComplete` | Polled each timer tick; goes high when the hardware finishes a trial |

These are resolved once at startup by `resolveCoreParameters` and reused every trial to avoid repeated parameter lookups.

---

## Trial Lifecycle Diagram

```
Session Start
     │
     ▼
ep_TimerFcn_Start
  ├── Compile protocol → populate TRIALS.parameters, TRIALS.trials
  ├── Create selector (epsych.TrialSelector.create)
  ├── selector.initialize(TRIALS)
  ├── Resolve CORE triggers (NewTrial, ResetTrig, TrialComplete)
  ├── Select first NextTrialID
  └── dispatchNextTrial (Trial #1)
            │
            ▼
    ┌───────────────────────┐
    │  Timer tick fires     │  ←──────────────────────────┐
    │  ep_TimerFcn_RunTime  │                             │
    └───────────────────────┘                             │
            │                                             │
            ▼                                             │
    Poll TrialComplete                                    │
    (hardware tag)                                        │
            │                                             │
     ┌──────┴──────┐                                     │
     │ Not done?   │ → skip, wait for next tick           │
     └──────┬──────┘                                     │
            │ Trial done                                  │
            ▼                                             │
    Collect Read parameters → build data struct           │
    Store in TRIALS.DATA(TrialIndex)                      │
    Append trial to .mat file on disk                     │
    selector.onComplete(trialID, data)                    │
    Broadcast NewData event                               │
    Increment TrialIndex                                  │
            │                                             │
            ▼                                             │
    (Optional) Operator recompile                         │
            │                                             │
            ▼                                             │
    selector.selectNext → NextTrialID                     │
            │                                             │
            ▼                                             │
    dispatchNextTrial ──────────────────────────────────► │
      ├── ResetTrig.trigger()                             │
      ├── Write TRIALS.trials(NextTrialID, :) to          │
      │   all writable hw.Parameter objects              │
      ├── NewTrial.trigger()                             │
      └── Broadcast NewTrial event                       │
            │                                             │
            └─────────────────────────────────────────── ┘
                       (repeat for each trial)

Session Stop
  └── ep_TimerFcn_Stop: set all interfaces to Idle
```

---

## Phase 1 — Session Startup (`ep_TimerFcn_Start`)

Before the first trial runs, `ep_TimerFcn_Start` initializes every subject's runtime state:

1. **Compile the protocol.** The compiled protocol (previously generated by the Experiment Design GUI or `ep_CompileProtocol`) provides:
   - `TRIALS.parameters` — `hw.Parameter` array, one per column of the trials matrix.
   - `TRIALS.trials` — cell matrix of all unique trial conditions (rows) × parameter values (columns).

2. **Create and initialize the trial selector.** `epsych.TrialSelector.create(selectorConfig)` returns the appropriate selector subclass (default: `epsych.DefaultTrialSelector`). `selector.initialize(TRIALS)` sets up internal counts or any adaptive state.

3. **Resolve CORE triggers.** `Runtime.resolveCoreParameters(i)` searches for the three required hardware trigger parameters (`NewTrial`, `ResetTrig`, `TrialComplete`) scoped to the subject's box ID and caches them in `RUNTIME.CORE(i)`. An error is thrown immediately if any trigger is missing.

4. **Create temporary data file.** A `.mat` file is created in `RUNTIME.TempDataDir` to accumulate per-trial data. Trials are appended incrementally so a crash loses only the current in-progress trial.

5. **Select and dispatch trial #1.** `selector.selectNext` returns the first `NextTrialID`, then `dispatchNextTrial` sends it to hardware.

---

## Phase 2 — Trial Dispatch (`dispatchNextTrial`)

`dispatchNextTrial` is called at session start and immediately after each trial completes. It programs hardware with the parameters for the *upcoming* trial (identified by `TRIALS.NextTrialID`):

1. **Reset hardware state** — `CORE.ResetTrig.trigger()` fires a reset pulse so hardware components return to a known idle state before new values are written.

2. **Write writable parameters** — All `hw.Parameter` objects whose `Access` is not `'Read'` receive the values from the selected trial row:
   ```matlab
   [P.Value] = deal(trialRow{:});
   ```
   Setting `Value` on a hardware-backed parameter immediately pushes the value to the hardware. For software parameters, the value is stored locally.

3. **Start the trial** — `CORE.NewTrial.trigger()` fires a start pulse that tells the hardware to begin the trial (e.g., play a stimulus).

4. **Broadcast `NewTrial` event** — An `epsych.TrialsData` event is posted through `RUNTIME.HELPER`, notifying any registered listeners (e.g., GUIs, loggers) that a new trial has begun.

---

## Phase 3 — Trial Monitoring (`ep_TimerFcn_RunTime`)

The MATLAB timer fires on every tick. For each subject, the runtime checks whether the current trial has completed:

- **`TrialComplete` polling** — The `CORE.TrialComplete` parameter is read from hardware. If it is low (`false`), the timer exits immediately and waits for the next tick. No subject processing is skipped independently; each subject is checked in order.
- **`FORCE_TRIAL` override** — If `TRIALS.FORCE_TRIAL` is `true`, the completion check is bypassed and trial advancement proceeds unconditionally. This is useful for manual override or testing.

---

## Phase 4 — Trial Completion and Data Collection

When `TrialComplete` goes high:

1. **Read all readable parameters** — `RUNTIME.all_parameters(Access='Read')` returns every `hw.Parameter` accessible for reading. Values are collected into a `data` struct keyed by `validName`.

2. **Annotate with trial metadata:**
   ```matlab
   data.TrialIndex        = RUNTIME.TRIALS(i).TrialIndex;
   data.TrialID           = RUNTIME.TRIALS(i).NextTrialID;
   data.computerTimestamp = datetime('now');
   ```

3. **Store and save** — The data struct is appended to `TRIALS.DATA(TrialIndex)` in memory and saved to the `.mat` file under a unique variable name (`data_0001`, `data_0002`, …). Using `-append` ensures that previously saved trials are never overwritten.

4. **Notify the selector** — `selector.onComplete(trialID, data)` allows the selector to update adaptive state (e.g., staircase tracking) based on the response.

5. **Broadcast `NewData` event** — Listeners (GUIs, analysis tools) are notified that new trial data is available.

6. **Increment `TrialIndex`.**

---

## Phase 5 — Between-Trial Operations

After data is saved but before the next trial is dispatched, two optional operations may occur:

### Operator Recompile

If `TRIALS.RECOMPILE_REQUESTED` is `true` (set by the operator through a GUI), the protocol is recompiled at this safe boundary:
- `protocol.compile()` regenerates `TRIALS.parameters` and `TRIALS.trials`.
- `selector.onRecompile(TRIALS)` lets the selector reconcile its state (e.g., reset trial counts if the number of conditions changed).
- If recompile fails, the previous state is preserved and an error is logged.

### Trial Selection

`selector.selectNext(TRIALS)` returns the row index (`NextTrialID`) for the next trial. The default selector (`epsych.DefaultTrialSelector`) picks from the least-used active trials, breaking ties randomly — ensuring balanced trial presentation over time.

Custom selectors can implement any strategy (adaptive thresholding, blocked designs, etc.) by subclassing `epsych.TrialSelector` and implementing `initialize`, `selectNext`, and `onRecompile`.

---

## Parameter Flow

### Design Time → Runtime

At design time, the Experiment Design GUI assigns **trial levels** to each parameter:
- Each `hw.Parameter` stores its levels in its `Values` cell array.
- `ep_CompileProtocol` expands these into the `trials` cell matrix (rows = conditions, columns = parameters) and separates parameters into write and read lists.

### Runtime Write Path (MATLAB → Hardware)

```
TRIALS.trials(NextTrialID, col)
        │
        ▼
hw.Parameter.Value = <new value>
        │
        ▼
Parameter.PostUpdateFcn (if enabled)
        │
        ▼
Hardware interface write (e.g., TDT tag write)
```

Setting `hw.Parameter.Value` triggers any registered `PreUpdateFcn`, `EvaluatorFcn`, and `PostUpdateFcn` callbacks in sequence (when enabled), then delegates to the parent interface to write the value to the hardware.

### Runtime Read Path (Hardware → MATLAB)

```
hw.Parameter.Value  (getter)
        │
        ▼
Hardware interface read (e.g., TDT tag read)
        │
        ▼
data.(parameter.validName) = value
        │
        ▼
TRIALS.DATA(TrialIndex)
        │
        ▼
Appended to .mat file
```

### Parameter Persistence (JSON)

Parameters can be saved to and loaded from JSON files using `Runtime.writeParametersJSON` / `Runtime.readParametersJSON`. This supports **experiment phases** where parameter settings change between blocks without restarting the session. Each loaded phase is tracked in `RUNTIME.Phase` with a timestamp and source path.

The `updateTrialsFromParameters` method syncs writable `TRIALS` fields from current parameter values, keeping the trials matrix consistent with any runtime parameter adjustments.

---

## Parameter Access Modes

`hw.Parameter.Access` controls how each parameter participates in the trial lifecycle:

| Access | Write path | Read path |
|---|---|---|
| `'Write'` | Dispatched each trial | Not read back |
| `'Read'` | Not dispatched | Read at trial end |
| `'Read / Write'` or `'Any'` | Dispatched each trial | Read at trial end |

Trigger parameters (`isTrigger = true`) are excluded from normal dispatch and are only activated via `.trigger()`.

---

## Session Stop (`ep_TimerFcn_Stop`)

When the experiment ends, `ep_TimerFcn_Stop`:
1. Sets all interfaces to `hw.DeviceState.Idle`.
2. Broadcasts a `ModeChange` event.
3. Deletes the `RUNTIME.HELPER` event dispatcher.

Data accumulated in the temporary `.mat` file remains on disk. The GUI or save functions are responsible for consolidating and moving the final data file.

---

## Extending Trial Selection

To implement a custom trial selection strategy, subclass `epsych.TrialSelector`:

```matlab
classdef MyAdaptiveSelector < epsych.TrialSelector
    methods
        function initialize(obj, TRIALS)
            % Called once at session start.
            % Set up any internal state (e.g. staircase variables).
        end

        function nextTrialID = selectNext(obj, TRIALS)
            % Called after each trial completes.
            % Return a row index into TRIALS.trials.
            nextTrialID = ...;
        end

        function onRecompile(obj, TRIALS)
            % Called if the operator triggers a mid-session recompile.
            % Update internal state to match the new TRIALS struct.
        end

        function onComplete(obj, trialID, data)
            % Optional. Called with response data after each trial.
            % Update adaptive state here.
        end
    end
end
```

Register the selector in the Experiment Design GUI by entering the class name in the **Trial Function** field, or set `protocol.Options.trialFunc` programmatically.

---

## See Also

- [`documentation/epsych/epsych_Runtime.md`](epsych_Runtime.md) — `epsych.Runtime` property and method reference
- [`documentation/epsych/epsych_TrialSelector.md`](epsych_TrialSelector.md) — `epsych.TrialSelector` base class reference
- [`documentation/epsych/Event_Notifications.md`](Event_Notifications.md) — Runtime event system (`NewTrial`, `NewData`, `ModeChange`)
- [`documentation/hw/`](../hw/) — Hardware interface and `hw.Parameter` documentation
