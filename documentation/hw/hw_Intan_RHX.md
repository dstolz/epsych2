# `hw.Intan_RHX`

`hw.Intan_RHX` is an `hw.Interface` implementation that connects EPsych to
[Intan RHX](https://intantech.com/RHX_software.html) acquisition software via
its built-in TCP command server.

Once connected, EPsych can start and stop recordings, read and write named
hardware parameters (sampling rate, filter settings, amplifier configuration,
etc.), and issue stimulus trigger pulses — all through the same interface API
used by every other hardware backend.

**Source:** `obj/+hw/@Intan_RHX/Intan_RHX.m`

---

## Prerequisites

Intan RHX must be running and its TCP command server must be enabled before
constructing a connected interface. The command server listens on
**port 5000** by default (configurable in the RHX software under
`Network > Command Port`). No additional MATLAB toolboxes are required beyond
the Instrument Control Toolbox (for `tcpclient`).

---

## Construction

```matlab
% Connect to RHX on the same machine (default host/port)
iface = hw.Intan_RHX();

% Connect to a specific host and port
iface = hw.Intan_RHX('192.168.1.10', 5000);

% Create offline — useful for serialization/deserialization without hardware
iface = hw.Intan_RHX('192.168.1.10', 5000, Connect=false);

% Adjust TCP timeout
iface = hw.Intan_RHX('localhost', 5000, Timeout=10);
```

### Constructor arguments

| Argument | Type | Default | Description |
|---|---|---|---|
| `host` | char | `'127.0.0.1'` | Hostname or IP address of the RHX command server |
| `port` | double | `5000` | TCP port of the RHX command server |
| `Timeout` | double | `5` | Maximum wait for TCP response (seconds) |
| `Connect` | logical | `true` | When `false`, skips TCP connection on construction |

---

## Properties

| Property | Description |
|---|---|
| `Host` | Hostname or IP address of the RHX command server |
| `Port` | TCP port number |
| `Timeout` | TCP read/write timeout in seconds |
| `IsConnected` | `true` once the TCP connection is open |
| `Module` | `hw.Module` array — one entry (`'RHX'`) populated on connect |
| `mode` | Current `hw.DeviceState`; reading it queries the hardware, writing it sends a `set runmode` command |
| `Type` | Constant `"Intan_RHX"` — identifies this backend in serialized protocols |
| `HW` | Always `[]`; present only to satisfy the `hw.Parameter` internal contract |

---

## Run mode control

The `mode` property maps between `hw.DeviceState` values and RHX run mode
commands:

| `hw.DeviceState` | RHX command sent |
|---|---|
| `Idle` | `set runmode stop` |
| `Standby` | `set runmode stop` |
| `Record` | `set runmode record` |
| Other | `set runmode run` |

Reading `mode` sends `get runmode` to the hardware and parses the response.
When the interface is offline, `mode` returns the last cached value.

```matlab
% Start recording
iface.mode = hw.DeviceState.Record;

% Stop
iface.mode = hw.DeviceState.Idle;

% Check current mode
disp(iface.mode)
```

---

## Reading and writing parameters

Parameters must first be registered on the interface's module (either during
`setup_interface` or manually using `add_parameter`). Once registered,
`get_parameter` and `set_parameter` translate each call into an RHX TCP
command.

```matlab
% Add a parameter to track
iface.add_parameter('amp.samplingrate', 20000);

% Read it back (sends: get amp.samplingrate)
rate = iface.get_parameter('amp.samplingrate');

% Write a new value (sends: set amp.samplingrate 30000)
iface.set_parameter('amp.samplingrate', 30000);

% Read the raw RHX response string instead of the parsed value
raw = iface.get_parameter('amp.samplingrate', ReturnRaw=true);
% raw == 'Return: amp.samplingrate 30000'
```

Multiple parameters can be passed as a cell array of names or as an
`hw.Parameter` array. `set_parameter` accepts a scalar value (applied to all
parameters) or a cell array of values matching the parameter count.

```matlab
iface.set_parameter({'filter.lowcutoff', 'filter.highcutoff'}, {300, 6000});
```

---

## Triggering

RHX supports up to eight manual stimulus trigger keys (`f1`–`f8`). To issue a
trigger pulse from EPsych, first register a trigger parameter and store the
desired key in its `UserData.TriggerKey` field:

```matlab
p = iface.add_parameter('stim1', 0, isTrigger=true);
p.UserData.TriggerKey = 'f1';

% Issue the pulse (sends: execute manualstimtriggerpulse f1)
t = iface.trigger('stim1');   % returns datetime of delivery
```

If `UserData.TriggerKey` is not set, the key defaults to `'f1'`.

---

## Connection management

```matlab
% Explicit connect after offline construction
iface = hw.Intan_RHX('localhost', 5000, Connect=false);
iface.connect();

% Disconnect
iface.close_interface();

% The destructor calls close_interface automatically
clear iface
```

`connect()` is idempotent — calling it on an already-connected interface does
nothing. Calling `close_interface()` when already disconnected is also safe.

---

## Module management

On successful connection, `setup_interface` creates a single `hw.Module`
named `'RHX'` (label `'RHX'`, index `1`). This module represents the RHX
device as a whole.

When constructing offline and then loading parameters from a saved protocol,
the module and its parameters are restored by the Protocol deserialization
layer. If you need to replace the module array manually (e.g. during testing),
use `setModules`, which is only permitted while offline:

```matlab
iface = hw.Intan_RHX('localhost', 5000, Connect=false);
m = hw.Module(iface, 'RHX', 'RHX', uint8(1));
iface.setModules(m);
```

---

## TCP command protocol

Commands are sent as plain text over a TCP socket, terminated with a newline
(`LF`). The RHX software parses commands case-insensitively.

| Operation | Command format | Example |
|---|---|---|
| Read a parameter | `get <parameter>` | `get runmode` |
| Write a parameter | `set <parameter> <value>` | `set runmode record` |
| Execute an action | `execute <action> [key]` | `execute manualstimtriggerpulse f1` |

### Response format

Successful responses start with `Return:`:

```
Return: RunMode Record
Return: amp.samplingrate 20000
```

Error and warning responses are free-form text beginning with `Error` or
`Warning:`. `set_parameter` logs a warning via `vprintf` when a non-success
response is received but does not throw.

### Timeout behavior

`sendCommand_` polls `NumBytesAvailable` in a 1 ms loop up to `obj.Timeout`
seconds. On timeout it returns an empty string, which `isSuccessResponse_`
treats as failure.

---

## Integration with epsych.Protocol

`hw.Intan_RHX` participates fully in the Protocol save/load cycle:

- **`toStruct`** serializes `Host`, `Port`, `Type`, and all module parameters.
- **`createInterfaceFromStruct_`** reconstructs the interface with
  `Connect=false` so that opening a saved protocol does not attempt to connect
  to hardware.
- **`getAvailableInterfaceSpecs`** registers the `'Intan RHX'` entry in the
  Protocol Designer interface picker.

### Saving and loading a protocol

```matlab
% Build a protocol with an Intan interface
iface = hw.Intan_RHX('192.168.1.50', 5000, Connect=false);
m = hw.Module(iface, 'RHX', 'RHX', uint8(1));
iface.setModules(m);
iface.add_parameter('amp.samplingrate', 20000);

prot = epsych.Protocol();
prot.addInterface(iface);
prot.save('my_protocol.eprot');

% Load it back — interface is offline until connect() is called
prot2 = epsych.Protocol();
prot2.load('my_protocol.eprot');
iface2 = prot2.Interfaces(end);   % find by index or type
iface2.connect();                  % connect to hardware when ready
```

---

## Protocol Designer

When the Protocol Designer is open, `'Intan RHX'` appears in the
**Add Interface** dropdown with two configuration fields:

- **Host** — hostname or IP of the RHX server (text input, default `127.0.0.1`)
- **Port** — command server port (numeric input, default `5000`)

Clicking **Add** calls the `createFcn` from `getAvailableInterfaceSpecs`, which
creates an offline `hw.Intan_RHX` instance. The interface is stored in the
protocol struct without establishing a TCP connection.

---

## `hw.DeviceState` mapping

| `hw.DeviceState` | Meaning in RHX context |
|---|---|
| `Idle` | RHX stopped (`Stop` mode) |
| `Standby` | RHX stopped (same as Idle for RHX; mapped to `Stop`) |
| `Record` | RHX recording to disk |

RHX `Run` and `Trigger` modes (acquisition without saving) are mapped to
`hw.DeviceState.Standby` when reading `mode` back from hardware.

---

## See also

- [hw_Interface.md](hw_Interface.md) — Abstract base class contract
- [hw_Interface_Tutorial.md](hw_Interface_Tutorial.md) — Guide to authoring new backends
- [hw_Module.md](hw_Module.md) — Module and parameter ownership
- [hw_Parameter.md](hw_Parameter.md) — Parameter configuration and callbacks
