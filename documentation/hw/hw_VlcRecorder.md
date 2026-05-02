# `hw.VlcRecorder`

`hw.VlcRecorder` is a concrete `hw.Interface` subclass that connects EPsych
to a running VLC media player instance via VLC's built-in **RC (remote
control) TCP socket**. The class exposes playback and recording controls as
`hw.Parameter` objects and named triggers, integrating VLC-based webcam
capture into the standard EPsych hardware layer.

> **Source file:** `obj/+hw/@VlcRecorder/VlcRecorder.m`

---

## Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Constructor](#constructor)
5. [Connection lifecycle](#connection-lifecycle)
6. [Parameters](#parameters)
7. [Triggers](#triggers)
8. [Usage examples](#usage-examples)
9. [VLC volume scale](#vlc-volume-scale)
10. [Recording workflow](#recording-workflow)
11. [Verbose logging](#verbose-logging)
12. [Extending or modifying](#extending-or-modifying)
13. [Known limitations](#known-limitations)

---

## Overview

`hw.VlcRecorder` provides a thin MATLAB wrapper around the VLC RC socket
protocol. It does not spawn or manage the VLC process itself — VLC must
already be running with the RC interface enabled before you call
`obj.connect()`.

All communication is one-way by design: the RC protocol is write-oriented,
so `get_parameter()` always returns `nan`. Parameter values are cached in
`hw.Parameter.Value` on the MATLAB side and are not polled back from VLC.

---

## Prerequisites

### VLC RC interface

Start VLC with the following flags:

```
vlc --extraintf rc --rc-host 127.0.0.1:4212 --rc-quiet
```

| Flag | Purpose |
|------|---------|
| `--extraintf rc` | Enable the RC socket interface alongside any other GUI |
| `--rc-host 127.0.0.1:4212` | Bind the socket to this host and port |
| `--rc-quiet` | Suppress the VLC console prompt (reduces noise in MATLAB) |

The `host` and `port` must match what you pass to the `hw.VlcRecorder`
constructor (or the `getCreationSpec()` factory).

### MATLAB requirements

- MATLAB R2024b (or compatible release with `tcpclient` and
  `configureTerminator`).
- Instrument Control Toolbox (provides `tcpclient`).

---

## Architecture

`hw.VlcRecorder` follows the standard EPsych hw-layer pattern:

```
hw.Interface (abstract)
    └── hw.VlcRecorder
            ├── hw.Module  "VlcRecorder"
            │       ├── hw.Parameter  MediaFile
            │       ├── hw.Parameter  Volume
            │       ├── hw.Parameter  RecordingFile
            │       ├── hw.Parameter  Play        (trigger)
            │       ├── hw.Parameter  Stop        (trigger)
            │       ├── hw.Parameter  Pause       (trigger)
            │       ├── hw.Parameter  StartRecord (trigger)
            │       └── hw.Parameter  StopRecord  (trigger)
            └── tcpclient (HW property)
```

- A single `hw.Module` named `"VlcRecorder"` groups all parameters.
- Three visible parameters expose media file, volume, and recording
  output path.
- Five invisible trigger parameters map to VLC RC commands.
- A private `tcpclient` handle (`obj.HW`) carries the TCP connection.

---

## Constructor

```matlab
obj = hw.VlcRecorder()
obj = hw.VlcRecorder(host)
obj = hw.VlcRecorder(host, port)
obj = hw.VlcRecorder(host, port, timeout)
```

All arguments are optional.

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `host` | text scalar | `'127.0.0.1'` | IP address or hostname for the VLC RC socket |
| `port` | positive integer | `4212` | TCP port matching `--rc-host` |
| `timeout` | positive scalar | `5` | Connection timeout in seconds passed to `tcpclient` |

The constructor does **not** open a network connection. Call `connect()` to
establish the link.

---

## Connection lifecycle

### `obj.connect()`

Opens the TCP connection, calls `setup_interface()` to create the module and
parameters, then drains the VLC greeting message. Sets `obj.IsConnected =
true` on success.

Throws an error (from `tcpclient`) if VLC is not reachable at the specified
host and port.

Calling `connect()` on an already-connected object is a no-op.

### `obj.disconnect()`

Closes the connection, clears the `tcpclient` handle, resets the internal
`isRecording_` flag, and sets `obj.IsConnected = false`.

Calling `disconnect()` on a disconnected object is a no-op.

---

## Parameters

Parameters are created during `connect()` and are visible in any GUI or
runtime code that queries `obj.all_parameters()`.

| Name | Type | Access | Default | Description |
|------|------|--------|---------|-------------|
| `MediaFile` | String | Write | `''` | Media URI or path to open in VLC (e.g., `'dshow://'` for DirectShow webcam). Sending this parameter triggers the VLC `add` command. If `RecordingFile` is non-empty, the `:sout=` option is appended automatically. |
| `Volume` | Integer | Any | `100` | Playback volume 0–200 (100 = unity gain). See [VLC volume scale](#vlc-volume-scale). |
| `RecordingFile` | File | Any | `''` | Output file path for VLC recording. Set this **before** setting `MediaFile`; the value is injected as `:sout=#file{dst=...}` at the time `MediaFile` is applied. |

Trigger parameters (`Play`, `Stop`, `Pause`, `StartRecord`, `StopRecord`)
are hidden from `all_parameters()` by default. Pass `includeTriggers=true`
to include them:

```matlab
all = obj.all_parameters(includeTriggers=true);
```

---

## Triggers

Call `obj.trigger(name)` to send a one-shot RC command.

| Trigger name | VLC RC command | Notes |
|--------------|---------------|-------|
| `'Play'` | `play` | Resume or start playback |
| `'Stop'` | `stop` | Stop playback; resets internal `isRecording_` flag |
| `'Pause'` | `pause` | Toggle pause |
| `'StartRecord'` | `record` | Starts recording. **Idempotent** — no command sent if already recording |
| `'StopRecord'` | `record` | Stops recording. **Idempotent** — no command sent if not recording |

`StartRecord` and `StopRecord` share VLC's toggle-based `record` command but
hide that detail from callers by tracking the current state in the private
`isRecording_` property. This prevents accidental double-toggles.

Stopping playback with `'Stop'` automatically resets the recording flag so
that a subsequent `'StartRecord'` works correctly after the next
`'MediaFile'` assignment.

---

## Usage examples

### Basic playback

```matlab
obj = hw.VlcRecorder('127.0.0.1', 4212);
obj.connect();

obj.set_parameter('Volume', 80);
obj.set_parameter('MediaFile', 'C:\videos\stimulus.mp4');
obj.trigger('Play');

pause(10);
obj.trigger('Stop');
obj.disconnect();
```

### Webcam recording to a file

```matlab
obj = hw.VlcRecorder();
obj.connect();

% Set output file BEFORE MediaFile — it is injected at add-time.
obj.set_parameter('RecordingFile', 'C:\data\subject01_trial03.ts');
obj.set_parameter('MediaFile', 'dshow://');

obj.trigger('Play');
obj.trigger('StartRecord');

pause(30);  % record for 30 s

obj.trigger('StopRecord');
obj.trigger('Stop');
obj.disconnect();
```

### Using the factory (getCreationSpec)

`getCreationSpec()` integrates `hw.VlcRecorder` with EPsych's hardware
discovery and GUI-driven setup workflow.

```matlab
spec = hw.VlcRecorder.getCreationSpec();

% spec.Options lists host, port, and timeout fields.
% spec.createFcn(opts) constructs the object once the user fills in the form.

opts.host    = '127.0.0.1';
opts.port    = 4212;
opts.timeout = 5;
obj = spec.createFcn(opts);
obj.connect();
```

---

## VLC volume scale

VLC uses an internal 0–512 scale where **256 = 100% (unity gain)**.
`hw.VlcRecorder` accepts a user-friendly 0–200 scale and converts:

$$\text{vlcVol} = \text{round}(\text{Volume} \times 2.56)$$

The result is clamped to [0, 512]. A `Volume` setting of `100` sends
`volume 256` to VLC.

---

## Recording workflow

VLC records by injecting a **stream-output (`:sout`) chain** at the moment a
media item is added to the playlist. This means:

1. Set `RecordingFile` to the desired output path **first**.
2. Then set `MediaFile` to the media URI.

When both are set, `set_parameter('MediaFile', uri)` sends:

```
add <uri> :sout=#file{dst=<RecordingFile>}
```

If `RecordingFile` is empty, the plain `add <uri>` command is sent and no
file output is configured.

Changing `RecordingFile` after `MediaFile` has been sent has no effect on
the currently playing item.

---

## Verbose logging

Set the global verbose level to 3 to see RC commands as they are sent:

```matlab
global VERBOSE_LEVEL;
VERBOSE_LEVEL = 3;
```

With this level active, every outgoing command is printed:

```
hw.VlcRecorder -> add dshow:// :sout=#file{dst=C:\data\capture.ts}
hw.VlcRecorder -> play
hw.VlcRecorder -> record
```

See [`helpers/vprintf.m`](../../helpers/vprintf.m) for details on the
`vprintf` verbosity system.

---

## Extending or modifying

### Adding new RC commands

Add a new trigger in `setup_interface()`:

```matlab
obj.add_parameter('Mute', 0, ...
    isTrigger   = true, ...
    Visible     = false, ...
    Description = 'Trigger: toggle VLC mute.');
```

Then handle it in `trigger()`:

```matlab
case 'Mute'
    obj.sendCommand_('mute');
```

### Adding new parameters

Follow the same `add_parameter` pattern in `setup_interface()` and add a
matching `case` block in `set_parameter()`.

### Polling VLC state

The RC protocol does support some query commands (e.g., `is_playing`,
`get_time`). Override `get_parameter()` and call `sendCommand_()` followed
by a short `readAvailable_()` loop if you need live feedback. The current
implementation returns `nan` for all parameters since webcam capture does
not require state polling.

---

## Known limitations

| Limitation | Detail |
|------------|--------|
| VLC must be pre-launched | `hw.VlcRecorder` does not start or restart VLC. If the process is not running, `connect()` throws a TCP error. |
| Write-only RC protocol | VLC RC responses are not parsed. `get_parameter()` always returns `nan`. |
| `:sout=` is set at add-time | You cannot change the recording file for a media item that is already loaded. Stop, update `RecordingFile`, then re-set `MediaFile`. |
| VLC `record` is a toggle | The class tracks this internally via `isRecording_`, but restarting MATLAB or reconnecting resets the flag without querying VLC's actual state. |
| Single module | All parameters live in one module named `"VlcRecorder"`. Multi-module setups (e.g., separate capture and playback devices) would require a second `hw.VlcRecorder` instance. |

---

## See also

- [hw_Interface.md](hw_Interface.md) — abstract base class contract
- [hw_Interface_Tutorial.md](hw_Interface_Tutorial.md) — guide to writing a new `hw.Interface` subclass
- [hw_Module.md](hw_Module.md) — module and parameter grouping
- [hw_Parameter.md](hw_Parameter.md) — parameter types, access modes, and validation
