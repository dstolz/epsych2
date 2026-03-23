# `hw.Interface`

`hw.Interface` is the abstract base class that standardizes how EPsych talks
to hardware backends.

Concrete subclasses expose one or more `hw.Module` objects, each containing
`hw.Parameter` instances. Higher-level code can then discover parameters,
filter them, read their values, update them, and trigger events without being
coupled to a specific device API.

You do not instantiate `hw.Interface` directly. Instead, you work with a
subclass such as a software-backed shim or a device-specific implementation.

In this repository, the main concrete subclasses are `hw.Software`,
`hw.TDT_Synapse`, and `hw.TDT_RPcox`.

For a step-by-step guide to authoring a new hardware backend, see
[hw_Interface_Tutorial.md](hw_Interface_Tutorial.md).

---

## Role in the hardware layer

`hw.Interface` sits above concrete device drivers and below the rest of the
application:

- Subclasses manage connection setup and shutdown.
- Modules group related parameters for a device or subsystem.
- Parameters provide the uniform read/write surface used by GUIs and runtime
  code.

This separation lets the same experiment and GUI code run against hardware
implementations or software-backed shims.

---

## When to use this class

Use `hw.Interface` as the common contract when you need code to work across
multiple hardware backends.

Typical cases include:

- GUI code that needs to list, display, and edit parameters.
- Runtime code that needs to trigger named hardware actions.
- Test code that swaps a real device implementation for `hw.Software`.
- New driver development where a subclass must fit into the existing EPsych
  hardware layer.

---

## Class contract

Subclasses are expected to define these abstract members:

- `Module`: Array of `hw.Module` objects owned by the interface.
- `Type`: Constant string identifier for the implementation.
- `mode`: Current `hw.DeviceState` value.
- `setup_interface()`: Allocate or connect hardware resources.
- `close_interface()`: Release hardware resources.
- `trigger(name)`: Trigger a hardware event.
- `set_parameter(name, value)`: Write one or more parameters.
- `get_parameter(name)`: Read one or more parameters.

The abstract API is intentionally small. Discovery and filtering helpers are
implemented once in `hw.Interface` (previously in `helpers/`, now consolidated) so subclasses only need to handle device-
specific I/O.

In practice, a concrete subclass is responsible for:

- creating its `Module` array
- populating each module with `hw.Parameter` objects
- translating parameter reads and writes into backend-specific calls
- maintaining the current device `mode`
- cleaning up device resources when the interface is closed

For a worked example of how to implement those responsibilities, see
[hw_Interface_Tutorial.md](hw_Interface_Tutorial.md).

---

## Repository subclasses

### `hw.Software`

`hw.Software` is the simplest implementation. It stores parameter values in
memory and is mainly used for testing GUIs, protocol logic, and workflows
that should run without a physical device connection.

### `hw.TDT_Synapse`

`hw.TDT_Synapse` connects EPsych to TDT Synapse through the Synapse API
wrapper. It exposes Synapse modules and parameters through the common
interface helpers (now in `hw.Interface`) and tracks current experiment metadata.

### `hw.TDT_RPcox`

`hw.TDT_RPcox` connects to RPvds-based TDT devices through the TDTRP layer.
It loads one or more circuits, creates corresponding `hw.Module` objects, and
routes parameter I/O through the shared interface contract.

---

## Common usage

Most code interacts with concrete subclasses through inherited helper methods.

```matlab
I = hw.TDT_Synapse(...);

rewardParam = I.find_parameter("Reward");
allVisible = I.all_parameters();
writeOnly = I.filter_parameters('Access', 'Write');

I.set_parameter("Reward", 1);
```

If a parameter name exists on multiple modules, `find_parameter` may return an
array of `hw.Parameter` handles.

For software-only testing, the same workflow can be used with a shim:

```matlab
I = hw.Software();
P = I.find_parameter("Reward");
```

---

## Helper methods

### `find_parameter`

```matlab
P = I.find_parameter(name)
P = I.find_parameter(name, includeInvisible=true)
P = I.find_parameter(name, silenceParameterNotFound=true)
```

Finds parameters by name across all modules.

- Accepts a character vector, string scalar, or cell array of names.
- Preserves the order of requested names in the returned array.
- Returns an empty array when nothing matches.
- Logs a warning through `vprintf` unless
  `silenceParameterNotFound=true`.

### `filter_parameters`

```matlab
P = I.filter_parameters(propertyName, propertyValue)
P = I.filter_parameters(propertyName, propertyValue, testFcn=@contains)
```

Filters parameters by applying a comparison function to one property.

Examples:

```matlab
readable = I.filter_parameters('Access', 'Read');
stimParams = I.filter_parameters('Name', "Stim", testFcn=@contains);
```

By default, trigger parameters and invisible parameters are excluded from the
candidate set unless they are explicitly requested.

### `all_parameters`

```matlab
P = I.all_parameters()
P = I.all_parameters(includeTriggers=false, includeInvisible=true)
```

Collects every parameter from every module and optionally filters out:

- trigger parameters
- invisible parameters
- array-valued parameters

This is the common starting point for parameter introspection logic.

### `local_test`

```matlab
tf = hw.Interface.local_test(fcn, val, pat)
```

This static helper converts the output of a comparison function into a single
logical result. It is mainly used internally by `filter_parameters`, but it is
useful to understand because it defines what counts as a match.

---

## Relationship to modules and parameters

`hw.Interface` owns the top-level `Module` array. Each `hw.Module` then owns
its `Parameters` array.

That means the common traversal pattern is:

1. Start from a concrete interface instance.
2. Enumerate or search its modules.
3. Read, filter, or update the parameters exposed by those modules.

For detailed module behavior, see [hw_Module.md](hw_Module.md). For detailed
parameter behavior, see [hw_Parameter.md](hw_Parameter.md).

---

## Matching behavior

`filter_parameters` uses the static helper `local_test` to normalize the
output of a comparison function into a scalar logical value.

This matters because different MATLAB functions return matches in different
forms:

- `isequal` returns a scalar logical.
- `regexp` may return numeric match indices.
- Some comparisons may return cell arrays.

`local_test` treats non-empty results as a match, which makes these functions
usable through a common filtering path.

---

## Example workflow

This example shows a typical parameter-discovery flow that works across
different subclasses.

```matlab
I = hw.TDT_Synapse(...);

visibleParams = I.all_parameters();
readWriteParams = I.filter_parameters('Access', 'Read / Write');
rewardParam = I.find_parameter("Reward");

if ~isempty(rewardParam)
  I.set_parameter("Reward", 1);
end
```

The important idea is that calling code does not need to know how the backend
stores or communicates with its parameters. That work is delegated to the
subclass implementation.

---

## Notes and limitations

- `hw.Interface` defines the shared API, but it does not enforce how a
  subclass organizes backend-specific connection logic.
- Parameter lookup is name-based, so duplicate parameter names across modules
  can return multiple matches.
- The helper methods assume each module exposes its parameters through the
  `Module.Parameters` property.
- Error handling for backend communication is implemented by subclasses, not
  by the base class.

---

## Design notes

- `hw.Interface` inherits from `matlab.mixin.Heterogeneous`, which allows
  arrays of mixed interface subclasses where MATLAB supports heterogeneous
  handle arrays.
- It also inherits from `matlab.mixin.SetGet`, which keeps the interface
  compatible with older handle-style property workflows used elsewhere in the
  codebase.
- The class does not implement actual hardware I/O. That responsibility stays
  in subclasses such as software shims or device-specific drivers.

---

## Related classes

- `hw.Module` groups parameters that belong to a single subsystem or device.
- `hw.Parameter` stores metadata and delegates reads and writes through the
  interface.
- `hw.Software` is a lightweight implementation that satisfies the same
  contract without talking to external hardware.

---

## Related files

- [obj/+hw/@Interface/Interface.m](../obj/+hw/@Interface/Interface.m): Base
  class implementation.
- [obj/+hw/@Module/Module.m](../obj/+hw/@Module/Module.m): Module container
  class used by interfaces.
- [obj/+hw/@Parameter/Parameter.m](../obj/+hw/@Parameter/Parameter.m):
  Parameter abstraction exposed by modules.
- [obj/+hw/@Software/Software.m](../obj/+hw/@Software/Software.m): Minimal
  software-backed implementation of the interface contract.
- [hw_Interface_Tutorial.md](hw_Interface_Tutorial.md): Step-by-step guide to
  authoring a custom `hw.Interface` subclass.

These implementations are the main code references when building a new
hardware backend.
