# epsych.Runtime

`epsych.Runtime` is the session-state container used during experiment execution.

Source class:

- `obj/+epsych/@Runtime/Runtime.m`

Primary method files:

- `obj/+epsych/@Runtime/all_parameters.m`
- `obj/+epsych/@Runtime/find_parameter.m`
- `obj/+epsych/@Runtime/filter_parameters.m`
- `obj/+epsych/@Runtime/updateTrialsFromParameters.m`
- `obj/+epsych/@Runtime/dispatchNextTrial.m`
- `obj/+epsych/@Runtime/resolveCoreParameters.m`

## Responsibilities

- hold hardware/software interfaces and helper objects
- store and expose runtime trial state (`TRIALS`)
- resolve and cache required trigger parameters
- provide cross-interface parameter query/filter utilities
- synchronize writable trial columns from live parameter values

## Core Properties

- `NSubjects`: subject count
- `HW`, `S`, `Interfaces`: attached interface references
- `TRIALS`: runtime trial table and metadata
- `CORE`: cached trigger parameters (`NewTrial`, `ResetTrig`, `TrialComplete`)
- `HELPER`, `TIMER`: runtime service objects
- `DataFile`, `TempDataDir`, `dfltDataPath`: output tracking

## Parameter Query APIs

### all_parameters

```matlab
P = r.all_parameters(...
    includeInvisible=false, includeTriggers=false, includeArray=true, ...
    Access='Read', Interface={}, asStruct=false);
```

Recent behavior:

- Supports class-based interface filtering via `Interface` option.
- Can return struct keyed by `validName` when `asStruct=true`.

### find_parameter

```matlab
P = r.find_parameter(name, ...
    Interface={}, InterfaceName={}, ModuleName={}, ...
    includeInvisible=false, silenceParameterNotFound=false);
```

Recent behavior:

- Pre-filter by interface class (`Interface`) and interface type string (`InterfaceName`).
- Optional `ModuleName` filtering.
- Preserves requested input name order when matches exist.

### filter_parameters

```matlab
P = r.filter_parameters(propertyName, propertyValue, ...
    testFcn=@isequal, includeInvisible=false, includeTriggers=false);
```

Returns parameters whose property values satisfy `testFcn`.

## Trial Sync API

### updateTrialsFromParameters

```matlab
r.updateTrialsFromParameters(parameters);
```

- Uses `TRIALS.writeparams` to decide which incoming parameters are writable.
- Uses `TRIALS.writeParamIdx` to map parameter names to compiled trial columns.
- Writes current parameter values into every row of the corresponding `TRIALS.trials` column.

## Trigger Resolution and Trial Dispatch

### resolveCoreParameters

Locates and caches required trigger parameters per subject:

- `_NewTrial~<BoxID>`
- `_ResetTrig~<BoxID>`
- `_TrialComplete~<BoxID>`

### dispatchNextTrial

Per subject:

1. trigger reset
2. apply writable parameter values
3. trigger new trial
4. publish `NewTrial` notification

## Typical Usage

```matlab
r = epsych.Runtime;
r.resolveCoreParameters(1);

params = r.all_parameters(HW=true, S=true, Access='Read');
r.updateTrialsFromParameters(params);

r.dispatchNextTrial(1);
```

## Related Documentation

- `documentation/epsych/epsych_Protocol.md`
- `documentation/overviews/Architecture_Overview.md`
