# util.VideoConverter

`util.VideoConverter` batch-converts video files with ffmpeg: recursively scan a folder with a regular expression, then convert every match with true per-file progress, optional parallelism, and instant cancellation. `gui.VideoConverterSetup` is a simple GUI wrapper.

It exists to turn `hw.VlcRecorder` captures (`.avi`/`.ts` — VLC's mp4 muxer is broken for dshow capture, see [hw.VlcRecorder](../hw/hw_VlcRecorder.md)) into shareable, playable files, but it is a general-purpose batch transcoder, not tied to VLC.

## What problem it solves

MATLAB's [FFmpeg Toolbox](https://www.mathworks.com/matlabcentral/fileexchange/42296-ffmpeg-toolbox) (Takeshi Ikuma) already provides `ffmpegtranscode`, and this class deliberately keeps its option vocabulary (`VideoCodec`, `x264Crf`, `AudioCodec`, `Range`, …). The problem is how `ffmpegtranscode` *runs*: it shells out via a single blocking `system()` call, so MATLAB's main thread — and with it the toolbox's own `Period=1` progress timer — is frozen for the entire encode. Its intra-file progress is effectively vestigial, and its default progress display is a modal waitbar per file.

`util.VideoConverter` launches `ffmpeg.exe` itself as a tracked `System.Diagnostics.Process` (the same pattern `hw.VlcRecorder` uses for VLC), redirecting and asynchronously draining both stdio streams so the process can never deadlock on a full pipe. That gets:

- **True per-file progress** — tailing ffmpeg's own `-progress` output, not a timer that can't fire.
- **Instant cancellation** — `proc.Kill()` on the actual ffmpeg process, not a wrapper shell.
- **N-way parallelism** — `MaxParallel` concurrent ffmpeg processes; each is a separate OS process, so no Parallel Computing Toolbox is required.
- **A responsive GUI** — the scheduler is timer-driven, so `gui.VideoConverterSetup` never freezes mid-batch.

## Key concepts

### Commit-by-rename (the core safety mechanism)

Every job encodes to an extension-preserving sidecar next to the planned output — `rec_conv.mp4` becomes `rec_conv.part7f3a91.mp4` during the encode — and is renamed onto the final path only after ffmpeg exits 0 **and** the sidecar is non-empty. Extension preservation matters: ffmpeg infers the output muxer from the extension, so a bare `.part` suffix would break format detection.

This single mechanism is what makes several other behaviors safe:

- **Converting in place** (`OutputFolder=""`, matching container) is safe even when source and destination end up being the same path: ffmpeg never writes directly over the source.
- **A killed or crashed job never leaves a truncated file at the final path** — cancellation and forced-failure both delete the sidecar, never the (nonexistent) final output.
- **`DeleteSource` only fires after the rename succeeds**, and only when `VerifyBeforeDelete` (default `true`) confirms the output's duration is plausible. A forced failure — bad codec option, disk full, whatever — always leaves the source untouched, even with `DeleteSource=true`.
- **Overwrite policy is checked twice**: once at `scan()` (so the preview table already shows `skipped` before you press Convert) and again immediately before the rename (a long encode is plenty of time for the destination to appear from elsewhere).

### Self-collision on rescan

If a source file's own planned output path would equal itself (or already looks like a previous output — `ExcludePattern` defaults to catching `_conv` / `.part*` suffixes), `scan()` excludes it before it ever becomes a row in `Results`. This is stronger than a runtime guard: the file is never queued, so it can never be touched, let alone clobbered.

### Progress contract

`ProgressFcn` (or the `Progress` event) is called as `fcn(src, evt)` with a plain, well-behaved contract — not the toolbox's `fcn(timerSrc, evt, progfile, N)` plus a `'delete'` sentinel string. `evt` is a `util.ProgressEventData` with `Stage`, `JobIndex`, `Percent`, `OverallPercent`, `Fps`, `Speed`, `ElapsedSeconds`, `EtaSeconds`, etc. `Percent` is `NaN` (not `0`) when a file's duration can't be determined, so a GUI can honestly show "—" instead of a lying progress bar. The default is a no-op — nothing is ever shown unless you ask.

### Toolbox bugs this class deliberately does not reproduce

`ffmpegtranscode` is still used as this class's dependency-bootstrap and duration-probe fallback (via `ffmpeginfo`), and as a cross-check oracle in the smoke test. Three bugs were found reading its source and are worth knowing if you use the toolbox directly:

1. `AudioSampleRate` throws (`addOutputParameters` registers `OutputSampleRate`; `set_outopts` cases on `AudioSampleRate`; they never meet).
2. `FastSearch='on'` combined with `Range(1)>0` seeks twice (an always-true `isfield` check in `set_outopts`), producing a near-empty output.
3. `VideoCrop` is wired to a filter that expects a different coordinate convention than the one documented.

`util.VideoConverter`'s own `buildArgs` avoids all three: `Range`/`FastSearch` emit `-ss` on exactly one side, and `VideoCrop` is `[left top right bottom]`, authoritatively.

### Duration probing is lazy and toolbox-independent

A file's duration is probed only at launch (not at `scan()` — probing 500 files up front would block MATLAB for minutes), and cascades `ffprobe` → `ffmpeginfo` (if the FFmpeg Toolbox happens to be on the path) → parsing `ffmpeg -i`'s stderr. The class works fully even if the Toolbox Add-On is entirely absent.

## Requirements and dependencies

- `ffmpeg.exe` reachable via the `FfmpegExe` property, the `ffmpeg`/`exepath` preference (`ffmpegsetup` from the FFmpeg Toolbox sets this), a standard install path, or the system `PATH`. `ensureDependencies`/`findFfmpegExe` degrade gracefully (return `ok=false`/`""`) rather than throwing when it can't be found — mirroring `hw.VlcRecorder.findVlcExe()`.
- `ffprobe.exe` alongside `ffmpeg.exe`, if present, is used for fast duration probing (optional — the class still works without it).
- The FFmpeg Toolbox Add-On is optional; when present it is used only for the duration-probe fallback and as the smoke test's cross-check oracle, never for execution.
- `uifigure`/`uigridlayout`/`uitable` for `gui.VideoConverterSetup`.

## Constructor

```matlab
c = util.VideoConverter(Name=Value, ...)
```

Any public property may be set as a name-value pair (via `options.?util.VideoConverter` in the constructor's `arguments` block), including every `ffmpegtranscode`-vocabulary option (`VideoCodec`, `x264Crf`, `x264Preset`, `AudioCodec`, `AacBitRate`, `Range`, `Units`, `VideoScale`, `VideoCrop`, `VideoFlip`, …), discovery options (`RootFolder`, `FilePattern`, `ExcludePattern`, `Recursive`), output naming (`OutputFolder`, `MirrorTree`, `OutputExtension`, `NamePrefix`, `NameSuffix`, `NameReplace`), safety (`Overwrite`, `DeleteSource`, `VerifyBeforeDelete`, `DryRun`), and engine tuning (`MaxParallel`, `PollPeriod`, `ProgressFcn`).

## Usage examples

### Example 1: Basic batch conversion

```matlab
c = util.VideoConverter(RootFolder="D:\data", MaxParallel=2);
files = c.scan();           % populates c.Results; string.empty(0,1) if none found
c.convert();                % asynchronous -- returns immediately
c.waitUntilDone();          % block in a script; or use ProgressFcn/Progress instead
disp(c.Results(:,{'SourceFile','OutputFile','Status'}))
```

### Example 2: Custom filter, output folder, and progress callback

```matlab
c = util.VideoConverter( ...
    RootFolder = "D:\data", ...
    FilePattern = "(?i)\.(avi|ts)$", ...
    OutputFolder = "D:\converted", MirrorTree = true, ...
    x264Crf = 20, x264Preset = "slow", ...
    ProgressFcn = @(src,evt) fprintf('%s: %.0f%%\n', evt.SourceFile, evt.Percent));
c.scan();
c.convert();
c.waitUntilDone();
```

### Example 3: Preview before committing (DryRun)

```matlab
c = util.VideoConverter(RootFolder="D:\data", DryRun=true);
c.scan();
c.convert();
c.waitUntilDone();
disp(c.Results.Args)   % exact ffmpeg command lines that WOULD have run; nothing touched disk
```

### Example 4: GUI

```matlab
c = util.VideoConverter();
g = c.setupGUI();       % opens gui.VideoConverterSetup
```

## `Results` table

One row per scanned file: `Index`, `Selected`, `SourceFile`, `OutputFile`, `Status` (`pending|running|done|failed|skipped|cancelled|dryrun`), `Percent`, `DurationSec`, `ElapsedSec`, `Fps`, `Speed`, `BytesIn`, `BytesOut`, `ExitCode`, `Message`, `Args` (the exact ffmpeg command line — the first thing to check when a job fails), `StartTime`, `EndTime`.

### Selecting which files convert

`scan()` is a *proposal*: every row it finds comes back `Selected`. Narrowing it is `select`:

```matlab
c.scan();
c.select(3, false);                     % leave file 3 out
c.select([1 2 5], true);                % ...or name the ones to keep
c.select(c.Results.BytesIn > 1e9);      % logical mask, one element per row
c.convert();                            % converts the selected 'pending' rows
```

A deselected row is not part of the batch **at all**: it is never queued, and it is left out of the progress accounting rather than sitting at 0% and holding `OverallPercent` down forever. It keeps `Status = 'pending'` when the batch ends, which is the honest record that nothing was decided about it — re-select it and convert again. Selection is per scan (a new `scan()` selects everything again) and cannot be changed while a batch runs, since the queue is built once at `convert()`.

## GUI: gui.VideoConverterSetup

```matlab
g = gui.VideoConverterSetup(Converter)
g = gui.VideoConverterSetup(Converter, Name=Value, ...)
```

Name–value options: `Parent` (embed instead of owning a figure), `WindowStyle`, `PersistPrefs` (remembers the window position and the settings, in `getpref` group `'ep_VideoConverter'`).

A file table (Do / Source / Output / Duration / Size / Status / %) sits beside Source, Encoding (with five presets plus Custom), Output, and Run panels, and Scan / Convert / Cancel / Reset buttons with an overall-progress label. Every form label and its control carry the same tooltip explaining what the setting does. The GUI edits the passed-in `Converter`'s properties directly and listens to its `Progress` event — it never polls, and it does not own the `Converter`'s lifetime (closing the GUI never cancels or deletes it).

### Choosing files, and opening them

The **Do** column is a tick per row, written through `Converter.select`, and it is the only editable cell in the table. It is disabled while a batch runs, because the queue is built once at `convert()` and a tick changed mid-run would be a lie. Right-clicking the table gives **Open Video**, **Open Converted Video**, and **Open Containing Folder** — each hands one file to the operating system exactly as a double-click would, and each needs *exactly one* highlighted row, so a careless right-click over 200 highlighted rows cannot open 200 windows. The same menu ticks and unticks whole blocks: **Convert / Skip Selected Rows** for the highlighted ones, **Convert All / None** for the lot.

### Reset, and what is remembered

**Reset** puts every setting back to the default `util.VideoConverter` itself declares — read from the class through its metaclass, so this GUI cannot drift from the class it configures. The root and output folders are deliberately left alone: they are where this batch reads and writes, not settings with a recommended value.

With `PersistPrefs` (the default), the settings an operator changes are saved as they change and come back next session — including the folders, which is the point. Two things are never remembered: **Delete source after conversion** and **Dry run**, which are decisions about the batch in front of the operator. And a remembered value is applied only where the caller left the property at its class default, so `gui.VideoConverterSetup(util.VideoConverter(MaxParallel=4))` still gets 4.

Each side panel's height is computed from the rows it declares, and an owned window grows on open until the whole panel stack fits (up to the screen height), so a `Position` saved under an earlier layout cannot leave controls out of view. Only a screen too short for the stack falls back to scrolling the side column. In the file table the two path columns share the leftover width and the four short columns are fixed, so nothing needs a horizontal scroll.

### From the session window

`epsych.RunExpt` opens the same GUI from **Utilities → Video → Batch Video Converter...**, on a converter seeded for the recorder's output: `RootFolder` is the session's **Video Recording Path** — the project's, else this machine's (falling back to the Data Save Path, and left unset when neither folder exists) and `FilePattern` is `(?i)\.ts$`, the extension `hw.VlcRecorder` writes. Both are editable in the window, and the item stays enabled while a session runs — the converter only reads and writes files, though an encode does compete with the session for CPU.

## Verification

`tmp/smoke_test_videoconverter.m` — generates its own synthetic fixtures via ffmpeg's `lavfi testsrc`/`sine` sources (no external test files needed) and covers dependency bootstrap, the `buildArgs` argument mapping, recursive scanning, `DryRun`, genuine mid-file progress (the core premise of this class), parallel execution, cancellation, the overwrite/rescan policy, `DeleteSource` gating, an optional cross-check against `ffmpegtranscode`, and the GUI — including that every form label carries a tooltip, that Reset restores the class defaults without clearing the folders, that settings are remembered without overriding a value the caller asked for, and that a deselected file stays out of both the batch and the progress accounting. Run headlessly:

```
matlab -batch "addpath('C:\src\epsych2'); epsych_startup; r=smoke_test_videoconverter(); exit(double(~r.allPassed))"
```

## See also

`hw.VlcRecorder` (the `System.Diagnostics.Process` child-process pattern this class follows), `gui.VlcRecorderSetup` (the GUI idiom this class follows), `documentation/hw/hw_VlcRecorder.md`.
