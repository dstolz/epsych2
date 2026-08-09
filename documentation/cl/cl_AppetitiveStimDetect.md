# cl_AppetitiveStimDetect

`cl_AppetitiveStimDetect` is the trial selector for the appetitive stimulus-detection task. It is an `epsych.TrialSelector` subclass that implements the task's staircase, catch-trial scheduling, and reminder-trial override. This document is for developers maintaining the task or using it as a template for their own adaptive selectors.

It replaces the legacy standalone function `cl_TrialSelection_Appetitive_StimDetect.m`, which has been removed.

Implementation: [cl/@cl_AppetitiveStimDetect/cl_AppetitiveStimDetect.m](../../cl/@cl_AppetitiveStimDetect/cl_AppetitiveStimDetect.m)

Base-class reference: [../epsych/epsych_TrialSelector.md](../epsych/epsych_TrialSelector.md)

## Purpose

On every trial boundary the selector combines:

- a reminder-trial override,
- response-code decoding from the most recent completed trial (`epsych.BitMask`),
- staircase updates to the stimulus `Depth`, and
- probabilistic insertion of catch trials

to choose the next row of the trials table.

## Quick summary

- First trial: select the first stimulus row.
- Reminder requested: force the reminder row.
- Hit: make the next stimulus weaker by decreasing `Depth` by `StepOnHit` (direction configurable, see below).
- Miss: make the next stimulus stronger by increasing `Depth` by `StepOnMiss` (direction configurable, see below).
- Abort, correct rejection, or false alarm: keep the same stimulus depth. A pending Hit/Miss step is **not** reverted by these outcomes, so it survives any number of intervening catch trials and takes effect on the next stimulus trial.
- Catch-trial probability: occasionally replace the next stimulus trial with a catch trial.

## How it is configured

Set the protocol's trial function to the class name — in the Protocol Designer's **Protocol Options** dialog or programmatically:

```matlab
P.setOption('trialFunc', 'cl_AppetitiveStimDetect');
```

The runtime instantiates the selector at run start via `epsych.TrialSelector.create` and calls `initialize`, `setRuntime`, `selectNext`, and `onComplete` per the standard [selector lifecycle](../epsych/epsych_TrialSelector.md#runtime-lifecycle).

## Trial type codes

The trials table must include a `TrialType` write parameter with at least one row per category:

| Code | Meaning |
|---|---|
| `0` | Stimulus (signal-present) trial |
| `1` | Catch (no-signal) trial |
| `2` | Reminder trial |

The selector always chooses the first matching row (`find(..., 1)`).

## Required parameters

`initialize` builds named lookups (`obj.P` for parameter handles, `obj.T` for trial-table columns) from `TRIALS.parameters`. The protocol must define these writable parameters:

- `TrialType`, `Depth` — trial-table columns driving selection and the staircase
- `ReminderTrials` — when set to `1`, the next trial is forced to the reminder row
- `StepOnHit` — amount subtracted from `Depth` after a hit
- `StepOnMiss` — amount added to `Depth` after a miss
- `P_Catch` — probability of inserting a catch trial
- `RepeatDelayOnAbort` — when true, repeats the same stimulus delay after an abort (see below)
- `StimDelay` — stimulus-delay parameter whose randomization the abort logic manages

Depth bounds are read from the `Depth` parameter itself: after a Hit/Miss step, the selector clamps the new value to `Depth.Min`/`Depth.Max` before writing it into the trials table, matching the bounds `hw.Parameter` also enforces when the value is dispatched (see [../hw/hw_Parameter.md](../hw/hw_Parameter.md)).

### Optional parameters

- `StepDirectionOnHit`, `StepDirectionOnMiss` — sign of the `Depth` step applied on a Hit/Miss: `-1` = Down, `+1` = Up. When absent (or `0`), the selector defaults to `-1` on Hit (weaker) and `+1` on Miss (stronger) — the historical behavior. Define these as writable protocol parameters only if a task needs to invert the default staircase direction.

## Selection logic (`selectNext`)

1. On the first trial (`TRIALS.TrialIndex == 1`), return the first stimulus row.
2. If `ReminderTrials` is `1`, return the first reminder row.
3. Decode the completed-trial response history with `epsych.BitMask.decode([TRIALS.DATA.RespCode])`.
4. Find the depth of the most recent stimulus trial; if none exists yet, start from the maximum compiled depth.
5. Update the next stimulus depth from the latest outcome:
   - `Hit`: step by `StepDirectionOnHit * StepOnHit` (default direction: decrement, i.e. weaker)
   - `Miss`: step by `StepDirectionOnMiss * StepOnMiss` (default direction: increment, i.e. stronger)
   - `Abort`: keep the same depth; if `RepeatDelayOnAbort` is enabled, temporarily suspend `StimDelay` randomization so the identical delay repeats (after three consecutive aborts, randomization is restored instead)
   - `CorrectReject`: keep the same depth and restore `StimDelay` randomization
   - `FalseAlarm`: keep the same depth and restore `StimDelay` randomization; a false alarm that was also an abort schedules a catch row immediately
6. Only on a Hit or Miss: clamp the new depth to `Depth.Min`/`Depth.Max`, then write it into every stimulus row of the live trials table (through the runtime handle stored by `setRuntime`), so the dispatcher sends the new value to hardware. Abort/CorrectReject/FalseAlarm never touch the table, so a pending step is not lost to an intervening catch trial.
7. Schedule a catch trial with probability `P_Catch` — suppressed after an abort and after a catch trial, and forced if the last ten trials were all stimulus trials. Otherwise return the first stimulus row.

## Notes and caveats

- The selector assumes `epsych.BitMask.decode` returns logical fields `Hit`, `Miss`, `Abort`, `CorrectReject`, `FalseAlarm`, and `TrialType_<code>`.
- `onRecompile` is currently a no-op; the selector rebuilds nothing after an operator recompile.
- The abort/StimDelay logic stores a snapshot in `StimDelay.UserData` while randomization is suspended; the private helper `restore_stimdelay_randomization_` restores the flag.

## Related files

- [cl/@cl_AppetitiveStimDetect/cl_AppetitiveStimDetect.m](../../cl/@cl_AppetitiveStimDetect/cl_AppetitiveStimDetect.m)
- [cl/@cl_AppetitiveDetection_GUI_B/create_gui.m](../../cl/@cl_AppetitiveDetection_GUI_B/create_gui.m) — the task GUI that exposes these parameters
- [cl_SaveDataFcn.md](cl_SaveDataFcn.md) — the task's save function
- [../epsych/epsych_TrialLifecycle.md](../epsych/epsych_TrialLifecycle.md) — where trial selection happens in a session
