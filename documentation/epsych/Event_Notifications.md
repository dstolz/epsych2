# Event Notifications

This reference describes the EPsych runtime event system for developers writing GUIs, analysis tools, or paradigm-specific code that must react to a running session.

## Overview

EPsych exposes its public custom event notifications through `epsych.Helper`.
The helper declares three runtime events:

- `NewData`
- `NewTrial`
- `ModeChange`

Source: [obj/+epsych/@Helper/Helper.m](../../obj/+epsych/@Helper/Helper.m)

The live broadcaster instance is `RUNTIME.HELPER`, created by `epsych.RunExpt` at run start and deleted by `ep_TimerFcn_Stop`.

Psychophysics analysis objects such as `psychophysics.Psych` subclasses also rebroadcast `NewData` on their own local `Helper` after recomputing derived results. That second layer is useful for GUIs that depend on processed behavioral metrics rather than raw runtime state.

Source: [obj/+psychophysics/Psych.m](../../obj/+psychophysics/Psych.m)

## Event Payloads

### `epsych.TrialsData`

`NewData` and `NewTrial` send an `epsych.TrialsData` payload.

Properties:

- `Data`: full trial struct for the current subject or box
- `Subject`: subject identifier
- `BoxID`: box identifier

Source: [obj/+epsych/TrialsData.m](../../obj/+epsych/TrialsData.m)

### `epsych.eventModeChange`

`ModeChange` sends an `epsych.eventModeChange` payload.

Properties:

- `NewMode`: new runtime state as a `hw.DeviceState`

Source: [obj/+epsych/eventModeChange.m](../../obj/+epsych/eventModeChange.m)

## Runtime Events

### `NewData`

#### Description

`NewData` indicates that a trial has completed and the runtime data structure has been updated. This event is emitted after parameter values are read from the interfaces, written into `RUNTIME.TRIALS(i).DATA`, and appended to the crash-recovery file.

Primary emit site: [runtime/timerfcns/ep_TimerFcn_RunTime.m](../../runtime/timerfcns/ep_TimerFcn_RunTime.m)

#### When to use it

Use `NewData` when the listener should react to completed trial outcomes.

Common uses:

- update online performance summaries
- refresh trial-history tables
- recompute psychometric or detection metrics
- trigger training-mode logic after each response

#### Example

```matlab
hl = addlistener(RUNTIME.HELPER, 'NewData', @(src, event) onNewData(src, event));

function onNewData(~, event)
    trials = event.Data;
    fprintf('Box %d now has %d completed trials\n', ...
        trials.BoxID, numel(trials.DATA));
end
```

#### Real uses in this repository

- Runtime-to-analysis subscription: [obj/+psychophysics/Psych.m](../../obj/+psychophysics/Psych.m)
- Detection analysis subscription: [obj/+psychophysics/@Detection/Detection.m](../../obj/+psychophysics/@Detection/Detection.m)
- Training callback: [cl/@cl_AppetitiveDetection_GUI_B/eval_rwdelay_training_mode.m](../../cl/@cl_AppetitiveDetection_GUI_B/eval_rwdelay_training_mode.m)

### Analysis-layer `NewData`

#### Description

Psychophysics objects listen to runtime `NewData`, recompute derived results, and then emit their own `NewData` event from a local helper. This separates raw runtime updates from processed analysis updates.

Emit site: `notifyDataUpdate_` in [obj/+psychophysics/Psych.m](../../obj/+psychophysics/Psych.m)

#### When to use it

Use analysis-layer `NewData` when your listener depends on recomputed behavioral results instead of raw trial storage.

Common uses:

- update psychometric plots
- update performance tables
- refresh history tables
- show d-prime, hit rate, or false-alarm summaries

#### Example

```matlab
hl = addlistener(psychObj.Helper, 'NewData', @(src, event) onPsychUpdate(src, event));

function onPsychUpdate(~, event)
    trials = event.Data;
    fprintf('Analysis updated for subject %s\n', string(trials.Subject));
end
```

#### Real uses in this repository

- Performance table: [obj/+gui/@Performance/Performance.m](../../obj/+gui/@Performance/Performance.m)
- History table: [obj/+gui/@History/History.m](../../obj/+gui/@History/History.m)
- Appetitive GUI listener: [cl/@cl_AppetitiveDetection_GUI_B/create_gui.m](../../cl/@cl_AppetitiveDetection_GUI_B/create_gui.m)

### `NewTrial`

#### Description

`NewTrial` indicates that the next trial has been dispatched: its parameter values have been written to hardware and the new-trial trigger has fired.

Emit site: [obj/+epsych/@Runtime/dispatchNextTrial.m](../../obj/+epsych/@Runtime/dispatchNextTrial.m). This runs once per subject when `RUNTIME.TRIALS` is first populated at session start, and again after each completed trial from `ep_TimerFcn_RunTime`.

#### When to use it

Use `NewTrial` when the listener needs to react to the upcoming trial rather than the completed one.

Common uses:

- update a Next Trial table
- display the upcoming depth or trial type
- prepare trial-specific GUI state
- log scheduling decisions

#### Example

```matlab
hl = addlistener(RUNTIME.HELPER, 'NewTrial', @(src, event) onNewTrial(src, event));

function onNewTrial(~, event)
    trials = event.Data;
    fprintf('NextTrialID = %d\n', trials.NextTrialID);
end
```

#### Real uses in this repository

- Appetitive GUI listener and handler: [cl/@cl_AppetitiveDetection_GUI_B/create_gui.m](../../cl/@cl_AppetitiveDetection_GUI_B/create_gui.m), [cl/@cl_AppetitiveDetection_GUI_B/cl_AppetitiveDetection_GUI_B.m](../../cl/@cl_AppetitiveDetection_GUI_B/cl_AppetitiveDetection_GUI_B.m)

### `ModeChange`

#### Description

`ModeChange` signals that the runtime has transitioned to a different operating state, such as Record, Preview, Pause, Stop, or Idle.

Emit sites:

- Record / Preview (run start, after the behavior GUI launches): [obj/+epsych/@RunExpt/PsychTimerStart.m](../../obj/+epsych/@RunExpt/PsychTimerStart.m)
- Pause and Stop (operator commands): [obj/+epsych/@RunExpt/ExptDispatch.m](../../obj/+epsych/@RunExpt/ExptDispatch.m)
- Idle (hardware returned to idle at session end): [runtime/timerfcns/ep_TimerFcn_Stop.m](../../runtime/timerfcns/ep_TimerFcn_Stop.m)

#### When to use it

Use `ModeChange` when GUI or controller code needs to react to runtime state transitions instead of trial-level data.

Common uses:

- enable or disable controls
- clean up windows or listeners on stop
- update status indicators (see `gui.ModeIndicator`)
- trigger end-of-session behavior

#### Example

```matlab
hl = addlistener(RUNTIME.HELPER, 'ModeChange', @(src, event) onModeChange(src, event));

function onModeChange(~, event)
    switch event.NewMode
        case hw.DeviceState.Record
            fprintf('Experiment is recording\n')
        case hw.DeviceState.Pause
            fprintf('Experiment is paused\n')
        case hw.DeviceState.Stop
            fprintf('Experiment has stopped\n')
        case hw.DeviceState.Idle
            fprintf('Runtime is idle\n')
    end
end
```

#### Real uses in this repository

- Appetitive GUI registration: [cl/@cl_AppetitiveDetection_GUI_B/create_gui.m](../../cl/@cl_AppetitiveDetection_GUI_B/create_gui.m)
- Appetitive GUI handler: [cl/@cl_AppetitiveDetection_GUI_B/cl_AppetitiveDetection_GUI_B.m](../../cl/@cl_AppetitiveDetection_GUI_B/cl_AppetitiveDetection_GUI_B.m)
- Mode indicator widget: [obj/+gui/@ModeIndicator/ModeIndicator.m](../../obj/+gui/@ModeIndicator/ModeIndicator.m)

## Summary Table

| Event | Source object | Payload | Best used for |
| --- | --- | --- | --- |
| `NewData` | `RUNTIME.HELPER` | `epsych.TrialsData` | completed-trial updates and raw runtime data |
| `NewData` | `psychObj.Helper` | `epsych.TrialsData` | derived analysis refresh and analysis-driven GUIs |
| `NewTrial` | `RUNTIME.HELPER` | `epsych.TrialsData` | upcoming-trial UI and scheduling state |
| `ModeChange` | `RUNTIME.HELPER` | `epsych.eventModeChange` | runtime state transitions |

## Notes

- `epsych.Helper` is the only class in the current codebase that declares public custom EPsych events.
- The repository also contains many MATLAB property listeners such as `PostSet`, but those are standard MATLAB property events rather than EPsych runtime notifications.
- If a component depends on derived behavioral results, prefer subscribing to the psychophysics object's `Helper.NewData` rather than directly to `RUNTIME.HELPER.NewData`.
- `RUNTIME.HELPER` is deleted at session stop; listeners should tolerate the source object disappearing and should be cleaned up in your GUI's destructor (see [../design/Customized_GUI_Instructions.md](../design/Customized_GUI_Instructions.md)).

## Related documentation

- [epsych_TrialLifecycle.md](epsych_TrialLifecycle.md) — where each event fires within a trial
- [epsych_Runtime.md](epsych_Runtime.md) — the `RUNTIME` object that owns `HELPER`
- [../design/Customized_GUI_Instructions.md](../design/Customized_GUI_Instructions.md) — building event-driven GUIs
