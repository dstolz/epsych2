# epsych.Runtime

## Overview

`epsych.Runtime` is the shared state object for a running EPsych session.
It does not itself run the experiment loop. Instead, it gives the rest of the runtime a single place to read and update session state, interface handles, trial metadata, and parameter snapshots.

Source files:

- [obj/+epsych/@Runtime/Runtime.m](../obj/+epsych/@Runtime/Runtime.m)
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
- `ON_HOLD`: Logical flag used when runtime flow is paused.
- `TrialComplete`: Manual trial-complete flag when a protocol uses explicit completion signaling.

### Interface References

- `HW`: Hardware interface objects. The code expects each object to expose methods such as `all_parameters` and `find_parameter`.
- `S`: Software interface object, used similarly to `HW` for parameter access.
- `HWinUse`: String array describing which hardware types are in use.
- `usingSynapse`: Compatibility flag indicating a Synapse-backed configuration.

### Trial And Service State

- `TRIALS`: Protocol-specific runtime trial structure. `updateTrialsFromParameters` assumes it contains `writeparams`, `writeParamIdx`, and `trials` fields.
- `HELPER`: Helper or dispatcher object used by runtime services and GUIs.
- `TIMER`: MATLAB timer object that supports runtime callbacks.

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
- Parameters are collected through `obj.getAllParameters`.
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

`P = getAllParameters(obj, optInt, Name=Value...)`

Collects parameters from the runtime's software and hardware interfaces.

Supported options in the current implementation:

- `HW`: Include hardware parameters. Default is `true`.
- `S`: Include software parameters. Default is `true`.
- `includeInvisible`: Include invisible parameters. Default is `false`.
- `includeTriggers`: Include trigger parameters. Default is `false`.
- `includeArray`: Include array-valued parameters. Default is `true`.
- `Access`: Restrict to `Read`, `Write`, or `Read / Write`. Default is `Read`.
- `asStruct`: Return a struct keyed by each parameter's `validName` instead of an array. Default is `false`.

This method is the main way higher-level code gets a filtered view of runtime parameters without needing to know whether they came from hardware or software.

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
3. Query parameters with `getAllParameters` when building GUIs, validation logic, or save data.
4. Save a parameter snapshot with `writeParametersJSON` when a session state should be reproducible.
5. Reload a saved state with `readParametersJSON` when restoring a phase or repeating a known configuration.
6. Push writable parameter values into `TRIALS` with `updateTrialsFromParameters` before trial execution logic depends on them.

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
P = r.getAllParameters(HW=true, S=true, Access='Read', asStruct=true);
disp(fieldnames(P))
```

### Update Trial Values From Writable Parameters

```matlab
params = r.getAllParameters(HW=true, S=false, includeTriggers=false);
r.updateTrialsFromParameters(params);
```

## Assumptions And Integration Notes

- `HW` and `S` must expose the parameter query APIs used by `getAllParameters`.
- `readParametersJSON` assumes interface identity can be recovered through `ParentType` strings stored in the JSON file.
- `updateTrialsFromParameters` assumes the `TRIALS` structure has already been prepared by protocol compilation or setup code.
- The class derives from `dynamicprops`, which is why `readParametersJSON` can create `obj.Phase` on demand.

## Related Documentation

- [Parameter_Control.md](Parameter_Control.md)
- [hw_Interface.md](hw_Interface.md)
- [hw_Parameter.md](hw_Parameter.md)
- [Architecture_Overview.md](Architecture_Overview.md)
- [Class_Map.md](Class_Map.md)
- [EPsychInfo.md](EPsychInfo.md)

## Version History

- 2026-04-06: Updated the runtime documentation to match the current class and split method implementations, including JSON import/export details, dynamic `Phase` behavior, and trial synchronization assumptions.
- 2026-04-03: Updated to reflect the `Runtime.m` API and added practical usage examples.
- March 2026: Initial documentation.
