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
- `Transform` (String): rotate or flip the frame, via VLC's `transform` video
  filter. One of `none` (default), `90`, `180`, `270`, `hflip`, `vflip`,
  `transpose`, `antitranspose`. One filter takes one type, so rotating *and*
  flipping is not offered — those eight values are every orientation VLC can
  produce. Applied after the crop, in both recording and preview modes, so the
  crop values keep meaning what the operator sees in the un-rotated preview.
- `EnableCaption` (Boolean): burn a caption into the **recording**. Default
  `false`. Declared `PersistWithPhase` for the same reason the window options
  are. This is separate from `DisplayBanner`, which marks a preview as *not*
  being recorded and is still never burned in.
- `CaptionTemplate` (String): the caption text, with `{tokens}` filled in when
  recording starts. Default `{subject}  {datetime}`. Recognised tokens:
  `{subject}` `{subjects}` `{box}` `{file}` `{date}` `{time}` `{datetime}`.
  `{subject}` names the subject the recording file is named after, so a caption
  and its filename can never disagree; `{subjects}` lists them all for a rig
  running several boxes past one camera. An unsupplied or unknown token expands
  to **nothing** rather than surviving as literal braces — a recording captioned
  `{subject}` is worse than one with a gap.
- `CaptionText` (String, not visible): the resolved caption actually burned in.
  `epsych.RunExpt.videoCaptionText_` fills it at recording start, since only a
  session knows its subjects; left empty, the recorder expands the template
  against what it knows on its own (the clock), so a recorder driven directly
  still captions its recordings. It is deliberately **not** persisted to
  preferences — a remembered one would caption a recording with the previous
  session's subject.
- `CaptionPosition` (String): which corner the caption sits in, as a cardinal
  direction — `southwest` (default), `south`, `southeast`, `west`, `center`,
  `east`, `northwest`, `north`, `northeast`. Mapped to VLC's `--marq-position`
  bitfield by `hw.VlcRecorder.CAPTION_POSITIONS`; cardinal names because the
  operator picks a corner, not a number.
- `CaptionColor` (String): `yellow` (default), `white`, `green`, `cyan`,
  `magenta`, `red`, `black`. Red is offered but is not the default: a red
  overlay reads as "recording" on camera software, which is not what this marks.
- `CaptionSize` (Integer): caption font size in pixels, 6–200. Default `20`.

An unknown `CaptionPosition`, `CaptionColor`, or `Transform` is refused with a
log message and the previous value kept, rather than being forwarded to VLC as
a malformed option — a caption in the wrong corner is a far better outcome than
a run with no video. `CaptionSize` clamps instead, being a number with a range.

- `MinimalView` (Boolean): start VLC in minimal view (`--qt-minimal-view`) —
  video and playback controls only, with no menu bar, playlist, or status bar.
  Default `true`.
- `AlwaysOnTop` (Boolean): keep the VLC window above other windows
  (`--video-on-top`). Default `false`. Useful when the operator works in
  another application and needs the camera view to stay visible.

Both window options are passed on every launch in their explicit form
(`--qt-minimal-view` / `--no-qt-minimal-view`), never only when enabled. VLC
persists these settings in the user's `vlcrc`, so an operator who toggled
minimal view (Ctrl+H) or always-on-top in their own VLC would otherwise carry
that setting into every session here. They are also declared
`PersistWithPhase`, since they are settings the operator sets and leaves rather
than momentary buttons — without that, `hw.Parameter.isTransientControl` treats
any Boolean the trial dispatcher never refreshes as a button press and a saved
phase drops it.

## Two VLC quirks the command line depends on

Both were established on the bench (VLC 3, dshow capture, verified by decoding
a frame back out of the recording) and both fail **silently** — no error, no log
line, just a recording that quietly lacks what was asked for. Standing proof:
`tmp/smoke_test_vlcrecorder_caption.m`, whose gated `LaunchVlc=true` step
records for real and asserts the frame dimensions changed.

**A caption must be declared inside the transcode chain.** `--sub-source=marq`
attaches the marquee to the display vout, which the `--sout` branch never
passes through; a recording made with it — even with `soverlay` — comes out
clean. That is exactly why `DisplayBanner` has always been safe to use without
it leaking into recordings. Burning one in needs `sfilter=marq,soverlay` inside
`#transcode{...}`, with the `--marq-*` options carrying the text and appearance
as usual. `captionOpts_` builds those options and `buildVlcArgs_` adds the
`sfilter`.

**A video filter chain inside `--sout` must be single-quoted.**

| Where | Form | Chains? |
|---|---|---|
| Display (`--video-filter=`) | `a:b` | yes, as-is |
| Recording (`vfilter=` in `--sout`) | `'a:b'` — single quotes | only with the quotes |

Unquoted, VLC's sout config-chain parser splits the value at the `:` and keeps
only the **first** filter. With a crop and a rotation configured, the crop
applies and the rotation simply never happens. `videoFilterSpec_` therefore
returns the chain *unquoted* and leaves the quoting to whichever branch consumes
it — the two are not interchangeable.

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

`obj.setupGUI()` opens `gui.VlcRecorderSetup`: a live webcam preview with an interactive crop rectangle for configuring `DeviceName`, `FrameRate`, `Resolution`, and the `Crop*` parameters, an **Orientation** dropdown for `Transform`, a **Caption in recording** section (the enable checkbox, the template field, and the corner/colour/size controls, which grey out when the caption is off but keep their values so unticking never loses the operator's template), a **VLC window** section holding the `MinimalView` and `AlwaysOnTop` checkboxes, plus a "Preview in VLC" toggle to verify the actual recorded frame before starting a session.

Every one of these is mirrored into the `ep_RunExpt_Video` preference group on Apply and seeded back by `epsych.RunExpt.getVlcRecorder_`, so a rig keeps its caption and orientation across sessions — `CaptionText` excepted, as above.

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
