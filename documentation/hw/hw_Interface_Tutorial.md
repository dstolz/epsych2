# `hw.Interface` tutorial

This tutorial shows the standard EPsych workflow for authoring a new
`hw.Interface` subclass.

Use `hw.TDT_Synapse` and `hw.TDT_RPcox` as the two reference patterns:

- `hw.TDT_Synapse` discovers modules and parameters dynamically from a live
  API.
- `hw.TDT_RPcox` is configured from a known set of RPvds circuits and then
  scans each circuit's exported tags.

If you are building support for a new device family, the usual job is to
adapt one of those two patterns rather than invent a third architecture.

---

## 1. Create the class folder

Place the new interface under `obj/+hw/@YourInterfaceName/`.

Typical layout:

```text
obj/+hw/@YourInterfaceName/
  YourInterfaceName.m
  setup_interface.m
```

EPsych keeps the constructor and public methods in the class file and places
the setup logic in a separate `setup_interface.m` helper. Both
`hw.TDT_Synapse` and `hw.TDT_RPcox` follow this pattern.

## 2. Define the required class contract

Every subclass must provide:

- a protected `Module` array of `hw.Module`
- a constant `Type` string
- a settable `mode` property backed by `hw.DeviceState`
- protected `setup_interface()` and `close_interface()` methods
- public `trigger()`, `set_parameter()`, and `get_parameter()` methods

Minimal skeleton:

```matlab
classdef YourInterfaceName < hw.Interface

  properties (SetAccess = protected)
    HW
    Module
  end

  properties (SetObservable, AbortSet)
    mode (1,1) hw.DeviceState
  end

  properties (Constant)
    Type = "YourInterfaceName"
  end

  methods
    function obj = YourInterfaceName(varargin)
      obj.setup_interface(varargin{:});
    end
  end

  methods (Access = protected)
    setup_interface(obj, varargin)
    close_interface(obj)
  end

  methods
    function t = trigger(obj, name)
    end

    function ok = set_parameter(obj, name, value)
    end

    function value = get_parameter(obj, name)
    end
  end
end
```

The inherited helpers `find_parameter`, `all_parameters`, and
`filter_parameters` already solve parameter discovery. Your subclass only
needs to solve backend-specific connection and I/O.

## 3. Decide how modules are discovered

There are two established discovery models in this repository.

### Pattern A: discover modules from the backend (`hw.TDT_Synapse`)

`hw.TDT_Synapse` connects to the API first, queries available devices and
sample rates, and then creates one `hw.Module` per discovered gizmo.

The sequence is:

1. Construct the API object.
2. Put the backend into a safe starting state.
3. Ask the backend for module names and rates.
4. Create `hw.Module` objects from that metadata.
5. Query parameter metadata for each module.
6. Create `hw.Parameter` objects from the returned metadata.

Relevant implementation:

- [obj/+hw/@TDT_Synapse/TDT_Synapse.m](../obj/+hw/@TDT_Synapse/TDT_Synapse.m)
- [obj/+hw/@TDT_Synapse/setup_interface.m](../obj/+hw/@TDT_Synapse/setup_interface.m)

Representative setup flow:

```matlab
obj.HW = SynapseAPI(obj.Server);

if obj.HW.getMode > 0
  obj.HW.setMode(0);
end

obj.HW.setModeStr('Standby');

h = obj.HW.getSamplingRates;

for m = 1:length(mName)
  obj.Module(m) = hw.Module(obj, mLabel{m}, mName{m}, mIdx(m));
  obj.Module(m).Fs = mFs(m);
end
```

Use this pattern when the vendor API can tell you what modules and parameters
exist at runtime.

### Pattern B: create modules from configuration, then scan tags (`hw.TDT_RPcox`)

`hw.TDT_RPcox` starts from constructor inputs rather than discovery. The user
supplies RPvds file paths, device types, and aliases. The interface then
creates one backend object per configured device and scans that device's tag
table.

The sequence is:

1. Normalize constructor inputs to cell arrays.
2. Create one backend object per configured device.
3. Create one `hw.Module` per backend object.
4. Store per-module metadata such as `Fs` and source file.
5. Read exported tags from the backend.
6. Convert each tag into a `hw.Parameter`.

Relevant implementation:

- [obj/+hw/@TDT_RPcox/TDT_RPcox.m](../obj/+hw/@TDT_RPcox/TDT_RPcox.m)
- [obj/+hw/@TDT_RPcox/setup_interface.m](../obj/+hw/@TDT_RPcox/setup_interface.m)

Representative setup flow:

```matlab
for i = 1:length(moduleType)
  obj.HW(i) = TDTRP(RPvdsFile{i}, moduleType{i});

  M = hw.Module(obj, moduleType{i}, moduleAlias{i}, 1);
  M.Fs = obj.HW.RP.GetSFreq;
  M.Info.RPvdsFile = RPvdsFile{i};

  pt = obj.HW.PARTAG;
  pt = [pt{:}];

  for p = 1:length(pt)
    P = hw.Parameter(obj);
    P.Name = pt(p).tag_name;
    P.Module = M;
    M.Parameters(p) = P;
  end

  obj.Module(i) = M;
end
```

Use this pattern when the hardware layout is known ahead of time, but the
parameter list still comes from the device or circuit.

## 4. Build `hw.Module` objects first

Each module needs a parent interface, a display label, a hardware-facing
name, and an index:

```matlab
M = hw.Module(obj, label, name, index);
M.Fs = sampleRate;
M.Info.BackendName = backendName;
```

Guidelines:

- `Label` is what the rest of EPsych will usually display.
- `Name` should preserve the backend's own module name where possible.
- `Index` should be stable and backend-meaningful if the device API exposes
  one.
- Store extra backend metadata in `M.Info` rather than adding ad hoc
  interface properties.

## 5. Convert backend metadata into `hw.Parameter` objects

Once a module exists, populate its `Parameters` array.

Both TDT interfaces construct `hw.Parameter(obj)` directly and then assign
metadata fields such as `Name`, `Type`, `Access`, `Module`, `Min`, `Max`,
`isArray`, and `Visible`.

Typical dynamic-discovery pattern:

```matlab
P = hw.Parameter(obj);
P.Name = backendInfo.Name;
P.Unit = backendInfo.Unit;
P.Min = backendInfo.Min;
P.Max = backendInfo.Max;
P.Access = backendInfo.Access;
P.Type = backendInfo.Type;
P.isArray = backendInfo.IsArray;
P.Module = M;

M.Parameters(end+1) = P;
```

For hand-authored interfaces or software shims, `hw.Module.add_parameter()`
is often simpler because it creates and appends the parameter in one step.

## 6. Apply EPsych naming conventions deliberately

The current TDT backends use parameter name prefixes to drive behavior.

- Trigger parameters start with `!`.
- Synapse hides names beginning with `_` or `~`.
- RPcox hides names beginning with `_`, `~`, `#`, or `%`.
- RPcox marks array parameters from `tag_size > 1`.

Examples from the repository:

```matlab
P.isTrigger = P.Name(1) == '!';
P.Visible = ~any(P.Name(1) == '_~#%');
```

```matlab
P.isTrigger = P.Name(1) == '!';
P.Visible = P.Name(1) ~= '_';
P.Visible = P.Name(1) ~= '~';
```

If your backend does not already encode these meanings in the parameter name,
define your own mapping in `setup_interface()` and keep it consistent.

## 7. Map backend types into EPsych parameter types

The interface layer expects parameter `Type` values that fit the
`hw.Parameter` contract:

- `Float`
- `Integer`
- `Boolean`
- `Buffer`
- `Coefficient Buffer`
- `String`
- `Undefined`

`hw.TDT_Synapse` receives these values directly from the API metadata.
`hw.TDT_RPcox` has to translate numeric RP tag codes into EPsych type names.

That translation step is part of the interface author's job. Do it once in
`setup_interface()` and keep the rest of the code type-agnostic.

## 8. Implement mode translation

Your `mode` property is the bridge between backend state and
`hw.DeviceState`.

`hw.TDT_Synapse` uses a direct mapping because the API already exposes a mode
enumeration compatible with EPsych:

```matlab
function set.mode(obj,mode)
  obj.HW.setMode(double(mode));
end

function m = get.mode(obj)
  m = hw.DeviceState(obj.HW.getMode());
end
```

`hw.TDT_RPcox` needs an explicit translation table because `GetStatus`
returns backend-specific codes:

```matlab
m = double(obj.HW.RP.GetStatus);
switch m
  case 1
    m = hw.DeviceState.Idle;
  case {3, 5}
    m = hw.DeviceState.Standby;
  case 7
    m = hw.DeviceState.Record;
  otherwise
    m = hw.DeviceState.Error;
end
```

If your backend does not expose a clean state model, define a conservative
mapping and document it.

## 9. Implement `trigger`, `set_parameter`, and `get_parameter`

This is where backend-specific I/O lives. The common pattern in both TDT
classes is:

1. Resolve names to `hw.Parameter` handles with `find_parameter()`.
2. Convert values into the backend's required format.
3. Perform the backend call.
4. Preserve request order in the return value.

Minimal write/read pattern:

```matlab
function ok = set_parameter(obj, name, value)
  if isa(name, 'hw.Parameter')
    P = name;
  else
    P = obj.find_parameter(name);
  end

  if isvector(P) && isscalar(value)
    value = repmat(value, size(P));
  end

  for i = 1:length(P)
    ok = backendWrite(P(i), value(i));
  end
end

function value = get_parameter(obj, name)
  if isa(name, 'hw.Parameter')
    P = name;
    name = {P.Name};
  else
    P = obj.find_parameter(name);
  end

  value = cell(size(P));
  for i = 1:length(P)
    value{i} = backendRead(P(i));
  end

  [~, idx] = ismember(name, {P.Name});
  value = value(idx);

  if isscalar(value)
    value = value{1};
  end
end
```

Use the parameter handle to recover whatever backend routing data you need.
For Synapse, the write path uses `p.Module.Label` and `p.Name`. For RPcox,
the write path uses the tag name directly.

## 10. Keep `trigger()` separate from normal writes

Trigger parameters are modeled as a quick pulse high then low. Both TDT
implementations do this explicitly instead of routing triggers through the
normal write path.

Typical pattern:

```matlab
e = backendWrite(P, 1);
t = now;
pause(0.001)
e = backendWrite(P, 0);
```

Keep `trigger()` separate even if the backend technically exposes triggers as
ordinary writable values. That preserves the semantics expected by
`hw.Parameter.Trigger()`.

## 11. Release resources in `close_interface()`

The shutdown sequence should do two things:

1. put the hardware into a safe or idle state
2. delete or release the backend handle if it exists

Both TDT implementations first return the device to idle and then delete the
backend object.

Use this method for cleanup logic only. Do not put discovery or normal state
updates here.

## 12. Smoke-test the new interface

After implementing the class, validate the contract with a short MATLAB
session:

```matlab
I = hw.YourInterfaceName(...);

disp(I.Type)
disp({I.Module.Label})

P = I.all_parameters();
disp({P.Name})

reward = I.find_parameter("Reward", silenceParameterNotFound=true);
if ~isempty(reward)
  I.get_parameter(reward);
end
```

Then test three behaviors explicitly:

- ordinary scalar read/write
- array parameter read/write if the backend supports arrays
- trigger pulse behavior for any parameter marked `isTrigger=true`

## 13. Authoring checklist

Before considering the interface complete, verify the following:

- constructor gathers the configuration needed to connect
- `setup_interface()` fills `obj.HW` and `obj.Module`
- every `hw.Parameter` has its `Module` property assigned
- `Type`, `Access`, `Min`, `Max`, `Visible`, and `isArray` are populated when
  the backend exposes that metadata
- `mode` round-trips cleanly between backend state and `hw.DeviceState`
- `trigger`, `set_parameter`, and `get_parameter` accept either names or
  `hw.Parameter` handles
- `get_parameter` preserves the requested name order
- `close_interface()` safely releases resources

## 14. Choosing between the two TDT examples

Use `hw.TDT_Synapse` as your template when:

- the backend can enumerate modules at runtime
- the backend provides rich parameter metadata
- modules are identified by names and indices returned by the API

Use `hw.TDT_RPcox` as your template when:

- the caller already knows which device or circuit instances should exist
- the backend exposes a tag table rather than rich object metadata
- you need to translate vendor-specific tag codes into EPsych parameter types

In both cases, the core design stays the same: build `hw.Module` objects,
populate `hw.Parameter` metadata, and implement a thin translation layer for
mode changes and I/O.

---

## Related references

- [hw_Interface.md](hw_Interface.md): Main API and behavior reference for
  `hw.Interface`.
- [hw_Module.md](hw_Module.md): Module container details.
- [hw_Parameter.md](hw_Parameter.md): Parameter metadata and delegation
  behavior.

