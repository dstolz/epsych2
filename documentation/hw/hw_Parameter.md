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

- `Name`, `Description`, `Unit`
- `Access`, `Type`, `Format`, `Visible`
- `UpdateEveryTrial`, `SetOnce`
- `PreUpdateFcnEnabled`, `EvaluatorFcnEnabled`, `PostUpdateFcnEnabled`
- `UserData`, `isArray`, `isTrigger`, `isRandom`, `Min`, `Max`

Callback function handles (`PreUpdateFcn`, `EvaluatorFcn`, `PostUpdateFcn`)
and their argument lists (`PreUpdateFcnArgs`, `EvaluatorFcnArgs`,
`PostUpdateFcnArgs`) are assigned as properties after construction.

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

`Trigger()` delegates to `Parent.trigger(p)` and updates `lastUpdated`. It
only acts when `isTrigger` is true. Marking a parameter as a trigger also
defaults its `UpdateEveryTrial` flag to false, because triggers fire on
demand rather than carrying a per-trial value.

---

## Core behavior

### Metadata and display

- `Name`: Parameter name shown in GUIs and logs.
- `Description`: Short descriptive text.
- `Unit`: Unit suffix appended to `ValueStr` when non-empty.
- `Module`: Handle to the module this parameter belongs to (resolved lazily
  from the parent when not set explicitly).
- `FullName` (dependent): `'ModuleName.ParamName'`; useful for qualified
  lookups via `find_parameter`.
- `Format`: Display format used by `sprintf` or `num2str`.

If `Type` is set to `'String'`, `'File'`, or `'StimType'`, the class uses
`'%s'` formatting. Otherwise, the default display format is `'%g'`.

### Access modes

`Access` must be one of:

- `'Read'`
- `'Write'`
- `'Any'`

(The legacy value `'Read / Write'` is still accepted and normalized to
`'Any'`.)

When a parameter is write-only, reading `Value` returns `NaN` and logs a
message with `vprintf`. Writing to a read-only parameter raises an error.

That read-back message means a caller asked for something that does not exist,
so the framework itself never triggers it: expression evaluation, `toStruct`,
protocol loading, and the Protocol Designer all substitute the parameter's
first design-time level (`Values{1}`, or `NaN` when `Values` is empty) rather
than reading a write-only `Value`. Seeing the message in the log is therefore a
signal about the code that logged it, not routine noise.

### Type values

`Type` must be one of:

- `'Float'`
- `'Integer'`
- `'Boolean'`
- `'Buffer'`
- `'Coefficient Buffer'`
- `'String'`
- `'File'`
- `'StimType'`
- `'Undefined'`

`'File'` parameters hold one or more file paths; the Protocol Designer
provides a dedicated file-list editor for them. `'StimType'` parameters hold
a `stimgen.StimType` object and are supported on every backend; the stimulus
object itself is passed to `Parent.set_parameter` like any other value, and
each backend takes what it needs from it. See
[Stimulus parameters on hardware](#stimulus-parameters-on-hardware).

`'String'` and `'StimType'` are the two *index-selecting* types
(`hw.Parameter.expressionSelectsIndex`): an `Expression` on either of them
returns the index of the item to use rather than the value itself. See
[Selecting an item by index](#selecting-an-item-by-index-string-and-stimtype).

`stimgen` ships as a git submodule (see [../stimgen.md](../stimgen.md)). If it
has not been checked out, `'StimType'` parameters cannot resolve their class:
MATLAB substitutes a placeholder struct when loading a saved protocol rather
than raising an error, so the values are silently degraded. `epsych_startup`
warns when the submodule is missing.

### Stimulus parameters on hardware

A `'StimType'` parameter is written like any other type. `set.Value` calls
`Parent.set_parameter(p, stim)` with the `stimgen.StimType` object itself, and
the backend decides what to make of it — there is no separate stimulus API and
no per-parameter tag mapping to configure.

Two static helpers on `hw.Interface` are what a backend uses to do that:

| Helper | Purpose |
|---|---|
| `hw.Interface.isStimulusValue(value)` | True when the value handed to `set_parameter` is a stimulus. Call it before coercing a value to a number or a string. Array-valued parameters arrive wrapped in a scalar cell, so this unwraps one. |
| `hw.Interface.stimulusPayload(stim, Fs)` | Reduce a stimulus to a struct of `Signal`, `Fs`, `N`, `Duration`, `SoundLevel`, `Class`, `DisplayName` — one element per stimulus. |

`stimulusPayload` exists because two things are easy to get wrong and should
not be re-derived per backend:

- **Sample rate.** `stimgen` builds `Signal` against `stim.Fs`, so a stimulus
  authored at one rate is the wrong duration and pitch on a device running at
  another. Pass the module's `Fs` and the stimulus is regenerated at the device
  rate. The rate is assigned on the stimulus itself, so the regeneration
  happens once rather than on every trial. Pass nothing — or `hw.Module.Fs`
  still sitting at its 1 Hz "unset" default — to take the stimulus as authored.
- **Signal freshness.** `Signal` is empty on a freshly constructed or freshly
  deserialized stimulus, and the rebuild triggered by an `Fs` assignment runs
  inside a `PostSet` listener, where MATLAB downgrades an error to a warning
  and leaves the previous signal in place. `stimulusPayload` therefore calls
  `update_signal` explicitly — the same thing `stimgen.StimPlayer`,
  `stimgen.StimInspector`, and `stimgen.calibration.Engine` do. A stimulus that
  cannot be built at the device rate raises
  `hw:Interface:StimulusGenerationFailed` rather than playing a stale waveform.

#### What each backend does with a stimulus

| Backend | Behavior |
|---|---|
| `hw.TDT_RPcox` | Writes the waveform to the parameter's own RPvds tag, generated at the module's `Fs` (which `connect()` reads from the device). `TDTRP.write` bounds the write against the tag's declared size, so a stimulus that overruns the circuit's buffer is reported rather than silently truncated. A parameter holding several stimuli writes the first and says so. |
| `hw.Software` | Stores it, as with every other type. |
| `hw.TDT_Synapse`, `hw.Teensy`, `hw.Intan_RHX` | No waveform sink exists on these transports, so the write is logged at verbosity 2 and the stimulus stays on the `hw.Parameter`, where experiment code and GUIs still read it. |
| `hw.Bpod`, `hw.VlcRecorder` | Fall through their existing "no device write" paths; the value is kept host-side. |

A backend that gains a waveform output later needs no change here — it just
stops ignoring the value it is already being handed.

### Trial-level behavior

- `Values`: Design-time trial levels, one cell element per level. Set through
  `epsych.Protocol.addParameter` / the Protocol Designer and expanded into
  the trials matrix by `Protocol.compile()`.
- `UpdateEveryTrial`: When true (the default for non-trigger parameters), the
  runtime trial dispatcher rewrites this parameter on every trial. When
  false, the per-trial dispatch leaves the parameter alone — useful
  for operator-adjusted settings that should hold their value mid-session.
- `SetOnce`: When true (and `UpdateEveryTrial` is false), the dispatcher
  writes the parameter on the **first** trial dispatch only — its value
  reaches the hardware once at session start and is then left alone.
  Defaults to true for `'Coefficient Buffer'` parameters, whose large,
  session-static value (e.g. calibration filter coefficients) is wasteful to
  rewrite every trial. Both flags are exposed as checkboxes in the Protocol
  Designer parameter table (`Update Every Trial`, `Set Once`), which keeps
  them mutually exclusive.

### Value tracking

- `Value`: Current parameter value.
- `ValueStr`: Human-readable representation of the current value.
- `lastUpdated`: MATLAB `datenum` timestamp of the last successful update.
- `isArray`: True when the stored value contains more than one element.
- `isRandom`: If true, writes randomize the value before passing it on.
  Requires finite `Min` and `Max`.
- `Min` / `Max`: Bounds. Numeric writes are clamped into `[Min, Max]`
  (per-side, controlled by `BoundsInclusive`) before being applied.

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

`PreUpdateFcnArgs`, `EvaluatorFcnArgs`, and `PostUpdateFcnArgs` let you append
extra arguments when the corresponding callback is invoked.

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

What the result *means* depends on the parameter's `Type`:

| Type | The expression result is |
|---|---|
| `Float`, `Integer`, `Boolean` | the value itself |
| `String`, `StimType` | a **1-based index** choosing one of the parameter's items — see [Selecting an item by index](#selecting-an-item-by-index-string-and-stimtype) |

Other types (`File`, `Buffer`, `Coefficient Buffer`, `Undefined`) do not take
expressions; the Protocol Designer refuses to store one on them.

### How it fits in the update pipeline

When `Expression` is non-empty, the update sequence becomes:

1. `PreUpdateFcn`
2. Randomization (if `isRandom`)
3. **Expression evaluation** ← this step
4. `EvaluatorFcn`
5. Clamping to `[Min, Max]`
6. Parent write, `lastUpdated`, `PostUpdateFcn`

The expression must be a single expression — no assignments — whose own result
becomes the effective value. The value produced by step 2 is available for
reading as the variable `Value`. Sibling parameters in the same module are
injected by their `Name`; cross-module parameters can be referenced as
`ModuleName.ParamName`.

On a `String` or `StimType` parameter, step 3 has one extra half-step: the
result is validated as an index and replaced by `Values{index}` before the
pipeline continues.

### Setting an expression

```matlab
p.Expression = "FrequencyHz * 2";
```

Or assign it at construction time via `UserData` convention — but `Expression`
is a first-class property, so prefer setting it directly:

```matlab
p = hw.Parameter(parent, Name='PeriodMs');
p.Expression = "1000 / FrequencyHz";
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
| No assignments | Assignments (`=`) are not allowed. The expression's own result becomes the new value; read the incoming value via the variable `Value` if needed (e.g., `"Value * 0.5"`). An assignment such as `"Value = X * 2"` raises an evaluation error at runtime. |
| No recursion | An expression on parameter `P` cannot reference `P` itself. |
| Sibling access | Other parameters in the **same module** are available by their `Name`. |
| Cross-module access | Parameters on other modules are referenced as `ModuleName.ParamName`. These are rewritten to safe aliases before evaluation. |
| Property access | Parameter properties can be referenced as `Param.Prop` (sibling) or `ModuleName.Param.Prop` (cross-module), where `Prop` is one of `Min`, `Max`, `Values`, `Value`. |
| Multi-level parameters | If the parameter defines more than one design-time level (`Values`), the expression is treated as a level generator that `compile()` has already expanded; it is **not** re-evaluated at runtime when the dispatcher assigns per-trial values. `String` and `StimType` are exempt: there `Values` is an item list, not a set of levels, so the expression stays live no matter how many items there are. |
| Index result | On a `String` or `StimType` parameter the result must be a single whole number from 1 to the item count. Fractional, out-of-range, or non-scalar results raise an error at runtime. |

---

### Selecting an item by index (String and StimType)

`String` and `StimType` values cannot be produced by arithmetic, so an
expression on those types answers a different question: **which of the
parameter's items should this trial use?** `Values` holds the items, and the
expression returns the 1-based index of the one to select.

```matlab
cue = hw.Parameter(parent, Name='Cue', Type='String');
cue.Values = {'left', 'right', 'center'};   % three items to choose from
cue.Expression = "CueIndex";                % a sibling parameter holds 1, 2, or 3

cueIndexParam.Value = 2;
cue.Value = '';          % incoming value is discarded; the index decides
disp(cue.Value)          % right
```

Rules for the result:

- It must be a **single whole number** — not a vector, not a fraction.
- It must fall **within `1:numel(Values)`**.
- MATLAB arithmetic produces fractions easily (`Trial / 2`, `Level * 0.5`), so
  wrap the calculation in `round()`, `fix()`, `floor()`, or `ceil()`:

  ```matlab
  cue.Expression = "round(Score / 10)";
  ```

- To keep a computed index inside the list no matter what the inputs do, clamp
  it as well:

  ```matlab
  cue.Expression = "min(max(round(Score / 10), 1), 3)";
  ```

- `mod` is a convenient way to cycle through the items:

  ```matlab
  cue.Expression = "mod(TrialCount, 3) + 1";
  ```

Because the item list is a lookup table rather than a set of trial levels,
`compile()` does **not** expand it into the trial cross product: a 3-item cue
paired with a 4-level frequency yields 4 trials, not 12. Remove the expression
and the same list reverts to being 3 ordinary trial levels (12 trials).

`Min`/`Max` clamping does not apply to these types, so the index is never
silently corrected — an out-of-range result is reported, not rounded down.

For `StimType` parameters an index may be assigned directly
(`stim.Value = 2` with `stim.Expression = "Value"`), because the expression
replaces the incoming value before the stimulus-object type check runs. Without
an expression, a `StimType` parameter still accepts only a `stimgen.StimType`.

---

### Examples

#### Simple transform using a sibling parameter

Both `FrequencyHz` and `PeriodMs` live in the same module.

```matlab
freqParam  = hw.Parameter(parent, Name='FrequencyHz');
periodParam = hw.Parameter(parent, Name='PeriodMs');

periodParam.Expression = "1000 / FrequencyHz";

freqParam.Value  = 500;   % sets FrequencyHz to 500
periodParam.Value = 0;    % expression fires: 1000/500 → 2
disp(periodParam.Value)   % 2
```

#### Scale by a constant

```matlab
gainParam.Expression = "Value * 0.5";
gainParam.Value = 10;   % stored as 5
```

#### Cross-module reference

`SpeakerModule` is a different module on the same hardware interface.

```matlab
attParam.Expression = "SpeakerModule.Gain - 6";
attParam.Value = 0;   % expression reads SpeakerModule.Gain at write time
```

#### Combined with `EvaluatorFcn`

The expression runs first, then the evaluator clamps the result.

```matlab
p.Expression  = "FrequencyHz * scaleFactor";
p.EvaluatorFcn = @(obj, v) max(min(v, obj.Max), obj.Min);
p.Min = 0;
p.Max = 20000;
```

#### Conditional expression

```matlab
p.Expression = "FrequencyHz * (AttenuationLevel > 0)";
```

---

### Checking calculations before runtime

The Protocol Designer's **Protocol → Check Calculations...** dialog
(Ctrl+Shift+K) simulates how every Expression will evaluate at runtime — using
the exact runtime evaluator, per-trial dispatch order, and Min/Max clamping —
and reports errors, silent clamping, stale-reference hazards, and dormant
expressions before an experiment runs. Programmatic equivalents:
`epsych.Protocol.analyzeExpressions()` and `epsych.Protocol.dryRunExpressions()`.
`epsych.Protocol.validate()` (and therefore `compile()`) also reports expression
problems: expressions guaranteed to fail at runtime block compilation.

---

### Seeing which parameters depend on which

The Protocol Designer's **Protocol → Plot Parameter Dependencies...** menu item
(Ctrl+Shift+G) opens a new figure showing every parameter that references
another parameter in its `Expression`, plus the parameters they reference.
Arrows point from a referenced parameter to the parameter calculated from it,
so following them left to right is the order values are derived.

Node colour marks each parameter's role — calculated, plain value source,
expression that never evaluates (multi-level or `Read` access), expression with
a problem, or a reference that matches no parameter. Edge colour marks the
hazards `Check Calculations` reports: a reference dispatched later in the trial
(so the expression sees the *previous* trial's value), a reference cycle, an
ambiguous `Module.Param` name, and a missing reference. A `*` after a label
means that parameter's value varies across trials. Click any node for its
expression, dispatch position, and warnings.

Calculated parameters whose expressions reference nothing are not drawn; the
dialog reports how many were left out.

The programmatic equivalent is `epsych.Protocol.dependencyGraph()`, which
returns the `digraph` plus node and edge metadata without opening a figure.

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

1. Rejects the write if `Access` is `'Read'`.
2. Runs `PreUpdateFcn`, if present.
3. Randomizes the value when `isRandom` is true.
4. Evaluates `Expression`, if non-empty. For `'String'` and `'StimType'` the
   result is resolved through `hw.Parameter.selectValueByIndex` into one of the
   entries of `Values`.
5. Runs `EvaluatorFcn`, if present.
6. Clamps numeric values into `[Min, Max]` (per `BoundsInclusive`).
7. Updates array bookkeeping.
8. Calls `Parent.set_parameter(p, value)`. `'StimType'` is no exception: the
   backend receives the `stimgen.StimType` object itself.
9. Sets `lastUpdated = now`.
10. Runs `PostUpdateFcn`, if present.

### Expression evaluation internals

Expression evaluation is implemented in the private method `evaluateExpression_`,
a thin wrapper over the shared static methods
`hw.Parameter.resolveExpressionContext` (reference rewriting and context
construction, with a caller-supplied value lookup) and
`hw.Parameter.evalExpressionInContext` (the `eval` step). The same core is used
by the Protocol Designer's Check Calculations tool, so design-time previews and
runtime evaluation cannot drift apart.

- Qualified `ModuleName.ParamName` tokens are detected with `regexp` and
  replaced with safe variable aliases before `eval` is called.
- The context struct is unpacked into the local workspace one field at a time via
  `eval([name ' = context.(...);'])`, then `eval(expressionText)` runs.
- Cross-module parameter values are read at the moment the expression is
  evaluated (live `param.Value`), not from design-time `Values` cell arrays.
  This differs from `ProtocolDesigner`'s expression evaluator, which works
  with `Values` during compile-time expansion.
- `resolveExpressionContext` reads *every* sibling, referenced or not, so the
  value lookup runs against parameters the expression never mentions. The
  runtime lookup therefore falls back to `Values{1}` for write-only
  parameters, matching `analyzeExpressions` and `orderByDependencies`;
  otherwise one unreadable sibling would log on every dispatch and put `NaN`
  into the context. Headless coverage:
  `tmp/smoke_test_writeonly_parameter_reads.m`.
- Expression errors produce an `hw:Parameter:ExpressionError` exception with the
  parameter name and the underlying MATLAB error message. Context-build failures
  (e.g., module not accessible) are logged at verbosity level 0 and do not abort
  evaluation.
- Index resolution for `'String'`/`'StimType'` happens after `eval`, in
  `hw.Parameter.selectValueByIndex`. It raises
  `hw:Parameter:IndexExpressionNoItems`, `…NotScalar`, `…NotInteger`, or
  `…OutOfRange`; the messages name `round()`/`fix()` and the valid range so the
  operator can fix the expression without consulting this document.

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

## Related files

- [obj/+hw/@Parameter/Parameter.m](../../obj/+hw/@Parameter/Parameter.m): Class definition
- [obj/+hw/@Parameter/toStruct.m](../../obj/+hw/@Parameter/toStruct.m): Serialization to struct
- [obj/+hw/@Parameter/toJSON.m](../../obj/+hw/@Parameter/toJSON.m): Serialization to JSON string
- [obj/+epsych/@Runtime/writeParametersJSON.m](../../obj/+epsych/@Runtime/writeParametersJSON.m): Writes all runtime parameters to a JSON file

## Related documentation

- [hw_Module.md](hw_Module.md): The module container that owns parameters
- [hw_Interface.md](hw_Interface.md): The interface layer that backs reads and writes
- [../epsych/epsych_TrialLifecycle.md](../epsych/epsych_TrialLifecycle.md): How parameters are dispatched and read during trials
