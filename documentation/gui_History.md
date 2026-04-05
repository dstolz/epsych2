# gui.History

## Overview

`gui.History` renders a trial-by-trial summary table for behavioral sessions.
It listens for new data events from a linked psychophysics object and updates
an on-screen table with relative time, decoded response labels, and selected
trial parameters.

Source file: [obj/+gui/@History/History.m](../obj/+gui/@History/History.m)

## What This Class Does

- Creates a `uitable` in a provided figure or panel container.
- Subscribes to `NewData` events and refreshes table contents automatically.
- Reorders rows by descending `TrialID` so recent trials appear first.
- Colors rows by decoded response bit for quick visual review.
- Supports optional color overrides via `BitColors`.

## Constructor

```matlab
H = gui.History(pObj, container)
H = gui.History(pObj, container, BitColors=colors)
H = gui.History(pObj, container, ColumnFormats=formats)
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

### Returns

- `H`
  - A `gui.History` instance.

## Display Format

The table shows these columns in order:

1. `Time` (relative to first trial timestamp, formatted `mm:ss`)
2. `Response` (decoded response bit text)
3. Each field in `ParametersOfInterest`

Rows are displayed in descending trial order.

All values are converted to character data via `sprintf` before assignment to
the table, and `ColumnFormat` is set to `char` for every column.

Compatibility notes:

- `ParameterColumnFormats` remains supported for legacy parameter-only
  formatting.
- When both `ColumnFormats` and `ParameterColumnFormats` are set,
  `ColumnFormats` takes precedence.

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

- [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md)
- [EPsychInfo.md](EPsychInfo.md)
- [Architecture_Overview.md](Architecture_Overview.md)

## Version History

- 2026-04-03: Initial documentation for `gui.History`.
