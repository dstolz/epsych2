# cl_AppetitiveStimDetect

`cl_AppetitiveStimDetect` is the trial selector for the appetitive stimulus-detection task. It is an `epsych.TrialSelector` subclass that implements the task's staircase, catch-trial scheduling, and reminder-trial override. This document is for developers maintaining the task or using it as a template for their own adaptive selectors.

It replaces the legacy standalone function `cl_TrialSelection_Appetitive_StimDetect.m`, which has been removed.

Implementation: [paradigms/TrialSelectors/@cl_AppetitiveStimDetect/cl_AppetitiveStimDetect.m](../../paradigms/TrialSelectors/@cl_AppetitiveStimDetect/cl_AppetitiveStimDetect.m)

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
- Reminder requested: force the reminder row and present it at 0 dB depth — see [Reminder trials](#reminder-trials).
- Hit: make the next stimulus weaker by decreasing `Depth` by `StepOnHit` (direction configurable, see below).
- Miss: make the next stimulus stronger by increasing `Depth` by `StepOnMiss` (direction configurable, see below).
- Abort, correct rejection, or false alarm: keep the same stimulus depth. A pending Hit/Miss step is **not** reverted by these outcomes, so it survives any number of intervening catch trials and takes effect on the next stimulus trial.
- Catch-trial probability: rises with every delivered stimulus trial and resets once a catch trial completes — see [Catch-trial hazard function](#catch-trial-hazard-function).
- Catch trials switched off: only stimulus rows are scheduled, and the hazard is held at its floor — see [Switching catch trials off](#switching-catch-trials-off).

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

- `TrialType`, `Depth` — trial-table columns driving selection and the staircase (`TrialType` needs one row per code: `0` stimulus, `1` catch, `2` reminder)
- `ReminderTrials` — when set to `1`, the next trial is forced to the reminder row at 0 dB depth (see [Reminder trials](#reminder-trials))
- `Depth_StepOnHit` — amount subtracted from `Depth` after a hit
- `Depth_StepOnMiss` — amount added to `Depth` after a miss
- `P_Catch` — the catch-trial hazard function. All three of its fields carry meaning: `Min` is the floor, `Value` the step per delivered stimulus trial, `Max` the ceiling. See [Catch-trial hazard function](#catch-trial-hazard-function)
- `RepeatDelayOnAbort` — when true, repeats the same stimulus delay after an abort (see below)
- `StimDelay` — stimulus-delay parameter whose randomization the abort logic manages

Depth bounds are read from the `Depth` parameter itself: after a Hit/Miss step, the selector clamps the new value to `Depth.Min`/`Depth.Max` before writing it into the trials table, matching the bounds `hw.Parameter` also enforces when the value is dispatched (see [../hw/hw_Parameter.md](../hw/hw_Parameter.md)).

### Optional parameters

- `StepDirectionOnHit`, `StepDirectionOnMiss` — sign of the `Depth` step applied on a Hit/Miss: `-1` = Down, `+1` = Up. When absent (or `0`), the selector defaults to `-1` on Hit (weaker) and `+1` on Miss (stronger) — the historical behavior. Define these as writable protocol parameters only if a task needs to invert the default staircase direction.
- `CatchTrialsEnabled` — Boolean switch gating catch-trial presentation. The selector creates it if the protocol does not declare it, so this parameter normally needs no attention; see [Switching catch trials off](#switching-catch-trials-off).

## Selection logic (`selectNext`)

1. On the first trial (`TRIALS.TrialIndex == 1`), return the first stimulus row.
2. If `ReminderTrials` is `1` (or a reminder was already granted for this `TrialIndex`), return the first reminder row, with its `Depth` overwritten to 0 dB, and clear the request — see [Reminder trials](#reminder-trials).
3. Decode the completed-trial response history with `epsych.BitMask.decode([TRIALS.DATA.RespCode])`.
4. Find the depth of the most recent stimulus trial; if none exists yet, start from the maximum compiled depth.
5. Update the next stimulus depth from the latest outcome:
   - `Hit`: step by `StepDirectionOnHit * StepOnHit` (default direction: decrement, i.e. weaker)
   - `Miss`: step by `StepDirectionOnMiss * StepOnMiss` (default direction: increment, i.e. stronger)
   - `Abort`: keep the same depth; if `RepeatDelayOnAbort` is enabled, temporarily suspend `StimDelay` randomization so the identical delay repeats (after three consecutive aborts, randomization is restored instead)
   - `CorrectReject`: keep the same depth and restore `StimDelay` randomization
   - `FalseAlarm`: keep the same depth and restore `StimDelay` randomization; a false alarm that was also an abort schedules a catch row immediately
6. Only on a Hit or Miss: clamp the new depth to `Depth.Min`/`Depth.Max`, then write it into every stimulus row of the live trials table (through the runtime handle stored by `setRuntime`), so the dispatcher sends the new value to hardware. Abort/CorrectReject/FalseAlarm never touch the table, so a pending step is not lost to an intervening catch trial.
7. Unless `CatchTrialsEnabled` is off, schedule a catch trial with the hazard probability described below — suppressed after an abort and after a catch trial. Otherwise return the first stimulus row.

## Reminder trials

`cl_AppetitiveDetection_BoxGUI`'s **Reminder** button sets `ReminderTrials` to `1`. That is all it does: the request is **queued, not immediate**. The trial in progress runs to its natural end and the reminder is presented as the next trial. The button's `PostUpdateFcn` only logs the press — it deliberately does *not* set `TRIALS.FORCE_TRIAL`, which ended the trial in progress early and wrote a `DATA` record from a response the subject had not finished making. Everything about *what* the reminder is lives here, in the selector.

A reminder is a **signal-present trial at 0 dB depth** — full modulation, the most salient stimulus the task produces — regardless of where the staircase currently sits. `forceReminderTrial_` writes that depth into the reminder row of the live trials table rather than reading whatever the protocol compiled there, so the reminder does not depend on the protocol's `Depth` values.

The trial keeps `TrialType = 2`, which is what makes the override safe:

- the staircase measures from the last completed **stimulus** trial, so the reminder's 0 dB never becomes `lastStim`
- the catch-trial hazard ignores reminder trials, so the catch schedule is neither advanced nor reset
- the Next Trial panel and the Response History label the trial from `TrialTypeNames`, so it reads as `Reminder` rather than as an anomalous stimulus trial

### The reminder is invisible to the schedule

A reminder takes the next trial's slot and changes nothing else: **subsequent trials continue exactly as they would have had no reminder been presented.** A reminder is an operator interruption, not a measurement of the subject, so its own outcome is not a datum — scoring it as a hit must not walk the staircase down, and scoring it as a miss must not walk it up.

`selectNext` gets this by construction rather than by special cases:

1. Reminder trials are removed from the decoded history (`RC`, and the matching `Depth` vector) before anything reads it, so every `(end)` in the staircase and catch logic refers to the last *real* trial.
2. The reminder override is applied **last**, after the staircase step, the hazard advance, and the catch draw have all run. The trial the reminder displaces is therefore scored on the pass that grants the reminder, not a trial later.
3. The hazard's advance-once guard is keyed on the **count of completed non-reminder trials** (`lastHazardOutcome_`), not on `TrialIndex`. A reminder adds a `TrialIndex` but no outcome, so it can neither advance the hazard nor let the trial before it advance the hazard twice.

The one thing a reminder does consume is the catch **draw** made on the pass that grants it: that draw's result is discarded and re-made for the following trial, at the same (unchanged) probability.

`tmp/smoke_test_reminder_trial.m` proves the invariant directly — it runs the same outcome sequence twice, once with a reminder spliced in and once without, and requires the staircase to land on the same depth.

### The request is consumed when it is granted

`ReminderTrials` is a one-shot, and the selector clears it in the same `selectNext` pass that acts on it (`consumeReminderRequest_`). It cannot be cleared on trial completion instead, because `ep_TimerFcn_RunTime` broadcasts `NewData` for the completed trial *before* it calls `selectNext` for the next one. A listener that cleared the toggle there — as the box GUI's `onNewData` did — withdrew the request during the very pass that was about to honor it, so no reminder was ever presented.

Two consequences follow:

- The button clears as soon as the reminder is committed to, not when the reminder trial ends. It therefore stays lit exactly while the request is queued, which is the operator's only feedback that a press registered. A press made *during* a reminder trial is still standing at the next selection pass and produces a second reminder.
- `reminderIndex_` records the `TrialIndex` a reminder was granted for, so a repeated `selectNext` for the same trial — which any control that sets `FORCE_TRIAL` can produce — still returns the reminder row after the toggle is spent.

Two edge cases are reported rather than papered over:

- **No reminder row compiled.** Borrowing a stimulus row would overwrite the depth the staircase is holding there, so the selector logs at level 0 and presents an ordinary stimulus trial at the current depth instead.
- **`Depth.Max` below 0 dB.** `hw.Parameter` clamps `Depth` to its own bounds on dispatch, so a working maximum below full depth would quietly weaken the reminder. The selector logs at level 0 when this is the case; raise **Maximum Depth (dB)** if reminders must reach full depth.

Behavior is covered end to end by `tmp/smoke_test_reminder_trial.m`.

## Catch-trial hazard function

A flat catch probability produces geometric waiting times: long runs with no catch trial are common, so the false-alarm rate is estimated from an unevenly spaced sample. The selector instead raises the probability with each stimulus trial, which clusters the waiting times around the target rate.

The probability is **carried forward on the selector** and advanced by the one trial that just completed:

```
delivered stimulus trial  ->  p = p + P_Catch.Value
completed catch trial     ->  p = P_Catch.Min
aborted or reminder trial ->  p unchanged
then, every trial         ->  p = min(max(p, P_Catch.Min), P_Catch.Max)
```

| Field | Meaning |
|---|---|
| `P_Catch.Min` | floor: the probability at session start and immediately after a catch trial |
| `P_Catch.Value` | step added per delivered stimulus trial |
| `P_Catch.Max` | ceiling the probability is clamped to |

With `Min = 0`, `Value = 0.1`, `Max = 1` the probability runs 0, 0.1, 0.2, … and reaches certainty on the tenth stimulus trial, so no run of stimulus trials can exceed ten.

Because the value accumulates rather than being recomputed from history, **an operator edit applies from that point forward and is never retroactive**. Five stimulus trials at `Value = 0.1` sit at 0.5; raising the step to 0.2 takes the next trial to 0.7, not to 1.0. The `Min`/`Max` clamp is re-applied every trial, so tightening the bounds takes effect immediately rather than waiting for the next step.

**Aborts are inert on both sides of the schedule.** An aborted stimulus trial never delivered a stimulus, so it does not advance `p`; an aborted catch trial never measured a false-alarm rate, so it does not reset `p`. A run of aborts therefore leaves the catch rate exactly where it was. Reminder trials (`TrialType == 2`) never reach the rule at all — they are dropped from the history before it is read.

`cl_AppetitiveStimDetect.advanceHazard` is a static, runtime-free implementation of the step rule above. The selector applies it at most once per completed trial, keyed on the count of completed **non-reminder** trials, so neither a repeated `selectNext` for the same trial nor an intervening reminder can double-advance the hazard. `tmp/smoke_test_pcatch_hazard.m` is the standing proof of the schedule.

### The live probability

On its first `selectNext` the selector creates a `P_Catch_Current` parameter on the `hw.Software` interface and writes the current `p` to it every trial. `cl_AppetitiveDetection_BoxGUI` shows it in the **Trial State** monitor, and because it is a visible, readable parameter it also lands in every saved `DATA` record, so the hazard state can be reconstructed offline.

Declaring `P_Catch_Current` in the protocol yourself is preferable — it then persists and serializes — and the selector will use the existing parameter rather than creating one. Either way it must be host-writable (not `Access = 'Read'`, which rejects every write) with `UpdateEveryTrial = false`, which is what keeps a mid-run recompile from giving it a trials-table column that dispatch would clobber.

### Switching catch trials off

Early training often wants no catch trials at all. `CatchTrialsEnabled` is a Boolean switch the selector consults before it schedules anything: while it is off, every trial is a stimulus trial and the hazard is **held at its floor** rather than left to accumulate — so switching catch trials back on resumes from the bottom of the schedule instead of firing a catch trial on the next draw.

`cl_AppetitiveDetection_BoxGUI` exposes it as the **Present Catch Trials** checkbox, which also greys out the `p(Catch)` fields while it is clear (the **Min / Max** row and the **Step** field), so the visible schedule and the running one cannot disagree.

Like `P_Catch_Current`, the parameter is created on the `hw.Software` interface at the selector's first `selectNext` when the protocol does not declare it — early enough for the box GUI, which `epsych.RunExpt` launches after `ep_TimerFcn_Start`. Declaring it in the protocol yourself is preferable (it then persists and serializes), and the same rules apply: host-writable, `UpdateEveryTrial = false`. A selector running without any of this — a protocol with no switch, or the runtime-free `epsych.SelfTest` pass — treats the parameter as absent, which means catch trials stay enabled.

### Caveats

- The hazard resets to `Min` at the start of every session; it is not carried across runs.
- `CatchTrialsEnabled` gates presentation only. The trials table still carries its catch row, and `P_Catch`'s `Min`/`Value`/`Max` keep whatever the operator last set.
- `hw.Parameter` clamps `Value` to `[Min Max]`. Since `Value` is the step and `Min`/`Max` the probability range, setting `Min = 0.2` silently clamps a step of 0.1 up to 0.2. Harmless at the intended `Min = 0`, but the clamp is silent.
- `hw.Parameter` does not validate `Min <= Max`. The GUI's widget limits prevent crossing them interactively, but a phase load or programmatic write can.

## Notes and caveats

- The selector assumes `epsych.BitMask.decode` returns logical fields `Hit`, `Miss`, `Abort`, `CorrectReject`, `FalseAlarm`, and `TrialType_<code>`.
- `onRecompile` is currently a no-op; the selector rebuilds nothing after an operator recompile.
- The abort/StimDelay logic stores a snapshot in `StimDelay.UserData` while randomization is suspended; the private helper `restore_stimdelay_randomization_` restores the flag.

## Related files

- [paradigms/TrialSelectors/@cl_AppetitiveStimDetect/cl_AppetitiveStimDetect.m](../../paradigms/TrialSelectors/@cl_AppetitiveStimDetect/cl_AppetitiveStimDetect.m)
- [paradigms/BoxGUIs/@cl_AppetitiveDetection_BoxGUI/build.m](../../paradigms/BoxGUIs/@cl_AppetitiveDetection_BoxGUI/build.m) — the task GUI that exposes these parameters
- [tmp/smoke_test_pcatch_hazard.m](../../tmp/smoke_test_pcatch_hazard.m) — hazard-schedule and end-to-end selector tests
- [cl_SaveDataFcn.md](cl_SaveDataFcn.md) — the task's save function
- [../epsych/epsych_TrialLifecycle.md](../epsych/epsych_TrialLifecycle.md) — where trial selection happens in a session
