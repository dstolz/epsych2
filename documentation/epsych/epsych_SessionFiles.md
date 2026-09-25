# `epsych.SessionFiles`

Find a subject's saved sessions on disk and describe each in one row. The
headless half of [`gui.SessionBrowser`](../gui/gui_SessionBrowser.md): no
figures and no runtime, so it runs in a script or a test.

```matlab
L = epsych.SessionFiles.locations("M001", Roster = epsych.SubjectRoster);
T = epsych.SessionFiles.scan(L.Names, Roots = L.Roots, VideoRoots = L.VideoRoots);
T(T.Trials > 0, {'StartTime','Duration','Trials','FileName'})

s = epsych.SessionFiles.summarize("D:\data\M001\M001_260925T090520.mat");
```

Static only; not constructible.

| Method | Does |
|---|---|
| `locations(name, Roster=, RunExpt=)` | Every root the subject's data can be under, its former names, and the crash-recovery folder |
| `scan(names, Roots=, VideoRoots=, IncludeRecovery=, RecoveryDir=, Progress=, UseCache=)` | A table, one row per session file, newest first, plus a report of what was searched and what was missing |
| `summarize(file, UseCache=)` | One file, one row (a scalar struct) |
| `blank()` | A row with every field unknown: the field set |
| `clearCache()` | Forget cached summaries |

## What a row says

`File`, `Folder`, `FileName`, `Source` (`Saved` or `Recovery`), `IsSession`,
`IsTest`, `StartTime`, `EndTime`, `Duration`, `Trials`, `BoxID`, `Paradigm`,
`ProtocolVersion`, `HasSnapshot` (the file carries its protocol, so a review
rebuilds the paradigm's controls), `VideoFile`, `NotesText`, `NumNotes`,
`EPsychVersion`, `Bytes`, `Modified`, `Error`.

`summarize` never throws for a file that exists. A damaged file comes back with
`Error` set and `IsSession` true — "this session's file is broken" is what
someone browsing it needs to see, not a row that silently vanished.

## Things a reader would otherwise re-derive

- **What counts as a session** is decided from `whos` alone: a struct named
  `Data` (saved), or a scalar struct named `info` (a recovery seed). Anything
  else in a subject's folder — an analysis file, an export — is skipped and
  counted (`report.NumSkipped`), never loaded.
- **Only what the summary needs is loaded.** A saved file loads `Data` and
  `Info`; a recovery seed loads `info` plus its first and last `data_NNNN`, the
  count coming from `whos`. `load` warnings (a class changed since the file was
  saved) are held back and logged at debug level, or one subject's scan would
  fill the command window.
- **Three file-name generations.** `<name>_260925T090520` (to the second),
  `RUNTIME_DATA_…_2609250905xx` (read to the minute — seeds written before
  2026-09-25 carry hundredths in the last two digits, from an `SS` in
  `ep_TimerFcn_Start`'s format since corrected to `ss`, and a name cannot say
  which it is), and `<name>_25-Sep-2025` (a date only).
- **StartTime** is the snapshot's session start where there is one (files
  saved since 2026-08), else the time in the name, else the first trial's
  completion. The oldest files' durations are therefore short by one trial.
- **A zero-trial file is a real row.** Older saving functions wrote one
  all-empty `Data` record for a session that completed nothing; that counts as
  zero trials, not one.
- **An unmerged recovery seed** — MATLAB killed mid-session — has its trials
  only in the `.epj` beside it. `scan` then describes the journal instead,
  which is also the file `epsych.ReviewSession` has to open.
- **Recovery copies are matched by the whole name**: `RUNTIME_DATA_M1_Box_`
  never finds `M10`'s.
- **Roots are deduplicated** after trimming a trailing separator and, on
  Windows, ignoring case — `D:\Data\` and `d:\data` are one root, not one root
  scanned twice.
- **Recordings** are matched the way `epsych.RunExpt.videoRecordingFilename`
  names them: `<videoRoot>/<subjectFolder>/<dataFileName>.ts`, or a suffixed
  conversion such as `_conv.mp4`. Every data root is searched for video too,
  since an empty recording root falls back to the data path.
- **Summaries are cached** per file on size and modification time, so a
  rescan after a session re-reads one file. A file overwritten in place is read
  again.
- **`locations` writes no preferences.** It reads behind `ispref`, because
  `getpref(group, pref, default)` *creates* a missing preference — an empty
  `RunExpt/DataPath` planted that way would replace RunExpt's fallback to `cd`.

Standing proof: `tmp/smoke_test_session_browser.m`.
