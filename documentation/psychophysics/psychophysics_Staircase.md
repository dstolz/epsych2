# Adaptive Staircase Analysis

## Overview

`psychophysics.Staircase` tracks the state of an adaptive staircase from EPsych trial data. It extracts the tracked stimulus values, computes step direction, detects reversals, and derives threshold statistics from recent reversal values. Only trials matching `StimulusTrialType` are used in the computation of step direction, reversals, and thresholds.

The class supports two workflows:

- Online analysis, where the object listens to `RUNTIME.HELPER.NewData` and updates automatically.
- Offline analysis, where the object is constructed from a saved `DATA` struct array and recomputed on demand.

The main implementation is in `obj/+psychophysics/@Staircase/Staircase.m`. Plotting support is implemented by helper methods in the same class folder.

## Quick Start

### Online mode

```matlab
S = psychophysics.Staircase(RUNTIME, Parameter);
```

In online mode, the constructor attaches a listener to `RUNTIME.HELPER` and updates whenever new trial data is published.

### Offline mode

```matlab
S = psychophysics.Staircase(DATA, Parameter);
S = psychophysics.Staircase(DATA, 'Depth');
fprintf('Threshold: %.3f\n', S.Results.Threshold);
```

In offline mode, no listener is attached. The staircase is computed immediately from `DATA`.

### Common configuration

```matlab
S = psychophysics.Staircase(DATA, Parameter, ...
    StaircaseDirection='Up', ...
    StimulusTrialType=epsych.BitMask.TrialType_0, ...
    ConvertToDecibels=true, ...
  Plot=true);
```

## Constructor

```matlab
S = psychophysics.Staircase(RUNTIME, Parameter)
S = psychophysics.Staircase(DATA, Parameter)
S = psychophysics.Staircase(..., Name=Value)
```

### Required inputs

- `RUNTIME` or `DATA`
  - Use `RUNTIME` for live updates.
  - Use `DATA` for saved-trial analysis.
- `Parameter`
  - The tracked parameter object. The class uses `Parameter.validName` to extract values from each trial.
  - In offline mode, this can also be a field name string such as `'Depth'` when the saved `DATA` struct already contains that field.
  - Saved trial structs are also accepted in offline mode when they expose the tracked parameter field and either `ResponseCode` or legacy `RespCode`.

### Name-value options

- `StimulusTrialType`
  - `epsych.BitMask` used to choose which trials participate in staircase analysis. Only these trials are used for step direction, reversal, and threshold computations.
  - Default: `epsych.BitMask.TrialType_0`
- `CatchTrialType`
  - Stored as a configuration property for workflows that distinguish catch trials.
  - Default: `epsych.BitMask.TrialType_1`
  - Current implementation note: `recompute_history` uses `StimulusTrialType` directly for reversal detection and threshold estimation.
- `StaircaseDirection`
  - Accepts `'Up'` or `'Down'`.
  - Default: `'Down'`
  - Controls how step-direction signs are normalized before reversal detection.
- `ThresholdFromLastNReversals`
  - Number of most recent reversals used to compute `Results.Threshold` and `Results.ThresholdStd`.
  - Default: `12`
- `ThresholdFormula`
  - Accepts `'Mean'` or `'GeometricMean'`.
  - Default: `'Mean'`
- `ConvertToDecibels`
  - When `true`, stimulus values are converted with `20*log10(x)` and nonpositive values become `NaN`.
- `Plot`
  - When `true`, plotting is enabled during construction.
- `PlotAxes`
  - Optional axes handle. If omitted or empty, `Plot` creates and owns a new figure.
- `ShowSteps`
  - Toggle plotting of step-direction markers.
- `ShowReversals`
  - Toggle plotting of reversal markers.

## Core Properties

### Configuration properties

- `Parameter`
  - Parameter object used to extract the tracked stimulus value from each trial.
- `StaircaseDirection`
  - Direction convention used during reversal analysis.
- `StimulusTrialType`
  - BitMask identifying trials that belong to the staircase.
- `CatchTrialType`
  - Auxiliary BitMask for workflows that separate catch trials.
- `ThresholdFromLastNReversals`
  - Window size used for threshold estimation.
- `ThresholdFormula`
  - Formula used to combine reversal values.
- `ConvertToDecibels`
  - Converts tracked values to decibels before analysis, referenced to full scale (100% depth): `dB = 20*log10(x/1)`.
  - Also toggled at runtime from the plot's right-click menu (**Y Axis in dB (re 100%)**), which recomputes the staircase and relabels the y axis.
- `Bits` and `BitColors`
  - Response-code categories and matching display colors used by plotting helpers.

### Appearance properties

- `LineColor`
  - Color of the staircase trace connecting successive trials.
- `NeutralColor`
  - Color of the step halo and of trials with no recognized response bit.
- `ReversalColor`
  - Outline color of the reversal triangles.
- `ThresholdColor`
  - Color of the threshold line and of its ±1 SD band.
- `StepColor`
  - Used by `directionColors_` for step-direction coloring.
- `MarkerSize`, `StepMarkerSize`, `ReversalMarkerSize`
  - Scatter `SizeData` for trial markers, step halos, and reversal outlines.

Accent colors deliberately avoid the response-outcome hues defined by
`epsych.BitMask` (green, red, blue, orange), so an overlay is never mistaken for
an outcome.

### Computed properties

- `Results`
  - Structure containing computed staircase outputs.
  - Fields include `ReversalCount`, `ReversalIdx`, `ReversalDirection`, `StepDirection`, `StimulusTrialIdx`, `Threshold`, and `ThresholdStd`.

### Dependent read-only properties

- `responseCodes`
  - Returns codes from `DATA.ResponseCode` and falls back to `DATA.RespCode` for older saved structs, or `[]` when no data is available.
- `stimulusValues`
  - Returns the tracked parameter values, optionally converted to decibels.
- `trialCount`
  - Returns `numel(obj.DATA)`.
- `ParameterName`
  - Returns `obj.Parameter.Name` when available, otherwise the class name of the parameter object.

## Public Methods

### `refresh_history`

```matlab
S.refresh_history()
```

Recomputes staircase history from the current `DATA`, refreshes the plot when plotting is enabled, and notifies listeners through `S.Helper`.

Use this after changing analysis settings such as `StaircaseDirection`, `StimulusTrialType`, `ThresholdFormula`, or `ThresholdFromLastNReversals` in offline workflows.

### Plot control

```matlab
S.Plot()
S.Plot(ax)
S.refreshPlot()
S.disablePlot()
```

- `Plot` creates or binds plotting axes and renders the current staircase state.
- `refreshPlot` redraws the plot from the current computed state.
- `disablePlot` deletes listeners and graphics owned by the staircase.

### How the plot reads

Marker color is the primary encoding: every trial is drawn in its response-outcome
color from `BitColors`. Shape separates trial types — circles are stimulus trials,
diamonds are catch trials. The overlays annotate those markers without hiding them:
a step draws a soft neutral halo behind its trial, a reversal draws a hollow
triangle around it, and the threshold is a horizontal line with a ±1 SD band across
the reversals it was computed from.

The legend sits inside the axes at the lower left, laid out horizontally over an
opaque background, and lists only what is currently drawn — including one color
swatch per outcome present in the data. The staircase trace and plain stimulus
marker are omitted from it, and up/down reversals share a single entry, so it stays
within two rows in an embedded axes. It is rebuilt only when its contents change.

The y axis is labeled `<Name> (<Unit>)` from the tracked `hw.Parameter`, using its raw `Unit`
string exactly as entered in the Protocol Designer. Parameters with no unit, and offline
staircases constructed from a DATA field name, are labeled with the name alone.

Right-clicking the plot axes exposes the analysis settings that are worth changing while
reviewing a session: **Threshold Reversals**, **Threshold Formula**, **Y Axis in dB (re 100%)**
(`ConvertToDecibels`), **Show Steps**, and **Show Reversals**. The decibel option converts the
tracked values with `20*log10(x)`, so the reported threshold and reversal values are in dB re
100% depth as well — the y-axis label swaps the raw unit for `dB re 100%`. Because the mean is
then taken in the decibel domain, the dB threshold is not simply `20*log10` of the linear
threshold.

The same menu offers **Open in Separate Window** (`S.popOut()`), which plots the staircase
larger in a window of its own. That window holds a *second* `psychophysics.Staircase` over the
same trials — the settings above are analysis settings, so a shared object would make changing
them in the pop-out rewrite the embedded plot too. The sibling starts from the host's trials and
settings, follows the same `NewData` events, and is deleted with its window; closing it, or
changing anything in it, leaves the GUI's plot alone. See
[../gui/gui_PopOut.md](../gui/gui_PopOut.md).

## How Analysis Works

### 1. Trial selection

The class selects staircase trials from `DATA.TrialType` when that field is available in saved offline data. Otherwise, it decodes `responseCodes` with `epsych.BitMask.decode` and selects the trials marked by `StimulusTrialType`. Only these selected trials are used for all subsequent computations, including step direction, reversal detection, and threshold estimation.

### 2. Stimulus extraction

The tracked values are read from `DATA.(Parameter.validName)` for object-based parameters, or directly from the named DATA field when offline mode is constructed with a string parameter name. If `ConvertToDecibels` is enabled, the values are converted with:

```matlab
v(v <= 0) = NaN;
v = 20*log10(v);
```

For offline compatibility, `responseCodes` are read from `DATA.ResponseCode` when present and fall back to `DATA.RespCode` for older saved structs.

### 3. Step direction

Step direction is computed only for consecutive stimulus values from trials matching `StimulusTrialType`. For these selected trials, the class computes:

```matlab
sd = sign(diff(stimulusValues));
```

If `StaircaseDirection` is `'Up'`, the sign is inverted before reversals are detected. The resulting directions are stored in `Results.StepDirection` for plotting and inspection. Trials not matching `StimulusTrialType` are ignored in this computation.

### 4. Reversal detection

Reversal detection ignores holds (zero-valued steps, which occur legitimately after an Abort/CorrectReject/FalseAlarm repeats the previous stimulus value) and `NaN` steps (which can arise from `ConvertToDecibels`). A reversal is detected when consecutive *nonzero* normalized step directions differ; the reversal is marked at the first stimulus trial that reaches the new extremum. The class stores the resulting locations in `Results.ReversalIdx` and the post-reversal direction in `Results.ReversalDirection`.

### 5. Threshold estimation

If at least one reversal is available, the class uses the most recent `ThresholdFromLastNReversals` reversal values and computes:

- `Results.Threshold` with either `mean` or `geomean`
- `Results.ThresholdStd` with `std`

## Examples

### Offline analysis from saved trials

```matlab
S = psychophysics.Staircase(DATA, Parameter, ThresholdFormula='GeometricMean');

fprintf('Reversals: %d\n', S.Results.ReversalCount);
fprintf('Threshold: %.3f\n', S.Results.Threshold);
fprintf('Threshold std: %.3f\n', S.Results.ThresholdStd);
```

### Listening for live updates

```matlab
S = psychophysics.Staircase(RUNTIME, Parameter);
addlistener(S.Helper, 'NewData', @(src, evt) disp(S.Results.Threshold));
```

### Plotting an existing staircase

```matlab
S = psychophysics.Staircase(DATA, Parameter);
S.Plot();
```

## Notes and Limitations

1. Staircase state is maintained in memory only. Save threshold and reversal results explicitly if they are needed later.
2. Trial selection matters. If `StimulusTrialType` does not match the real staircase trials, threshold estimates will be wrong.
3. `ConvertToDecibels` replaces nonpositive values with `NaN` before conversion.
4. `CatchTrialType` is stored by the object, but the main history computation path is driven by `StimulusTrialType`.
5. With only a small number of reversals, `Results.Threshold` and `Results.ThresholdStd` may be unstable.

## See Also

- `epsych.BitMask`
- `epsych.Helper`
- `hw.Parameter`
- [`gui.PopOut`](../gui/gui_PopOut.md) — the plot's **Open in Separate Window** option

## Changelog

- 2026-08-11: The y axis is labeled with the tracked parameter's raw `Unit`, and a **Y Axis in dB (re 100%)** right-click option toggles `ConvertToDecibels`.
- 2026-07-15: Reversal detection now ignores holds (zero steps) and `NaN` steps instead of counting them as reversals.
- 2026-03-21: Updated documentation to match the current constructor options, plotting API, step-direction behavior, and reversal-analysis flow in `psychophysics.Staircase`.
