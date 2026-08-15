# Best PEST — Maximum Likelihood Threshold Estimation

`psychophysics.BestPEST`  
Source: `obj/+psychophysics/@BestPEST/`  
Reference: Pentland, A. (1980). Maximum likelihood estimation: The best PEST. *Perception & Psychophysics*, 28(4), 377–379.

---

## Contents

- [Overview for Users](#overview-for-users)
  - [What it does](#what-it-does)
  - [How it works](#how-it-works)
  - [Psychometric function choice](#psychometric-function-choice)
  - [Key parameters and their effects](#key-parameters-and-their-effects)
  - [When to use Best PEST vs. Staircase](#when-to-use-best-pest-vs-staircase)
- [Developer Reference](#developer-reference)
  - [Class hierarchy](#class-hierarchy)
  - [Constructor](#constructor)
  - [Properties](#properties)
  - [Results struct](#results-struct)
  - [Public methods](#public-methods)
  - [Integration with trial selection](#integration-with-trial-selection)
  - [Integration with plotting / GUI components](#integration-with-plotting--gui-components)
  - [Internal architecture](#internal-architecture)
  - [Reset / watermark mechanism](#reset--watermark-mechanism)
  - [Stopping criterion](#stopping-criterion)
  - [Edge cases and error handling](#edge-cases-and-error-handling)

---

## Overview for Users

### What it does

Best PEST finds a **detection threshold** — the stimulus level at which a subject responds correctly at a specified probability. After every trial it fits a psychometric function to all accumulated responses using maximum likelihood estimation (MLE) and places the next stimulus at the most informative location (the current threshold estimate). This is more statistically efficient than a classical up/down staircase because every trial directly informs the estimate, not just reversal points.

### How it works

1. **Each trial** — the subject is presented with a stimulus at the level suggested by `Results.NextLevel` and their response (detect/miss) is recorded.
2. **After each trial** — the algorithm fits a sigmoid-shaped curve to all response history. The x-axis position of that curve (the threshold, θ) that best predicts the observed data is found via a systematic grid search.
3. **Next level** — the next stimulus is placed at the current best estimate of θ. This point carries the maximum statistical information about the threshold.
4. **Threshold at target** — separately, the stimulus level that would produce any desired probability (e.g. 75% correct) is computed analytically from the fitted curve and reported as `ThresholdAtTarget`.
5. **Confidence interval** — a profile likelihood confidence interval narrows as more trials accumulate, providing a measure of estimate precision.

### Psychometric function choice

Three curve shapes are available (`PsychometricFunction` property):

| Shape | Best used when… | Notes |
|---|---|---|
| **Logistic** (default) | Most detection and discrimination tasks | Simple, symmetric; θ = 50% base-CDF point |
| **Normal** | Intensity discrimination; response statistics expected to be Gaussian | Symmetric; θ = mean, slope = precision (1/σ) |
| **Weibull** | Psychoacoustic tasks with intensity in linear units; frequency discrimination | Asymmetric; θ is the scale parameter (≈63% base-CDF point), **not** the 50% threshold — use `ThresholdAtTarget` to find the actual detection point |

For most behavioural paradigms with a binary (yes/no or go/no-go) response, **Logistic** is the safest default.

### Key parameters and their effects

#### `Range`  *(required)*
Sets the minimum and maximum stimulus levels the algorithm will consider. Keep it wide enough to bracket the true threshold. If the range is too narrow the threshold can be pushed against the boundary and the estimate will be biased.

> **Tip:** For dB SPL tasks a typical starting range might be `[0 80]` or `[10 40]`.

#### `GuessRate`
The probability of a positive response at zero stimulus level (the lower asymptote, γ). For **yes/no** or **go/no-go** tasks, leave at the default `0`. For **2-AFC** tasks, set to `0.5` because the subject guesses correctly half the time by chance.

#### `LapseRate`
The probability that the subject misses a clearly detectable stimulus (the upper asymptote offset, λ). Common values are 0 to 0.05. A non-zero lapse rate prevents the fitted curve from reaching 1 and makes the estimate more robust to inattentive responses.

#### `TargetProbability`
The proportion correct for which `ThresholdAtTarget` is reported. Typical values:
- `0.5` — 50% point of the base curve (default; equals θ for Logistic/Normal with symmetric asymptotes)
- `0.75` — standard 2-AFC threshold (performance halfway between chance and perfect)
- `0.794` — d′ = 1 criterion in yes/no tasks

> **Note:** `NextLevel` (the next stimulus) is always placed at θ regardless of `TargetProbability`. `ThresholdAtTarget` is a reporting output only.

#### `Slope` / `EstimateSlope`
The slope controls how steeply the psychometric function rises. With `EstimateSlope=false` (default) you fix the slope and only θ is estimated — this converges faster but requires a reasonable slope assumption. With `EstimateSlope=true` both θ and slope are estimated jointly from the data, which requires more trials but makes no assumption about slope.

> **Tip:** When using a fixed slope, try to set it to a value consistent with your species/paradigm. If the assumed slope is much shallower than reality, the initial estimates will be noisy. Starting values around `1–5` are typical for behavioural audiograms.

#### `ConfidenceLevel`
Coverage of the profile log-likelihood CI (default `0.95`). A narrower interval (`ConfidenceIntervalWidth` in `Results`) indicates a more precise estimate and can be used as a stopping criterion.

#### `GridResolution`
Number of candidate threshold values evaluated during MLE (default `1000`). Higher values give a more precise estimate but slightly more computation. For most tasks 500–2000 is sufficient.

### When to use Best PEST vs. Staircase

| Consideration | Best PEST | Staircase |
|---|---|---|
| Statistical efficiency | Higher — uses all trials | Lower — only reversals count |
| Minimum useful trials | ~20–40+ | ~6+ (for a few reversals) |
| Does it require a model (slope)? | Yes | No |
| Works with GuessRate ≠ 0 (2-AFC)? | Yes (set `GuessRate=0.5`) | Not natively |
| Confidence interval on threshold? | Yes (`ConfidenceInterval`) | No |
| Slope estimate? | Optional | No |

Best PEST is preferred for longer sessions where statistical efficiency matters. Staircase is simpler and may be appropriate for quick screening or when you do not want to assume a psychometric function shape.

---

## Developer Reference

### Class hierarchy

```
matlab.mixin.SetGet
    └── handle
            └── psychophysics.Psych   (abstract base)
                    └── psychophysics.BestPEST
```

`psychophysics.Psych` provides:
- `DATA` property — growing struct array of trial records
- `RUNTIME` property — attached Runtime object (online mode)
- `refresh()` — calls `recomputeResults_()` and notifies listeners
- `update_data(~, event)` — NewData listener callback that calls `refresh()`
- `parameterFieldName_()` — resolves the tracked parameter field name from `DATA`
- `bitMaskToTrialTypeValue_(bit)` — converts `epsych.BitMask.TrialType_N` to integer N
- `trialTypeMask_(bit)` — logical trial-type mask over all `DATA`

### Constructor

```matlab
bp = psychophysics.BestPEST(source, Parameter, Range=[min max])
bp = psychophysics.BestPEST(source, Parameter, Range=[min max], Name=Value)
```

| Argument | Type | Description |
|---|---|---|
| `source` | Runtime object or DATA struct array | Online or offline mode |
| `Parameter` | Parameter object or string | Field to extract as stimulus level |
| `Range` | `(1,2) double` | **Required.** `[min max]` of the stimulus variable |

All other inputs are name-value pairs matching the [Properties](#properties) table below.

**Online mode** — pass a Runtime object. A listener is attached to `RUNTIME.EVENTS` `'NewData'` and `refresh()` is called automatically after each trial.

**Offline mode** — pass a DATA struct array. `refresh()` is called immediately in the constructor; no listener is created.

```matlab
% Online
bp = psychophysics.BestPEST(RUNTIME, Parameter, Range=[-40 0], GuessRate=0.5);

% Offline (2-AFC audiogram data, 75% target, Weibull fit)
bp = psychophysics.BestPEST(DATA, 'Depth', Range=[-60 0], ...
    PsychometricFunction='Weibull', ...
    GuessRate=0.5, TargetProbability=0.75);
fprintf('Threshold at 75%%: %.2f dB\n', bp.Results.ThresholdAtTarget);
```

### Properties

All properties listed below are `SetObservable`. GUI components can listen for `PostSet` events to update displays when a property is changed at runtime.

#### Stimulus range

| Property | Default | Description |
|---|---|---|
| `Range` | `[0 1]` | `[min max]` of the stimulus range. Must bracket the true threshold. |

#### Psychometric model

| Property | Default | Description |
|---|---|---|
| `PsychometricFunction` | `"Logistic"` | Curve shape: `"Logistic"`, `"Normal"`, or `"Weibull"` |
| `Slope` | `1` | Fixed slope when `EstimateSlope=false` |
| `EstimateSlope` | `false` | Joint 2-D MLE over θ and slope |
| `SlopeRange` | `[0.1 10]` | Search range for slope (used only when `EstimateSlope=true`) |
| `SlopeGridResolution` | `50` | Grid points for slope axis (used only when `EstimateSlope=true`) |
| `GuessRate` | `0` | Lower asymptote γ; set to `0.5` for 2-AFC |
| `LapseRate` | `0` | Upper asymptote offset λ |

#### Estimation control

| Property | Default | Description |
|---|---|---|
| `GridResolution` | `1000` | Threshold axis grid points |
| `TargetProbability` | `0.5` | Probability for `ThresholdAtTarget` output |
| `ConfidenceLevel` | `0.95` | Profile log-likelihood CI coverage |

#### Trial classification

| Property | Default | Description |
|---|---|---|
| `PositiveResponseBit` | `epsych.BitMask.Hit` | `epsych.BitMask` identifying a positive ("detected") response |
| `StimulusTrialType` | `epsych.BitMask.TrialType_0` | Only trials matching this type contribute to estimation |
| `CatchTrialType` | `epsych.BitMask.TrialType_1` | Stored for external use; not used internally by BestPEST |

#### Read-only / dependent

| Property | Description |
|---|---|
| `Results` | Struct of current estimation outputs (see below) |
| `ResetCount` | Number of trials present at the last `reset()` call |

### Results struct

`bp.Results` is updated after every trial (online) or on construction (offline).

| Field | Type | Description |
|---|---|---|
| `NextLevel` | scalar | **Next recommended stimulus level.** Equal to `ThresholdEstimate`, clamped to `Range`. This is the value trial selection should use for the next stimulus. |
| `ThresholdEstimate` | scalar | ML estimate of θ (location/scale parameter). |
| `ThresholdAtTarget` | scalar | Stimulus level yielding `TargetProbability`. Computed analytically from the fitted curve. `NaN` if `TargetProbability` is unreachable given `GuessRate`/`LapseRate`. |
| `SlopeEstimate` | scalar or `[]` | ML slope estimate when `EstimateSlope=true`; `[]` otherwise. |
| `ConfidenceInterval` | `(1,2)` | `[lower upper]` profile log-likelihood CI on `ThresholdEstimate`. |
| `ConfidenceIntervalWidth` | scalar | `diff(ConfidenceInterval)`. Use as a stopping criterion. |
| `Grid` | vector or matrix | Threshold grid (row vector for 1-D; meshgrid matrix for 2-D). |
| `LogLikelihood` | vector or matrix | Normalized log-likelihood (max = 0) over `Grid`. Use for plotting the posterior landscape. |
| `TrialCount` | integer | Number of stimulus trials used in the current estimate (after watermark). |
| `StimulusLevels` | row vector | Stimulus levels of included trials. |
| `Responses` | row vector | Binary responses (1 = positive) of included trials. |

**Before any trials accumulate** (or after `reset()`), `NextLevel = max(Range)` and all other fields are `[]` or `0`.

### Public methods

#### `reset()`

```matlab
bp.reset()
```

Sets a watermark at `numel(bp.DATA)`. All trials recorded before `reset()` are preserved in `DATA` but are excluded from subsequent estimation. `refresh()` is called automatically, so `Results.NextLevel` immediately returns to `max(Range)` (the easiest stimulus).

Use this to restart estimation mid-session without clearing hardware state — for example, when switching from a training block to a test block, or when the subject's criterion shifts.

```matlab
% After a warmup block, restart estimation cleanly
bp.reset();
% Optionally change parameters for the test block
bp.Range = [-60 -10];
bp.TargetProbability = 0.75;
```

> **Note:** `bp.ResetCount` reports the watermark value after the last reset. Multiple resets are additive — only the most recent watermark applies.

### Integration with trial selection

Trial selection functions query `bp.Results.NextLevel` after each trial to determine the next stimulus:

```matlab
% Minimal trial selection pattern
nextStimLevel = bp.Results.NextLevel;
% Apply nextStimLevel to the parameter before scheduling the next trial
Parameter.Value = nextStimLevel;
```

The trial selector should:

1. Wait for the `'NewData'` listener to update `bp.Results` (online) or call `bp.refresh()` explicitly (offline/testing).
2. Read `bp.Results.NextLevel` — this is always within `Range`.
3. Optionally check `bp.Results.ConfidenceIntervalWidth` against a stopping threshold.
4. Optionally read `bp.Results.ThresholdAtTarget` to report a running threshold estimate in a separate display.

The class does **not** schedule trials or interact with hardware directly.

### Integration with plotting / GUI components

`bp.Results` exposes all fields needed for standard psychophysical plots:

```matlab
% Psychometric function overlay on log-likelihood landscape
plot(bp.Results.Grid, bp.Results.LogLikelihood);
xline(bp.Results.ThresholdEstimate, '--k', 'ML Threshold');

% Running threshold estimate across trials
plot(1:bp.Results.TrialCount, cumulative_threshold_estimates);

% Confidence interval shading
fill([bp.Results.ConfidenceInterval(1), bp.Results.ConfidenceInterval(2), ...
      bp.Results.ConfidenceInterval(2), bp.Results.ConfidenceInterval(1)], ...
     [yMin, yMin, yMax, yMax], [0.8 0.8 0.8], 'EdgeColor','none');
```

To react to live updates in a GUI, listen to `psychophysics.Psych` refresh events or `PostSet` on `Results`:

```matlab
addlistener(bp, 'Results', 'PostSet', @myUpdateCallback);
```

### Internal architecture

The class is split across five files in `obj/+psychophysics/@BestPEST/`:

| File | Role |
|---|---|
| `BestPEST.m` | Class definition — properties, constructor, `reset()`, `emptyResults_()`, method stubs |
| `recomputeResults_.m` | Protected override — orchestrates the full estimation pipeline |
| `computeLogLikelihood_.m` | Grid-based MLE; 1-D (fixed slope) or 2-D (joint θ+slope); profile CI |
| `evaluatePsychFn_.m` | Evaluates P(x; θ, slope) with γ/λ; broadcast-compatible |
| `invertPsychFn_.m` | Analytically inverts P to recover x at a target probability |

**`recomputeResults_` pipeline** (called by `Psych.refresh()` after each trial):

```
DATA
 └─ apply watermark (resetCount_)
     └─ filter by StimulusTrialType
         └─ extract stimLevels, responses
             └─ computeLogLikelihood_   →  logL, thetaGrid, slopeGrid, ci
                 └─ argmax(logL)        →  ThresholdEstimate [, SlopeEstimate]
                     ├─ clamp to Range  →  NextLevel
                     └─ invertPsychFn_  →  ThresholdAtTarget
```

**Log-likelihood normalization:** `logL` is shifted so `max(logL) = 0`. This improves numerical stability and makes the CI threshold a fixed value: `logL_thresh = -chi2inv(ConfidenceLevel, 1) / 2`.

**Trial-type resolution:** `recomputeResults_` first looks for a `TrialType` field in `DATA`. If absent, it decodes the `RespCode` / `ResponseCode` bitmask using `epsych.BitMask.decode` and matches against `StimulusTrialType`.

**Value containers:** Stimulus levels that are structs or objects with a `.Value` field are automatically unwrapped before estimation.

### Reset / watermark mechanism

`resetCount_` is a private scalar that acts as a lower-bound index into `DATA`. `recomputeResults_` slices `DATA(resetCount_+1 : end)` before processing. Calling `reset()` sets `resetCount_ = numel(DATA)` so the next call sees an empty window and returns `NextLevel = max(Range)`. The watermark cannot be moved backward.

### Stopping criterion

There is no automatic stopping. A caller can stop the procedure when:

```matlab
bp.Results.ConfidenceIntervalWidth < toleranceThreshold
% e.g. stop when CI < 2 dB
```

or after a fixed number of trials (`bp.Results.TrialCount`).

### Edge cases and error handling

| Situation | Behaviour |
|---|---|
| `DATA` is empty or all trials are before the watermark | `Results = emptyResults_()`, `NextLevel = max(Range)` |
| No trials match `StimulusTrialType` | Same as above |
| `RespCode` / `ResponseCode` field absent | `Results = emptyResults_()`, warning via `vprintf` |
| `TargetProbability` unreachable given `GuessRate`/`LapseRate` | `ThresholdAtTarget = NaN`, warning logged via `vprintf(0,1,...)` |
| All stimulus levels are equal (flat likelihood) | MLE returns `mean(Range)`; CI spans `Range` |
| `EstimateSlope=true` with few trials | 2-D likelihood is flat; estimate is unstable until ~40+ trials |
