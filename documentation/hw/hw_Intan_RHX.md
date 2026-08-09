# `hw.Intan_RHX`

`hw.Intan_RHX` is an `hw.Interface` implementation that connects EPsych to
[Intan RHX](https://intantech.com/RHX_software.html) acquisition software via
its built-in TCP command server.

Once connected, EPsych can start and stop recordings, read and write named
hardware parameters (sampling rate, filter settings, amplifier configuration,
etc.), and issue stimulus trigger pulses — all through the same interface API
used by every other hardware backend.

**Source:** `obj/+hw/@Intan_RHX/Intan_RHX.m`

> **Status: under development.** `hw.Intan_RHX` is still being validated and
> its API may change without notice.

---

## Prerequisites

Intan RHX must be running and its TCP command server must be enabled before
constructing a connected interface. The command server listens on
**port 5000** by default (enable it in the RHX software under
`Network > Remote TCP Control`). No additional MATLAB toolboxes are required:
`tcpclient` ships with base MATLAB (it does **not** require the Instrument
Control Toolbox).

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

% Carry protocol-level configuration (settings file, expected sample rate and
% controller type). Normally these are set in the Protocol Designer, not by hand.
iface = hw.Intan_RHX('localhost', 5000, Connect=false, ...
    SettingsFile='C:/cfg/rhx.xml', SamplingRate=30000, ...
    ControllerType='ControllerStimRecord');
```

### Constructor arguments

| Argument | Type | Default | Description |
|---|---|---|---|
| `host` | char | `'127.0.0.1'` | Hostname or IP address of the RHX command server |
| `port` | double | `5000` | TCP port of the RHX command server |
| `Timeout` | double | `5` | Maximum wait for TCP response (seconds) |
| `Connect` | logical | `true` | When `false`, skips TCP connection on construction |
| `SettingsFile` | char | `''` | RHX `.xml` settings file to load at connect (protocol-level) |
| `SamplingRate` | double | `0` | Declared board sample rate in Hz; `0` = unspecified (protocol-level) |
| `ControllerType` | char | `''` | Expected RHX controller type, validated at connect (protocol-level) |

The `SettingsFile`, `SamplingRate`, and `ControllerType` options are the
protocol-level configuration edited in the Protocol Designer (see below); they
are seeded on the object before `connect()` so `setup_interface` can load the
settings file and validate the sample rate / controller type against the
hardware.

---

## Properties

| Property | Description |
|---|---|
| `Host` | Hostname or IP address of the RHX command server |
| `Port` | TCP port number |
| `Timeout` | TCP read/write timeout in seconds |
| `IsConnected` | `true` once the TCP connection is open |
| `Module` | `hw.Module` array — one entry (`'RHX'`) populated on connect |
| `mode` | Current `hw.DeviceState`; reading it queries the hardware (throttled), writing it sends a `set runmode` command and confirms it took |
| `SettingsFile` | RHX `.xml` settings file loaded at connect. **Protocol-level** (serialized in the `.eprot`). Setter normalizes `\`→`/` and **rejects embedded spaces** |
| `SamplingRate` | Declared board sample rate in Hz (`0` = unspecified). **Protocol-level**; validated against the hardware at connect (see below) |
| `ControllerType` | Expected RHX controller type (e.g. `ControllerRecordUSB3`, `ControllerStimRecord`). **Protocol-level**, but the hardware `get type` is authoritative and overrides it at connect |
| `RecordingRootDir` | Root directory for recordings. **Per-machine**, seeded by RunExpt from the `ep_RunExpt_Intan` pref group; **not** serialized. Setter normalizes `\`→`/` and **rejects embedded spaces** |
| `ActiveSamplingRate` | Board sample rate in Hz read back from RHX at connect (read-only) |
| `ActiveRecordingFile` | Best-effort full path of the active recording, reconstructed after Record confirms |
| `ActiveFileTimestamp` | The `YYMMDD_HHMMSS` suffix RHX assigned to the active file |
| `ModeChangeTimeout` | Seconds to wait for a `runmode` change to confirm (default 2) |
| `ModePollInterval` | Minimum seconds between live `runmode` queries; throttles the per-tick watchdog (default 0.25) |
| `SettingsLoadWait` | Seconds to wait after `loadsettingsfile` (default 5) |
| `Type` | Constant `"Intan_RHX"` — identifies this backend in serialized protocols |
| `HW` | Always `[]`; present only to satisfy the `hw.Parameter` internal contract |

---

## Run mode control

Writing the `mode` property maps `hw.DeviceState` values to RHX run mode
commands:

| `hw.DeviceState` written | RHX command sent |
|---|---|
| `Record` | `set runmode record` |
| `Preview` | `set runmode run` (acquire, do not save to disk) |
| `Idle` / `Standby` / `Stop` / `Pause` / `Error` | `set runmode stop` |

After sending, `mode` polls `get runmode` until the change is confirmed
(RHX run-mode changes are not immediate), up to `ModeChangeTimeout` seconds.
A pending USB upload aborts a `set runmode`, so on a Stim/Record controller
the write first waits for `get uploadinprogress` to be `False`.

Reading `mode` maps the RHX run mode back to a `hw.DeviceState`:

| RHX `RunMode` read | `hw.DeviceState` returned |
|---|---|
| `Record` | `Record` |
| `Run` | `Preview` |
| `Trigger` | `Standby` |
| `Stop` | `Idle` |
| (unparseable / timeout) | last cached value — **never** `Idle` |

Reads are **throttled**: the run-time watchdog reads `mode` every timer tick,
so `get runmode` is issued at most once per `ModePollInterval` (default
0.25 s) and cached in between. A garbled or timed-out reply returns the cached
value rather than fabricating `Idle`, because the watchdog treats `Idle` as
"stop the session". When offline, `mode` returns the last cached value.

```matlab
% Start recording
iface.mode = hw.DeviceState.Record;

% Stop
iface.mode = hw.DeviceState.Idle;

% Check current mode
disp(iface.mode)
```

---

## Recording to disk

When a session starts in Record mode, `epsych.RunExpt` calls `prepareRecording`
on every interface just before the mode write, while the hardware is still
stopped (RHX ignores `filename.*` once the board is running). The Intan
interface then points RHX at the same file the behavioral data will use:

- **Path**: `<RecordingRootDir>/<subjectFolder>/`, mirroring the webcam
  recorder's layout. `RecordingRootDir` is seeded from the `ep_RunExpt_Intan`
  preference group (see below); when empty it falls back to the session's Data
  Save Path.
- **Base filename**: the stem of subject 1's reserved data filename
  (`RUNTIME.SessionDataFilename(1)`), so the `.rhd`/`.rhs`, the `.mat`, and the
  `.ts` video all share a name.

RHX **always** appends its own `_YYMMDD_HHMMSS` timestamp to the base filename
(and, with `CreateNewDirectory` enabled — the RHX default — nests the file in a
timestamped directory). Exact name equality with the `.mat` is therefore
impossible; the files are paired **by prefix**. After Record confirms, the
interface reads `filename.activefiletimestamp` and logs the reconstructed
on-disk name in `ActiveRecordingFile`.

> **No spaces.** The RHX `set`/`execute` grammar takes a fixed number of
> space-delimited words, so a path or subject name containing a space cannot be
> expressed. A **Record** run with a spaced target raises
> `hw:Intan_RHX:UnrepresentableFilename` and aborts (a silently unrecorded
> ephys session would only be discovered in analysis); a **Preview** run warns
> and continues, since it never writes to disk. Choose a space-free recording
> path and subject name. The Customize dialog rejects spaced paths up front.

## Settings file

`SettingsFile` names an RHX `.xml` settings file. It is **protocol-level
configuration** — set per interface in the Protocol Designer and serialized in
the `.eprot` — so a protocol carries its intended settings file. The
`ep_RunExpt_Intan` preference group (Customize dialog) still provides a
per-machine **fallback**: RunExpt applies the machine pref only when the
protocol left `SettingsFile` blank (see `configureIntanRecorder_`), so the
protocol's value always wins.

It is loaded via `execute loadsettingsfile` during `connect()` — after forcing
the board to Stop, since loading has no effect while running. It is loaded
**once per connection**: because interfaces stay connected across runs within a
session, an unchanged path is not reloaded. If the value changes mid-session,
the next run reloads it (loading takes several seconds; see `SettingsLoadWait`).
The settings path is also space-free.

## Sample rate and controller type validation

RHX fixes the board sample rate and reports the controller type from the loaded
settings file / hardware; both are **read-only** over the TCP command interface
(`sampleratehertz` and `type`). The protocol's `SamplingRate` and
`ControllerType` are therefore treated as *declared expectations* that are
validated against the hardware at connect rather than pushed to it:

- **`SamplingRate`** — when non-zero, `setup_interface` reads
  `get sampleratehertz` into `ActiveSamplingRate` and warns (`vprintf` level 0)
  if the board's actual rate disagrees, which indicates the loaded settings file
  is not the one the protocol was designed for. When `0` (unspecified) no query
  is issued.
- **`ControllerType`** — the hardware `get type` is authoritative and is adopted
  as the effective `ControllerType`; if the protocol declared a different type,
  a warning is emitted before the hardware value is used. `ControllerType` in
  turn gates `.rhs` vs `.rhd` file naming and whether manual stim triggers are
  honored.

Only `SettingsFile` is actually written into RHX; `SamplingRate` and
`ControllerType` are validated, not set.

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

RHX replies to a `set` only on a **syntax error**, so `set_parameter` is
fire-and-forget: the logical it returns means "sent", not "confirmed by the
hardware". A value containing a space cannot be expressed in the RHX grammar
and raises `hw:Intan_RHX:MalformedSet`.

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

Manual stim triggers are a **Stim/Record controller** feature. On a plain
Recording controller RHX ignores `manualstimtriggerpulse` silently, so
`trigger()` suppresses the command (warning once, via the cached
`ControllerType`) rather than leave the caller believing a pulse was delivered.

---

## Connection management

```matlab
% Explicit connect after offline construction
iface = hw.Intan_RHX('localhost', 5000, Connect=false);
iface.connect();

% Disconnect
iface.disconnect();

% The destructor releases the connection automatically
clear iface
```

`connect()` is idempotent — calling it on an already-connected interface does
nothing. Calling `disconnect()` when already disconnected is also safe.
Interfaces are left connected across runs within a session and are released
only when the session window closes.

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

Commands are sent as plain text over a TCP socket with **no terminator** —
matching Intan's reference client, which sends none and compares replies by
exact equality. (A trailing newline risks being tokenized into the value of a
`set`.) RHX parses commands case-insensitively.

| Operation | Command format | Example |
|---|---|---|
| Read a parameter | `get <parameter>` | `get runmode` |
| Write a parameter | `set <parameter> <value>` | `set runmode record` |
| Execute an action | `execute <action> [key]` | `execute manualstimtriggerpulse f1` |

### Response format

RHX replies to a `get` with a line beginning `Return:`, but replies to a `set`
or `execute` **only on a syntax error** — a successful write produces no
response at all:

```
Return: RunMode Record
Return: amp.samplingrate 20000
```

Because writes are silent on success, this backend treats `set`/`execute` as
fire-and-forget (waiting for a reply would block for the full `Timeout`). Where
confirmation matters — e.g. a run-mode change — it is obtained by polling
`get runmode`, not by reading a write's reply.

Each command has exactly two words after `set` (or one/two after `execute`), so
**values may not contain spaces**; the helpers raise
`hw:Intan_RHX:MalformedSet` / `hw:Intan_RHX:MalformedExecute` rather than send a
malformed command.

### Resynchronization

Since a rejected `set`/`execute` does leave an error response on the socket,
each command first **drains** any unsolicited bytes (logging them via
`vprintf`) so the next `get` cannot misread a stray error as its own answer.

### Timeout behavior

A `get` polls `NumBytesAvailable` in a 1 ms loop up to `Timeout` seconds; on
timeout it returns an empty string (logged via `vprintf`).

---

## Integration with epsych.Protocol

`hw.Intan_RHX` participates fully in the Protocol save/load cycle:

- **`toStruct`** serializes `Host`, `Port`, `Type`, all module parameters, and
  the protocol-level Intan configuration: `SettingsFile`, `SamplingRate`, and
  `ControllerType`. `RecordingRootDir` is **not** serialized — it is a
  per-machine preference (`ep_RunExpt_Intan`) and a machine-specific path must
  not travel inside a portable `.eprot`. RunExpt seeds `RecordingRootDir` (and,
  as a fallback, `SettingsFile`) from the preference group before connecting
  (see `configureIntanRecorder_`), keeping `getpref` out of the hardware layer.
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
**Add Interface** dropdown with the following configuration fields:

- **Host** — hostname or IP of the RHX server (text input, default `127.0.0.1`)
- **Port** — command server port (numeric input, default `5000`)
- **Settings File** — RHX `.xml` settings file loaded at connect (file picker,
  `*.xml`; must be space-free)
- **Sampling Rate (Hz)** — declared board sample rate, `0` = unspecified
  (numeric input); validated against the hardware at connect
- **Controller Type** — expected RHX controller type, e.g.
  `ControllerRecordUSB3` / `ControllerStimRecord` (text input); the hardware is
  authoritative at connect

Clicking **Add** (or **Modify** on an existing interface) calls the `createFcn`
from `getAvailableInterfaceSpecs`, which creates an offline `hw.Intan_RHX`
instance carrying these values. The interface is stored in the protocol struct
without establishing a TCP connection.

---

## `hw.DeviceState` mapping

| `hw.DeviceState` | Meaning in RHX context |
|---|---|
| `Idle` | RHX stopped (`Stop` mode) — also what a read maps `Stop` to |
| `Preview` | RHX acquiring without saving (`Run` mode) |
| `Standby` | Read-back of RHX `Trigger` mode (waiting for a hardware trigger) |
| `Record` | RHX recording to disk |

Writing `Standby`, `Stop`, `Pause`, or `Error` all send `set runmode stop`.
Reading maps RHX `Run` → `Preview`, `Trigger` → `Standby`, `Stop` → `Idle`, so
the states EPsych actually writes (`Record`, `Preview`, `Idle`) round-trip.

---

## See also

- [hw_Interface.md](hw_Interface.md) — Abstract base class contract
- [hw_Interface_Tutorial.md](hw_Interface_Tutorial.md) — Guide to authoring new backends
- [hw_Module.md](hw_Module.md) — Module and parameter ownership
- [hw_Parameter.md](hw_Parameter.md) — Parameter configuration and callbacks
