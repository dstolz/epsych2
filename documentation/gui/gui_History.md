# gui.History

## Overview

`gui.History` renders a trial-by-trial summary table for behavioral sessions.
It listens for new data events from a linked psychophysics object and updates
an on-screen table with relative time, decoded response labels, and selected
trial parameters.

Source file: [obj/+gui/@History/History.m](../../obj/+gui/@History/History.m)

## What This Class Does

- Creates a `uitable` in a provided figure or panel container.
- Subscribes to `NewData` events and refreshes table contents automatically.
- Shows the newest trial at the top by default (chronological `DATA` order,
  not `TrialID`, which is a schedule/condition identifier).
- Supports user sorting via column header clicks (uifigure containers); the
  selected sort is reapplied on every trial update instead of being reset.
- Provides a right-click context menu to show/hide parameter columns and to
  reset sorting to the default (newest first).
- Persists column selection and sort order across MATLAB sessions with
  `getpref`/`setpref`, keyed to the hosting GUI figure.
- Colors rows by decoded response bit for quick visual review.
- Supports optional color overrides via `BitColors`.

## Constructor

```matlab
H = gui.History(pObj, container)
H = gui.History(pObj, container, BitColors=colors)
H = gui.History(pObj, container, ColumnFormats=formats)
H = gui.History(pObj, container, PreferenceTag=tag)
```

### Inputs

- `pObj`
  - Psychophysics object with `DATA`, `responseCodes`, `BitColors`, and `Helper`.
- `container`
  - Figure or panel that hosts the table. If empty, a new figure is created.
- `BitColors`
  - Optional hex color list used instead of `pObj.BitColors`.
- `ColumnFormats`
  - Optional `sprintf` format string(s) applied to all displayed columns.
  - Provide either one format for every column or one format per displayed column.
- `PreferenceTag`
  - Optional key for saved preferences. Defaults to the hosting figure `Tag`
    (or `Name`), so each GUI keeps its own column and sorting preferences.

### Returns

- `H`
  - A `gui.History` instance.

## Display Format

The table shows these columns in order:

1. `Time` (relative to first trial timestamp, formatted `mm:ss`)
2. `Response` (decoded response bit text)
3. Each field in `ParametersOfInterest`

Rows are displayed newest-first by default. Clicking a column header sorts by
that column (click again to reverse direction). Sorting uses raw trial values,
so numeric columns order numerically rather than lexicographically, and the
selected sort persists across trial updates.

All values are converted to character data via `sprintf` before assignment to
the table, and `ColumnFormat` is set to `char` for every column. Columns
without a configured format use their natural string form.

Compatibility notes:

- `ParameterColumnFormats` remains supported for legacy parameter-only
  formatting.
- When both `ColumnFormats` and `ParameterColumnFormats` are set,
  `ColumnFormats` takes precedence.
- Formats are remembered per parameter, so columns toggled off and back on
  via the context menu keep their configured format.

## Context Menu and Preferences

Right-clicking the table opens a context menu with:

- `Show Columns` - check/uncheck the scalar `DATA` fields to display as
  parameter columns.
- `Reset Sort (Newest First)` - restore the default row ordering.

Column selection and sort order are saved with `setpref` under group
`epsych2_gui_History`, keyed by `PreferenceTag` (default: the hosting figure
`Tag` or `Name`). Saved preferences are applied on the first data update, so
they take precedence over programmatic defaults assigned right after
construction (e.g., in a paradigm GUI's `create_gui`).

## Color Resolution

Row background color resolution is handled by private method `getBitColors`.
The method supports:

- Direct hex-string overrides from `History.BitColors`.
- Numeric `Nx3` RGB arrays from `psychObj.BitColors`.
- Hex-string arrays from `psychObj.BitColors`.

Validation behavior:

- If colors are provided per response count, they are used directly.
- If colors are indexed by bitmask value, entries are selected by bit index.
- Invalid color layouts raise an error with a descriptive message.

## Event and Lifecycle Behavior

- On construction, the class may register a listener on `pObj.Helper` event
  `NewData`.
- On each event, `update` recomputes table data and row colors.
- On object deletion, listener resources are cleaned up in `delete`.

## Usage Example

```matlab
fig = uifigure('Name', 'Trial History');
H = gui.History(pObj, fig);

H.ParametersOfInterest = {'SNR', 'TargetLevel', 'Block'};
H.update();
```

## Notes

- The class expects a valid psychophysics object as checked by
  `epsych.Helper.valid_psych_obj`.
- `ParametersOfInterest` fields must exist in each trial struct in `pObj.DATA`.
- If no trial data are available, update calls exit early without changing UI.

## Related Documentation

- [../overviews/RunExpt_GUI_Overview.md](../overviews/RunExpt_GUI_Overview.md)
- [../epsych/EPsychInfo.md](../epsych/EPsychInfo.md)
- [../overviews/Architecture_Overview.md](../overviews/Architecture_Overview.md)

## Version History

- 2026-07-15: Newest trial now shown at top (chronological order instead of
  `TrialID`). Added user-sortable columns that persist across trial updates,
  a right-click menu for column selection and sort reset, and per-GUI
  preference persistence via `getpref`/`setpref`.
- 2026-04-03: Initial documentation for `gui.History`.

