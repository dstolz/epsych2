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
  - Converts tracked values to decibels before analysis.
- `Bits` and `BitColors`
  - Response-code categories and matching display colors used by plotting helpers.

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

A reversal is detected when consecutive normalized step directions differ. The class stores the resulting locations in `Results.ReversalIdx` and the post-reversal direction in `Results.ReversalDirection`.

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

## Changelog

- 2026-03-21: Updated documentation to match the current constructor options, plotting API, step-direction behavior, and reversal-analysis flow in `psychophysics.Staircase`.
