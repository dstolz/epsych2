# `hw.Module`

`hw.Module` represents one named hardware module, or software-backed module
shim, within an EPsych hardware interface.

It groups a set of `hw.Parameter` objects under a shared label, hardware name,
and index so GUIs and runtime code can address related parameters together.
Modules also provide the JSON serialization entry points used to save and
restore parameter state.

---

## Constructor

```matlab
obj = hw.Module(HW, Label, Name, Index)
```

### Inputs

- `HW`
  - Parent `hw.Interface` implementation that owns the module.
- `Label`
  - Short module label used for display and serialization.
- `Name`
  - Hardware-specific module name.
- `Index`
  - Unsigned module index within the parent interface.

---

## Role in the hardware layer

`hw.Module` sits between `hw.Interface` and `hw.Parameter`:

- `hw.Interface` owns one or more modules through its `Module` property.
- Each `hw.Module` owns zero or more `hw.Parameter` handles in its
  `Parameters` array.
- GUIs and runtime code can enumerate the interface, then work with
  parameters through their module grouping.

Typical pattern:

```matlab
I = hw.TDT_Synapse();
stimModule = I.Module(1);
reward = stimModule.add_parameter('Reward', 0, Unit='uL', Type='Float');
reward.Value = 5;
```

---

## Key properties

- `parent`
  - Parent `hw.Interface` instance.
- `Label`
  - Human-readable module label.
- `Name`
  - Hardware-facing module name.
- `Index`
  - Module index used by the parent implementation.
- `Fs`
  - Positive finite sample-rate or update-rate metadata. Defaults to `1`.
- `Parameters`
  - Row array of `hw.Parameter` handles belonging to the module.
- `Info`
  - Struct of module-specific metadata supplied by the parent interface.

---

## Creating parameters

Use `add_parameter` to create a new `hw.Parameter`, initialize its metadata,
and append it to the module:

```matlab
P = obj.add_parameter(name, value)
P = obj.add_parameter(name, value, Name=Value)
```

### Common name-value options

- `Description`
- `Unit`
- `Access`
- `Type`
- `Format`
- `Visible`
- `PreUpdateFcnEnabled`
- `EvaluatorFcnEnabled`
- `PostUpdateFcnEnabled`
- `UserData`
- `isArray`
- `isTrigger`
- `isRandom`
- `Min`
- `Max`

Example:

```matlab
stim = hw.Module(I, 'Stim', 'RX8', uint8(1));

p = stim.add_parameter('PulseWidth', 5, ...
    Description="Stimulus pulse width", ...
    Unit='ms', ...
    Type='Float', ...
    Min=0, ...
    Max=50);
```

Important behavior:

- If `value` is a string scalar, `add_parameter` converts it to `char`.
- If the resulting value is character data, the created parameter `Type` is
  forced to `'String'`.
- The new parameter is created with the module's parent interface as the
  `hw.Parameter` parent, then appended to `obj.Parameters`.

For detailed parameter metadata behavior, see [hw_Parameter.md](hw_Parameter.md).

---

## JSON serialization

`hw.Module` provides two helper methods for saving and restoring parameter
state:

```matlab
obj.writeParametersJSON(filepath)
obj.readParametersJSON(filepath)
```

### `writeParametersJSON`

- Writes module metadata: `Label`, `Name`, `Index`, and `Fs`.
- Serializes each `hw.Parameter` by calling its serialization helper.
- Stores function handles as strings.
- Stores `Inf`, `-Inf`, and `NaN` bounds using string sentinels so they round
  trip through JSON.

### `readParametersJSON`

- Reads a file previously written by `writeParametersJSON`.
- Matches existing parameters by `Name` and updates them in place.
- Creates missing parameters with `add_parameter`, then applies the saved
  fields.
- Warns when the serialized module metadata does not match the target module,
  but still proceeds.

### Current limitation

`PostUpdateFcnArgs` is intentionally not serialized or restored because
heterogeneous cell arrays do not round-trip reliably through JSON.

---

## Related files

- [obj/+hw/@Module/Module.m](../obj/+hw/@Module/Module.m): Class definition.
- [obj/+hw/@Module/writeParametersJSON.m](../obj/+hw/@Module/writeParametersJSON.m): JSON write helper.
- [obj/+hw/@Module/readParametersJSON.m](../obj/+hw/@Module/readParametersJSON.m): JSON read helper.
- [obj/+hw/@Parameter/Parameter.m](../obj/+hw/@Parameter/Parameter.m): Parameter class used by modules.
- [hw_Parameter.md](hw_Parameter.md): Detailed parameter reference.
