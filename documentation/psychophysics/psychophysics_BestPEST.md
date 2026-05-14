# Best PEST — Maximum Likelihood Threshold Estimation

`psychophysics.BestPEST`  
Source: `obj/+psychophysics/@BestPEST/`  
Reference: Pentland, A. (1980). Maximum likelihood estimation: The best PEST. *Perception & Psychophysics*, 28(4), 377–379.

---

## Contents

- [Overview for Users](#overview-for-users)
  - [What it does](#what-it-does)
  - [How it works — step by step](#how-it-works--step-by-step)
  - [Psychometric function choice](#psychometric-function-choice)
  - [Key parameters and their effects](#key-parameters-and-their-effects)
  - [Setting up for common paradigms](#setting-up-for-common-paradigms)
  - [Reading the results](#reading-the-results)
  - [When to stop the experiment](#when-to-stop-the-experiment)
  - [When to use Best PEST vs. Staircase](#when-to-use-best-pest-vs-staircase)
- [Developer Reference](#developer-reference)
  - [Class hierarchy](#class-hierarchy)
  - [Constructor](#constructor)
  - [Properties reference](#properties-reference)
  - [Results struct reference](#results-struct-reference)
  - [Public methods](#public-methods)
  - [Integration with trial selection](#integration-with-trial-selection)
  - [Integration with plotting and GUI components](#integration-with-plotting-and-gui-components)
  - [Online mode — event listener pattern](#online-mode--event-listener-pattern)
  - [Internal architecture](#internal-architecture)
  - [Log-likelihood and confidence interval computation](#log-likelihood-and-confidence-interval-computation)
  - [2-D slope estimation mode](#2-d-slope-estimation-mode)
  - [Reset and watermark mechanism](#reset-and-watermark-mechanism)
  - [Stopping criterion](#stopping-criterion)
  - [Performance notes](#performance-notes)
  - [Edge cases and error handling](#edge-cases-and-error-handling)

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-14 | Expanded for dual audiences; added 2-D slope estimation details, GUI/listener patterns, paradigm setup guide, and performance notes. |

---

## Overview for Users

### What it does

Best PEST finds a **detection threshold** — the stimulus level at which a subject responds correctly at a specified probability. After every trial it fits a sigmoid-shaped curve (a psychometric function) to all accumulated responses using maximum likelihood estimation (MLE) and places the next stimulus at the most informative possible location: the current threshold estimate. This is more statistically efficient than a classical staircase because every trial contributes to the estimate, not just the reversal points.

### How it works — step by step

1. **Each trial** — the subject is presented with a stimulus at the level suggested by `Results.NextLevel` and their response (detected / missed) is recorded.
2. **After each trial** — the algorithm evaluates how well each candidate threshold value on a fine grid would predict the entire observed response history. The candidate that fits best is the maximum-likelihood estimate of θ.
3. **Next level** — the next stimulus is placed at the current best estimate of θ. At this stimulus level the psychometric function has its steepest slope, meaning each response provides the most statistical information possible about the true threshold.
4. **Threshold at target** — separately, the stimulus level that would produce any desired probability (e.g. 75% correct) is computed analytically from the fitted curve and reported as `ThresholdAtTarget`.
5. **Confidence interval** — a profile likelihood confidence interval narrows as more trials accumulate. Its width (`ConfidenceIntervalWidth`) is a direct measure of estimate precision and is the recommended stopping criterion.

### Psychometric function choice

The psychometric function is the mathematical shape of the detection curve. Three options are available via `PsychometricFunction`:

| Shape | Formula (base CDF) | θ meaning | Best used when… |
|---|---|---|---|
| **Logistic** (default) | `1 / (1 + exp(-slope·(x−θ)))` | 50% base-CDF point | Most go/no-go or yes/no detection tasks; symmetric response distribution |
| **Normal** | `Φ(slope·(x−θ))` | Mean; slope = 1/σ | Intensity discrimination; when underlying variable is Gaussian |
| **Weibull** | `1 − exp(−(x/θ)^slope)` | Scale (~63.2% base-CDF) | Psychoacoustic tasks where x is in linear (not dB) units; modulation depth |

> **Weibull note:** θ for the Weibull is a scale parameter, not the 50% threshold. Always use `ThresholdAtTarget` (with an appropriate `TargetProbability`) rather than `ThresholdEstimate` directly when the Weibull is selected.

For most behavioural paradigms with a binary (yes/no or go/no-go) response, **Logistic** is the safest default.

### Key parameters and their effects

#### `Range` *(required)*

Sets the minimum and maximum stimulus levels the algorithm considers. Keep it wide enough to bracket the true threshold. If the range is too narrow the estimate will be forced against the boundary and will be biased.

> **Tip:** A common starting point for dB SPL tasks is a range about 40–60 dB wide and centred near your expected threshold. If the subject's true threshold might fall anywhere from 10 to 70 dB SPL, set `Range = [0 80]`.

#### `GuessRate`

The probability of a positive response at an inaudible stimulus level (lower asymptote, γ). This accounts for chance-level performance:

- **Yes/no or go/no-go tasks:** leave at `0` (default). The subject should not respond to silence.
- **2-AFC tasks:** set to `0.5`. The subject picks one of two intervals by chance, so they are correct 50% of the time even with no signal.

Setting this incorrectly will bias the threshold estimate. For a 2-AFC task with `GuessRate=0`, the estimated threshold will be pushed to a level that only produces ~50% performance rather than the true 75% point.

#### `LapseRate`

The probability that the subject fails to respond to a clearly detectable stimulus (upper asymptote offset, λ). A small non-zero value (e.g. `0.02–0.05`) accounts for inattentive trials and prevents the fitted curve from ever reaching 100%, which makes the estimate more robust. Leave at `0` (default) for clean, well-trained subjects.

#### `TargetProbability`

The proportion correct for which `ThresholdAtTarget` is reported. This is a **reporting output only** — it does not affect where the next stimulus is placed.

| Task | Typical value | Meaning |
|---|---|---|
| Yes/no detection | `0.5` | 50% point of the base curve |
| 2-AFC detection | `0.75` | Midpoint between chance (50%) and perfect (100%) |
| Yes/no with d′ = 1 criterion | `0.794` | ~79.4% correct for Gaussian model |

#### `Slope` / `EstimateSlope`

The slope controls how steeply the psychometric function rises around θ. A steeper slope means the subject transitions sharply from near-zero to near-perfect performance over a small stimulus range; a shallower slope means the transition is gradual.

- **`EstimateSlope = false`** (default): the slope is fixed at `Slope`. Only θ is estimated. This converges faster and requires fewer trials, but you must provide a reasonable slope assumption. Starting values of `1–5` are typical for behavioural audiograms.
- **`EstimateSlope = true`**: both θ and slope are jointly estimated over a 2-D grid. This requires more trials (~40+) before the estimates stabilise but makes no assumption about the slope.

> **Tip:** If the assumed slope is much shallower than reality, early estimates will be noisy and `NextLevel` may wander. Running a few pilot trials first to gauge the slope is worthwhile before committing to a fixed value.

#### `ConfidenceLevel`

Coverage of the profile log-likelihood confidence interval (default `0.95`, i.e. 95%). The interval is computed from the region of the log-likelihood curve within a chi-squared threshold of the peak. A **wider** interval means there is more uncertainty in the estimate; a **narrower** interval means the estimate has converged. Use `Results.ConfidenceIntervalWidth` as a stopping criterion.

#### `GridResolution`

Number of candidate threshold values tested during each MLE update (default `1000`). Higher values produce a smoother log-likelihood curve and slightly more precise estimates but take longer to compute. Values of 500–2000 are appropriate for most tasks.

### Setting up for common paradigms

**Go/no-go pure-tone detection**
```matlab
bp = psychophysics.BestPEST(RUNTIME, Parameter, ...
    Range=[-80 0], ...        % dB attenuation; 0 = max level, -80 = near silence
    GuessRate=0, ...
    LapseRate=0.02, ...
    TargetProbability=0.5);
```

**2-AFC tone-in-noise detection**
```matlab
bp = psychophysics.BestPEST(RUNTIME, Parameter, ...
    Range=[0 60], ...         % dB SNR
    GuessRate=0.5, ...        % chance performance in a forced-choice task
    TargetProbability=0.75);  % standard 2-AFC criterion
```

**Modulation depth detection (Weibull on linear scale)**
```matlab
bp = psychophysics.BestPEST(RUNTIME, Parameter, ...
    Range=[0.01 1.0], ...     % modulation depth, linear units
    PsychometricFunction="Weibull", ...
    GuessRate=0.5, ...
    TargetProbability=0.75);
% Use Results.ThresholdAtTarget, not Results.ThresholdEstimate, for the threshold
```

**Offline analysis of saved data**
```matlab
bp = psychophysics.BestPEST(DATA, 'Depth', ...
    Range=[-60 0], GuessRate=0.5, TargetProbability=0.75);
fprintf('Threshold: %.1f dB (CI: %.1f–%.1f)\n', ...
    bp.Results.ThresholdAtTarget, ...
    bp.Results.ConfidenceInterval(1), ...
    bp.Results.ConfidenceInterval(2));
```

### Reading the results

After each trial `bp.Results` is automatically updated. The key fields are:

| Field | What to use it for |
|---|---|
| `NextLevel` | **Feed this to the next trial's parameter value.** Always within `Range`. |
| `ThresholdEstimate` | The current best guess for θ. For Logistic/Normal this is the 50% point of the fitted curve. |
| `ThresholdAtTarget` | The stimulus level that produces `TargetProbability`. Use this as your reported threshold. |
| `ConfidenceIntervalWidth` | How uncertain the estimate is. Use this as a stopping criterion. |
| `ConfidenceInterval` | `[lower, upper]` bounds on `ThresholdEstimate`. |
| `TrialCount` | Number of trials contributing to the current estimate. |

`ThresholdEstimate` and `ThresholdAtTarget` give the same answer for a symmetric function (Logistic or Normal) when `TargetProbability = 0.5` and `GuessRate = LapseRate = 0`. They differ when asymmetric boundaries are set or when using the Weibull.

### When to stop the experiment

There is no built-in automatic stopping. The recommended approach is to check `ConfidenceIntervalWidth` after each trial block:

```matlab
% Stop when the 95% CI is narrower than 2 dB
if bp.Results.ConfidenceIntervalWidth < 2.0
    % End the block
end
```

As a rough guide, for typical behavioural detection tasks:

| Trials | `ConfidenceIntervalWidth` (approximate) |
|---|---|
| 10 | 10–30+ stimulus units (highly variable) |
| 30 | 5–15 stimulus units |
| 60 | 2–5 stimulus units |
| 100+ | < 2 stimulus units |

These figures depend strongly on the slope of the psychometric function and the true lapse rate.

### When to use Best PEST vs. Staircase

| Consideration | Best PEST | Staircase |
|---|---|---|
| Statistical efficiency | Higher — uses all trials | Lower — only reversals count |
| Minimum useful trials | ~20–40+ | ~6+ |
| Requires a slope assumption? | Yes (unless `EstimateSlope=true`) | No |
| Works with `GuessRate ≠ 0`? | Yes | Not natively |
| Confidence interval? | Yes | No |
| Slope estimate? | Optional | No |
| Computational cost | Low–moderate | Negligible |

Best PEST is preferred for longer sessions where statistical efficiency matters. Staircase is simpler and may be appropriate for quick screening or when you prefer not to commit to a psychometric function shape.

---

## Developer Reference

### Class hierarchy

```
handle
 └── matlab.mixin.SetGet
      └── psychophysics.Psych   (abstract base; provides DATA, RUNTIME, Helper, refresh)
           └── psychophysics.BestPEST
```

`psychophysics.Psych` provides:

| Member | Description |
|---|---|
| `DATA` | Growing struct array of per-trial records |
| `RUNTIME` | Attached Runtime object (online mode) |
| `Helper` | `epsych.Helper` for event broadcasting |
| `refresh()` | Calls `recomputeResults_()`, then notifies `Results PostSet` listeners |
| `update_data(~, evt)` | `NewData` listener callback; stores new trial, then calls `refresh()` |
| `parameterFieldName_()` | Resolves the tracked parameter field name from `DATA` |
| `bitMaskToTrialTypeValue_(bit)` | Converts `epsych.BitMask.TrialType_N` to integer N |
| `resolveRespCodeField_(data)` | Finds the `RespCode`/`ResponseCode` field in a DATA slice |

### Constructor

```matlab
bp = psychophysics.BestPEST(source, Parameter, Range=[min max])
bp = psychophysics.BestPEST(source, Parameter, Range=[min max], Name=Value)
```

| Argument | Type | Description |
|---|---|---|
| `source` | Runtime object **or** DATA struct array | Online or offline mode |
| `Parameter` | Parameter object **or** string | Field to extract as stimulus level |
| `Range` | `(1,2) double` | **Required.** `[min max]` of the stimulus variable |

All other inputs are name-value pairs matching the properties below.

**Online mode** — pass a Runtime object. A listener is attached to `RUNTIME.HELPER` `'NewData'` and `refresh()` is called automatically after each trial.

**Offline mode** — pass a DATA struct array directly. `refresh()` is called immediately in the constructor; no listener is attached.

```matlab
% Online — attaches to runtime event stream
bp = psychophysics.BestPEST(RUNTIME, Parameter, Range=[-40 0], GuessRate=0.5);

% Offline — analyze a saved DATA struct immediately
bp = psychophysics.BestPEST(DATA, 'Depth', ...
    Range=[-60 0], PsychometricFunction="Weibull", ...
    GuessRate=0.5, TargetProbability=0.75);
```

### Properties reference

All properties are `SetObservable`. GUI components may attach `PostSet` listeners to respond to runtime changes.

#### Stimulus range

| Property | Type | Default | Description |
|---|---|---|---|
| `Range` | `(1,2) double` | `[0 1]` | `[min max]` of the stimulus variable |

#### Psychometric model

| Property | Type | Default | Description |
|---|---|---|---|
| `PsychometricFunction` | string | `"Logistic"` | `"Logistic"`, `"Normal"`, or `"Weibull"` |
| `Slope` | `(1,1) double` | `1` | Fixed slope when `EstimateSlope=false` |
| `EstimateSlope` | logical | `false` | Joint 2-D MLE over θ × slope |
| `SlopeRange` | `(1,2) double` | `[0.1 10]` | Slope search range (used only when `EstimateSlope=true`) |
| `SlopeGridResolution` | integer | `50` | Slope grid points (used only when `EstimateSlope=true`) |
| `GuessRate` | `(1,1) double` | `0` | Lower asymptote γ; set `0.5` for 2-AFC |
| `LapseRate` | `(1,1) double` | `0` | Upper asymptote offset λ |

#### Estimation control

| Property | Type | Default | Description |
|---|---|---|---|
| `GridResolution` | integer | `1000` | Threshold axis grid points |
| `TargetProbability` | `(1,1) double` | `0.5` | Probability for `ThresholdAtTarget` output |
| `ConfidenceLevel` | `(1,1) double` | `0.95` | Profile log-likelihood CI coverage |

#### Trial classification

| Property | Type | Default | Description |
|---|---|---|---|
| `PositiveResponseBit` | `epsych.BitMask` | `BitMask.Hit` | BitMask identifying a positive (detected) response |
| `StimulusTrialType` | `epsych.BitMask` | `BitMask.TrialType_0` | Only trials matching this type contribute to estimation |
| `CatchTrialType` | `epsych.BitMask` | `BitMask.TrialType_1` | Stored for external use; not consumed internally by BestPEST |
| `ExcludedTrials` | logical mask or indices | `[]` | Trials permanently excluded across all resets |

#### Read-only / dependent

| Property | Description |
|---|---|
| `Results` | Struct of current estimation outputs (see below) |
| `ResetCount` | Number of trials present at the last `reset()` call |

### Results struct reference

`bp.Results` is updated after every trial in online mode, or on construction in offline mode. **Before any trials accumulate** (or after `reset()`), `NextLevel = mean(Range)` and all other fields are `[]` or `0`.

| Field | Type | Description |
|---|---|---|
| `NextLevel` | scalar | **Next recommended stimulus level.** Use this as the stimulus for the next trial. Equal to `ThresholdEstimate`, clamped to `Range`. |
| `ThresholdEstimate` | scalar | ML estimate of θ. For Logistic/Normal: the 50% base-CDF point. For Weibull: the scale parameter (~63.2% base-CDF). |
| `ThresholdAtTarget` | scalar | Stimulus level yielding `TargetProbability`. Analytically derived. `NaN` if the target probability is outside the range achievable given `GuessRate`/`LapseRate`. |
| `SlopeEstimate` | scalar or `[]` | ML slope estimate when `EstimateSlope=true`; `[]` when slope is fixed. |
| `ConfidenceInterval` | `(1,2)` | `[lower upper]` profile log-likelihood CI on `ThresholdEstimate`. |
| `ConfidenceIntervalWidth` | scalar | `diff(ConfidenceInterval)`. Primary stopping criterion. |
| `Grid` | vector or matrix | Threshold grid used for MLE. Row vector `(1 × nTheta)` when `EstimateSlope=false`; meshgrid matrix `(nSlope × nTheta)` when `EstimateSlope=true`. |
| `LogLikelihood` | vector or matrix | Normalized log-likelihood (max = 0) over `Grid`. Same shape as `Grid`. Use for plotting the likelihood landscape. |
| `TrialCount` | integer | Number of stimulus trials used in the current estimate (after watermark). |
| `StimulusLevels` | `(1×N) double` | Signal strengths of all included stimulus trials. |
| `Responses` | `(1×N) double` | Binary responses (1 = positive) of all included stimulus trials. |

### Public methods

#### `reset()`

```matlab
bp.reset()
```

Sets a watermark at `numel(bp.DATA)`. All trials recorded before `reset()` are preserved in `DATA` but excluded from all subsequent estimation. `refresh()` is called automatically, so `Results.NextLevel` immediately returns to `mean(Range)`.

Use this when switching from a training block to a test block, after a criterion shift, or to re-run estimation with different parameters on the same session.

```matlab
% After a warmup block, restart estimation and change the target criterion
bp.reset();
bp.Range             = [-60 -10];
bp.TargetProbability = 0.75;
```

Multiple calls to `reset()` are cumulative — each call moves the watermark forward; it cannot be moved backward.

### Integration with trial selection

Trial selection functions query `bp.Results.NextLevel` after each trial to determine the next stimulus. `NextLevel` is always within `Range` (clamped).

```matlab
% Minimal trial-selector pattern
function level = getNextLevel(bp)
    level = bp.Results.NextLevel;
end
```

A more complete pattern that also checks for stopping:

```matlab
function [level, done] = selectTrial(bp, ciThreshold)
    done  = bp.Results.ConfidenceIntervalWidth < ciThreshold;
    level = bp.Results.NextLevel;
    Parameter.Value = level;
end
```

The class does **not** schedule trials or interact with hardware. All parameter setting and hardware communication is handled elsewhere.

### Integration with plotting and GUI components

`bp.Results` exposes all fields needed for standard psychophysical plots.

#### Log-likelihood landscape (1-D, fixed slope)

```matlab
figure;
plot(bp.Results.Grid, bp.Results.LogLikelihood, 'b-');
xline(bp.Results.ThresholdEstimate, '--k', 'ML Threshold');
fill([bp.Results.ConfidenceInterval([1 1 2 2])], ...
     [min(ylim) 0 0 min(ylim)], [0.85 0.85 1], ...
     'EdgeColor','none', 'FaceAlpha',0.4);
xlabel('Stimulus Level'); ylabel('Log-likelihood (normalized)');
```

#### Log-likelihood landscape (2-D, joint slope estimation)

When `EstimateSlope=true`, `Grid` and `LogLikelihood` are both `(nSlope × nTheta)` matrices:

```matlab
thetaVec = bp.Results.Grid(1, :);     % first row → all θ values
slopeVec = bp.Results.Grid(:, 1);     % first column → all slope values
imagesc(thetaVec, slopeVec, bp.Results.LogLikelihood);
axis xy; colormap hot;
xlabel('Threshold θ'); ylabel('Slope');
title('Joint log-likelihood');
```

#### Fitted psychometric function overlay

```matlab
theta = bp.Results.ThresholdEstimate;
slope = bp.Results.SlopeEstimate;
if isempty(slope), slope = bp.Slope; end

xFit = linspace(bp.Range(1), bp.Range(2), 500);
pFit = bp.GuessRate + (1 - bp.GuessRate - bp.LapseRate) ./ ...
       (1 + exp(-slope .* (xFit - theta)));  % Logistic

figure;
scatter(bp.Results.StimulusLevels, ...
    bp.Results.Responses + 0.02*randn(size(bp.Results.Responses)), ...
    20, 'k', 'filled', 'MarkerFaceAlpha', 0.3);
hold on;
plot(xFit, pFit, 'b-', 'LineWidth', 2);
xline(bp.Results.ThresholdAtTarget, '--r', sprintf('%.1f', bp.Results.ThresholdAtTarget));
xlabel('Stimulus Level'); ylabel('P(correct)');
ylim([-0.1 1.1]);
```

### Online mode — event listener pattern

In online mode, `bp.Results` is updated automatically after each `NewData` event fires. GUI components should attach a `PostSet` listener to `Results` to react to updates:

```matlab
hl = addlistener(bp, 'Results', 'PostSet', @(~,~) updateDisplay(bp));

function updateDisplay(bp)
    thresholdLabel.Text = sprintf('Threshold: %.1f', bp.Results.ThresholdAtTarget);
    ciLabel.Text        = sprintf('CI width:  %.2f', bp.Results.ConfidenceIntervalWidth);
end
```

To rebuild the estimation grid when `Range` changes at runtime:

```matlab
addlistener(bp, 'Range', 'PostSet', @(~,~) bp.refresh());
```

Changes to `SetObservable` properties trigger a `PostSet` event but do **not** automatically call `refresh()`. Call `bp.refresh()` explicitly after programmatic property changes if an immediate estimate update is needed.

### Internal architecture

The class is split across five files in `obj/+psychophysics/@BestPEST/`:

| File | Role |
|---|---|
| `BestPEST.m` | Class definition — properties, constructor, `reset()`, `emptyResults_()`, method stubs |
| `recomputeResults_.m` | Protected override of `Psych` abstract method — orchestrates the full estimation pipeline |
| `computeLogLikelihood_.m` | Grid-based MLE; 1-D (fixed slope) or 2-D (joint θ + slope); profile CI |
| `evaluatePsychFn_.m` | Evaluates `P(x; θ, slope)` with γ/λ; broadcast-compatible arrays |
| `invertPsychFn_.m` | Analytically inverts `P` to recover `x` at a target probability |

#### `recomputeResults_` pipeline

Called by `Psych.refresh()` after each trial (online) or on construction (offline):

```
DATA
 └─ apply watermark (resetCount_)
     └─ filter by StimulusTrialType (TrialType field, or BitMask.decode fallback)
         └─ extract stimLevels (unwrap .Value containers), binary responses
             └─ computeLogLikelihood_   →  logL, thetaGrid, slopeGrid, ci
                 └─ argmax(logL)        →  ThresholdEstimate [, SlopeEstimate]
                     ├─ clamp to Range  →  NextLevel
                     └─ invertPsychFn_  →  ThresholdAtTarget
```

### Log-likelihood and confidence interval computation

`computeLogLikelihood_` builds a grid over `Range` with `GridResolution` points and evaluates the log-likelihood of the entire response history at each grid point via vectorized broadcasting:

$$\ell(\theta_j) = \sum_i \left[ r_i \log P(x_i;\theta_j) + (1-r_i)\log(1-P(x_i;\theta_j)) \right]$$

The grid is normalized so `max(logL) = 0`. This makes the CI threshold a universal constant regardless of session length:

```
logL_threshold = −chi2inv(ConfidenceLevel, 1) / 2
```

The CI spans all grid points where `logL ≥ logL_threshold`.

### 2-D slope estimation mode

When `EstimateSlope=true`, the computation expands to a 2-D grid of `(nSlope × nTheta)` points:

```matlab
[thetaGrid, slopeGrid] = meshgrid(thetaVec, slopeVec);
% P evaluated over (nSlope × nTheta × nTrials), sum over trials axis
% logL result is (nSlope × nTheta)
```

The ML estimates are the row and column indices of `max(logL(:))`. The CI is computed from the **profile log-likelihood** — the maximum of `logL` over the slope axis at each θ — so it remains a 1-D interval on θ.

In `bp.Results` with `EstimateSlope=true`:
- `Grid` is an `(nSlope × nTheta)` meshgrid matrix.
- `LogLikelihood` is an `(nSlope × nTheta)` matrix.
- `SlopeEstimate` is the ML slope value (scalar).

Extract vectors for plotting:
```matlab
thetaVec = bp.Results.Grid(1, :);   % row 1 → all θ values
slopeVec = bp.Results.Grid(:, 1);   % column 1 → all slope values
```

### Reset and watermark mechanism

`resetCount_` is a private scalar lower-bound index into `DATA`. `recomputeResults_` operates on `DATA(resetCount_+1 : end)`. Calling `reset()` sets `resetCount_ = numel(DATA)`, making the active window empty until new trials arrive.

`ExcludedTrials` (set on the `Psych` base) applies a permanent mask before the watermark. Excluded trials are never seen by `recomputeResults_` regardless of resets.

### Stopping criterion

There is no automatic stopping. Recommended patterns:

```matlab
% Stop when 95% CI width drops below 2 stimulus units
if bp.Results.ConfidenceIntervalWidth < 2.0
    endBlock();
end

% Stop after a fixed trial count
if bp.Results.TrialCount >= 80
    endBlock();
end
```

### Performance notes

Computation is fully vectorized and runs once per trial. Approximate timings on a modern desktop:

| `GridResolution` | `EstimateSlope` | `SlopeGridResolution` | Time per trial |
|---|---|---|---|
| 1000 | false | — | < 1 ms |
| 2000 | false | — | < 2 ms |
| 1000 | true | 50 | ~10–20 ms |
| 2000 | true | 100 | ~50–100 ms |

For online use with trial rates faster than ~5/s, keep `GridResolution ≤ 1000` and `SlopeGridResolution ≤ 50`, or disable joint slope estimation.

### Edge cases and error handling

| Situation | Behaviour |
|---|---|
| `DATA` is empty or all trials are before the watermark | `Results = emptyResults_()`, `NextLevel = mean(Range)` |
| No trials match `StimulusTrialType` | Same as above |
| `RespCode`/`ResponseCode` field absent | `Results = emptyResults_()`; no error thrown |
| `TargetProbability` unreachable given `GuessRate`/`LapseRate` | `ThresholdAtTarget = NaN`; warning logged via `vprintf(0,1,...)` |
| All stimulus levels are identical (flat likelihood) | MLE returns `mean(Range)`; CI spans `Range` |
| `EstimateSlope=true` with very few trials (<~20) | 2-D likelihood is flat; estimates are unstable until sufficient trials accumulate |
