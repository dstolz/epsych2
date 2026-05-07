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
    Access='Any', ...
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
- `'Any'`

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

## Expression-driven values

The `Expression` property lets you define a MATLAB expression that is evaluated
automatically each time a value is written to the parameter. The result of the
expression becomes the effective value, replacing whatever was passed to
`p.Value = ...`.

This is useful when a parameter's value should be derived from other parameters
at runtime — for example, computing a period from a frequency, or scaling one
channel relative to another.

### How it fits in the update pipeline

When `Expression` is non-empty, the update sequence becomes:

1. `PreUpdateFcn`
2. Randomization (if `isRandom`)
3. **Expression evaluation** ← new step
4. `EvaluatorFcn`
5. Parent write, `lastUpdated`, `PostUpdateFcn`

The expression receives the value produced by step 2 as the variable `Value`,
and must leave the result in `Value`. Sibling parameters in the same module are
injected by their `Name`; cross-module parameters can be referenced as
`ModuleName.ParamName`.

### Setting an expression

```matlab
p.Expression = "Value = FrequencyHz * 2";
```

Or assign it at construction time via `UserData` convention — but `Expression`
is a first-class property, so prefer setting it directly:

```matlab
p = hw.Parameter(parent, Name='PeriodMs');
p.Expression = "Value = 1000 / FrequencyHz";
```

Clear an expression by setting it back to `""`:

```matlab
p.Expression = "";
```

---

### Expression syntax rules

| Rule | Detail |
|---|---|
| Single statement | Semicolons (`;`) are not allowed. |
| Assignment target | Assign your result to `Value`. If the expression does not contain an assignment, the return value of `eval` is ignored and `Value` retains the incoming value. |
| No recursion | An expression on parameter `P` cannot reference `P` itself. |
| Sibling access | Other parameters in the **same module** are available by their `Name`. |
| Cross-module access | Parameters on other modules are referenced as `ModuleName.ParamName`. These are rewritten to safe aliases before evaluation. |

---

### Examples

#### Simple transform using a sibling parameter

Both `FrequencyHz` and `PeriodMs` live in the same module.

```matlab
freqParam  = hw.Parameter(parent, Name='FrequencyHz');
periodParam = hw.Parameter(parent, Name='PeriodMs');

periodParam.Expression = "Value = 1000 / FrequencyHz";

freqParam.Value  = 500;   % sets FrequencyHz to 500
periodParam.Value = 0;    % expression fires: Value = 1000/500 → 2
disp(periodParam.Value)   % 2
```

#### Scale by a constant

```matlab
gainParam.Expression = "Value = Value * 0.5";
gainParam.Value = 10;   % stored as 5
```

#### Cross-module reference

`SpeakerModule` is a different module on the same hardware interface.

```matlab
attParam.Expression = "Value = SpeakerModule.Gain - 6";
attParam.Value = 0;   % expression reads SpeakerModule.Gain at write time
```

#### Combined with `EvaluatorFcn`

The expression runs first, then the evaluator clamps the result.

```matlab
p.Expression  = "Value = FrequencyHz * scaleFactor";
p.EvaluatorFcn = @(obj, v) max(min(v, obj.Max), obj.Min);
p.Min = 0;
p.Max = 20000;
```

#### Conditional expression

```matlab
p.Expression = "Value = FrequencyHz * (AttenuationLevel > 0)";
```

---

### Context available inside an expression

| Variable name | Source |
|---|---|
| `Value` | Incoming value after randomization. This is also the output. |
| `<SiblingName>` | Current `.Value` of each other parameter in the same `Module`, keyed by `matlab.lang.makeValidName(Name)`. Only numeric, logical, char, and string values are included. |
| `exprMod_<ModuleName>_<ParamName>` | Rewritten alias for any `ModuleName.ParamName` cross-module reference. You never need to use this alias directly — write `ModuleName.ParamName` in the expression string and the rewrite is automatic. |

Cross-module context is read from `thisModule.parent.Module`, which is the full
list of modules on the owning hardware interface. If the interface is not
accessible (e.g., the parameter is unattached), cross-module references are
silently skipped and the expression runs with only the sibling context.

---

### Serialization

`Expression` is included in `toStruct` / `fromStruct` and round-trips through
JSON via `toJSON`. Protocols saved with expression-enabled parameters will
restore expressions on load.

---

## Dependent properties

### `validName`

`validName` returns a MATLAB-safe variable name derived from `Name`.

```matlab
p.Name = 'Pulse Width (ms)';
varName = p.validName;
```

---

## Developer notes

### Delegation model

When you read `p.Value`, the class:

1. Checks whether the parameter is write-only.
2. Reads the local value for `hw.Software` parents.
3. Otherwise calls `Parent.get_parameter(p, includeInvisible=true)`.

When you write `p.Value`, the class:

1. Runs `PreUpdateFcn`, if present.
2. Randomizes the value when `isRandom` is true.
3. Evaluates `Expression`, if non-empty.
4. Runs `EvaluatorFcn`, if present.
5. Updates array bookkeeping.
6. Calls `Parent.set_parameter(p, value)`.
7. Sets `lastUpdated = now`.
8. Runs `PostUpdateFcn`, if present.

### Expression evaluation internals

Expression evaluation is implemented in the private method `evaluateExpression_`
and the file-local helper `localRewriteQualifiedRefs_`.

- Qualified `ModuleName.ParamName` tokens are detected with `regexp` and
  replaced with safe variable aliases before `eval` is called.
- The context struct is unpacked into the local workspace one field at a time via
  `eval([name ' = context.(...);'])`, then `eval(expressionText)` runs.
- Cross-module parameter values are read at the moment the expression is
  evaluated (live `param.Value`), not from design-time `Values` cell arrays.
  This differs from `ProtocolDesigner`'s expression evaluator, which works
  with `Values` during compile-time expansion.
- Expression errors produce an `hw:Parameter:ExpressionError` exception with the
  parameter name and the underlying MATLAB error message. Context-build failures
  (e.g., module not accessible) are logged at verbosity level 0 and do not abort
  evaluation.

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
