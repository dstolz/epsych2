# VlcRecorderSetup

`gui.VlcRecorderSetup` is a MATLAB App Designer–style UI for configuring `hw.VlcRecorder` capture parameters (device, frame rate, resolution, and crop) against a live webcam preview.

It is designed to be embedded inside another UI (panel/grid/etc.) or used standalone in its own figure, and can also be opened directly from the recorder via `rec.setupGUI()`.

## What problem it solves

`hw.VlcRecorder`'s `FrameRate`, `Resolution`, and `CropTop`/`CropBottom`/`CropLeft`/`CropRight` parameters previously had to be set blind with `set_parameter`, with no way to see what the camera frame actually looks like. This class provides:

- A live MATLAB `webcam` preview of the configured (or best-guess) camera.
- An interactive crop rectangle (`images.roi.Rectangle`) on top of the preview, kept in sync with four numeric crop fields.
- Device, resolution, and frame-rate controls.
- A "Preview in VLC" toggle to verify the actual VLC `croppadd` output before recording.

## Key concepts

### VLC/webcam exclusivity

VLC holds the DirectShow camera exclusively. The GUI stops the recorder (`Recorder.trigger('Stop')`) before opening the MATLAB webcam, and releases the webcam before any VLC preview is launched. Closing the GUI does not change the recorder's running state either way.

### Apply/OK commit semantics (not immediate)

Edits to device, resolution, frame rate, and crop are staged locally in the UI. Nothing is written to the recorder until you:

- Click **Apply** — pushes all current values to `Recorder.set_parameter(...)` and keeps the window open, or
- Click **OK** — applies, then closes the window.

Closing the window (or its parent) without clicking Apply/OK discards any unapplied edits; a status message ("Unapplied changes…") warns when edits are pending.

### Crop coordinate convention

The ROI `Position` is `[x y w h]` in image data coordinates. The displayed frame occupies the data range `[0.5, W+0.5]` horizontally and `[0.5, H+0.5]` vertically (pixel centers at integers), so:

```
CropLeft   = round(x - 0.5)
CropTop    = round(y - 0.5)
CropRight  = round(W + 0.5 - (x + w))
CropBottom = round(H + 0.5 - (y + h))
```

and the inverse when a numeric crop field is edited. No even-pixel rounding happens here — `hw.VlcRecorder.cropFilterSpec_` already rounds crop values up to an even number for x264 and logs when it does, so duplicating that here would double-round. If a crop combination would shrink the region below a minimum size (16 px), the offending values are proportionally reduced and reflected back into the fields.

Dragging the rectangle updates the four spinners live; the values are only marked "dirty" (and the recorder only updated on Apply/OK) once the drag gesture ends. Editing a spinner directly moves the rectangle to match.

### Device-name mapping

The device dropdown (editable) is populated from the union of `hw.VlcRecorder.listDevices()` (PnP `FriendlyName`s — what VLC's `--dshow-vdev` matches) and `webcamlist` (what the MATLAB preview can open). These are usually identical. If the selected recording device can't be matched to a `webcamlist` entry, the preview opens the first available camera instead and shows a status warning; the committed `DeviceName` is unaffected.

### Resolution and Apply

When the preview is running, Apply always commits the *actual previewed frame size* as `Resolution` (even if the dropdown shows "(camera default)") — this pins the crop values to the frame size VLC will actually receive, since crops are only meaningful relative to a known frame size. When the preview is disabled or unavailable, Apply commits whatever the Resolution dropdown shows.

## Requirements and dependencies

- MATLAB Image Acquisition/USB Webcams support package (`webcam`, `webcamlist`) for the live preview. Without it, the GUI still opens in a numeric-only mode (fields seeded from `Recorder.get_parameter`), with a status message explaining preview is disabled.
- Image Processing Toolbox (`images.roi.Rectangle`) for the crop ROI.
- `uifigure`, `uigridlayout`, `uiaxes`, `uidropdown`, `uispinner`, `uibutton`, `uilabel`.

## Constructor

```matlab
g = gui.VlcRecorderSetup(Recorder)
g = gui.VlcRecorderSetup(Recorder, Name=Value, ...)
```

Name–value options:

- `Parent` (default `[]`): if provided, the GUI is embedded in this container; otherwise a new `uifigure` is created and owned.
- `WindowStyle`: `"normal" | "alwaysontop" | "modal"` (only used when `Parent=[]`).
- `EnablePreview` (default `true`): set `false` to skip opening the webcam entirely (headless use, or when a camera is known to be busy). Crop fields remain numerically editable.
- `PersistPrefs` (default `true`): when applying, also mirror `DeviceName`, `FrameRate`, `Resolution`, and the four crop values to `getpref('ep_RunExpt_Video', ...)` so a later `RunExpt` webcam session can pick them up.

## Usage examples

### Example 1: From an existing recorder

```matlab
rec = hw.VlcRecorder();
g = rec.setupGUI();
```

### Example 2: Standalone window

```matlab
rec = hw.VlcRecorder();
g = gui.VlcRecorderSetup(rec, WindowStyle="alwaysontop");
```

### Example 3: Embedded in an existing app container

```matlab
fig = uifigure();
h = uipanel(fig);
g = gui.VlcRecorderSetup(rec, Parent=h);
```

### Example 4: Headless / numeric-only (no webcam opened)

```matlab
rec = hw.VlcRecorder();
g = gui.VlcRecorderSetup(rec, EnablePreview=false, PersistPrefs=false);
```

## "Preview in VLC" toggle

Clicking **Preview in VLC**:

1. Applies current values to the recorder (same as clicking Apply).
2. Releases the MATLAB webcam.
3. Calls `Recorder.trigger('Play')` so VLC opens showing exactly the cropped/resized frame it would record.
4. Disables device/resolution/crop controls (Apply/OK/toggle remain active) and relabels the button "Back to Setup".

Clicking **Back to Setup** stops VLC and reopens the MATLAB preview. No recording is ever started from this GUI (`RecordingFile` is left untouched).

## Lifecycle and cleanup

- If `Parent` is not provided, the class creates and owns a new `uifigure`; closing it deletes the object.
- If embedded, a listener deletes the object when the parent is destroyed.
- On deletion: the preview timer is stopped and deleted, the webcam is released, the crop ROI and listeners are deleted, and (if the figure is owned) its position is saved via `getpref`/`setpref` under preference group `VlcRecorderSetup`, key `Position`.
- The preview uses a private `timer` object (not `gui.GenericTimer`, which looks up timers process-wide by name and would collide across multiple open instances).

## Notes and limitations

- The preview runs at a fixed ~10 Hz sampling of `snapshot(cam)`; this is a setup aid, not a low-latency viewfinder.
- `Camera.AvailableResolutions` (MATLAB) may not exactly match what VLC's DirectShow backend negotiates; VLC's `--dshow-size` requests the size and the driver picks the nearest.
- Frame rate only affects VLC's capture (`--dshow-fps`), not the speed of the MATLAB preview.

## Related files

- `obj/+gui/@VlcRecorderSetup/VlcRecorderSetup.m` (this class)
- `obj/+hw/@VlcRecorder/VlcRecorder.m` (`setupGUI()`, `set_parameter`/`get_parameter`/`trigger`, crop even-rounding in `cropFilterSpec_`)
- `documentation/hw/hw_VlcRecorder.md`
