# `hw.VlcRecorder` — Webcam Preview and Recording

> **Source file:** `obj/+hw/@VlcRecorder/VlcRecorder.m`
> **Base class:** `hw.Interface` — see [hw_Interface.md](hw_Interface.md)

`hw.VlcRecorder` lets EPsych capture video from a webcam during an experiment. It opens a **live preview window using VLC** and, when a `RecordingFile` is configured, simultaneously records the video to disk using VLC's built-in `--sout` stream duplicator. Both the preview and recording are driven by a single VLC process — no additional tools are required.

---

## Contents

- [Requirements](#requirements)
- [Quick start — standalone usage](#quick-start--standalone-usage)
- [Recording files and formats](#recording-files-and-formats)
- [Integration: start recording at trial onset](#integration-start-recording-at-trial-onset)
- [API reference](#api-reference)
  - [Constructor](#constructor)
  - [connect / disconnect](#connect--disconnect)
  - [set\_parameter](#set_parameter)
  - [get\_parameter](#get_parameter)
  - [trigger](#trigger)
  - [selectDevice](#selectdevice)
  - [getCreationSpec (static)](#getcreationspec-static)
- [How VLC is launched](#how-vlc-is-launched)
- [Troubleshooting](#troubleshooting)
- [See also](#see-also)

---

## Requirements

| Requirement | Details |
|-------------|---------|
| [VLC media player](https://www.videolan.org/vlc/) | Expected at `C:\Program Files (x86)\VideoLAN\VLC\vlc.exe`. Adjust `vlcExePath_` in code if installed elsewhere. |
| A DirectShow webcam | Any built-in or USB camera visible in Windows Device Manager works. |
| Windows OS | Device enumeration uses PowerShell `Get-PnpDevice`. |

No ffmpeg or MATLAB toolboxes are required.

> **First-time VLC setup:** If VLC fails to start after a fresh install or update, run `vlc-cache-gen.exe` (found in the VLC install folder) as administrator once to rebuild the plugin cache.

---

## Quick start — standalone usage

```matlab
rec = hw.VlcRecorder();
rec.connect();

% Pick the camera interactively (or set 'DeviceName' directly)
rec.selectDevice();

% Optionally configure a recording output file
rec.set_parameter('RecordingFile', 'C:\data\session1.ts');

% Launch VLC — preview opens, recording starts if RecordingFile is set
rec.trigger('Play');

pause(30);  % run experiment...

% Stop VLC and finalise the recording
rec.trigger('Stop');
rec.disconnect();
```

Omit `set_parameter('RecordingFile', ...)` to run in **preview-only** mode with no file written.

---

## Recording files and formats

The output format is inferred from the file extension:

| Extension | Container | Notes |
|-----------|-----------|-------|
| `.ts` (default) | MPEG-TS | Most robust for live capture — readable even if VLC is killed before a clean stop. |
| `.mp4` | MP4 | Cleaner playback in most players, but requires a clean `trigger('Stop')` to finalise the container. |

Video is encoded as **H.264 at 1200 kbps, 30 fps** via VLC's `transcode` module. Audio is disabled (`--no-audio`).

Output path recommendations:
- Use an **absolute path** (e.g. `C:\data\mouse042_session3.ts`).
- The output directory must already exist — EPsych does not create it automatically.
- Embed the subject name and date in the filename to avoid accidental overwrites.

---

## Integration: start recording at trial onset

For automated experiments, launch recording from a **trial selector function** that is called before every trial.

```matlab
function TRIALS = MyTrialSelectFcn(TRIALS)
% Start webcam on trial 1, stop on last trial.

if TRIALS.TrialIndex == 1 && ~isfield(TRIALS, 'vlcRecorder')
    subject = TRIALS.Subject.Name;
    ts      = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    recFile = sprintf('C:\\data\\%s_%s.ts', subject, ts);

    rec = hw.VlcRecorder();
    rec.connect();
    rec.set_parameter('DeviceName',    'Integrated Camera');
    rec.set_parameter('RecordingFile', recFile);
    rec.trigger('Play');

    TRIALS.vlcRecorder = rec;
end

% ... your normal trial selection logic ...
```

To stop recording at session end, hook into the stop timer function or the RunExpt close handler, calling `TRIALS.vlcRecorder.trigger('Stop')`.

---

## API reference

### Constructor

```matlab
obj = hw.VlcRecorder()
```

Creates the object without connecting. No processes are launched. Call `connect()` before using any parameters or triggers.

---

### connect / disconnect

```matlab
obj.connect()
obj.disconnect()
```

`connect()` registers all parameters and triggers via `setup_interface()`. Idempotent — calling it twice is safe.

`disconnect()` calls `trigger('Stop')` internally to kill any running VLC process, then marks `IsConnected = false`.

---

### set_parameter

```matlab
obj.set_parameter('DeviceName',    'Integrated Camera')
obj.set_parameter('MediaFile',     'dshow://')
obj.set_parameter('RecordingFile', 'C:\data\session.ts')
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DeviceName` | String | `'Integrated Camera'` | The DirectShow video device name. Must match exactly what Windows reports. Use `selectDevice()` to pick interactively. |
| `MediaFile` | String | `'dshow://'` | Media source URI passed to VLC. Use `'dshow://'` for webcam capture; can be changed to a file path or RTSP URL for other sources. |
| `RecordingFile` | File path | `''` | Output file. Leave empty for preview-only mode. `.ts` and `.mp4` extensions are recognized; all other extensions default to MPEG-TS mux. |

Parameters can be changed while VLC is stopped. Changing a parameter after `trigger('Play')` takes effect on the next `trigger('Play')`.

---

### get_parameter

```matlab
value = obj.get_parameter('DeviceName')
value = obj.get_parameter('RecordingFile')
value = obj.get_parameter('MediaFile')
```

Returns the currently stored value as a `char`. Returns `nan` for trigger names or unrecognised parameter names.

---

### trigger

```matlab
obj.trigger('Play')         % start VLC (preview + optional recording)
obj.trigger('Stop')         % close VLC and finalise the recording file
obj.trigger('Pause')        % no-op (not supported over command line)
obj.trigger('StartRecord')  % restart VLC with recording if not already recording
obj.trigger('StopRecord')   % restart VLC in preview-only mode
```

`trigger` also accepts an `hw.Parameter` handle in place of a name string (the `hw.Interface` convention).

**`Stop` is always safe to call** — it is a no-op if VLC is not running.

**`StartRecord` / `StopRecord`** briefly close and reopen VLC because VLC's `--sout` chain cannot be modified on a running instance. There is a short (~1 second) gap in the preview window during this transition.

---

### selectDevice

```matlab
selected = obj.selectDevice()
```

Queries available camera devices via PowerShell `Get-PnpDevice -Class Camera -Status OK` and shows a list dialog. The chosen device is stored automatically via `set_parameter('DeviceName', ...)`. The return value (`selected`) can be ignored unless you need it programmatically.

Returns `""` if the dialog is cancelled or no devices are found.

---

### getCreationSpec (static)

```matlab
spec = hw.VlcRecorder.getCreationSpec()
```

Returns an `hw.InterfaceSpec` describing this interface for the hardware configuration UI. This is called by the framework — you normally do not need to call it directly.

---

## How VLC is launched

VLC is launched by writing a temporary `.bat` file and invoking it via `cmd /c`. This approach avoids PowerShell escaping issues with the complex `--sout` argument string that VLC requires.

**Display-only mode** (`RecordingFile` is empty):
```
vlc.exe dshow:// --one-instance --dshow-vdev="<DeviceName>" --no-audio
```

**Record + preview mode** (`RecordingFile` is set):
```
vlc.exe dshow:// --one-instance --dshow-vdev="<DeviceName>" --no-audio
    --sout "#duplicate{dst=display,
              dst=transcode{vcodec=h264,vb=1200,fps=30,acodec=none}
                  :standard{access=file,mux=<ts|mp4>,dst='<RecordingFile>'}}"
    --sout-keep
```

VLC is stopped by first sending the `vlc://quit` command via the `--one-instance` bus, waiting 1 second for a clean exit, then using `taskkill /IM vlc.exe` as a fallback if the process is still running. The 1-second wait gives VLC time to flush and close the output muxer cleanly.

> **One VLC instance at a time:** The `--one-instance` flag means a second `trigger('Play')` will reuse the same VLC window. Call `trigger('Stop')` before changing parameters and relaunching.

---

## Troubleshooting

**No devices appear in `selectDevice()`**
PowerShell `Get-PnpDevice -Class Camera -Status OK` found no OK-status camera devices. Open Device Manager and confirm the camera is listed without errors. On some systems the camera class is registered differently — check `Get-PnpDevice -Class Camera` (without `-Status OK`) in PowerShell to see whether the device appears with a different status.

**VLC preview does not open**
Verify that `vlcExePath_` (`C:\Program Files (x86)\VideoLAN\VLC\vlc.exe` by default) is correct for your installation. Try launching VLC manually with a `dshow://` URI to confirm your DirectShow setup is functional.

**Recording file is empty or very small**
The `DeviceName` must exactly match the DirectShow device name (including capitalisation and punctuation). Use `selectDevice()` rather than typing it manually. Also confirm the output directory exists before calling `trigger('Play')`.

**`StopRecord` / `StartRecord` cause a brief preview gap**
This is expected — VLC must be fully restarted to change the `--sout` chain. The gap is typically about 1 second.

**Recording is incomplete after a MATLAB crash**
Use `.ts` (MPEG-TS) output. Unlike MP4, MPEG-TS does not require a clean finalisation step, so frames already written remain readable even if VLC is killed abruptly.

**VLC shows a "could not start" dialog after an update**
Run `vlc-cache-gen.exe` (located in the VLC install folder) as administrator once to rebuild the plugin cache.

---

## See also

- [hw_Interface.md](hw_Interface.md) — abstract base class that all hardware interfaces implement
- [hw_Module.md](hw_Module.md) — `hw.Module` used internally to register parameters
- [hw_Parameter.md](hw_Parameter.md) — `hw.Parameter` handles used by `trigger()` and `set_parameter()`
- `runtime/timerfcns/ep_TimerFcn_Start.m` — hook for custom start logic
- `runtime/timerfcns/ep_TimerFcn_Stop.m` — hook for custom stop logic
