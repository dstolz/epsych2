# `hw.Parameter`

`hw.Parameter` represents a single hardware or software parameter exposed to
EPsych.

It combines parameter metadata used by GUIs and experiment code with a current
value and optional update callbacks. For software-backed parents, the value can
be stored locally. For hardware-backed parents, reads and writes are delegated
to the parent interface.

---

## Constructor

```matlab
p = hw.Parameter(parentHwInterface)
p = hw.Parameter(parentHwInterface, Name=Value)
```

The constructor accepts named options for the main metadata and behavior
settings, including:

- `Name`, `Description`, `Unit`, `Module`
- `Access`, `Type`, `Format`, `Visible`
- `PreUpdateFcn`, `EvaluatorFcn`, `PostUpdateFcn`, `PostUpdateFcnArgs`
- `PreUpdateFcnEnabled`, `EvaluatorFcnEnabled`, `PostUpdateFcnEnabled`
- `UserData`, `isArray`, `isTrigger`, `isRandom`, `Min`, `Max`

### Constructor example

```matlab
p = hw.Parameter(parentHwInterface, ...
    Name='PulseWidth', ...
    Description="Pulse width of the stimulator", ...
    Unit='ms', ...
    Access='Read / Write', ...
    Type='Float', ...
    Format='%.3f', ...
    Min=0, ...
    Max=50);
```

---

## Basic usage

### Read and write values

```matlab
currentValue = p.Value;

p.Value = 10;

disp(p.ValueStr)
```

`ValueStr` returns a formatted display string based on `Format` and `Unit`.

### Trigger parameters

Some parameters represent trigger events rather than ordinary scalar values.

```matlab
p.isTrigger = true;
p.Trigger();
```

`Trigger()` delegates to `Parent.trigger(p)` and updates `lastUpdated`.

---

## Core behavior

### Metadata and display

- `Name`: Parameter name shown in GUIs and logs.
- `Description`: Short descriptive text.
- `Unit`: Unit suffix appended to `ValueStr` when non-empty.
- `Module`: Handle to the module this parameter belongs to.
- `Format`: Display format used by `sprintf` or `num2str`.

If `Type` is set to `'String'`, the class uses `'%s'` formatting. Otherwise,
the default display format is `'%g'`.

### Access modes

`Access` must be one of:

- `'Read'`
- `'Write'`
- `'Read / Write'`

When a parameter is write-only, reading `Value` returns `NaN` and logs a
message with `vprintf`.

### Type values

`Type` must be one of:

- `'Float'`
- `'Integer'`
- `'Boolean'`
- `'Buffer'`
- `'Coefficient Buffer'`
- `'String'`
- `'Undefined'`

### Value tracking

- `Value`: Current parameter value.
- `ValueStr`: Human-readable representation of the current value.
- `lastUpdated`: MATLAB `datenum` timestamp of the last successful update.
- `isArray`: True when the stored value contains more than one element.
- `isRandom`: If true, writes randomize the value before passing it on.
- `Min` / `Max`: Bounds used by randomization and some validation paths.

Convert `lastUpdated` to `datetime` with:

```matlab
dt = datetime(p.lastUpdated, 'ConvertFrom','datenum', 'TimeZone','local');
```

For array values, `ValueStr` shows a shortened preview of up to 12 elements and
the total number of values.

---

## Update callbacks

`hw.Parameter` supports three callback hooks around value updates:

- `PreUpdateFcn(obj, value)`: Runs before randomization and evaluation.
- `EvaluatorFcn(obj, value)`: Can validate or transform the input value.
- `PostUpdateFcn(obj, value, ...)`: Runs after the parent write and timestamp update.

Each callback also has a matching logical enable flag:

- `PreUpdateFcnEnabled`
- `EvaluatorFcnEnabled`
- `PostUpdateFcnEnabled`

This lets code temporarily disable a callback without clearing its function
handle.

`PostUpdateFcnArgs` lets you append extra arguments when calling
`PostUpdateFcn`.

### Callback example

```matlab
p.Min = 0;
p.Max = 10;

p.EvaluatorFcn = @(obj, v) min(max(v, obj.Min), obj.Max);
p.PostUpdateFcn = @(obj, v) vprintf(3, 'Updated %s to %g', obj.Name, v);

p.Value = 25;
```

In this example, the evaluator clamps the supplied value to the configured
range before it is passed to the parent interface.

---

## Delegation model

When you read `p.Value`, the class:

1. Checks whether the parameter is write-only.
2. Reads the local value for `hw.Software` parents.
3. Otherwise calls `Parent.get_parameter(p, includeInvisible=true)`.

When you write `p.Value`, the class:

1. Runs `PreUpdateFcn`, if present.
2. Randomizes the value when `isRandom` is true.
3. Runs `EvaluatorFcn`, if present.
4. Updates array bookkeeping.
5. Calls `Parent.set_parameter(p, value)`.
6. Sets `lastUpdated = now`.
7. Runs `PostUpdateFcn`, if present.

This keeps experiment code working with a consistent `Value` API while leaving
the actual hardware interaction to the parent object.

---

## Dependent properties

### `validName`

`validName` returns a MATLAB-safe variable name derived from `Name`.

```matlab
p.Name = 'Pulse Width (ms)';
varName = p.validName;
```

---

## Serialization

`hw.Parameter` provides three methods for serializing and restoring parameter
state.

### `toStruct`

Converts the parameter to a plain MATLAB struct suitable for JSON encoding or
other storage formats. Bounds that are `Inf`, `-Inf`, or `NaN` are stored as
string sentinels to survive round-tripping through `jsonencode` / `jsondecode`.

```matlab
S = p.toStruct();
```

### `fromStruct`

Restores parameter fields from a struct previously produced by `toStruct`.

```matlab
p.fromStruct(S);
```

### `toJSON`

Serializes the parameter to a pretty-printed JSON string. `UserData` is
excluded (not reliably serializable) and `ParentType` is appended so the
JSON record is self-describing.

When called with no output argument, the JSON text is copied to the system
clipboard and a message is logged via `vprintf`.

```matlab
% Return JSON text
jsonText = p.toJSON();

% Copy to clipboard (no output)
p.toJSON();
```

---

## Recent updates

- Added `toJSON` method: returns pretty-printed JSON string and optionally
  copies it to the clipboard when called with no output.
- Added Serialization section documenting `toStruct`, `fromStruct`, and `toJSON`.
- Updated to match the current named-option constructor signature.
- Renamed documentation file to follow the subdirectory-based naming
  convention used in the repository prompt.

---

## Related files

- [obj/+hw/@Parameter/Parameter.m](../obj/+hw/@Parameter/Parameter.m): Class definition
- [obj/+hw/@Parameter/toStruct.m](../obj/+hw/@Parameter/toStruct.m): Serialization to struct
- [obj/+hw/@Parameter/toJSON.m](../obj/+hw/@Parameter/toJSON.m): Serialization to JSON string
- [obj/+epsych/@Runtime/writeParametersJSON.m](../obj/+epsych/@Runtime/writeParametersJSON.m): Writes all runtime parameters to a JSON file
