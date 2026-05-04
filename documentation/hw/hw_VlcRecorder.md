# `hw.VlcRecorder` — Webcam Preview and Recording

> **Source file:** `obj/+hw/@VlcRecorder/VlcRecorder.m`
> **Test script:** `tmp/VlcRecorder_example.m`

`hw.VlcRecorder` lets EPsych capture video from a webcam during an experiment. It opens a live preview window using **VLC** and records the video to a file using **ffmpeg**. Both happen simultaneously — the researcher sees the feed in real time, and a complete recording is saved to disk for later review.

You do not need to start VLC or ffmpeg manually. EPsych launches and closes them for you.

---

## Contents

- [`hw.VlcRecorder` — Webcam Preview and Recording](#hwvlcrecorder--webcam-preview-and-recording)
  - [Contents](#contents)
  - [Requirements](#requirements)
  - [Quick start — RunExpt Video menu](#quick-start--runexpt-video-menu)
  - [Recording files](#recording-files)
  - [Integration: start recording on the first trial](#integration-start-recording-on-the-first-trial)
    - [Custom trial selector function](#custom-trial-selector-function)
  - [API reference](#api-reference)
    - [Constructor](#constructor)
    - [connect / disconnect](#connect--disconnect)
    - [set\_parameter](#set_parameter)
    - [trigger](#trigger)
    - [selectDevice](#selectdevice)
  - [Codec and quality settings](#codec-and-quality-settings)
  - [Troubleshooting](#troubleshooting)
  - [See also](#see-also)

---

## Requirements

| Software | Where EPsych looks |
|----------|--------------------|
| [VLC media player](https://www.videolan.org/vlc/) (any recent version) | `C:\Program Files (x86)\VideoLAN\VLC\vlc.exe` |
| [ffmpeg](https://ffmpeg.org/download.html) | `C:\prgms_on_path\ffmpeg.exe` |
| A DirectShow webcam (built-in laptop camera, USB camera, etc.) | Listed automatically by EPsych |

If your VLC or ffmpeg are in different locations you can change the paths in code — see [Codec and quality settings](#codec-and-quality-settings).

> **First-time VLC setup:** If VLC shows a "could not start" dialog after being installed or updated, run `vlc-cache-gen.exe` (found in the VLC install folder) as administrator once to rebuild its plugin cache. The dialog will no longer appear after that.

---

## Quick start — RunExpt Video menu

The simplest way to use `hw.VlcRecorder` is through the **RunExpt** experiment control window. No code is required.

1. Open the RunExpt window (`epsych.RunExpt()`).
2. Click **Video → Webcam Preview / Record...** (or press **Ctrl+W**).
3. A list of available cameras appears. Select your camera and click **OK**.
4. VLC opens and shows the live webcam feed immediately.
5. A file-save dialog appears. Choose where to save the recording.
   - Click **Save** to begin recording.
   - Click **Cancel** to keep the live preview without saving.
6. When done, click **Video → Stop Webcam** (or close the RunExpt window — the recording is stopped automatically).

The recording is not started until you choose a file in step 5, so the preview can be running well before you commit to a filename.

---

## Recording files

Files are saved in **MPEG-TS (`.ts`)** format by default, which is the most robust choice for interrupted recordings — the file is still readable even if the experiment crashes before a clean stop. MP4 is also available but requires a clean close to finalise the container.

Output file recommendations:
- Use an **absolute path** (e.g. `C:\data\recordings\mouse042_session3.ts`).
- Include the subject name and session date in the filename.
- The recording directory must exist before starting — EPsych does not create it automatically when triggered from code.

---

## Integration: start recording on the first trial

For automated experiments you may want recording to start automatically when the first trial begins, using the same output folder and naming convention as your behavioural data. There are two ways to do this.

### Custom trial selector function

The **trial selector function** is called before every trial. You can detect the first trial (`TrialIndex == 1`) and start recording then.

```matlab
function TRIALS = MyTrialSelectFcn(TRIALS)
% MyTrialSelectFcn  Example trial selector with first-trial webcam start.

% --- Start webcam on trial 1 ----------------------------------------
if TRIALS.TrialIndex == 1 && ~isfield(TRIALS, 'vlcRecorder')
    subject = TRIALS.Subject.Name;
    ts      = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    recFile = sprintf('C:\\data\\%s_%s_webcam.ts', subject, ts);

    rec = hw.VlcRecorder();
    rec.connect();
    rec.set_parameter('DeviceName',    'Integrated Camera');
    rec.set_parameter('MediaFile',     'dshow://');
    rec.set_parameter('RecordingFile', recFile);
    rec.trigger('Play');

    TRIALS.vlcRecorder = rec;
end

% --- Stop webcam when the session ends (last trial + 1) -------------
% (Optional — the RunExpt close handler also stops it automatically.)

% --- Your normal trial selection logic below ------------------------
% ... choose TRIALS.NextTrialID as usual ...
```

> **Note:** `TRIALS` is a struct returned by value. Any fields you add (like `TRIALS.vlcRecorder`) persist across calls because EPsych stores the returned struct in `RUNTIME.TRIALS(i)` after each call.

---

## API reference

### Constructor

```matlab
obj = hw.VlcRecorder()
```

Creates the recorder object. Does not launch VLC or ffmpeg yet — call `connect()` next.

---

### connect / disconnect

```matlab
obj.connect()
obj.disconnect()
```

`connect()` registers the parameters and triggers but does not open any processes. VLC and ffmpeg only launch when you call `trigger('Play')`.

`disconnect()` stops any running processes (same as `trigger('Stop')`) and cleans up.

---

### set_parameter

```matlab
obj.set_parameter('DeviceName',    'Integrated Camera')
obj.set_parameter('MediaFile',     'dshow://')
obj.set_parameter('RecordingFile', 'C:\data\session.ts')
```

| Parameter | What it controls |
|-----------|-----------------|
| `DeviceName` | The webcam to capture from. Must match the DirectShow device name exactly (see `selectDevice()` to pick interactively). Default: `'Integrated Camera'`. |
| `MediaFile` | The media source URI passed to VLC. Always use `'dshow://'` for webcam capture. |
| `RecordingFile` | Where ffmpeg saves the recording. Leave empty for preview-only. |

Set all three parameters before calling `trigger('Play')`.

---

### trigger

```matlab
obj.trigger('Play')        % start VLC preview and ffmpeg recording
obj.trigger('Stop')        % stop both; finalise the recording file
obj.trigger('StartRecord') % start recording if not already running (ffmpeg only)
obj.trigger('StopRecord')  % stop recording but keep VLC preview open
obj.trigger('Pause')       % no-op (not supported in this backend)
```

`trigger('Stop')` is safe to call even if nothing is running.

---

### selectDevice

```matlab
selected = obj.selectDevice()
```

Shows a dialog listing all available DirectShow video devices (queried live from ffmpeg). The selected device is stored automatically — the return value can be ignored. If the dialog is cancelled, the previously configured device name is unchanged.

This is what the RunExpt **Video** menu calls when you choose **Webcam Preview / Record...**.

---

## Codec and quality settings

Video is recorded using **H.264 (libx264)** at a constant-rate factor (CRF) of 28 with the `ultrafast` encoding preset. This gives small files with minimal CPU load, suitable for continuous real-time capture.

To change these or the tool paths, set the private properties before calling `connect()`:

```matlab
obj = hw.VlcRecorder();
obj.ffmpegExePath_ = 'D:\tools\ffmpeg.exe';   % custom ffmpeg path
obj.vlcExePath_    = 'C:\Program Files\VideoLAN\VLC\vlc.exe';
obj.crf_           = 23;        % higher quality (larger file)
obj.preset_        = 'fast';    % slower encoding, better compression
obj.connect();
```

| Setting | Default | Effect |
|---------|---------|--------|
| `crf_` | `28` | Lower = better quality, larger file. Range 0–51. |
| `preset_` | `'ultrafast'` | `fast` / `medium` improve compression at cost of CPU. |

---

## Troubleshooting

**VLC shows "could not start" dialog**
Run `vlc-cache-gen.exe` (in the VLC install folder) as administrator. This rebuilds the plugin cache after a VLC update. The dialog is cosmetic — recording still works — but rebuilding the cache eliminates it.

**No devices listed in `selectDevice()`**
Confirm that ffmpeg is installed and on the path. Run `ffmpeg -list_devices true -f dshow -i dummy` in a command prompt to see the raw device list.

**Recording file is empty or very small**
The device name must exactly match what DirectShow reports. Use `selectDevice()` rather than typing the name manually. Also ensure the output directory exists.

**VLC preview does not open**
Check that `vlcExePath_` points to a valid `vlc.exe`. Verify VLC launches manually first.

**Recording does not stop cleanly on experiment end**
Ensure your stop-timer function calls `obj.trigger('Stop')` and `obj.disconnect()`, or store the recorder on `RUNTIME` so the standard close handler can reach it.

---

## See also

- `tmp/VlcRecorder_example.m` — minimal standalone usage example
- `runtime/timerfcns/ep_TimerFcn_Start.m` — where to hook a custom start function
- `runtime/timerfcns/ep_TimerFcn_Stop.m` — where to hook a custom stop function
- `runtime/trial_selection/DefaultTrialSelectFcn.m` — template for custom trial selectors
- [hw_Interface.md](hw_Interface.md) — abstract base class all hardware interfaces share
