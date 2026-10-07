# The Behavior Analysis Window

`epsych.BehaviorAnalysis` is the window for everything that happens to saved behavior sessions after they are recorded. You open a data root, choose the sessions to analyse, look at each staircase and its numbers, follow a subject over time, compare groups of sessions, and export the tables another program needs. It needs no hardware and no running session.

It is a window over the [`behavior.*` classes](behavior_Classes.md). Everything it shows can also be computed from a script, and **File ▸ Generate Script** writes that script for you.

```text
1 Open a root · 2 Check sessions · 3 Session · 4 Subject · 5 Compare · 6 Table · 7 Export
```

Version 1 analyses **staircases**: `psychophysics.Staircase` and `psychophysics.SessionMetrics` on every session, with a psychometric fit. Detection and N-AFC analyses are planned. They are listed in the Analysis dropdown, marked "v2", and cannot be chosen yet.

## Starting it

```matlab
>> epsych.BehaviorAnalysis                         % reopen the last root
>> epsych.BehaviorAnalysis("D:\Data\Lab")          % open this data root
```

Only one analysis window exists at a time. A second call brings the open window forward, and opens the root in it if you name a different one. It never replaces the window, because the window may hold decisions you have not saved. `epsych.BehaviorAnalysis.find()` returns the open window.

**Not during a session.** Scanning a root reads every file on the MATLAB thread that runs the trial loop. While `epsych.RunExpt` is running, the window refuses to scan:

> A session is running. The root can be scanned once it has stopped; Review Session... is still available.

**Review Session…** stays available, because it opens one file you chose.

## Opening a root

**File ▸ Open Root… (Ctrl+O)** opens a data root. You can also use the header's **Open Root…** button or **File ▸ Recent Roots** (the last ten). A root is laid out the way EPsych saves sessions:

```text
<root>\<Project>\<Subject>\<Subject>_<yyMMddTHHmmss>[_tag...].mat
```

- The **subject** is the folder a session file sits in.
- The **project** is the folder above it. When the subject folder sits directly under the root, the project is the root's own name.
- The roster, when one is configured, only adds facts about each subject (sex, species, projects, last protocol). It never decides which subject a file belongs to, and it is never written.

### What is written where

**Opening a root writes nothing into it.** A data root is often a shared or synced drive, and looking at it must not change it.

- The **scan cache** goes to `%LOCALAPPDATA%\EPsych\AnalysisCache\catalog_<8 hex digits>.mat`, never beside the data. A rescan (**F5**) reopens only the files whose size or date changed.
- Your decisions are kept in the **project file**, `<root>\EPsych_Analysis\project.json`. The folder and the file appear at the first **Save Project (Ctrl+S)**. Nothing else is ever written under the root.
- The project file keeps its three previous versions in `EPsych_Analysis\.history`.

**A root you cannot write to.** When the project file cannot be saved, a yellow bar appears under the header with **Choose store folder…**. The folder you choose holds this root's `project.json` from then on, and is remembered for this root on this computer. Choosing it reopens the root, so make the choice before you edit. Unsaved edits are not carried to the new folder.

The same bar says when the project file is **read-only**: it could not be read, or a newer EPsych wrote it. The window never writes such a file back.

## The window

- **Header**, two lines:
  - the root (hover over it to see where the project file and the scan cache are), **Open Root…**, the counts ("n sessions · m subjects · k hidden · r test · c checked"), and the save state: **New**, **Saved**, **Unsaved** or **Read-only**;
  - the analysis settings you change most: **Preset**, **Analysis**, **Parameter**, **Window**, **Exclude test trials** and **Exclude trial types**.
- **Notification bar**: a store that cannot be written, and the number of warnings from the scan and the project file. **Warnings** lists them; **Dismiss** hides the bar until something else needs saying.
- **Browser** on the left (**Ctrl+B** hides it).
- **Four tabs**: Session, Subject, Compare, Table (**Ctrl+1** to **Ctrl+4**).
- **Status line** along the bottom. What the window just did, and what the Study is busy with.

The title bar shows the root's name, with a `*` while there are unsaved changes.

**Toolbar**, left to right. Each button's tooltip names its shortcut.

| Pictogram | Does |
|---|---|
| folder with a magnifier · circling arrow · floppy disk | Open a root (Ctrl+O) · Rescan (F5) · Save the project file (Ctrl+S) |
| gear · page of code · table with an arrow · axes with a line | Analysis settings · Generate a script for the checked sessions (Ctrl+G) · Export tables (Ctrl+E) · Export the figure on this tab (Ctrl+Shift+F) |
| three staircases · page played back · person and list · struck-through eye | Overlay the checked staircases (Compare tab) · Review the shown session (Ctrl+R) · The Subject tab (Ctrl+2) · Hide or unhide the shown session (Del) |

## Browser

A checkbox tree: **Project ▸ Subject ▸ Session**. A session reads

```text
2026-10-07 11:42 · Pre Passive · 182 trials  [20+]  *
```

That is when it started, its filename tags, and its trial count. `[20+]` means the session has its own trial window. `*` means it has a comment.

- **Checked** sessions are the **analysed set**. The Subject, Compare and Table tabs, the exports and the generated script all use them. Checking a subject or a project checks every session listed under it. The checked set is saved in the project file.
- **Selecting** a session shows it on the Session tab and its subject on the Subject tab. **Enter** or a double-click also brings the Session tab forward.
- **Colours**: grey is hidden, unreadable or empty (no trials). Amber is a file-level QC flag, such as a name that does not match its folder. Italic is a session run in test mode.

**Find (Ctrl+F)** filters the list as you type. Several words must all match the project, subject, tags or file name.

**Show** narrows the list:

- **All** lists every session that is not hidden.
- **Checked** lists only the analysed ones.
- **Hidden** lists only the hidden ones.
- **Test** lists sessions run in test mode.
- **Needs attention** lists sessions with a file-level QC flag, an error, or no trials.

Filtering never unchecks anything. Checking or unchecking in a filtered list changes only the sessions it lists.

The pane under the tree describes the selected node:

- for a session: the file, when it ran and for how long, the box and paradigm, the subject's sex and species (and the roster's), the tags, the QC flags, the trial window in force, the comment and the operator's notes;
- for a subject: how many sessions and when, the roster's facts, its comment, and its level in every grouping.

**Right-click** a node for:

- Open
- Review Session…
- Hide / Unhide
- Trial Window Override…
- Comment…
- Assign to grouping ▸
- Check subtree / Uncheck subtree
- Copy Path
- Show in Folder

## Filename tags

EPsych names a session `<Subject>_<yyMMddTHHmmss>`. Anything after that, split at `_`, is a **tag**: `SUBJ-ID-1234_261007T114223_Pre_Passive` has the tags `Pre` and `Passive`. Tags carry no meaning to EPsych. They are labels you added when you saved, and the window uses them as they are.

- A subject name may contain underscores (`Rat_7_B_261007T114223_Post`). The first time stamp in the name ends the subject.
- A single capital letter right after the stamp (`_A`) is the letter EPsych adds when two files would have the same name. It is not a tag.
- Tags are numbered by position. **Tag 1** is the first tag of every session, **Tag 2** the second, and so on. A session with no tag in a position is in the group "(none)".
- A file whose name does not start with its folder's subject is flagged `name_mismatch` but still analysed under its folder's subject.

## Trial windows

Which trials of a session are analysed is a **trial window**:

| Text | Trials |
|---|---|
| `all` | every trial |
| `last 100` | the last 100 |
| `first 50` | the first 50 |
| `3-83` | trials 3 to 83 |
| `20+` | trial 20 to the end |

The header's **Window** applies to every session. A single session can have its own: **Session ▸ Trial Window Override… (Ctrl+W)**, the Session tab's **Trial window** field, or the browser's right-click menu. Clear the override to go back to the settings' window. Text that is not a trial window is refused, and the field shows what it was before.

The other exclusions apply to every session:

- **Exclude test trials** leaves out trials run in Preview.
- **Exclude trial types** leaves out the listed `TrialType` values, for example `2` for reminder trials.

One rule decides which trials are excluded (`behavior.Session.exclusionMask`). The window, the exports and the generated script all call it.

## Hidden sessions and comments

**Hide (Del)** takes a session out of every list, count, analysis and export without touching its file. Hide a pilot session, a session where the equipment failed, or a session saved twice. **Show ▸ Hidden** lists the hidden sessions, and **Hide / Unhide** brings one back. A hidden session that is still checked is left out of the analysis until it is shown again.

**Comment… (Ctrl+N)** attaches a note to a session (or, from a subject node, to the subject). Comments are kept in the project file and exported in the `sessions` table.

## Session

The selected session:

- its **staircase**, drawn by `psychophysics.Staircase` itself, titled with the subject;
- the **trial window** in force, editable here as this session's override;
- the **numbers**: the reversal threshold ± SD over the reversals used, the sliding-block thresholds, the weighted threshold when the weighted correction is on, the fitted threshold with its CI, d′, A′, criterion, and the hit, false-alarm and abort rates;
- the session metrics table and the **psychometric fit**;
- **QC flags**, the operator's **notes**, and **Copy Values** and **Review Session…** buttons.

**The staircase's right-click menu is another way to edit the settings.** Changing **Threshold from last N reversals**, the threshold formula or the weighted correction there changes the analysis settings for every session, and every tab follows. A remembered right-click choice from the live experiment GUI never overrides the settings here.

## Subject

The subject of the selected node:

- its reversal threshold per session over time, with the fitted threshold beside it;
- a **learning curve** of any value (d′, abort rate, trials, …), chosen above it;
- **every staircase** of the subject overlaid;
- a table of its sessions. Double-click a row to open it on the Session tab.

It shows the subject's checked sessions. When none of them is checked, it shows all of its visible sessions.

## Compare

The checked sessions, one value each, grouped:

- **Group by** puts sessions into groups along x.
- **Color by** colours the points.
- **X axis** sets the levels along x for **Subject lines**.
- **Value** is the number compared: reversal threshold, fitted threshold, weighted threshold, d′, A′, the rates, reversals, trials, and more.
- **Plot**:
  - **Box**, **Bar (mean)** and **Strip** plot one value per session in each group. Each subject's median is marked as a larger diamond.
  - **Subject lines** draws one line per subject through its median at each level. Use it for paired designs such as Pre and Post.
  - **Staircase overlay** draws every checked session's staircase on one axes.
- **Bootstrap CI** adds a percentile bootstrap confidence interval on each group's mean.

### Groups and facets

A **facet** is any property that puts a session in a group. The facets are:

- the project and the project path, the subject, Tag 1, Tag 2, … and all tags together;
- sex and species, paradigm, protocol version and box;
- the date, the ISO week, the month and the year;
- the session's number within its subject (1, 2, …).

**Groupings** are named facets you define: **Groups ▸ Manage Groupings… (Ctrl+M)**.

- Give the grouping a name (Treatment) and its levels (Control, Noise).
- Put each subject in a level.
- When one session differs from its subject, give that session its own level.

A grouping becomes the facet "Group: Treatment" everywhere: Group by, Color by, the exports' `group_Treatment` column and the generated script. The browser's right-click **Assign to grouping ▸** does the same from the tree.

**Groups ▸ Group by / Color by / X axis** choose a facet from the menu bar.

### Descriptive statistics

Beside the plot, per group, the window shows:

- n, mean, SD, SEM;
- the median and the interquartile range (Q1, Q3);
- with Bootstrap CI ticked, a confidence interval on the mean, from a fixed seed. A group of fewer than five values has no CI.

The same numbers, in one sentence, go to the status line.

**There are no p-values in this version, by decision.** Inferential tests (t-tests, rank tests, mixed models) are planned. Until then, the window describes the data and leaves the inference to you.

## Table

The numbers of the checked sessions, one row each.

- Choose the columns on the right with Ctrl+click. **Default Columns** puts them back.
- Click a header to sort.
- Double-click a row to open that session.
- **Copy** puts the shown columns on the clipboard as tab-separated text, formatted as the CSV export is, ready to paste into a spreadsheet or a notebook.
- **Export…** opens the export dialog.

## Presets and settings

**Analysis ▸ Settings…** (the gear) shows every analysis setting:

- the general settings;
- **Staircase**: direction, reversals used, formula, weighted correction and its steps;
- **Fit**: engine, shape, criterion and its scale, guess and lapse rates, bootstrap;
- **Metrics**: the correction for rates of 0 and 1;
- **QC**: minimum trials, maximum abort rate, minimum reversals;
- **Compare**: bootstrap CI, its level and its resamples.

A value the settings cannot use, or a combination that cannot run, is named under the grid and greys **OK** and **Apply**. **Defaults** fills in the default settings, to apply if you choose.

Every result is labelled with its **settings hash**, eight hex digits that name the settings that produced it. Changing a setting that changes a number recomputes every session. Changing a QC limit or a Compare option changes no number, so nothing is recomputed: after changing a QC limit, use **Analysis ▸ Recompute All** to flag the sessions against it.

A **preset** is a named copy of the settings and the Compare view:

- **Preset ▸ Save as…**, or **Save Current as…** in the settings dialog, saves the applied settings under a name.
- Choosing a preset in the header, or in **Analysis ▸ Presets**, applies it.
- **Manage…** opens the settings dialog's preset list to apply, rename or delete one.

The header shows the preset whose settings are in force, or "(custom)". Presets are kept in the project file, so everyone who opens the root has them.

**Analysis ▸ Parameter** chooses the tracked parameter. **(auto)** takes each session's best candidate, and flags `parameter_differs` on a session whose choice differs from most of the others. **Analysis ▸ Recompute All** forgets every result and analyses every visible session again.

## Export

**File ▸ Export Tables… (Ctrl+E)** writes tidy tables of the checked sessions. When none is checked, it exports every visible session. The tables are:

- `sessions`, `subjects`, `thresholds`, `fits`, `metrics`;
- optionally `reversals` and `notes`.

You choose the tables, the formats, the folder and a file-name prefix.

| Format | Writes |
|---|---|
| CSV | one UTF-8 file per table |
| Excel | one workbook, a sheet per table |
| MAT | one struct, `EPsychExport` |

Every export also writes `<prefix>columns.csv`, the dictionary of every column: its type, unit and meaning. A number that was not measured is an empty cell, never a word. Each session is identified by its **key**, its path under the root, so an export still matches the data after the root is copied elsewhere.

**File ▸ Export Figure… (Ctrl+Shift+F)** saves the figure on the tab in front:

- the staircase on the Session tab;
- the threshold timeline on the Subject tab;
- the comparison on the Compare tab.

The format follows the extension: `.png`, `.pdf` or `.svg`.

## The generated script

**File ▸ Generate Script** writes a plain MATLAB script that reproduces an analysis exactly:

- **Checked Sessions (Compare)…** (Ctrl+G) covers the checked sessions, with the Compare view's facets.
- **This Session…** covers the session on the Session tab.
- **Every Visible Session…** covers the whole root.

The script needs nothing but EPsych and the data. It holds:

- every setting, written out, with a check that they still hash to the value the results were made with;
- every session by its key, with its trial window;
- the very analysis call the window makes;
- the tables, the statistics and the figures;
- a check that each session gives the numbers the window gave when the script was written. It prints "replicated exactly" or lists the differences.

The script does not use the window, your preferences or the project file. To run it on a copy of the data elsewhere, set `ROOT` before running it. Set `OUTFOLDER` to choose where its export goes.

```matlab
>> ROOT = "E:\Copy\Lab";  run("replicate_checked_sessions.m")
```

## Keyboard shortcuts

| Keys | Does |
|---|---|
| Ctrl+O | Open Root… |
| F5 | Rescan |
| Ctrl+S | Save Project |
| Ctrl+E | Export Tables… |
| Ctrl+G | Generate Script (checked sessions) |
| Ctrl+Shift+F | Export Figure… |
| Enter | Open the selected session |
| Ctrl+R | Review Session… |
| Del | Hide / Unhide |
| Ctrl+W | Trial Window Override… |
| Ctrl+N | Comment… |
| Ctrl+M | Manage Groupings… |
| Ctrl+1 … Ctrl+4 | Session, Subject, Compare, Table |
| Ctrl+B | Show or hide the browser |
| Ctrl+F | Find |
| F1 | This guide |

A shortcut does not reach the window while the cursor is in a text field. Click the tree or a plot first.

## Closing

Closing the window with unsaved changes asks **Save**, **Discard** or **Cancel**. So does opening another root. Unsaved changes are hidden sessions, windows, comments, groupings, settings, presets, the Compare view and the checked set.

## Files written

| Where | What | When |
|---|---|---|
| `<root>\EPsych_Analysis\project.json` | everything decided in the window | Save Project |
| `<root>\EPsych_Analysis\.history\project_*.json` | the three previous versions | each save |
| alternate store folder | `project.json` and `.history` instead of the above | when chosen for a root that cannot be written |
| `%LOCALAPPDATA%\EPsych\AnalysisCache\catalog_*.mat` | the scan cache, one per root | each scan |
| the folder you choose | exported tables, `columns.csv`, figures, scripts | when you export or generate |
| MATLAB preferences, group `epsych2_BehaviorAnalysis` | window position, recent roots, last root, alternate stores, browser shown, Show filter, last tab, export folder and formats, figure format | when you use the control |

Nothing else is written, and nothing under the root but `EPsych_Analysis\`.

**See also:** [behavior classes](behavior_Classes.md) · `epsych.ReviewSession` · `gui.SessionBrowser`
