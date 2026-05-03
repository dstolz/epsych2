# `hw.VlcRecorder`

`hw.VlcRecorder` is a concrete `hw.Interface` subclass that connects EPsych
to a running VLC media player instance via VLC's built-in **RC (remote
control) TCP socket**. The class exposes playback and recording controls as
`hw.Parameter` objects and named triggers, integrating VLC-based webcam
capture into the standard EPsych hardware layer.

> **Source file:** `obj/+hw/@VlcRecorder/VlcRecorder.m`

---

## Contents

- [`hw.VlcRecorder`](#hwvlcrecorder)
  - [Contents](#contents)
  - [Overview](#overview)
  - [Prerequisites](#prerequisites)
    - [VLC RC interface](#vlc-rc-interface)
    - [MATLAB requirements](#matlab-requirements)
  - [Architecture](#architecture)
    - [Recording mechanism](#recording-mechanism)
  - [Constructor](#constructor)
  - [Connection lifecycle](#connection-lifecycle)
    - [`obj.connect()`](#objconnect)
    - [`obj.disconnect()`](#objdisconnect)
  - [Parameters](#parameters)
  - [Triggers](#triggers)
  - [Usage examples](#usage-examples)
    - [Basic playback](#basic-playback)
    - [Webcam recording to a file](#webcam-recording-to-a-file)
    - [Using the factory (getCreationSpec)](#using-the-factory-getcreationspec)
  - [VLC volume scale](#vlc-volume-scale)
  - [Recording workflow](#recording-workflow)
  - [Verbose logging](#verbose-logging)
  - [Extending or modifying](#extending-or-modifying)
    - [Adding new RC commands](#adding-new-rc-commands)
    - [Adding new parameters](#adding-new-parameters)
    - [Polling VLC state](#polling-vlc-state)
  - [Known limitations](#known-limitations)
  - [See also](#see-also)

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

### Recording mechanism

VLC's RC `add` command does **not** reliably pass per-item `:sout` options
through the socket interface. When a `RecordingFile` is set, `hw.VlcRecorder`
uses VLC's **VLM (Video LAN Manager)** instead, which is the correct way to
configure stream output via RC.

A VLM broadcast named `epsych_webcam` is created with a `#duplicate` sout
chain that sends the stream to both the VLC display window and the output
file simultaneously:

```
new epsych_webcam broadcast enabled
setup epsych_webcam input dshow://
setup epsych_webcam output #duplicate{dst=#display{},dst=#file{dst=C:\data\capture.ts}}
control epsych_webcam play    ← sent by trigger('Play')
control epsych_webcam stop    ← sent by trigger('Stop') or disconnect()
del epsych_webcam              ← sent by trigger('Stop') or disconnect()
```

When `RecordingFile` is empty, the plain `add <uri>` command is used and no
VLM broadcast is created.

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
| `MediaFile` | String | Write | `''` | Media URI or path to open in VLC (e.g., `'dshow://'` for DirectShow webcam). If `RecordingFile` is non-empty, a VLM broadcast named `epsych_webcam` is created; otherwise a plain `add` command is sent. Call `trigger('Play')` afterwards to start the stream. |
| `Volume` | Integer | Any | `100` | Playback volume 0–200 (100 = unity gain). See [VLC volume scale](#vlc-volume-scale). |
| `RecordingFile` | File | Any | `''` | **Absolute** output file path for the recording. Set this **before** setting `MediaFile`. When non-empty, a VLM broadcast with dual output (display + file) is used. Recording begins when `trigger('Play')` is called. |

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
| `'Play'` | `control epsych_webcam play` / `play` | Start or resume. Routes through VLM when `RecordingFile` was set; recording begins immediately. |
| `'Stop'` | `control epsych_webcam stop` + `del epsych_webcam` / `stop` | Stop playback and tear down VLM broadcast when active. |
| `'Pause'` | `control epsych_webcam pause` / `pause` | Toggle pause. |
| `'StartRecord'` | `record` | **No-op when VLM is active** (recording runs with playback). Otherwise sends the toggle — idempotent. |
| `'StopRecord'` | `record` | **No-op when VLM is active**. Otherwise sends the toggle — idempotent. |

When VLM is active, `Play` both starts playback and begins writing to the
recording file. `Stop` ends playback, finalises the file, and destroys the
VLM broadcast. `StartRecord`/`StopRecord` log a verbose message and are
otherwise no-ops.

When VLM is **not** active (no `RecordingFile` set), `StartRecord` and
`StopRecord` use VLC's `record` toggle. The class tracks toggle state in
`isRecording_` to keep them idempotent.

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

% Set output file (absolute path) BEFORE MediaFile.
% VLM broadcast is created when MediaFile is set.
obj.set_parameter('RecordingFile', 'C:\data\subject01_trial03.ts');  % absolute path
obj.set_parameter('MediaFile', 'dshow://');

obj.trigger('Play');   % starts playback AND recording via VLM
pause(30);             % record for 30 s
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

Recording is managed through VLC's **VLM (Video LAN Manager)** interface.
VLC's RC `add` command does not reliably pass per-item `:sout` options, so
VLM is used instead to attach the stream output chain.

Required sequence:

1. Set `RecordingFile` to an **absolute** output path before calling
  `set_parameter('MediaFile', ...)`.
2. Set `MediaFile` to the source URI (e.g., `'dshow://'`). The class creates
  the VLM broadcast and configures the sout chain at this point — no data
  flows yet.
3. Call `trigger('Play')` to start the stream. Recording begins immediately.
4. Call `trigger('Stop')` when done. The broadcast is stopped, the VLM entry
  is deleted, and the output file is finalised.

The sout chain used is:
```
#duplicate{dst=#display{},dst=#file{dst=<RecordingFile>}}
```
This routes the stream to both the VLC display window and the output file.

> **Use an absolute path.** A relative `RecordingFile` is resolved against
> VLC's working directory, not MATLAB's current folder.

If `RecordingFile` is empty when `MediaFile` is set, a plain `add <uri>`
command is sent with no file output.

To record a different file on the next trial, call `trigger('Stop')` first,
update `RecordingFile`, then set `MediaFile` again.

---

## Verbose logging

Set the global verbose level to 3 to see RC commands as they are sent:

```matlab
global VERBOSE_LEVEL;
VERBOSE_LEVEL = 3;
```

With this level active, every outgoing command is printed:

```
hw.VlcRecorder -> new epsych_webcam broadcast enabled
hw.VlcRecorder -> setup epsych_webcam input dshow://
hw.VlcRecorder -> setup epsych_webcam output #duplicate{dst=#display{},dst=#file{dst=C:\data\capture.ts}}
hw.VlcRecorder -> control epsych_webcam play
hw.VlcRecorder -> control epsych_webcam stop
hw.VlcRecorder -> del epsych_webcam
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
| VLM configured at `set_parameter('MediaFile')` | You cannot change the recording file while a VLM broadcast is active. Call `trigger('Stop')`, update `RecordingFile`, then set `MediaFile` again. |
| VLC `record` toggle (non-VLM mode) | Only relevant when `RecordingFile` is empty. Toggle state is tracked in `isRecording_`; reconnecting resets the flag without querying VLC. |
| Relative `RecordingFile` paths | Resolved against VLC's working directory, not MATLAB's. Always use absolute paths. |
| Single module | All parameters live in one module named `"VlcRecorder"`. Multi-device setups require a second `hw.VlcRecorder` instance. |

---

## See also

- [hw_Interface.md](hw_Interface.md) — abstract base class contract
- [hw_Interface_Tutorial.md](hw_Interface_Tutorial.md) — guide to writing a new `hw.Interface` subclass
- [hw_Module.md](hw_Module.md) — module and parameter grouping
- [hw_Parameter.md](hw_Parameter.md) — parameter types, access modes, and validation
