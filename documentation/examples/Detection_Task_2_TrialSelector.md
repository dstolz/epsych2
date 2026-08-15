# Detection Task 2 — Writing a Custom Trial Selector

Part of the [detection task worked example](Detection_Task_Walkthrough.md).
Example file: [ExampleDetectionSelector.m](../../examples/detection_task/ExampleDetectionSelector.m).
Base-class reference: [epsych.TrialSelector](../epsych/epsych_TrialSelector.md).

A trial selector decides which row of the compiled condition list runs next.
The default (`epsych.DefaultTrialSelector`) picks the least-used condition at
random — fine for many tasks, but a Go/No-Go task usually wants an explicit
catch-trial rate and protection against long runs of one type. That policy is
exactly what the example selector implements:

1. Catch trials are drawn with probability `CatchProbability` (default 0.25).
2. Runs of the same trial type are capped at `MaxConsecutive` (default 3).
3. Within the chosen type, the least-presented condition wins, ties broken at
   random — the same balancing rule as the default selector.

## The contract

Subclass `epsych.TrialSelector` and implement the three abstract methods:

| Method | Called | Job |
|---|---|---|
| `initialize(obj, TRIALS)` | Once at session start | Index/derive whatever the policy needs from the compiled trial list |
| `nextTrialID = selectNext(obj, TRIALS)` | Before every trial | Return a row index into `TRIALS.trials` |
| `onRecompile(obj, TRIALS)` | After an operator recompile | Reconcile internal state with the (possibly changed) trial list |

Two optional overrides:

| Method | Called | Job |
|---|---|---|
| `onComplete(obj, trialID, data)` | After every completed trial, with its DATA record | Adapt; tally outcomes |
| `setRuntime(obj, runtime, subjectIdx)` | Once, before the first trial | Base implementation stores `obj.runtime_` / `obj.subjectIdx_` |

The runtime instantiates the class named by `Protocol.Options.trialFunc` via
`epsych.TrialSelector.create`, so a selector needs a zero-argument constructor;
tunables belong in public properties with defaults, as `CatchProbability` and
`MaxConsecutive` are here.

## What TRIALS gives you

`initialize` receives the TRIALS struct with `parameters` (the `hw.Parameter`
array), `trials` (the conditions-by-parameters cell array), `writeparams`, and
`writeParamIdx` — a struct mapping each parameter's `validName` to its column.
The example uses it to split the condition list by type:

```matlab
col   = TRIALS.writeParamIdx.TrialType;
types = cell2mat(TRIALS.trials(:, col));
obj.goRows_    = find(types == 0);
obj.catchRows_ = find(types == 1);
```

Note `DATA`, `TrialIndex`, and `NextTrialID` do not exist yet at `initialize`
time.

Two rules keep selectors honest:

- **TRIALS is passed by value.** Writes to the struct inside `selectNext` are
  discarded. State that must persist between trials lives on the selector
  object; if you truly need to mutate the runtime copy, write through
  `obj.runtime_.TRIALS(obj.subjectIdx_)`.
- **Be fast and safe.** `selectNext` runs between trials on the session timer;
  the runtime warns above 0.25 s. Exceptions are caught and logged, and the
  session continues with the *previous* `NextTrialID` — a silently repeating
  condition is the usual symptom of a buggy selector.

## Adapting from outcomes

`onComplete` receives the trial's DATA record. Decoding `RespCode` there is
enough to drive any adaptive rule; the example just tallies:

```matlab
function onComplete(obj, trialID, data)
    RC = epsych.BitMask.decode(data.RespCode);
    obj.nHits        = obj.nHits        + double(RC.Hit);
    obj.nFalseAlarms = obj.nFalseAlarms + double(RC.FalseAlarm);
end
```

A shaping variant could, for instance, raise `CatchProbability` after a false
alarm, or restrict `goRows_` to the easiest levels until the hit tally clears a
criterion. For threshold-seeking policies see
[psychophysics.Staircase](../psychophysics/psychophysics_Staircase.md) and
[psychophysics.BestPEST](../psychophysics/psychophysics_BestPEST.md).

## Testing a selector headlessly

A selector needs nothing but a TRIALS struct, so its policy is testable without
any runtime — this is the pattern from `tmp/smoke_test_detection_example.m`:

```matlab
P = create_detection_protocol([tempname '.eprot']);
T = struct;
T.parameters  = P.COMPILED.parameters;
T.trials      = P.COMPILED.trials;
T.writeparams = P.COMPILED.writeparams;
for k = 1:numel(T.writeparams)   % writeParamIdx maps name -> column
    T.writeParamIdx.(T.writeparams{k}) = k;
end

sel = ExampleDetectionSelector;
sel.initialize(T);
ids = arrayfun(@(~) sel.selectNext(T), 1:400);   % draw a long sequence
```

Assert on the sequence (catch fraction, run lengths, balance) and the policy is
pinned down before it ever runs an animal.

## Wiring it into a protocol

```matlab
P.setOption('trialFunc', 'ExampleDetectionSelector')
```

The class must be on the path when the protocol validates and when the session
runs; `validate()` reports an unresolvable name as an error and `compile()`
then refuses to produce trials.

Validation: `tmp/smoke_test_detection_example.m` (headless;
`matlab -batch "run('tmp/smoke_test_detection_example.m')"`).

Next: [Detection_Task_3_BehaviorGUI.md](Detection_Task_3_BehaviorGUI.md)
