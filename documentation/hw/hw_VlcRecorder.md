# hw.VlcRecorder

`hw.VlcRecorder` is an `hw.Interface` implementation for webcam preview and optional recording through VLC.

Source class:

- `obj/+hw/@VlcRecorder/VlcRecorder.m`

## Overview

The interface exposes configurable parameters and trigger-style controls. Internally it launches VLC command-line capture and, when requested, records to file while previewing.

## Parameters

Configured with `set_parameter` and read with `get_parameter`.

- `DeviceName` (String): DirectShow camera device name.
- `VlcExePath` (String): full path to `vlc.exe`.
- `MediaFile` (String): VLC media URI (default `dshow://`).
- `RecordingFile` (File): output path; empty means preview-only.

## Triggers

Call via `trigger(name)`.

- `Play`: stop any running VLC, then launch with current settings.
- `Stop`: stop VLC.
- `Pause`: no-op (documented compatibility trigger).
- `StartRecord`: relaunch with recording enabled when currently preview-only.
- `StopRecord`: relaunch in preview-only mode while preserving configured recording path.

## Lifecycle

```matlab
rec = hw.VlcRecorder();
rec.connect();
rec.set_parameter('DeviceName', 'Integrated Camera');
rec.set_parameter('RecordingFile', 'C:\data\session.ts');
rec.trigger('Play');
% ... run ...
rec.trigger('Stop');
rec.disconnect();
```

`connect` creates module parameters/triggers through `setup_interface`. `disconnect` ensures VLC is stopped.

## Device Selection Helper

`selectDevice()` enumerates camera devices using PowerShell and lets the user choose from a list dialog.

## Integration Tips

- Ensure VLC is installed and `VlcExePath` is correct.
- Prefer `.ts` output for robustness when capture may be interrupted.
- Use absolute output paths and existing directories.

## Related Documentation

- `documentation/hw/hw_Interface.md`
- `documentation/overviews/RunExpt_GUI_Overview.md`
