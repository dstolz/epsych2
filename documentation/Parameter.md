# `hw.Parameter`

`hw.Parameter` represents a single hardware (or software) parameter exposed to EPsych.

A `hw.Parameter` instance wraps:

- **Metadata** describing the parameter (name, type, unit, access mode, formatting, etc.)
- A **current value** exposed through the `Value` property
- Optional **callbacks** that run before/after value updates

For non-software interfaces, reading/writing `Value` typically delegates to the parent `hw.Interface` implementation (via `Parent.get_parameter(...)` and `Parent.set_parameter(...)`). For software-only parents (e.g., `hw.Software`), the value is stored directly on the object.

---

## Basic usage

### Create and configure

```matlab
p = hw.Parameter(parentHwInterface);

p.Name        = 'PulseWidth';
p.Description = "Pulse width of the stimulator";
p.Unit        = 'ms';
p.Access      = 'Read / Write';
p.Type        = 'Float';
p.Format      = '%.3f';
p.Min         = 0;
p.Max         = 50;
```

### Read and write values

```matlab
% Read current value (may query hardware through Parent)
currentValue = p.Value;

% Write a new value (may write to hardware through Parent)
p.Value = 10;

% Human-friendly display string
disp(p.ValueStr);  % e.g. "10.000 ms"
```

### Triggers

Some parameters are treated as *triggers* (events) rather than scalar values.

```matlab
p.isTrigger = true;
p.Trigger();
```

`Trigger()` delegates to `Parent.trigger(p)` and updates `lastUpdated`.

---

## Key properties

### Identity and description

- `Name` (char): Parameter name displayed in GUI/logs.
- `Description` (string): Short descriptive text.
- `Unit` (char): Unit suffix appended to `ValueStr`.
- `Module`: Handle to the module object this parameter belongs to.

### Access, type, and formatting

- `Access` (char): One of:
  - `'Read'`
  - `'Write'`
  - `'Read / Write'`
- `Type` (char): One of:
  - `'Float'`, `'Integer'`, `'Boolean'`, `'Buffer'`, `'Coefficient Buffer'`, `'String'`, `'Undefined'`
- `Format` (char): `sprintf`/`num2str` formatting used by `ValueStr`.

Notes:

- If `Type` is set to `'String'`, `Format` is automatically set to `'%s'`.
- If `Format` is empty, it defaults to `'%s'` for strings, otherwise `'%g'`.

### Visibility and GUI

- `Visible` (logical): If false, the parameter can be hidden from UI.
- `handle`: Handle to an associated GUI object (if any).

### Value tracking

- `Value`: Read/write value.
  - If `Access` is `'Write'`, reads return `NaN` and log a message.
  - If `Access` is `'Read'`, writes may be rejected (depending on parent implementation).
- `ValueStr` (Dependent): A formatted string representation of `Value`.
  - For scalar values: `sprintf(Format, Value)`
  - For arrays: a truncated preview (up to 12 values) plus total length
  - Appends `Unit` when non-empty
- `lastUpdated` (double): Timestamp stored as MATLAB *datenum*.
  - Convert to `datetime`:

    ```matlab
    dt = datetime(p.lastUpdated, 'ConvertFrom','datenum', 'TimeZone','local');
    ```

### Behavior flags

- `isArray` (logical): True when the last set value had more than one element.
- `isTrigger` (logical): Treat this parameter as an event trigger.
- `isRandom` (logical): If true, `Value` writes randomize the value instead of using the supplied one.

### Value bounds

- `Min` / `Max` (double): Bounds used for randomization and (in some pathways) validation.

---

## Update callbacks

`hw.Parameter` supports optional callbacks that let you validate/transform values or run side effects during updates:

- `PreUpdateFcn(obj, value)`: Called before randomization and evaluation.
- `EvaluatorFcn(obj, value)`: Called to evaluate/transform the updated value. Its return value becomes the value that gets stored/written.
- `PostUpdateFcn(obj, value, ...)`: Called after the value is written and `lastUpdated` is set.
- `PostUpdateFcnArgs` (cell): Extra arguments appended when calling `PostUpdateFcn`.

Example: clamp and log a value update

```matlab
p.Min = 0;
p.Max = 10;

p.EvaluatorFcn = @(obj, v) min(max(v, obj.Min), obj.Max);
p.PostUpdateFcn = @(obj, v) vprintf(3, 'Updated %s to %g', obj.Name, v);

p.Value = 25;  % EvaluatorFcn clamps to 10
```

---

## Dependent properties

### `validName`

`validName` provides a MATLAB-safe variable name derived from `Name`:

```matlab
p.Name = 'Pulse Width (ms)';
varName = p.validName;  % e.g. "PulseWidth_ms_"
```

---

## Delegation model (how hardware reads/writes happen)

When you read `p.Value`, `hw.Parameter` typically:

- Checks `Access` (write-only parameters return `NaN`)
- If the parent is a software-only interface (`hw.Software`), reads the locally stored value
- Otherwise, calls the parent interface: `Parent.get_parameter(p, includeInvisible=true)`

When you write `p.Value`, `hw.Parameter` typically:

1. Runs `PreUpdateFcn` (if provided)
2. Randomizes the value if `isRandom` is true
3. Runs `EvaluatorFcn` (if provided)
4. Marks `isArray` and wraps array values when handing them off to the parent
5. Calls `Parent.set_parameter(p, value)`
6. Sets `lastUpdated = now`
7. Runs `PostUpdateFcn` (if provided)

This design keeps GUI code and experiment logic working with a consistent API (`Value`, `ValueStr`), while allowing the parent interface to decide how parameters are actually retrieved/applied.

---

## Related files

- [obj/+hw/Parameter.m](../obj/+hw/Parameter.m): Implementation of the `hw.Parameter` class
