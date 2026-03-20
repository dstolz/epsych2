# cl_TrialSelection_Appetitive_StimDetect

This document explains how `cl_TrialSelection_Appetitive_StimDetect` chooses the next trial in the appetitive stimulus-detection task.

The goal of the function is simple: inspect the most recent trial outcome, decide whether the next trial should be a stimulus, catch, or reminder trial, and update the stimulus depth used for the next stimulus presentation.

## Purpose

The function chooses the next trial row by combining:

- a reminder-trial override,
- response-code decoding from the most recent completed trial,
- staircase updates to the stimulus `Depth`, and
- probabilistic insertion of catch trials.

The implementation lives in [cl/cl_TrialSelection_Appetitive_StimDetect.m](../cl/cl_TrialSelection_Appetitive_StimDetect.m).

In practice, this function is used as a trial-selection callback inside an epsych runtime session. It is not usually called directly by hand during an experiment.

## Quick summary

- First trial: select the first stimulus row.
- Reminder requested: force the reminder row.
- Hit: make the next stimulus weaker by decreasing `Depth`.
- Miss: make the next stimulus stronger by increasing `Depth`.
- Abort, correct rejection, or false alarm: keep the same stimulus depth.
- Catch-trial probability: occasionally replace the next stimulus trial with a catch trial.

## Where it fits

This function sits between the runtime history and the next trial choice:

1. The runtime stores response outcomes in `TRIALS.DATA`.
2. This function decodes the latest outcome.
3. It updates the next stimulus depth if needed.
4. It writes `TRIALS.NextTrialID` so the runtime knows which trial row to run next.

## Inputs and outputs

Input:

- `TRIALS`: experiment runtime struct populated by the session runtime.

Output:

- `TRIALS`: returned with `TRIALS.NextTrialID` updated.
- For stimulus rows, the selected `Depth` is written back into `TRIALS.trials` before return.

## Expected trial-table layout

The function assumes `TRIALS.trials` contains at least these write parameters:

- `TrialType`
- `Depth`

It also assumes there is at least one row for each trial category used by the task:

- one stimulus row (`TrialType == 0`)
- one catch row (`TrialType == 1`)
- one reminder row (`TrialType == 2`) when reminder trials are enabled

The function always chooses the first matching row returned by `find(..., 1)`.

## Trial type codes

The function defines these local codes:

- `STIM = 0`
- `CATCH = 1`
- `REMIND = 2`

These codes are used both for row selection in `TRIALS.trials` and for decoded response history fields such as `RC.("TrialType_0")`.

## Runtime dependencies

The function reads or updates the following data:

- `TRIALS.TrialIndex`
- `TRIALS.trials`
- `TRIALS.writeParamIdx`
- `TRIALS.DATA.RespCode`
- `TRIALS.DATA.Depth`
- `TRIALS.DATA.StimDelay`
- `TRIALS.S.Module.Parameters`
- `TRIALS.HW.find_parameter('~ReminderTrial', includeInvisible=true)`

## Software parameters used

These parameters are expected to be available from the appetitive detection GUI configuration:

- `ReminderTrials`
- `StepOnHit`
- `StepOnMiss`
- `MinDepth`
- `MaxDepth`
- `P_Catch`

Related GUI definitions are in [cl/@cl_AppetitiveDetection_GUI_B/create_gui.m](../cl/@cl_AppetitiveDetection_GUI_B/create_gui.m).

### Parameter meaning

- `ReminderTrials`: when set to `1`, the next trial is forced to the reminder row.
- `StepOnHit`: amount subtracted from `Depth` after a hit.
- `StepOnMiss`: amount added to `Depth` after a miss.
- `MinDepth`: smallest allowed stimulus depth.
- `MaxDepth`: largest allowed stimulus depth.
- `P_Catch`: probability of inserting a catch trial after a non-catch trial.

## Selection logic

1. If `TRIALS.TrialIndex == 1`, the function selects the first `STIM` row and returns.
2. If `ReminderTrials` is enabled, it selects the first `REMIND` row, sets the hidden `~ReminderTrial` flag, and returns.
3. Otherwise it clears the reminder flag and decodes the completed-trial response history with `epsych.BitMask.decode`.
4. It finds the most recent stimulus trial depth. If no prior stimulus trial exists, it starts from the maximum configured depth.
5. It updates the next stimulus depth using the most recent outcome:
   - `Hit`: decrement by `StepOnHit`
   - `Miss`: increment by `StepOnMiss`
   - `Abort`: keep the same depth
   - `CorrectRejection` or `FalseAlarm`: keep the same depth for the next stimulus trial
6. With probability `P_Catch`, and only when the last completed trial was not a catch trial, it selects the first `CATCH` row and returns.
7. Otherwise it clamps the new depth to `[MinDepth, MaxDepth]`, writes that value into all stimulus rows, and selects the first `STIM` row.

## Worked examples

### Example 1: hit on the previous stimulus trial

Assume:

- previous stimulus depth was `0.25`
- `StepOnHit = 0.03`
- `MinDepth = 0.001`
- `P_Catch = 0`

Then the next stimulus depth becomes `0.22`, and the next trial is the first stimulus row.

### Example 2: miss on the previous stimulus trial

Assume:

- previous stimulus depth was `0.25`
- `StepOnMiss = 0.09`
- `MaxDepth = 1`
- `P_Catch = 0`

Then the next stimulus depth becomes `0.34`, and the next trial is the first stimulus row.

### Example 3: catch-trial insertion

Assume:

- latest completed trial was a stimulus trial
- `P_Catch = 0.1`
- the random draw is below `0.1`

Then the function schedules the first catch row instead of the next stimulus row.

### Example 4: abort on the previous trial

If the latest outcome is `Abort`, the function keeps the same stimulus depth and attempts to copy the previous `StimDelay` value forward before choosing the next trial.

## Usage example

This function is usually assigned in a protocol or runtime configuration rather than called manually. A conceptual example looks like this:

```matlab
TRIALS = cl_TrialSelection_Appetitive_StimDetect(TRIALS);
nextRow = TRIALS.NextTrialID;
```

For this to work correctly, `TRIALS` must already contain:

- completed trial history in `TRIALS.DATA`
- write-parameter indices in `TRIALS.writeParamIdx`
- GUI parameters in `TRIALS.S.Module.Parameters`
- hardware access through `TRIALS.HW`

## Common assumptions

- The function assumes `epsych.BitMask.decode` returns logical fields such as `Hit`, `Miss`, `Abort`, `CorrectRejection`, and `FalseAlarm`.
- The function assumes the latest completed trial has a valid `RespCode`.
- The function assumes `Depth` is a numeric write parameter for all stimulus rows.
- The function assumes the GUI has already created the parameters named in the previous section.

## Notes and caveats

- The GUI exposes a `TrialOrder` parameter, but the current function implementation does not branch on `TrialOrder`; the active logic is staircase-based.
- On abort, the function also attempts to restore `StimDelay` from the most recent completed trial before selecting the next trial.
- The `RepeatDelayOnAbort` parameter is defined in the GUI, but it is not currently consumed by this trial-selection function.

## Related files

- [cl/cl_TrialSelection_Appetitive_StimDetect.m](../cl/cl_TrialSelection_Appetitive_StimDetect.m)
- [cl/@cl_AppetitiveDetection_GUI_B/create_gui.m](../cl/@cl_AppetitiveDetection_GUI_B/create_gui.m)
- [documentation/RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md)

## Change history

- 2026-03-20: Expanded the documentation with examples, assumptions, and task context to match the current implementation.

