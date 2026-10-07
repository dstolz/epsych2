# The `behavior` package — offline behavioral analysis, class by class

The headless layer under [epsych.BehaviorAnalysis](BehaviorAnalysis_UserGuide.md). Everything the window shows is computed here, and everything here works from a script with no window at all — which is what lets the window write a script that reproduces what it shows.

```matlab
S = behavior.Study("D:\Data\Lab");            % scan the root, open its project
T = S.sessions();                              % one row per visible session
S.select(T.Key(1:6));
R = S.results();                               % behavior.Aggregate.thresholds over the checked sessions
D = behavior.Stats.describe(R, "Threshold", GroupBy = behavior.Facet("tag", Index = 1));
```

Standing proofs: `tmp/smoke_test_behavior_model.m` (Catalog, Settings, Facet, Session, Project, ScriptWriter, Export), `tmp/smoke_test_behavior_study.m` (Aggregate, Stats, Study), `tmp/smoke_test_behavior_plot.m` (Plot), `tmp/smoke_test_scriptwriter.m` (`literal` and the replication check), `tmp/smoke_test_behavior_sessionview.m` (the Session tab) and `tmp/smoke_test_behavior_app.m` (the window).

## Layering

| Layer | Where | Graphics? |
|---|---|---|
| What is on disk | `behavior.Catalog` | none |
| What a person decided | `behavior.Project` | none |
| What an analysis is | `behavior.Settings`, `behavior.Facet` | none |
| One session | `behavior.Session`, `behavior.fit.*` | none |
| Across sessions | `behavior.Aggregate`, `behavior.Stats` | none |
| App state and memo | `behavior.Study` (+ `behavior.StudyEvent`) | none |
| Pictures | `behavior.Plot` | draws into an axes it is given |
| Out | `behavior.Export`, `behavior.ScriptWriter` | none |
| The window | `epsych.BehaviorAnalysis`, `gui.behavior.*` | the shell and one view per tab |

Views never compute: they call `behavior.Study` and redraw on its events. That is the rule that keeps the Session tab's staircase, the Table tab's number and the generated script's number the same number.

## `behavior.Catalog` — what is on disk

`c = behavior.Catalog(root, CacheFolder=, ReadRecovery=)`, then `c.scan(Progress=, UseCache=)`. One row per session file under the root (`Sessions`), one per (project, subject) (`Subjects`), every `.mat` seen (`Files`), and `Warnings`.

- **Nothing is written under the root.** A scan's only file is its cache, `%LOCALAPPDATA%\EPsych\AnalysisCache\catalog_<hex8(lower(root))>.mat` (else under `tempdir`); a `CacheFolder` inside the root, or `""`, disables caching rather than break the rule. A rescan reopens only files whose bytes or modification time changed (`LastScanReads` counts them). A file whose read failed is not retried on later scans.
- **Sessions are files, keyed by path** relative to the root with `/`, in their on-disk spelling (`ProjA/SUBJ-ID-1234/SUBJ-ID-1234_261007T114223_PrePassive.mat`), compared with `behavior.Catalog.keyEquals` (case-insensitive on Windows). A key names the same session on every machine a dataset is copied to, which is what the project file, an export and a generated script rely on.
- **Subject and project come from the folder tree.** The subject is the folder a file sits in, the project the folder above that, or the root's own name when a subject folder sits directly under the root (`ProjectPath` keeps a deeper path). The file name contributes only what no file field records: its free tags.
- **Filename parsing** (`behavior.Catalog.parseName`): the subject prefix is matched lazily up to the FIRST `_yyMMddTHHmmss` (so `Rat_7_B` survives); the tokens after the stamp are `Tags`, in order, with no meaning attached — except a single capital letter in the first position, which is `epsych.RunExpt.defaultFilename`'s collision letter. Older `_dd-MMM-yyyy` names parse to the day. A name that disagrees with its folder is a QC flag (`name_mismatch`), never a refusal.
- **One load per file**: `epsych.SessionFiles.summarize(file, Extra=@(Data, info) ...)` describes the file and, during the same load, runs the catalog's `extra_` callback, which records the trial fields, the candidate parameters (`behavior.Session.candidates`), the outcome counts, the trial types, the subject's sex and species, and the protocol's parameter table (`behavior.Session.parameterTable`: field, name, unit, range).
- **File-level QC** (`QCFile`): `unreadable`, `no_trials`, `test_mode`, `name_mismatch`, `unparsed_name`, `not_in_subject_folder`.
- `applyRoster([] | path | roster)` enriches `Subjects` from `epsych.SubjectRoster` (known, sex, species, projects, last protocol, a former-name match) and never writes to it.

## `behavior.Settings` — what an analysis is

A value object holding every setting an analysis depends on, so "the settings a result was made with" is one thing that can be saved, compared, hashed and written into a script. Top-level: `Analysis` (Staircase in v1), `Parameter` ("" = the first candidate), `Window` (TrialWindow text), `ExcludeTest`, `ExcludeTrialTypes`, `IncludeAborts`, `StimulusTrialType`, `CatchTrialType`; sub-structs `Staircase` (direction, reversals, formula, weighted correction and its steps), `Fit` (engine, shape, criterion, bootstrap...), `Metrics`, `QC` (the flag thresholds), `Compare` (bootstrap CI for group means), and the reserved `Detection`/`NAFC`.

- `hash()` is `behavior.hex8` of the results-affecting settings in canonical text (`QC` and `Compare` excluded) — the memo key, the file-name fingerprint and the script's assertion.
- `toStruct`/`fromStruct` are JSON-safe and forgiving (unknown field ignored, bad value keeps the default and logs, a newer `SettingsVersion` warns). "Find it" numbers are `[]`, never NaN, because `jsonencode(NaN)` is `null`.
- `problems()` is the one validator a dialog and a script both ask; `staircaseArgs()`, `staircaseProperties()`, `metricsArgs()`, `fitArgs()` are the ONE place Settings becomes psychophysics options. The fit direction follows the staircase direction; there is no separate setting that could disagree.

## `behavior.Facet` — how sessions are grouped

An immutable descriptor: `Kind` (project, projectpath, subject, tag, tags, sex, species, paradigm, protocolversion, box, date, week, month, year, session, manual, none), `Index` (a tag position), `Name` (a grouping). `values(T)` gives one level per row of a sessions or results table ("(none)" where there is none), `order(T)` the display order, `toText`/`fromText` the `"tag:1"` / `"manual:Treatment"` spelling the project file and the script use, `available(T, groupingNames)` what a dropdown offers.

- **Tag levels are ordered by the phase they name**: each level by its earliest session, so Pre precedes Post whatever the alphabet says. Numbers numerically, dates chronologically, the rest naturally, "(none)" last.
- `week` is the ISO week (`2026-W53`); `session` is each subject's ordinal by Start across projects.

## `behavior.Session` — one session, loaded

`sess = behavior.Session.load(fileOrRow, Root=)` (a catalog row brings its identity, tags and parameter table; a bare path parses the name itself), then:

- `[excl, info] = behavior.Session.exclusionMask(Data, Window=, ExcludeTest=, ExcludeTrialTypes=)` — THE ONE RULE for which trials are in: outside the window, test trials, excluded trial types. The window, the analysis and the generated script all call it.
- `S = sess.staircase(settings, Window=)` — the configured `psychophysics.Staircase`, labelled from the session (`Subject`, `Unit`), excluded trials passed as `ExcludedTrials`.
- `F = sess.fit(S, settings)` — the common fit struct (`Engine, Shape, Threshold, Alpha, Beta, Gamma, Lambda, Levels, NumYes, NumTotal, Proportion, Curve, CI, Converged, Identifiable, Message, Raw`) from `behavior.fit.Builtin` over `Staircase.fitPsychometric`; `behavior.fit.Psignifit` is the v2 seam (`Fit.Engine="psignifit"`, `[Levels NumYes NumTotal]` is psignifit's data matrix) and reports itself unavailable until wired.
- `R = sess.analyze(settings, Window=)` — the whole v1 analysis as one plain struct (identity, parameter and unit, window, counts, reversal threshold and spread, sliding-block thresholds, weighted threshold, the `Track` the overlay plot draws, `Metrics` from `psychophysics.SessionMetrics`, the fit, QC flags, messages). **It never throws for a bad session**: a missing parameter, an empty window or an unidentifiable fit leaves NaN and a message, and the stages after it still run.
- QC flags (`qc_`): the file's, plus `low_trials`, `high_abort_rate`, `few_reversals`, `no_parameter`, `fit_failed`; `parameter_differs` is added by `behavior.Study.results`, which alone can see the root's modal parameter.

## `behavior.Project` — what a person decided

`P = behavior.Project.open(root, Store=)`: hidden sessions and why, per-session trial windows, comments, the settings, presets, the compare view's facets, named groupings (a level per subject, per-session overrides), and the checked selection — in ONE file, `<root>/EPsych_Analysis/project.json`, or `<Store>/project.json` for a root that cannot be written.

- **Opening writes nothing**; the store appears at the first `save()`. An unreadable file or a newer `FormatVersion` opens read-only (edits allowed, save refused).
- **Saving merges**: the file is re-read when it changed since it was loaded and merged record by record (sessions by key, subjects by name, presets and groupings by name; later `Modified` wins; a record only one side has is kept — except that a record present at the last read and untouched since is a REMOVAL, so an un-hidden session or a deleted preset does not come back from another writer's copy). The write is atomic; the previous file goes to `.history/` (newest three kept).
- **Encoding**: every datetime is ISO text to the millisecond, windows are TrialWindow text, "find it" numbers `[]`, records are arrays of objects (never objects keyed by path), no NaN/Inf/null anywhere. Times are local without a zone: two writers in different zones would mis-order edits.
- `applyGroupings(T)` puts `Group_<Name>`, `Hidden`, `Window`, `Comment` onto a sessions table — what `behavior.Study.sessions` and the `manual` facet read.

## `behavior.Study` — app state, headless

The window's model: `Catalog` + `Project` + the `Settings` (the project's), with memoized results and events (`CatalogChanged`, `ProjectChanged`, `SettingsChanged`, `SelectionChanged`, `ResultsChanged`, `Busy`).

- `result(key)` is memoized on **key | bytes | modification time || settings hash | window**: a repaint costs nothing, a settings change one analysis per session, a rescan that finds a file changed that file alone. `results(keys)` returns `behavior.Aggregate.thresholds` over them with `parameter_differs` flagged.
- `session(key)` keeps the last eight loaded sessions (LRU).
- Every decision goes through the Study (`select`, `setSettings`, `setWindow`, `hide`, `setComment`, groupings, `setFacets`, `save`), which forwards to the Project and raises the event the views redraw on. It never opens a window and never touches a preference.

## `behavior.Aggregate` and `behavior.Stats` — across sessions

`T = behavior.Aggregate.thresholds(results, sessions)`: one row per result, joined on key with the sessions table so every column a facet reads rides along (project, subject, tags, sex, paradigm, groupings, hidden, comment, notes), plus `Tag1..TagN`, `Date`, `SessionOrdinal` and `DaysSinceFirst` per subject, and every scalar the analysis produced (`valueColumns()` lists the ones a plot can be asked for). `bySubject(T, value, GroupBy=)` collapses a subject's sessions per level.

`D = behavior.Stats.describe(T, value, GroupBy=, Unit="session"|"subject", BootstrapCI=, ConfidenceLevel=, NumBoot=, Seed=)`: n, mean, SD, SEM, median, quartiles, min, max and — when asked and n ≥ 5 — a `bootci` interval on the mean, seeded with the global stream restored afterwards. **Descriptive only, by decision**: no test statistic exists in this package, so a p-value cannot appear by accident; inferential statistics are a later milestone with a class of their own.

## `behavior.Plot` — pictures over plain data

Static drawing into an axes the caller supplies (a `uiaxes` or a classic `axes`): `thresholdTimeline`, `metricTimeline`, `groupComparison` (box · bar · strip, points, per-subject medians, SEM or bootstrap CI), `subjectLines` (the paired-design picture), `staircaseOverlay` (one line per result through its `Track`), `psychometric`, `reversalHistogram`. Every object is tagged `BehaviorPlot:<Role>`; an empty input draws "No data" and never errors; NaN is skipped, never drawn as zero; a facet level keeps its colour across calls (`colorsFor`); the palette is a colour-blind-safe set that stays clear of the `epsych.BitMask` outcome hues; jitter is a fixed sequence so the global random stream is never touched.

## `behavior.Export` — tidy tables

`Tbls = behavior.Export.tables(T, results, Tables=, Subjects=)` builds `sessions`, `subjects`, `thresholds`, `fits`, `metrics`, `reversals` and `notes` FROM `schema()`, the single source of truth for every column's name (snake_case), type, unit and meaning; `write(Tbls, folder, Formats=["csv" "xlsx" "mat"], Prefix=)` writes them with a column dictionary beside them. CSV is UTF-8, logicals TRUE/FALSE, datetimes ISO, a NaN an empty field, **and Inf is never written**. `toTSV`/`copyTable` serve the Table tab's clipboard.

## `behavior.ScriptWriter` — a script that reproduces the analysis

`[code, info] = behavior.ScriptWriter.session(study, key, ...)` / `compare(study, keys, ...)`, `write(file, code)`. The script, in `%%` sections: a header; setup with `EPSYCHROOT`, `ROOT` and `OUTFOLDER` assigned only when undefined; `behavior.Settings(...)` with EVERY property written out and `assert(cfg.hash() == "...")` so a later default change cannot silently change the analysis; per session `behavior.Session.load(fullfile(ROOT, key)).analyze(cfg, Window=...)` — the same path the window takes — and `compareWithRecorded` against the values recorded at generation; the tables, the figures (`Staircase.Plot`, `behavior.Plot.*`), the export. It opens no window unless figures are asked for, reads or writes no preference, and touches no project file.

- `literal(v)` is exact: `eval(literal(v))` is `isequaln` to `v`, same class, same size, for double/single/integers/logical/char/string/cell/struct/datetime (to the last bit, zone and format kept)/duration/categorical/enumeration/table; a handle or an object throws rather than becoming something else.
- `checkFunction()` is the never-throwing `compareWithRecorded` every script ends with: "replicated exactly", or rounding counted, or every difference listed.

## `gui.behavior.View` and the tabs

A tab is a `gui.behavior.View`: it builds its graphics under the container the window gives it, reads everything from the Study, changes nothing but through the Study's methods, and redraws on the Study's events (`refresh(reason)`). `gui.behavior.SessionView` hosts the session's own `psychophysics.Staircase` in a grid cell of its own (the distribution toggle re-parents that cell), rebuilds it only when its signature (key | settings hash | window) changes, and writes a right-click change of the three analysis settings into `Study.setSettings` so every other tab follows — an offline staircase never restores remembered menu choices over the caller's settings (`psychophysics.Staircase`, 2026-10-07), so the Settings always win on a fresh show.

## Adding to the package

- A new value column: compute it in `behavior.Session.analyze`, carry it in `Aggregate.numbersFromResults_`, name it in `Aggregate.valueColumns`, and it is plottable, describable and exportable; add its `schema()` row to `Export`.
- A new facet kind: one `case` in `Facet.values` (and `order` if it is not natural order), one entry in `available`.
- A new analysis (Detection, NAFC): `Settings.Analysis`, a `Session.<analysis>` builder, and the result fields the rest reads; `Settings.Detection`/`NAFC` are reserved for their options.
- psignifit: `behavior.fit.Psignifit.fromCounts` with `Settings.Fit.Engine = "psignifit"`; the common fit struct needs no change.
