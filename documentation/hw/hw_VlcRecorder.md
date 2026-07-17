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
- `DisplayBanner` (String): text drawn over the video (a VLC `marq` sub-source,
  top-center, yellow) and used as the window title. Default `''` (no banner).
  Applied in preview-only mode only, so it is never burned into a recording;
  setting it has no effect while `RecordingFile` is set. Used by
  `epsych.RunExpt`'s Live Webcam View to mark a stream as not being recorded.
- `FrameRate` (Float): capture fps, forced via `--dshow-fps`. Default `30`, a
  reasonable rate for a normal webcam. `0` leaves the camera at its own
  default (which can be as low as 5 fps on some devices/formats).
- `Resolution` (Integer, 1x2 array `[width height]`): capture size, forced via
  `--dshow-size`. Default `[0 0]` (camera default).
- `CropTop`, `CropBottom`, `CropLeft`, `CropRight` (Integer): pixels to crop
  from each edge of the frame. Default `0`. Values are rounded up to the
  nearest even number (x264 requires even frame dimensions). Applied via a
  VLC `croppadd` video filter in both recording and preview-only modes.

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

## Setup GUI

`obj.setupGUI()` opens `gui.VlcRecorderSetup`: a live webcam preview with an interactive crop rectangle for configuring `DeviceName`, `FrameRate`, `Resolution`, and the `Crop*` parameters, plus a "Preview in VLC" toggle to verify the actual recorded frame before starting a session.

```matlab
rec = hw.VlcRecorder();
g = rec.setupGUI();
```

See `documentation/gui/VlcRecorderSetup.md` for details.

## Integration Tips

- Ensure VLC is installed and `VlcExePath` is correct.
- Prefer `.ts` output for robustness when capture may be interrupted.
- Use absolute output paths and existing directories.

## Related Documentation

- `documentation/hw/hw_Interface.md`
- `documentation/overviews/RunExpt_GUI_Overview.md`
- `documentation/gui/VlcRecorderSetup.md`
