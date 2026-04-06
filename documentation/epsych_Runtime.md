# epsych.Runtime

## Overview

`epsych.Runtime` is the central runtime state container used while an EPsych experiment is running.
It keeps together experiment state, hardware and software interface handles, trial metadata, and utility state used by GUI and timer-driven workflows.

Source file: [obj/+epsych/@Runtime/Runtime.m](../obj/+epsych/@Runtime/Runtime.m)

## What This Class Manages

- Subject-level state, such as `NSubjects` and start-time metadata.
- Hardware and software integration through `HW` and `S` interface objects.
- Trial bookkeeping in `TRIALS`, including per-trial values written from parameters.
- Runtime services (`HELPER`, `TIMER`) and acquired-data tracking fields.
- JSON export/import of parameter snapshots for reproducible experiment setup.

## Key Properties

- `NSubjects`: Number of subjects in the active experiment.
- `HWinUse`: Hardware names/types currently in use.
- `usingSynapse`: Backward-compatibility flag for Synapse usage.
- `TRIALS`: Trial-selection metadata and writable trial parameter table.
- `dfltDataPath`, `TempDataDir`, `DataFile`: Data path and file tracking.
- `HELPER`, `TIMER`: Runtime helper/event and timer service handles.
- `HW`, `S`: Hardware and software interface objects.
- `StartTime`, `TrialComplete`, `ON_HOLD`: Runtime state flags and timestamps.

## Method Reference

### Constructor

- `r = epsych.Runtime`
Creates an empty runtime object and initializes baseline state.

### Parameter Snapshot Methods

- `writeParametersJSON(obj, filepath, description)`
Writes all current parameters to a JSON file.
Implementation: [obj/+epsych/@Runtime/writeParametersJSON.m](../obj/+epsych/@Runtime/writeParametersJSON.m)

Behavior notes:
- Prompts for a save path if `filepath` is omitted.
- Stores parameter data using each `hw.Parameter` `toStruct` representation.
- Includes `ParentType` so values can be restored to the correct interface on load.
- Excludes `UserData` from JSON output to avoid non-serializable content.

- `readParametersJSON(obj, filepath)`
Loads parameter values from a JSON file and applies them to runtime interfaces.
Implementation: [obj/+epsych/@Runtime/readParametersJSON.m](../obj/+epsych/@Runtime/readParametersJSON.m)

Behavior notes:
- Prompts for a file if `filepath` is omitted or invalid.
- Matches loaded entries to interfaces via `ParentType`.
- Updates existing parameters in place using `fromStruct`.
- Appends load metadata to dynamic property `obj.Phase`.

- `epsych.Runtime.createTemplateJSON(filepath)`
Creates a template JSON file showing expected parameter fields and value formats.

### Query and Trial-Update Methods

- `P = getAllParameters(obj, optInt, Name=Value...)`
Returns parameters from software and/or hardware with optional filtering.

Common options:
- `HW`, `S`: Include hardware or software interfaces.
- `includeInvisible`, `includeTriggers`, `includeArray`: Filter parameter sets.
- `Access`: Restrict by access mode (`'Read'`, `'Write'`, `'Read / Write'`).
- `asStruct`: Return a struct keyed by parameter `validName`.

- `updateTrialsFromParameters(obj, Parameters)`
Writes matching parameter values into `obj.TRIALS.trials` using `TRIALS.writeparams` and `TRIALS.writeParamIdx`.

## Usage Examples

### Create Runtime and Save/Load Parameters

```matlab
r = epsych.Runtime;
r.NSubjects = 2;

r.writeParametersJSON("phaseA.json", "Baseline phase");
r.readParametersJSON("phaseA.json");
```

### Query Readable Parameters as a Struct

```matlab
P = r.getAllParameters(HW=true, S=true, Access='Read', asStruct=true);
disp(fieldnames(P));
```

### Propagate Parameter Values Into Trial Table

```matlab
params = r.getAllParameters(HW=true, S=false, includeTriggers=false);
r.updateTrialsFromParameters(params);
```

## Related Documentation

- [documentation/Parameter_Control.md](Parameter_Control.md)
- [documentation/hw_Interface.md](hw_Interface.md)
- [documentation/hw_Parameter.md](hw_Parameter.md)
- [documentation/Architecture_Overview.md](Architecture_Overview.md)
- [documentation/EPsychInfo.md](EPsychInfo.md)

## Version History

- 2026-04-03: Updated to reflect current `Runtime.m` API, added method behavior notes and practical usage examples.
- March 2026: Initial documentation.
