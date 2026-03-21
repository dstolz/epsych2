# Adaptive Staircase Analysis

## Overview

`psychophysics.Staircase` tracks the state of an adaptive staircase from EPsych trial data. It extracts the tracked stimulus values, computes step direction, detects reversals, and derives threshold statistics from recent reversal values.

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
fprintf('Threshold: %.3f\n', S.Threshold);
```

In offline mode, no listener is attached. The staircase is computed immediately from `DATA`.

### Common configuration

```matlab
S = psychophysics.Staircase(DATA, Parameter, ...
    StaircaseDirection='Up', ...
    StimulusTrialType=epsych.BitMask.TrialType_0, ...
    ConvertToDecibels=true, ...
    EnablePlot=true);
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

### Name-value options

- `StimulusTrialType`
  - `epsych.BitMask` used to choose which trials participate in staircase analysis.
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
  - Number of most recent reversals used to compute `Threshold` and `ThresholdStd`.
  - Default: `12`
- `ThresholdFormula`
  - Accepts `'Mean'` or `'GeometricMean'`.
  - Default: `'Mean'`
- `ConvertToDecibels`
  - When `true`, stimulus values are converted with `20*log10(x)` and nonpositive values become `NaN`.
- `EnablePlot`
  - When `true`, plotting is enabled during construction.
- `PlotAxes`
  - Optional axes handle. If omitted or empty, `enablePlot` creates and owns a new figure.
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

- `ReversalCount`
  - Number of detected reversals.
- `ReversalIdx`
  - Indices used by the class to reference detected reversal points.
- `ReversalDirection`
  - Direction assigned to each reversal after the class normalizes step signs.
- `StepDirection`
  - Per-trial direction array.
  - In the current implementation, non-step positions are represented as `0`, while nonempty step changes are stored as `-1` or `1`.
- `StimulusTrialIdx`
  - Indices of trials selected by `StimulusTrialType`.
- `Threshold`
  - Current threshold estimate from recent reversals.
- `ThresholdStd`
  - Standard deviation of the same reversal values used for `Threshold`.

### Dependent read-only properties

- `responseCodes`
  - Returns `[obj.DATA.ResponseCode]` or `[]` when no data is available.
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
S.enablePlot()
S.enablePlot(ax)
S.refreshPlot()
S.disablePlot()
```

- `enablePlot` creates or binds plotting axes and renders the current staircase state.
- `refreshPlot` redraws the plot from the current computed state.
- `disablePlot` deletes listeners and graphics owned by the staircase.

## How Analysis Works

### 1. Trial selection

The class decodes `responseCodes` with `epsych.BitMask.decode` and selects the trials marked by `StimulusTrialType`.

### 2. Stimulus extraction

The tracked values are read from `DATA.(Parameter.validName)`. If `ConvertToDecibels` is enabled, the values are converted with:

```matlab
v(v <= 0) = NaN;
v = 20*log10(v);
```

### 3. Step direction

For consecutive selected stimulus values, the class computes:

```matlab
sd = sign(diff(stimulusValues));
```

If `StaircaseDirection` is `'Up'`, the sign is inverted before reversals are detected. The resulting directions are stored in `StepDirection` for plotting and inspection.

### 4. Reversal detection

A reversal is detected when consecutive normalized step directions differ. The class stores the resulting locations in `ReversalIdx` and the post-reversal direction in `ReversalDirection`.

### 5. Threshold estimation

If at least one reversal is available, the class uses the most recent `ThresholdFromLastNReversals` reversal values and computes:

- `Threshold` with either `mean` or `geomean`
- `ThresholdStd` with `std`

## Examples

### Offline analysis from saved trials

```matlab
S = psychophysics.Staircase(DATA, Parameter, ThresholdFormula='GeometricMean');

fprintf('Reversals: %d\n', S.ReversalCount);
fprintf('Threshold: %.3f\n', S.Threshold);
fprintf('Threshold std: %.3f\n', S.ThresholdStd);
```

### Listening for live updates

```matlab
S = psychophysics.Staircase(RUNTIME, Parameter);
addlistener(S.Helper, 'NewData', @(src, evt) disp(S.Threshold));
```

### Plotting an existing staircase

```matlab
S = psychophysics.Staircase(DATA, Parameter);
S.enablePlot();
```

## Notes and Limitations

1. Staircase state is maintained in memory only. Save threshold and reversal results explicitly if they are needed later.
2. Trial selection matters. If `StimulusTrialType` does not match the real staircase trials, threshold estimates will be wrong.
3. `ConvertToDecibels` replaces nonpositive values with `NaN` before conversion.
4. `CatchTrialType` is stored by the object, but the main history computation path is driven by `StimulusTrialType`.
5. With only a small number of reversals, `Threshold` and `ThresholdStd` may be unstable.

## See Also

- `epsych.BitMask`
- `epsych.Helper`
- `hw.Parameter`

## Changelog

- 2026-03-21: Updated documentation to match the current constructor options, plotting API, step-direction behavior, and reversal-analysis flow in `psychophysics.Staircase`.
