# Adaptive Staircase Analysis

## Overview

`psychophysics.Staircase` tracks the state of an adaptive staircase from EPsych trial data. It extracts the tracked stimulus values, computes step direction, detects reversals, and derives threshold statistics from recent reversal values. Only trials matching `StimulusTrialType` are used in the computation of step direction, reversals, and thresholds.

The class supports two workflows:

- Online analysis, where the object listens to `RUNTIME.EVENTS.NewData` and updates automatically.
- Offline analysis, where the object is constructed from a saved `DATA` struct array and recomputed on demand.

The main implementation is in `obj/+psychophysics/@Staircase/Staircase.m`. Plotting support is implemented by helper methods in the same class folder.

## Quick Start

### Online mode

```matlab
S = psychophysics.Staircase(RUNTIME, Parameter);
```

In online mode, the constructor attaches a listener to `RUNTIME.EVENTS` and updates whenever new trial data is published.

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
> **`ThresholdFromLastNReversals` and `ThresholdFormula` are not accepted here.**
> They are settable properties rather than constructor name-value options — they
> are absent from the constructor's `arguments` block, so passing either one
> errors. Set them after construction and call `refresh_history()`:
>
> ```matlab
> S = psychophysics.Staircase(RUNTIME, Parameter);
> S.ThresholdFromLastNReversals = 8;
> S.ThresholdFormula = 'GeometricMean';
> S.refresh_history();
> ```
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
  - Number of most recent reversals used to compute `Results.Threshold` and `Results.ThresholdStd`.
  - Default: `12`. Set after construction, then call `refresh_history()`.
- `ThresholdFormula`
  - Accepts `'Mean'` or `'GeometricMean'`; combines the reversal values.
  - Default: `'Mean'`. Set after construction, then call `refresh_history()`.
  - Use `'Mean'` for a parameter already on a log scale, such as an AM depth
    in dB re 100%: the arithmetic mean of `20*log10(x)` IS `20*log10(geomean(x))`,
    so it is already the geometric mean of the linear quantity.
  - A geometric mean is undefined for negative values — which is every value
    of a dB depth below 100%. There `Results.Threshold` is `NaN`, the plot
    shows no threshold, and one message is logged rather than one per trial:
    this is computed from a `NewData` listener, so an error would repeat on
    every trial for the rest of the session.
- `ApplyWeightedCorrection`
  - When `true`, `Results.Threshold` is the Hoover-corrected threshold of a weighted
    staircase from `weightedThreshold`, `NaN` until it can be computed, and
    `Results.Weighted` holds the full result.
  - Default: `false`, so no existing session changes its numbers. Set after
    construction, then call `refresh_history()`.
- `WeightedStepAfterYes`, `WeightedStepAfterNo`
  - Signed steps after a yes and after a no, in the parameter's units; `NaN` (default)
    means find them. Also the defaults of `weightedThreshold`.
- `WeightedStepFieldYes`, `WeightedStepFieldNo`
  - DATA fields holding the steps per trial, e.g. `"Depth_StepOnHit"` /
    `"Depth_StepOnMiss"`; `""` (default) means none. Never guessed.
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
  - Fields include `ReversalCount`, `ReversalIdx`, `ReversalDirection`, `StepDirection`, `StimulusTrialIdx`, `Threshold`, `ThresholdStd`, and `Weighted` (the `weightedThreshold` result when `ApplyWeightedCorrection` is on, `[]` otherwise).

### Dependent read-only properties

- `responseCodes`
  - Returns codes from `DATA.ResponseCode` and falls back to `DATA.RespCode` for older saved structs, or `[]` when no data is available.
- `stimulusValues`
  - Returns the tracked parameter values, as recorded.
- `trialCount`
  - Returns `numel(obj.DATA)`.
- `ParameterName`
  - Returns `obj.Parameter.Name` when available, otherwise the class name of the parameter object.

## Public Methods

### `refresh_history`

```matlab
S.refresh_history()
```

Recomputes staircase history from the current `DATA`, refreshes the plot when plotting is enabled, and notifies listeners through `S.Events`.

Use this after changing analysis settings such as `StaircaseDirection`, `StimulusTrialType`, `ThresholdFormula`, or `ThresholdFromLastNReversals` in offline workflows.

### `fitPsychometric`

```matlab
F = S.fitPsychometric()
F = S.fitPsychometric(ThresholdCriterion=0.707, CriterionScale="absolute")
F = S.fitPsychometric(Shape="Weibull", Bootstrap=1000)
```

Fits a psychometric function to the staircase's trials by maximum likelihood
and returns threshold, slope, the fitted curve, and goodness of fit. It is the
*other* threshold this class can report: `Results.Threshold` is the mean of the
last N reversals, which converges on whatever proportion the step rule targets,
while the fit uses every scored trial at every level the session visited.

The fit is returned, never stored on `Results`, so it can never go stale beside
live trials. Check `F.Converged` and `F.Identifiable` before reading
`F.Threshold`; `F.Message` says what went wrong when either is false.

Two static companions are pure functions of their arguments and work with no
session at all:

```matlab
F = psychophysics.Staircase.fitProportions(levels, numYes, numTotal, ...)
P = psychophysics.Staircase.psychometricFunction(x, alpha, beta, ...)
x = psychophysics.Staircase.psychometricLevel(P, alpha, beta, ...)
```

See [psychophysics_StaircaseFit.md](psychophysics_StaircaseFit.md) for the
model, every option, the result struct, what the fit refuses to fit, and why
a slope from adaptive data should be read with care.

### `weightedThreshold`

```matlab
T = S.weightedThreshold()
T = S.weightedThreshold(StepFieldYes='Depth_StepOnHit', StepFieldNo='Depth_StepOnMiss')
T = S.weightedThreshold(StepAfterYes=-2, StepAfterNo=6, ExpectedTarget=0.75)
```

The threshold of a **weighted** (asymmetric-step) staircase, corrected as
Hoover (2025) prescribes: the mean of an equal number of ascending and
descending reversals, plus (δ₋ − δ₊)/4. `Results.Threshold` is the plain mean
of the last N reversals, which for a weighted staircase is biased toward the
tail of the psychometric function — and biased again when the reversals are
unbalanced.

The steps are stated, read from per-trial DATA fields (as
`cl_AppetitiveStimDetect` records `Depth_StepOnHit` / `Depth_StepOnMiss`), or
inferred from the track, and only the steps behind the reversals used are read.
Because each step is named by the response that preceded it and carries its
own sign, the correction is the same whichever way the parameter runs; there is
no direction to configure. `T.TargetProbability` is the ψ the steps actually
target, so a ratio wired backwards shows up as 0.25 rather than a plausible
threshold. Steps that change mid-session are flagged in `T.StepConsistency`,
not refused. Check `T.Valid` before reading `T.Threshold`.

`ApplyWeightedCorrection = true` makes the corrected value `Results.Threshold`
and the plotted threshold. The estimator is a pure static:

```matlab
T = psychophysics.Staircase.correctedReversalMean(values, isAscending, stepAfterYes, stepAfterNo, ...)
```

See [psychophysics_WeightedStaircase.md](psychophysics_WeightedStaircase.md)
for the equations, the step sources, what it refuses, and when the correction
does not apply (mAFC tasks with few alternatives, lapse rates above 1/10,
asymmetric psychometric functions).

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
reviewing a session: **Threshold Reversals**, **Threshold Formula**, **Show Steps**, and
**Show Reversals**. Values are plotted and analyzed in the parameter's own units; a quantity
wanted in dB is recorded in dB, as `cl_AppetitiveStimDetect` records `Depth`.

Choices made from that menu are **remembered across sessions** (preference group
`epsych2_psychophysics_Staircase`), keyed by the hosting figure's Tag (else Name) and the
tracked parameter, and restored when `Plot` attaches to axes. Only menu actions save, so
setting the properties from code is never persisted; a `ShowSteps`/`ShowReversals` passed
explicitly to `Plot` or the constructor still wins over the saved choice. A pop-out window
has its own Tag, so it remembers its own choices without overwriting the embedded plot's.

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

The tracked values are read from `DATA.(Parameter.validName)` for object-based parameters, or directly from the named DATA field when offline mode is constructed with a string parameter name. They are used as recorded; nothing is converted.

For offline compatibility, `responseCodes` are read from `DATA.ResponseCode` when present and fall back to `DATA.RespCode` for older saved structs.

### 3. Step direction

Step direction is computed only for consecutive stimulus values from trials matching `StimulusTrialType`. For these selected trials, the class computes:

```matlab
sd = sign(diff(stimulusValues));
```

If `StaircaseDirection` is `'Up'`, the sign is inverted before reversals are detected. The resulting directions are stored in `Results.StepDirection` for plotting and inspection. Trials not matching `StimulusTrialType` are ignored in this computation.

### 4. Reversal detection

Reversal detection ignores holds (zero-valued steps, which occur legitimately after an Abort/CorrectReject/FalseAlarm repeats the previous stimulus value) and `NaN` steps (a trial whose recorded value is `NaN`). A reversal is detected when consecutive *nonzero* normalized step directions differ; the reversal is marked at the first stimulus trial that reaches the new extremum. The class stores the resulting locations in `Results.ReversalIdx` and the post-reversal direction in `Results.ReversalDirection`.

### 5. Threshold estimation

If at least one reversal is available, the class uses the most recent `ThresholdFromLastNReversals` reversal values and computes:

- `Results.Threshold` with either `mean` or `geomean` (`NaN` when a geometric mean is asked of negative values)
- `Results.ThresholdStd` with `std`

Once at least `ThresholdFromLastNReversals` reversals exist, the same formula is also applied to every run of that many *consecutive* reversals (a window sliding by one reversal), and the lowest is kept:

- `Results.MinBlockThreshold` — the minimum block threshold, the best the subject managed at any point in the session, where `Results.Threshold` follows the track wherever it drifts late in a session
- `Results.MinBlockReversals` — `[first last]` reversal numbers of that block

The plot title shows it beside the current estimate, e.g. `Threshold (6/6 rev): -14.00 (min -16.40)`. Both are empty until one whole block exists, and neither is computed under `ApplyWeightedCorrection`.

## Examples

### Offline analysis from saved trials

```matlab
S = psychophysics.Staircase(DATA, Parameter);
S.ThresholdFormula = 'GeometricMean';   % a property, not a constructor option
S.refresh_history();

fprintf('Reversals: %d\n', S.Results.ReversalCount);
fprintf('Threshold: %.3f\n', S.Results.Threshold);
fprintf('Threshold std: %.3f\n', S.Results.ThresholdStd);
```

### Listening for live updates

```matlab
S = psychophysics.Staircase(RUNTIME, Parameter);
addlistener(S.Events, 'NewData', @(src, evt) disp(S.Results.Threshold));
```

### Plotting an existing staircase

```matlab
S = psychophysics.Staircase(DATA, Parameter);
S.Plot();
```

## Notes and Limitations

1. Staircase state is maintained in memory only. Save threshold and reversal results explicitly if they are needed later.
2. Trial selection matters. If `StimulusTrialType` does not match the real staircase trials, threshold estimates will be wrong.
3. `GeometricMean` needs nonnegative values; for a parameter recorded in dB, use `Mean`.
4. `CatchTrialType` is stored by the object, but the main history computation path is driven by `StimulusTrialType`.
5. With only a small number of reversals, `Results.Threshold` and `Results.ThresholdStd` may be unstable.

## See Also

- [Psychometric fitting](psychophysics_StaircaseFit.md) — `fitPsychometric`, `fitProportions`, and the psychometric function they share
- [Weighted-staircase threshold](psychophysics_WeightedStaircase.md) — `weightedThreshold`, `correctedReversalMean`, and `ApplyWeightedCorrection`
- [`psychophysics.BestPEST`](psychophysics_BestPEST.md), [`psychophysics.MLP`](psychophysics_MLP.md) — threshold estimation *during* a session
- `epsych.BitMask`
- `epsych.EventHub`
- `hw.Parameter`
- [`gui.PopOut`](../gui/gui_PopOut.md) — the plot's **Open in Separate Window** option

## Changelog

- 2026-09-11: `weightedThreshold` reports the Hoover (2025) corrected threshold
  of a weighted (asymmetric-step) staircase — a balanced reversal mean plus
  (δ₋ − δ₊)/4 — with the step ratio and the probability the steps actually
  target. Steps are stated, read from DATA fields, or inferred from the track.
  The estimator (`correctedReversalMean`) is a pure static. The opt-in
  `ApplyWeightedCorrection` property routes it into `Results.Threshold`, the
  plot, and the title; off by default. See
  [weighted-staircase threshold](psychophysics_WeightedStaircase.md).
  Separately, a trial whose tracked value is empty now reads as `NaN` in
  `stimulusValues` instead of being dropped by `[DATA.(field)]`, which slid
  every later level onto the wrong trial and, on a stimulus trial, made the
  constructor (and the `NewData` listener) throw.
- 2026-09-11: `ConvertToDecibels` and the **Y Axis in dB (re 100%)** menu item are
  removed; a staircase is analyzed in the parameter's own units. `GeometricMean`
  on negative reversal values — which is what a depth recorded in dB gives —
  no longer throws `geomean`'s error from the `NewData` listener on every trial;
  `Results.Threshold` is `NaN` and one message is logged.
- 2026-09-10: `fitPsychometric` fits a psychometric function to the staircase's
  own trials by maximum likelihood, reporting threshold, slope, an optional
  bootstrap interval, and goodness of fit — alongside, not instead of, the
  reversal threshold. The estimator (`fitProportions`) and the function it fits
  (`psychometricFunction` / `psychometricLevel`) are pure statics, testable with
  no session. See [psychometric fitting](psychophysics_StaircaseFit.md).
- 2026-08-13: A plot update extracts the session's stimulus values and decodes its response codes once and shares them, instead of walking the trials up to eight times (three separate `epsych.BitMask.decode` calls, plus a full extraction just to count trials for the subtitle). 52 ms -> 30 ms per trial at 1000 trials. `Psych.trialTypeMasks_` resolves several trial-type masks from one extraction; the shared vectors are held until the trials, the trial-type selection, the exclusions, or `ConvertToDecibels` change. The subtitle of an empty staircase now reads `0 trials` rather than `1 trials`.
- 2026-08-11: The y axis is labeled with the tracked parameter's raw `Unit`, and a **Y Axis in dB (re 100%)** right-click option toggles `ConvertToDecibels`.
- 2026-07-15: Reversal detection now ignores holds (zero steps) and `NaN` steps instead of counting them as reversals.
- 2026-03-21: Updated documentation to match the current constructor options, plotting API, step-direction behavior, and reversal-analysis flow in `psychophysics.Staircase`.
