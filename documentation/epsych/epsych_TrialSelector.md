# epsych.TrialSelector

**File:** `obj/+epsych/@TrialSelector/TrialSelector.m`  
**See also:** `obj/+epsych/@DefaultTrialSelector/DefaultTrialSelector.m`

---

## Overview

`epsych.TrialSelector` is the abstract base class for all trial selection strategies in EPsych. It defines the interface that the runtime uses to decide which trial to present next. You subclass it to implement custom selection logic — for example, weighted randomization, adaptive procedures, or interleaved protocols — without touching the runtime machinery.

The runtime instantiates a selector once per subject at run start via `epsych.TrialSelector.create(selectorConfig)` and stores it in `RUNTIME.TRIALS(i).selector`. From that point on the runtime calls `selectNext` before each trial and `onComplete` after each trial completes.

---

## Class Hierarchy

```
handle
 └── epsych.TrialSelector  (abstract)
      └── epsych.DefaultTrialSelector  (concrete, built-in)
      └── <YourCustomSelector>         (concrete, user-supplied)
```

---

## Runtime Lifecycle

The runtime calls the selector methods in this order:

| Stage | Timer function | Selector call |
|---|---|---|
| Run start | `ep_TimerFcn_Start` | `selector.initialize(TRIALS(i))`, then `selector.setRuntime(RUNTIME, i)`, then `selector.selectNext(TRIALS(i))` to pre-select the first trial |
| After each trial | `ep_TimerFcn_RunTime` | `selector.onComplete(NextTrialID, data)` then `selector.selectNext(TRIALS(i))` for the following trial |
| Operator recompile | `ep_TimerFcn_RunTime` | `selector.onRecompile(TRIALS(i))` then `selector.selectNext(TRIALS(i))` |

---

## Factory Method

### `epsych.TrialSelector.create(selectorConfig)`

Instantiates the correct selector based on the protocol `Options.trialFunc` field.

```matlab
selectorConfig = struct('trialFunc', C.PROTOCOL.Options.trialFunc);
sel = epsych.TrialSelector.create(selectorConfig);
```

**Logic:**
- If `trialFunc` is empty or `'< default >'`, returns an `epsych.DefaultTrialSelector`.
- If `trialFunc` is a class name string, calls `feval(className)` and validates the result is an `epsych.TrialSelector` subclass.
- Throws `epsych:TrialSelector:UnresolvableSelector` if the class cannot be found.

---

## Abstract Methods

You must implement all three of these in every subclass.

### `initialize(obj, TRIALS)`

Called once at run start. Use it to allocate and set up whatever internal state your selector needs (e.g., trial counts, adaptive model parameters).

```matlab
function initialize(obj, TRIALS)
    n = size(TRIALS.trials, 1);
    obj.myCount = zeros(n, 1);
end
```

**Parameters:**
- `TRIALS` — The runtime `TRIALS` struct for this subject (see [TRIALS struct fields](#the-trials-struct) below).

---

### `nextTrialID = selectNext(obj, TRIALS)`

Called before every trial (including the very first one). Returns the row index into `TRIALS.trials` for the trial to present next. Also responsible for updating any internal bookkeeping (e.g., incrementing a use counter).

```matlab
function nextTrialID = selectNext(obj, TRIALS)
    % pick a random active trial
    active = find(obj.active);
    nextTrialID = active(randi(numel(active)));
end
```

**Parameters:**
- `TRIALS` — Runtime `TRIALS` struct for this subject.

**Returns:**
- `nextTrialID` — Scalar integer row index into `TRIALS.trials`.

---

### `onRecompile(obj, TRIALS)`

Called when an operator triggers a protocol recompile mid-run. The number of trial rows may have changed. Reconcile your internal state to match the new `TRIALS` struct (e.g., resize count vectors, reset indices).

```matlab
function onRecompile(obj, TRIALS)
    newN = size(TRIALS.trials, 1);
    obj.myCount = zeros(newN, 1);
end
```

**Parameters:**
- `TRIALS` — Updated runtime `TRIALS` struct after the recompile.

---

## Concrete Methods

### `onComplete(obj, trialID, data)` *(override optional)*

Called after each trial completes, with the response data collected by the runtime. The base class implementation is a no-op. Override this to drive adaptive selection (e.g., update a psychometric model after each response).

```matlab
function onComplete(obj, trialID, data)
    obj.responses(trialID) = data.ResponseValue;
    obj.updateModel();
end
```

**Parameters:**
- `trialID` — Row index of the trial that just completed.
- `data` — Struct of response parameter values collected by the runtime.

---

### `setRuntime(obj, runtime, subjectIdx)` *(override optional)*

Called once after `initialize` with the live `epsych.Runtime` handle and the subject index. The base implementation stores both in the protected properties `runtime_` and `subjectIdx_`. Override (or just use the stored handles) in selectors that need to write back to `RUNTIME.TRIALS` — for example, to update the trials table with staircase-computed values.

---

## The TRIALS Struct

The `TRIALS` struct passed to every selector method has (at minimum) these fields relevant to selection:

| Field | Description |
|---|---|
| `trials` | Matrix of trial parameter values; rows are individual trials |
| `parameters` | Parameter definitions for the columns of `trials` |
| `TrialIndex` | Current trial counter (1-based, incremented after each trial) |
| `NextTrialID` | Row index set by the previous call to `selectNext` |
| `FORCE_TRIAL` | Logical flag; when true the runtime skips waiting for hardware trial completion and advances immediately (used by manual/reminder-trial overrides) |
| `RECOMPILE_REQUESTED` | Logical flag; true when the operator has requested a recompile at the next trial boundary |
| `Subject` | Subject identifier |
| `BoxID` | Hardware box index |

---

## Writing a Custom Selector

1. Create a new MATLAB class that subclasses `epsych.TrialSelector`.
2. Implement `initialize`, `selectNext`, and `onRecompile`.
3. Optionally override `onComplete` for adaptive logic.
4. Set `Options.trialFunc` in your protocol to the fully qualified class name.

**Minimal example:**

```matlab
classdef MyRandomSelector < epsych.TrialSelector
    properties (SetAccess = private)
        nTrials (1,1) double = 0
    end

    methods
        function initialize(obj, TRIALS)
            obj.nTrials = size(TRIALS.trials, 1);
        end

        function nextTrialID = selectNext(obj, ~)
            nextTrialID = randi(obj.nTrials);
        end

        function onRecompile(obj, TRIALS)
            obj.nTrials = size(TRIALS.trials, 1);
        end
    end
end
```

Register it in the protocol designer by entering `'MyRandomSelector'` in the trial function field, or set it programmatically:

```matlab
p.setOption('trialFunc', 'MyRandomSelector');
```

---

## Built-in Selector: `epsych.DefaultTrialSelector`

When no `trialFunc` is configured, the runtime uses `epsych.DefaultTrialSelector`. It tracks how many times each trial row has been presented and always selects from the least-used rows, breaking ties randomly. This produces a balanced, pseudorandom trial sequence.

**Properties:**
- `TrialCount (:,1) double` — Per-row use count.
- `activeTrials (:,1) logical` — Mask of rows eligible for selection (all `true` by default).

After a recompile that changes the number of trial rows, all counts are reset to zero.

---

## Randomizing a per-trial value

A selector often needs a value from a list on each trial — an inter-trial interval, a hold
duration, a stimulus level. `hw.Parameter.isRandom` redraws `randi([Min Max])` on every
dispatch, which is memoryless and unbalanced over a real session.
[`epsych.BlockSequence`](epsych_BlockSequence.md) is the alternative: it pregenerates a
block-randomized sequence and the selector indexes it with `TRIALS.TrialIndex`, so the value
for a trial is exact, balanced per block, and the same on a re-read or a rewind.

```matlab
obj.iti_ = epsych.BlockSequence([500 1000 1500 2000], Repeats = [2 2 2 1], Label = "ITI");
obj.iti_.validate();                                   % in initialize
...
iti = obj.iti_.valueAt(TRIALS.TrialIndex);             % in selectNext
obj.runtime_.TRIALS(obj.subjectIdx_).trials{nextTrialID, obj.itiCol_} = iti;
```

The driven parameter must have `isRandom = false`, or `set.Value` overwrites the selector's
value on dispatch.

## Related documentation

- [epsych_TrialLifecycle.md](epsych_TrialLifecycle.md) — where selector calls happen within a session
- [../paradigms/cl_AppetitiveStimDetect.md](../paradigms/cl_AppetitiveStimDetect.md) — a complete adaptive selector (staircase, catch trials, reminder override)
- [epsych_Protocol.md](epsych_Protocol.md) — where `Options.trialFunc` is stored

