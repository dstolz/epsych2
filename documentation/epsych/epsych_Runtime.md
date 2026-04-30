# epsych.Runtime

## Overview

`epsych.Runtime` is the shared state object for a running EPsych session.
It does not itself run the experiment loop. Instead, it gives the rest of the runtime a single place to read and update session state, interface handles, trial metadata, and parameter snapshots.

Source files:

- [obj/+epsych/@Runtime/Runtime.m](../obj/+epsych/@Runtime/Runtime.m)
- [obj/+epsych/@Runtime/resolveCoreParameters.m](../obj/+epsych/@Runtime/resolveCoreParameters.m)
- [obj/+epsych/@Runtime/dispatchNextTrial.m](../obj/+epsych/@Runtime/dispatchNextTrial.m)
- [obj/+epsych/@Runtime/writeParametersJSON.m](../obj/+epsych/@Runtime/writeParametersJSON.m)
- [obj/+epsych/@Runtime/readParametersJSON.m](../obj/+epsych/@Runtime/readParametersJSON.m)

## What The Class Is Responsible For

- Keeping session-wide scalar state such as subject count, start time, and hold flags.
- Holding references to hardware interfaces in `HW` and the software interface in `S`.
- Storing protocol runtime data in `TRIALS`, including the writable trial fields that mirror parameter values.
- Tracking helper services such as `HELPER` and the runtime `TIMER`.
- Recording data output locations through `dfltDataPath`, `TempDataDir`, and `DataFile`.
- Saving and restoring parameter states through JSON files.

In practice, other parts of EPsych treat `epsych.Runtime` as the object that ties together experiment setup, active interfaces, and live trial state.

## Property Guide

### Session State

- `NSubjects`: Number of subjects in the current session.
- `StartTime`: Session start timestamp.

### CORE Triggers

`CORE` is a struct array indexed by subject (one entry per subject). Each element holds cached handles to three mandatory hardware trigger parameters that are resolved once at session start and reused throughout the experiment.

| Field | Tag format | Purpose |
|---|---|---|
| `NewTrial` | `_NewTrial~<BoxID>` | Pulses the hardware to start the next trial after parameters have been written. |
| `ResetTrig` | `_ResetTrig~<BoxID>` | Pulses the hardware to reset RPvDs circuit components before parameter values are applied for a new trial. |
| `TrialComplete` | `_TrialComplete~<BoxID>` | Read-only boolean tag that the hardware sets to signal that the current trial has finished. Used for protocols that wait for explicit hardware completion before advancing. |

All three are boolean (trigger-type) tags that are marked invisible in the parameter list. They must be defined in the RPvDs circuit or Synapse tag set for every hardware box used in the session. See [CORE Trigger Requirements](#core-trigger-requirements) below for details on correct naming and placement.

### Interface References

- `HW`: Hardware interface objects. The code expects each object to expose methods such as `all_parameters` and `find_parameter`.
- `S`: Software interface object, used similarly to `HW` for parameter access.
- `HWinUse`: String array describing which hardware types are in use.
- `usingSynapse`: Compatibility flag indicating a Synapse-backed configuration.

### Trial And Service State

- `TRIALS`: Protocol-specific runtime trial structure. `updateTrialsFromParameters` assumes it contains `writeparams`, `writeParamIdx`, and `trials` fields.
- `HELPER`: Helper or dispatcher object used by runtime services and GUIs.
- `TIMER`: MATLAB timer object that supports runtime callbacks.
- `TrialComplete`: Software-side flag mirroring the `TrialComplete` hardware trigger. Used when a protocol waits for explicit completion signaling from the RPvDs circuit before moving to the next trial.

### Output Tracking

- `dfltDataPath`: Default output location.
- `TempDataDir`: Temporary acquisition directory.
- `DataFile`: One or more output file paths.

## Method Reference

### Constructor

`runtimeObj = epsych.Runtime`

Creates the runtime container. The constructor currently performs minimal initialization and logs creation through `vprintf`.

### Parameter Export

`writeParametersJSON(obj, filepath, description)`

Writes a snapshot of current parameters to JSON.

Implementation: [obj/+epsych/@Runtime/writeParametersJSON.m](../obj/+epsych/@Runtime/writeParametersJSON.m)

Behavior details:

- If `filepath` is omitted, the user is prompted with `uiputfile`.
- Parameters are collected through `obj.all_parameters`.
- Each parameter is serialized with `hw.Parameter.toStruct`.
- `UserData` is removed before writing, because it may contain content that cannot be reliably serialized.
- A `ParentType` field is added so the reader can map each parameter back to the correct interface.
- The file also stores a human-readable `Description` and a timestamp.

### Parameter Import

`readParametersJSON(obj, filepath)`

Loads a previously saved parameter JSON file and applies the values back to matching runtime interfaces.

Implementation: [obj/+epsych/@Runtime/readParametersJSON.m](../obj/+epsych/@Runtime/readParametersJSON.m)

Behavior details:

- If `filepath` is omitted or does not exist, the user is prompted with `uigetfile`.
- The JSON file is decoded and each entry is matched by `ParentType` first, then by parameter name.
- The software interface is treated specially when `ParentType` is `"Software"`.
- Matching parameters are updated in place using `fromStruct`.
- If a matching interface cannot be found, the parameter is skipped and a message is emitted through `vprintf`.
- Load metadata is appended to a dynamic `Phase` property on the runtime object. This includes description, JSON path, loaded parameter data, timestamp, and remaining file metadata.

### Template File Creation

`epsych.Runtime.createTemplateJSON(filepath)`

Creates a template JSON file that shows the structure expected by the import and export methods.

Behavior details:

- If no path is provided, the user is prompted for a save location.
- The template mirrors the fields written for `hw.Parameter` objects.
- The template includes `ParentType`, which is required for interface matching during load.

### Parameter Query

`P = all_parameters(obj, optInt, Name=Value...)`

Collects parameters from the runtime's software and hardware interfaces.

Supported options in the current implementation:

- `HW`: Include hardware parameters. Default is `true`.
- `S`: Include software parameters. Default is `true`.
- `includeInvisible`: Include invisible parameters. Default is `false`.
- `includeTriggers`: Include trigger parameters. Default is `false`.
- `includeArray`: Include array-valued parameters. Default is `true`.
- `Access`: Restrict to `Read`, `Write`, `Any`, or `All`. Default is `Read`.
- `asStruct`: Return a struct keyed by each parameter's `validName` instead of an array. Default is `false`.

This method is the main way higher-level code gets a filtered view of runtime parameters without needing to know whether they came from hardware or software.

### Resolve CORE Triggers

`resolveCoreParameters(obj, subjectIdx)`

Locates and caches the three mandatory hardware trigger parameters for one subject.

Implementation: [obj/+epsych/@Runtime/resolveCoreParameters.m](../obj/+epsych/@Runtime/resolveCoreParameters.m)

Behavior details:

- Searches all attached interfaces (hardware and software) using `find_parameter` with `includeInvisible=true`.
- Looks for each trigger by the scoped tag name `_<TriggerName>~<BoxID>`, where `BoxID` comes from `obj.TRIALS(subjectIdx).Subject.BoxID`.
- Stores the found `hw.Parameter` handles in `obj.CORE(subjectIdx).NewTrial`, `.ResetTrig`, and `.TrialComplete`.
- Errors immediately with `epsych:RunExpt:MissingTrigger` if any of the three triggers cannot be found. The experiment cannot start without all three.

This method must be called for every subject before any trial dispatch. Typically called once during session initialization.

### Dispatch Next Trial

`dispatchNextTrial(obj, subjectIdx)`

Applies the pre-selected trial parameters for one subject and fires the hardware trigger sequence.

Implementation: [obj/+epsych/@Runtime/dispatchNextTrial.m](../obj/+epsych/@Runtime/dispatchNextTrial.m)

Step-by-step sequence:

1. **Reset** — `obj.CORE(subjectIdx).ResetTrig.trigger()` pulses the hardware reset line, clearing any lingering state from the previous trial.
2. **Write parameters** — All `writeable` trial parameters for the current `NextTrialID` are applied to their hardware/software handles.
3. **Start** — `obj.CORE(subjectIdx).NewTrial.trigger()` pulses the hardware new-trial line, instructing the circuit to begin the new trial.
4. **Notify** — `obj.HELPER.notify('NewTrial', evtdata)` broadcasts the `NewTrial` software event with an `epsych.TrialsData` payload so GUIs and other listeners can update.

### Trial Synchronization

`updateTrialsFromParameters(obj, Parameters)`

Copies parameter values into the runtime's trial table for the subset of parameters listed in `obj.TRIALS.writeparams`.

Behavior details:

- Parameters not listed in `TRIALS.writeparams` are ignored.
- Each matching parameter name is resolved through `TRIALS.writeParamIdx`.
- The parameter value is written into the corresponding trial-column for all rows in `TRIALS.trials`.

Use this after parameter values have changed and the trial table needs to stay consistent with the active runtime configuration.

## Typical Workflow

1. Create or receive an `epsych.Runtime` object during experiment setup.
2. Attach hardware and software interface objects to `HW` and `S`.
3. Call `resolveCoreParameters(r, subjectIdx)` for each subject to cache the mandatory trigger handles.
4. Query parameters with `all_parameters` when building GUIs, validation logic, or save data.
5. Save a parameter snapshot with `writeParametersJSON` when a session state should be reproducible.
6. Reload a saved state with `readParametersJSON` when restoring a phase or repeating a known configuration.
7. Push writable parameter values into `TRIALS` with `updateTrialsFromParameters` before trial execution logic depends on them.
8. For each trial, call `dispatchNextTrial(r, subjectIdx)` to fire the hardware trigger sequence.

## Usage Examples

### Create A Runtime And Save A Snapshot

```matlab
r = epsych.Runtime;
r.NSubjects = 2;

r.writeParametersJSON("phaseA.json", "Baseline configuration");
```

### Restore A Saved Parameter State

```matlab
r.readParametersJSON("phaseA.json");

if isprop(r, "Phase")
    disp(r.Phase(end).Description)
end
```

### Get Parameters As A Struct

```matlab
P = r.all_parameters(HW=true, S=true, Access='Read', asStruct=true);
disp(fieldnames(P))
```

### Update Trial Values From Writable Parameters

```matlab
params = r.all_parameters(HW=true, S=false, includeTriggers=false);
r.updateTrialsFromParameters(params);
```

### Resolve CORE Triggers And Dispatch A Trial

```matlab
% During session setup — resolve triggers for subject 1 (box ID comes from TRIALS(1).Subject.BoxID)
r.resolveCoreParameters(1);

% Later, each trial iteration:
% 1. Select the next trial (handled by trial selection logic elsewhere)
% 2. Dispatch: reset hw -> write params -> trigger new trial -> notify listeners
r.dispatchNextTrial(1);
```

## CORE Trigger Requirements

For each hardware box used in a session, the RPvDs circuit or Synapse tag set **must** define three boolean (trigger-type) tags. The tags must follow this exact naming pattern, where `<n>` is the integer box ID:

| Tag name | Direction | Purpose |
|---|---|---|
| `_NewTrial~<n>` | Write (software → hardware) | Pulses high to tell the circuit a new trial has started. |
| `_ResetTrig~<n>` | Write (software → hardware) | Pulses high to reset circuit state between trials. |
| `_TrialComplete~<n>` | Read (hardware → software) | Set high by the circuit when the trial outcome is finalized. |

Examples for box 1:

- `_NewTrial~1`
- `_ResetTrig~1`
- `_TrialComplete~1`

These parameters are invisible in the normal parameter list (they will not appear in GUIs or saved parameter tables). `resolveCoreParameters` searches for them with `includeInvisible=true` and will throw an error if any are missing. If you see an `epsych:RunExpt:MissingTrigger` error at session start, verify that all three tags are present in your RPvDs or Synapse design for the correct box ID.

## Assumptions And Integration Notes

- `HW` and `S` must expose the parameter query APIs used by `all_parameters`.
- `readParametersJSON` assumes interface identity can be recovered through `ParentType` strings stored in the JSON file.
- `updateTrialsFromParameters` assumes the `TRIALS` structure has already been prepared by protocol compilation or setup code.
- The class derives from `dynamicprops`, which is why `readParametersJSON` can create `obj.Phase` on demand.
- `resolveCoreParameters` must be called before `dispatchNextTrial` for each subject. Calling `dispatchNextTrial` without a populated `CORE(subjectIdx)` will error.
- All three CORE trigger tags (`_NewTrial~<n>`, `_ResetTrig~<n>`, `_TrialComplete~<n>`) must be present in the hardware circuit for the session to start.

## Related Documentation

- [../gui/Parameter_Control.md](../gui/Parameter_Control.md)
- [../hw/hw_Interface.md](../hw/hw_Interface.md)
- [../hw/hw_Parameter.md](../hw/hw_Parameter.md)
- [../overviews/Architecture_Overview.md](../overviews/Architecture_Overview.md)
- [../overviews/Class_Map.md](../overviews/Class_Map.md)
- [EPsychInfo.md](EPsychInfo.md)

## Version History

- 2026-04-30: Added CORE Triggers section documenting `NewTrial`, `ResetTrig`, and `TrialComplete` — naming convention, resolution, dispatch sequence, and RPvDs/Synapse requirements.
- 2026-04-06: Updated the runtime documentation to match the current class and split method implementations, including JSON import/export details, dynamic `Phase` behavior, and trial synchronization assumptions.
- 2026-04-03: Updated to reflect the `Runtime.m` API and added practical usage examples.
- March 2026: Initial documentation.

