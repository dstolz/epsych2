# Event Notifications

## Overview

EPsych exposes its public custom event notifications through `epsych.Helper`.
The helper declares three runtime events:

- `NewData`
- `NewTrial`
- `ModeChange`

Source: [obj/+epsych/@Helper/Helper.m](../obj/+epsych/@Helper/Helper.m)

Psychophysics analysis objects such as `psychophysics.Psych` also rebroadcast `NewData` on their own local `Helper` after recomputing derived results. That second layer is useful for GUIs that depend on processed behavioral metrics rather than raw runtime state.

Source: [obj/+psychophysics/Psych.m](../obj/+psychophysics/Psych.m)

## Event Payloads

### `epsych.TrialsData`

`NewData` and `NewTrial` usually send an `epsych.TrialsData` payload.

Properties:

- `Data`: full trial struct for the current subject or box
- `Subject`: subject identifier
- `BoxID`: box identifier

Source: [obj/+epsych/TrialsData.m](../obj/+epsych/TrialsData.m)

### `epsych.ModeChangeEvent`

`ModeChange` sends an `epsych.ModeChangeEvent` payload.

Properties:

- `NewMode`: new runtime state, typically a `hw.DeviceState`

Source: [obj/+epsych/ModeChangeEvent.m](../obj/+epsych/ModeChangeEvent.m)

## Runtime Events

### `NewData`

#### Description

`NewData` indicates that a trial has completed and the runtime data structure has been updated. This event is emitted after parameter values are read from the interfaces, written into `RUNTIME.TRIALS(i).DATA`, and saved to disk.

Primary emit site: [runtime/timerfcns/ep_TimerFcn_RunTime.m](../runtime/timerfcns/ep_TimerFcn_RunTime.m)

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

- Runtime-to-analysis subscription: [obj/+psychophysics/Psych.m](../obj/+psychophysics/Psych.m#L77)
- Legacy detection subscription: [obj/+psychophysics/@Detect/Detect.m](../obj/+psychophysics/@Detect/Detect.m#L140)
- Training callback: [cl/@cl_AppetitiveDetection_GUI_B/eval_rwdelay_training_mode.m](../cl/@cl_AppetitiveDetection_GUI_B/eval_rwdelay_training_mode.m#L56)

### Analysis-layer `NewData`

#### Description

Psychophysics objects listen to runtime `NewData`, recompute derived results, and then emit their own `NewData` event from a local helper. This separates raw runtime updates from processed analysis updates.

Emit site: [obj/+psychophysics/Psych.m](../obj/+psychophysics/Psych.m#L241)

The same pattern is also present in older analysis classes:

- [obj/+psychophysics/@Detection/Detection.m](../obj/+psychophysics/@Detection/Detection.m#L112)
- [obj/+psychophysics/@Detect/Detect.m](../obj/+psychophysics/@Detect/Detect.m#L160)

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

- Performance table: [obj/+gui/@Performance/Performance.m](../obj/+gui/@Performance/Performance.m#L33)
- History table: [obj/+gui/@History/History.m](../obj/+gui/@History/History.m#L78)
- Appetitive GUI listener: [cl/@cl_AppetitiveDetection_GUI_B/create_gui.m](../cl/@cl_AppetitiveDetection_GUI_B/create_gui.m#L561)
- Aversive GUI listener: [cl/@cl_AversiveDetection_GUI/create_gui.m](../cl/@cl_AversiveDetection_GUI/create_gui.m#L407)

### `NewTrial`

#### Description

`NewTrial` indicates that the next trial has been selected, its parameter values have been written to hardware, and the system is ready for the next trial.

Primary emit site: [runtime/timerfcns/ep_TimerFcn_RunTime.m](../runtime/timerfcns/ep_TimerFcn_RunTime.m#L175)

It is also emitted once during startup:

- [runtime/timerfcns/ep_TimerFcn_Start.m](../runtime/timerfcns/ep_TimerFcn_Start.m#L170)

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
    if ~isprop(event, 'Data') || isempty(event.Data)
        return
    end

    trials = event.Data;
    fprintf('NextTrialID = %d\n', trials.NextTrialID);
end
```

#### Real uses in this repository

- Appetitive GUI listener: [cl/@cl_AppetitiveDetection_GUI_B/create_gui.m](../cl/@cl_AppetitiveDetection_GUI_B/create_gui.m#L560)
- Aversive GUI listener: [cl/@cl_AversiveDetection_GUI/create_gui.m](../cl/@cl_AversiveDetection_GUI/create_gui.m#L406)

The corresponding GUI handlers assume `event.Data` is present:

- [cl/@cl_AppetitiveDetection_GUI_B/cl_AppetitiveDetection_GUI_B.m](../cl/@cl_AppetitiveDetection_GUI_B/cl_AppetitiveDetection_GUI_B.m#L205)
- [cl/@cl_AversiveDetection_GUI/cl_AversiveDetection_GUI.m](../cl/@cl_AversiveDetection_GUI/cl_AversiveDetection_GUI.m#L178)

Usage note:
The startup path in `ep_TimerFcn_Start` currently notifies `NewTrial` without an explicit `epsych.TrialsData` payload, while the normal runtime path does include one. New listeners should therefore handle an empty or minimal event defensively.

### `ModeChange`

#### Description

`ModeChange` signals that the runtime has transitioned to a different operating state, such as Record, Pause, Stop, or Idle.

Emit sites:

- Record: [obj/+epsych/@RunExpt/ExptDispatch.m](../obj/+epsych/@RunExpt/ExptDispatch.m#L91)
- Pause: [obj/+epsych/@RunExpt/ExptDispatch.m](../obj/+epsych/@RunExpt/ExptDispatch.m#L97)
- Stop: [obj/+epsych/@RunExpt/ExptDispatch.m](../obj/+epsych/@RunExpt/ExptDispatch.m#L103)
- Idle: [runtime/timerfcns/ep_TimerFcn_Stop.m](../runtime/timerfcns/ep_TimerFcn_Stop.m#L13)

#### When to use it

Use `ModeChange` when GUI or controller code needs to react to runtime state transitions instead of trial-level data.

Common uses:

- enable or disable controls
- clean up windows or listeners on stop
- update status indicators
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

- Appetitive GUI registration: [cl/@cl_AppetitiveDetection_GUI_B/create_gui.m](../cl/@cl_AppetitiveDetection_GUI_B/create_gui.m#L562)
- Appetitive GUI handler: [cl/@cl_AppetitiveDetection_GUI_B/cl_AppetitiveDetection_GUI_B.m](../cl/@cl_AppetitiveDetection_GUI_B/cl_AppetitiveDetection_GUI_B.m#L175)
- Aversive GUI registration: [cl/@cl_AversiveDetection_GUI/create_gui.m](../cl/@cl_AversiveDetection_GUI/create_gui.m#L408)
- Aversive GUI handler: [cl/@cl_AversiveDetection_GUI/cl_AversiveDetection_GUI.m](../cl/@cl_AversiveDetection_GUI/cl_AversiveDetection_GUI.m#L151)

## Summary Table

| Event | Source object | Typical payload | Best used for |
| --- | --- | --- | --- |
| `NewData` | `RUNTIME.HELPER` | `epsych.TrialsData` | completed-trial updates and raw runtime data |
| `NewData` | `psychObj.Helper` | `epsych.TrialsData` | derived analysis refresh and analysis-driven GUIs |
| `NewTrial` | `RUNTIME.HELPER` | usually `epsych.TrialsData` | upcoming-trial UI and scheduling state |
| `ModeChange` | `RUNTIME.HELPER` | `epsych.ModeChangeEvent` | runtime state transitions |

## Notes

- `epsych.Helper` is the only class in the current codebase that declares public custom EPsych events.
- The repository also contains many MATLAB property listeners such as `PostSet`, but those are standard MATLAB property events rather than EPsych runtime notifications.
- If a component depends on derived behavioral results, prefer subscribing to the psychophysics object's `Helper.NewData` rather than directly to `RUNTIME.HELPER.NewData`.