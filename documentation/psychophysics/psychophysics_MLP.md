# MLP — Three-Parameter Maximum Likelihood Psychometric Function Estimation

`psychophysics.MLP`  
Source: `obj/+psychophysics/@MLP/`  
Reference: Shen, Y. and Richards, V.M. (2012). A maximum-likelihood procedure for estimating psychometric functions: Thresholds, slopes, and lapses of attention. *J. Acoust. Soc. Am.*, 132(2), 957–967.

---

## Contents

- [Overview for Users](#overview-for-users)
  - [What it does](#what-it-does)
  - [How it works — the short version](#how-it-works--the-short-version)
  - [The three parameters it estimates](#the-three-parameters-it-estimates)
  - [Sweet points — how stimuli are placed](#sweet-points--how-stimuli-are-placed)
  - [Sweet-point selection rules](#sweet-point-selection-rules)
  - [Psychometric function choice](#psychometric-function-choice)
  - [Key parameter effects and tuning guide](#key-parameter-effects-and-tuning-guide)
  - [MLP vs. BestPEST — when to use each](#mlp-vs-bestpest--when-to-use-each)
- [Developer Reference](#developer-reference)
  - [Class hierarchy](#class-hierarchy)
  - [Constructor](#constructor)
  - [All properties](#all-properties)
  - [Results struct](#results-struct)
  - [Public methods](#public-methods)
  - [Integration with trial selection](#integration-with-trial-selection)
  - [Integration with plotting / GUI components](#integration-with-plotting--gui-components)
  - [Internal architecture](#internal-architecture)
  - [Reset and watermark mechanism](#reset-and-watermark-mechanism)
  - [Weibull parameterization notes](#weibull-parameterization-notes)
  - [Performance considerations](#performance-considerations)

---

## Overview for Users

### What it does

MLP simultaneously estimates three properties of a psychometric function — **threshold**, **slope**, and **lapse rate** — using a Bayesian maximum-likelihood procedure. After every trial it updates its internal probabilistic model and places the next stimulus at the most informative signal level for the weakest-constrained parameter. This allows the experiment to converge on accurate estimates of the full shape of the psychometric function, not just the threshold.

Compared to BestPEST (which only estimates threshold, holding slope and lapse fixed), MLP is better when:
- You do not know the slope in advance and want the data to determine it.
- You have reason to believe attention lapses occur and want a robust threshold estimate that accounts for them.
- You want to characterize a full psychometric function (threshold + slope + lapse) rather than just a threshold.

### How it works — the short version

1. **Before any trials** — a prior belief about threshold (α), slope (β), and lapse (λ) is initialized as a 3D probability grid. The first stimulus is placed at the prior mean of the threshold.
2. **After each trial** — the subject's response (correct/incorrect) updates the probability grid via Bayes' rule. Grid cells that predict the observed responses well gain probability; cells that predict poorly lose it.
3. **Parameter estimates** — the grid cell with the highest probability (the MAP/ML estimate) gives the current best estimates of α, β, and λ.
4. **Sweet points** — from those estimates, the algorithm computes up to four signal strengths that would minimise the uncertainty of each parameter if tested next.
5. **Next stimulus** — one of those sweet points is chosen (randomly, or via an N-down M-up rule) and placed as `Results.NextLevel` for the trial-selection system to use.

This cycle repeats for every new trial. The probability grid narrows and sharpens around the true parameter values as data accumulate.

### The three parameters it estimates

| Parameter | Symbol | Meaning | Where to look in Results |
|---|---|---|---|
| Threshold | α (alpha) | Signal level at the midpoint of the psychometric function | `AlphaEstimate` |
| Slope | β (beta) | Steepness of the transition from guessing to perfect performance | `BetaEstimate` |
| Lapse rate | λ (lambda) | Probability of missing a clearly suprathreshold stimulus (inattention) | `LapseEstimate` |

The guess rate γ (lower asymptote, e.g. 0.5 for 2-AFC) is **fixed** and not estimated.

### Sweet points — how stimuli are placed

A "sweet point" is a signal strength that provides maximum statistical information about a specific parameter. It is defined as the stimulus level minimising the expected estimation variance for that parameter:

$$\sigma^2_\theta(x) = \frac{P(x)\,(1 - P(x))}{\left(\partial P / \partial \theta\right)^2}$$

The lower this quantity, the more information a trial at level *x* conveys about parameter θ.

**Logistic function — four sweet points:**

| Index | Sweet point | Purpose | Typical P(correct) |
|---|---|---|---|
| 1 | Lower β-sweet | Constrains slope (below threshold) | < 0.5 |
| 2 | α-sweet | Constrains threshold | ≈ 0.5–0.79 |
| 3 | Upper β-sweet | Constrains slope (above threshold) | > 0.79 |
| 4 | λ-sweet | Constrains lapse (= `MaxSignalStrength`) | ≈ 1 − λ |

**Weibull function — three sweet points:**

| Index | Sweet point | Purpose |
|---|---|---|
| 1 | k-sweet | Constrains scale parameter k |
| 2 | β-sweet | Constrains slope |
| 3 | λ-sweet | Constrains lapse (= `MaxSignalStrength`) |

Sweet points are recomputed after every trial as the parameter estimates refine.

### Sweet-point selection rules

#### `"Random"` (default)
On each trial one of the sweet points is drawn at random with equal probability. This samples all parameters proportionally across the session. Recommended when you have no strong expectation about which parameter needs the most data, or for shorter sessions.

#### `"UpDown"`
Implements an N-down M-up staircase that cycles through the ordered sweet points (low signal → high signal). By default `UpDownRule = [4 1]`:
- After **4 consecutive correct** responses → step *down* one sweet-point level (harder).
- After **1 incorrect** response → step *up* one sweet-point level (easier).

The procedure starts at the highest (λ-sweet, `MaxSignalStrength`) sweet point. This front-loads suprathreshold trials that quickly anchor the lapse estimate before moving toward the more informative middle sweet points.

`"UpDown"` converges on the sweet points that are most consistent with the subject's current performance and can be more efficient than `"Random"` for long sessions, particularly when the slope or lapse rate is the least-constrained parameter.

### Psychometric function choice

| Function | Formula | When to use |
|---|---|---|
| **Logistic** (default) | $P = \gamma + \frac{1-\gamma-\lambda}{1 + e^{-\beta(x-\alpha)}}$ | Most detection and discrimination tasks; symmetric S-shaped curve |
| **Weibull** | $P = \gamma + (1-\gamma-\lambda)(1 - k^{x^\beta})$ | Tasks in linear intensity units where a compressive nonlinearity is expected; α maps to scale parameter k ∈ (0, 1) |

For most behavioural tasks, **Logistic is the right choice**. The Weibull option requires careful attention to the `AlphaRange` and `MaxSignalStrength` parameters (see the [Weibull note](#weibull-parameterization-notes) in the developer section).

### Key parameter effects and tuning guide

#### `AlphaRange` *(required)*
The search window for the threshold. Must bracket the true threshold — if the true threshold falls outside this range the estimate will be pinned against the boundary.

> **Tip:** For an audiogram in dB SPL, `AlphaRange = [10 70]` is a reasonable starting point. For detection in linear units (Weibull), `AlphaRange` is the range for the scale parameter k and should be set to something like `[0.01 0.99]`.

#### `AlphaPriorMean` / `AlphaPriorStd`
The Gaussian prior on α. If left at `NaN` (default), `AlphaPriorMean` is set to the centre of `AlphaRange` and `AlphaPriorStd` to `diff(AlphaRange)/4`. Narrowing the prior (smaller `AlphaPriorStd`) focuses the early trials near the expected threshold but can bias the estimate if the prior is wrong. Widening it (larger `AlphaPriorStd`) makes the prior more diffuse and lets the data dominate sooner.

> **Rule of thumb:** A standard deviation of about 1/4 of the range width is a weakly informative prior that will not distort the estimate unless the true value is unusual.

#### `BetaRange` / `BetaPriorMean` / `BetaPriorStd`
Controls the prior on slope. The default prior (mean = 1, std = 0.75) was chosen in Shen & Richards (2012) for typical psychoacoustic slope values. If your task is known to produce steeper or shallower slopes, shift `BetaPriorMean` accordingly. A typical behavioural audiogram slope in the Logistic parameterization is in the range 1–3 dB⁻¹.

#### `LapseRange` / `LapsePriorMean` / `LapsePriorStd`
Controls the prior on the lapse rate. The default `[0 0.2]` allows up to 20% lapses. If your subject reliably performs well (e.g., highly trained animal), you can narrow this to `[0 0.05]`. A wider range is appropriate for clinical populations or inattentive observers. The default prior (mean = 0, std = 0.1) weakly expects low lapse rates.

#### `GuessRate`
The fixed lower asymptote γ. Set to:
- `0` — yes/no or go/no-go tasks (default)
- `0.5` — 2-AFC tasks where chance = 50%
- `1/n` — n-AFC tasks

#### `MaxSignalStrength`
The signal level used as the λ-sweet (catch/lapse) probe. It defaults to `AlphaRange(2)` but ideally should be set to a clearly suprathreshold level (e.g., the maximum output of your transducer). Setting it too low means lapse-estimation trials are not genuinely suprathreshold; setting it too high wastes effort on levels already known to be detectable.

#### `SweetPointGridResolution`
Number of x values searched when computing sweet points (default 1000). Reduce to ~200 for faster performance at some precision cost. Increase only if you observe discontinuities in the reported sweet points across trials.

#### `AlphaResolution` / `BetaResolution` / `LapseResolution`
Number of grid points in each parameter dimension (defaults: 21 × 10 × 5 = 1050 total cells). The defaults match the paper and give good accuracy at minimal computational cost. Increasing these values refines the estimate at the cost of more memory and compute time — for offline analysis you might use 41 × 20 × 10 for a finer grid.

### MLP vs. BestPEST — when to use each

| Consideration | MLP | BestPEST |
|---|---|---|
| Parameters estimated | α, β, λ jointly | α only (β and λ fixed) |
| Minimum useful trials | ~50–100 for stable β and λ | ~20–40 for α |
| Requires slope assumption? | No | Yes |
| Accounts for lapse rate? | Yes (estimated) | Yes (fixed by `LapseRate`) |
| 2-AFC support | Yes (`GuessRate=0.5`) | Yes (`GuessRate=0.5`) |
| Returns full psychometric curve? | Yes (`FittedPsychFn`) | Yes |
| Sweet-point targeting? | Yes — up to 4 sweet points | No — always at current α estimate |

**Use MLP** when you want to characterize the full psychometric function or when the slope is unknown. **Use BestPEST** for fast threshold screening with a known (or assumed) slope.

---

## Developer Reference

### Class hierarchy

```
handle
    └── psychophysics.Psych   (abstract base)
            └── psychophysics.MLP
```

`psychophysics.Psych` provides:
- `DATA` — growing struct array of per-trial records
- `RUNTIME` — attached Runtime object (online mode only)
- `refresh()` — calls `recomputeResults_()` and notifies listeners
- `update_data(~, event)` — `NewData` listener that triggers `refresh()`
- `StimulusTrialType`, `CatchTrialType` — `epsych.BitMask` identifiers
- Protected helpers: `bitMaskToTrialTypeValue_()`, `parameterFieldName_()`, `resolveRespCodeField_()`

### Constructor

```matlab
mlp = psychophysics.MLP(source, Parameter, AlphaRange=[-20 0])
mlp = psychophysics.MLP(source, Parameter, AlphaRange=[-20 0], Name=Value, ...)
```

`source` is either a Runtime object (online mode — MLP attaches a `NewData` listener and auto-updates) or a DATA struct array (offline mode — MLP calls `refresh()` immediately in the constructor).

`Parameter` is either a `hw.Parameter` object (online) or a string field name within the DATA struct (offline).

`AlphaRange` is the only required name-value argument. All other parameters have sensible defaults.

After construction, `Results.NextLevel` is available immediately and equals `AlphaPriorMean` (the prior mean of the threshold). In online mode the trial-selector should read `Results.NextLevel` before each trial.

### All properties

#### Parameter search ranges

| Property | Default | Description |
|---|---|---|
| `AlphaRange` | `[0 1]` | `[min max]` of the threshold (α) search grid. **Required** — set to bracket the expected threshold. |
| `BetaRange` | `[0.2 2]` | `[min max]` of the slope (β) search grid. Must be positive. |
| `LapseRange` | `[0 0.2]` | `[min max]` of the lapse rate (λ) grid. Must be non-negative. |

#### Grid resolutions

| Property | Default | Description |
|---|---|---|
| `AlphaResolution` | `21` | Number of α grid points. |
| `BetaResolution` | `10` | Number of β grid points. |
| `LapseResolution` | `5` | Number of λ grid points. |

#### Prior parameters

| Property | Default | Description |
|---|---|---|
| `AlphaPriorMean` | `NaN → mean(AlphaRange)` | Mean of Gaussian prior on α. |
| `AlphaPriorStd` | `NaN → diff(AlphaRange)/4` | Std of Gaussian prior on α. |
| `BetaPriorMean` | `1` | Mean of Gaussian prior on β. |
| `BetaPriorStd` | `0.75` | Std of Gaussian prior on β. |
| `LapsePriorMean` | `0` | Mean of Gaussian prior on λ. |
| `LapsePriorStd` | `0.1` | Std of Gaussian prior on λ. |

#### Psychometric function

| Property | Default | Description |
|---|---|---|
| `PsychometricFunction` | `"Logistic"` | `"Logistic"` or `"Weibull"`. |
| `GuessRate` | `0` | Fixed lower asymptote γ. Set `0.5` for 2-AFC. |

#### Stimulus placement

| Property | Default | Description |
|---|---|---|
| `MaxSignalStrength` | `NaN → AlphaRange(2)` | Signal level used as the λ-sweet proxy and upper bound for sweet-point search. |
| `SweetPointRule` | `"Random"` | `"Random"` or `"UpDown"`. |
| `UpDownRule` | `[4 1]` | `[N M]` for N-down M-up rule. Applies only when `SweetPointRule = "UpDown"`. |
| `SweetPointGridResolution` | `1000` | Number of x-grid points for numerical sweet-point computation. |

#### Response coding

| Property | Default | Description |
|---|---|---|
| `PositiveResponseBit` | `epsych.BitMask.Hit` | BitMask flag identifying a correct response in DATA records. |
| `StimulusTrialType` | `epsych.BitMask.TrialType_0` | BitMask identifying stimulus (non-catch) trials. |
| `CatchTrialType` | `epsych.BitMask.TrialType_1` | BitMask identifying catch trials. |

#### Read-only

| Property | Description |
|---|---|
| `Results` | Struct populated after each `refresh()`. See [Results struct](#results-struct). |
| `ResetCount` | Trial watermark from the last `reset()` call. Trials at or below this index are excluded from estimation. |

### Results struct

`mlp.Results` is updated automatically after every trial in online mode and after construction in offline mode.

| Field | Type | Description |
|---|---|---|
| `NextLevel` | scalar double | Signal strength recommended for the next trial. Feed to the trial-selector. Initialized to `AlphaPriorMean` before any trials. |
| `AlphaEstimate` | scalar double | Current ML estimate of threshold α. |
| `BetaEstimate` | scalar double | Current ML estimate of slope β. |
| `LapseEstimate` | scalar double | Current ML estimate of lapse rate λ. |
| `SweetPoints` | 4×1 or 3×1 double | Sweet-point signal strengths, sorted ascending (4 for Logistic, 3 for Weibull). |
| `SweetPointPcorrect` | 4×1 or 3×1 double | Predicted proportion correct at each sweet point under the ML parameters. |
| `CurrentSweetPointIndex` | scalar double | Index into `SweetPoints` that was selected for the next trial (UpDown rule). |
| `Posterior` | nα×nβ×nλ double | Normalized probability over the parameter grid. Useful for uncertainty visualization. |
| `FittedPsychFn` | struct | Fitted curve for plotting: `.x` (1×200 signal strengths) and `.P` (1×200 predicted P(correct)). |
| `TrialCount` | scalar double | Number of active stimulus trials used in the current estimate. |
| `StimulusLevels` | 1×nTrials double | Signal strengths of all active stimulus trials. |
| `Responses` | 1×nTrials double | Binary responses (1 = correct, 0 = incorrect) for all active stimulus trials. |

All fields are `[]` (or `0` for `TrialCount`) before any active trials are available.

### Public methods

#### `mlp.reset()`
Watermarks all current trials and restarts estimation. Subsequent calls to `refresh()` treat the next trial as the first. Also resets the UpDown staircase state (`sweetPointIdx_`, streaks). Does **not** delete DATA.

Useful when changing experimental conditions mid-session without losing the trial record.

### Integration with trial selection

The typical online integration pattern:

```matlab
% At experiment setup
mlp = psychophysics.MLP(RUNTIME, Parameter, ...
    AlphaRange = [-20 0], ...
    GuessRate  = 0.5, ...
    BetaPriorMean = 1.5, ...
    SweetPointRule = "UpDown");

% In the trial-selector (called before each trial)
nextLevel = mlp.Results.NextLevel;  % read the recommended level
Parameter.Value = nextLevel;        % apply to the Parameter object
```

In **offline mode** the same interface applies after loading a saved session:

```matlab
mlp = psychophysics.MLP(DATA, 'Level', AlphaRange=[-20 0], GuessRate=0.5);
% mlp.Results is populated immediately
nextLevel   = mlp.Results.NextLevel;
alphaHat    = mlp.Results.AlphaEstimate;
lapseHat    = mlp.Results.LapseEstimate;
```

Because `Results` is a `SetAccess = protected` struct property, subscribe to `PostSet` events to react to updates without polling:

```matlab
addlistener(mlp, 'Results', 'PostSet', @myUpdateCallback);
```

`psychophysics.Psych` also fires a `ResultsUpdated` event (if defined) via `notifyDataUpdate_()` after every `refresh()` cycle.

### Integration with plotting / GUI components

`Results.FittedPsychFn` provides ready-to-use x/P vectors:

```matlab
curve = mlp.Results.FittedPsychFn;
plot(curve.x, curve.P);
xlabel('Signal level');
ylabel('P(correct)');
hold on

% Overlay sweet points
sp  = mlp.Results.SweetPoints;
spp = mlp.Results.SweetPointPcorrect;
plot(sp, spp, 'ro', 'MarkerFaceColor', 'r');

% Mark the threshold estimate
xline(mlp.Results.AlphaEstimate, '--k', 'alpha estimate');
```

To visualize the **posterior uncertainty** over the threshold (marginalizing over β and λ):

```matlab
post    = mlp.Results.Posterior;       % (nAlpha x nBeta x nLapse)
alphaVec = linspace(mlp.AlphaRange(1), mlp.AlphaRange(2), mlp.AlphaResolution);
margAlpha = sum(post, [2 3]);          % sum over beta and lapse dimensions
margAlpha = margAlpha / sum(margAlpha);
plot(alphaVec, margAlpha);
xlabel('\alpha'); ylabel('Marginal posterior');
```

Similarly marginalise over dimensions 1 and 3 for β, or 1 and 2 for λ.

For a real-time plot that updates every trial, wire a `PostSet` listener on `Results` to a redraw function and use the same plotting code above.

### Internal architecture

All estimation logic is split across four private methods:

| Method | Responsibility |
|---|---|
| `evaluatePsychFn_(obj, x, alpha, beta, lapse)` | Evaluate P(x; α, β, γ, λ) for any broadcast-compatible array shapes. Handles both Logistic and Weibull. Output clamped to `[eps, 1-eps]`. |
| `computePosterior_(obj, stimLevels, responses)` | Build the factored 3D Gaussian log-prior, then accumulate the log-likelihood for all trials in a single vectorized `(nTrials × nα × nβ × nλ)` operation. Returns the unnormalized `(nα × nβ × nλ)` log-posterior. |
| `computeSweetPoints_(obj, alphaML, betaML, lapseML)` | Sweep a 1000-point x grid, compute σ²_param(x) via central finite-difference derivatives, and find the minima. Returns 4 (Logistic) or 3 (Weibull) sweet-point signal strengths. |
| `selectNextLevel_(obj, sweetPoints, responses)` | Apply the configured `SweetPointRule`. For `"UpDown"`, maintain streak counters and step the sweet-point index; for `"Random"`, draw uniformly with `randi`. |

`recomputeResults_.m` orchestrates these four steps after extracting active stimulus trials from `DATA` via the watermark and trial-type filtering inherited from `psychophysics.Psych`.

The total grid size for the default resolution is 21 × 10 × 5 = **1,050 cells**. For 200 trials, the full likelihood computation touches 200 × 1,050 ≈ 210 K floating-point values — all vectorized, with no per-trial loops. Wall time per `refresh()` call is typically under 5 ms on modern hardware.

### Reset and watermark mechanism

`reset()` stores `numel(obj.DATA)` in the private `resetCount_` watermark. `recomputeResults_.m` slices `DATA(resetCount_+1 : end)` to get the active window, so all historical DATA is preserved but excluded from estimation. This allows mid-session re-starts (e.g., after a condition change) without losing the original data record.

Call `reset()` before introducing a new stimulus set or after a block boundary that should start a fresh psychometric function estimate. The next trial's `NextLevel` immediately reflects `AlphaPriorMean` again.

### Weibull parameterization notes

The Weibull option uses the formulation from Shen & Richards (2012) Appendix A4:

$$P(x;\,k,\beta,\gamma,\lambda) = \gamma + (1-\gamma-\lambda)\,(1 - k^{x^\beta})$$

where:
- **k ∈ (0, 1)** is the scale parameter; `AlphaRange` specifies its search range.
- At x = 1, P = γ + (1−γ−λ)(1−k), so k directly sets the proportion correct at unit signal.
- As x → ∞, P → 1−λ (the upper asymptote).

**Practical implications:**
- `AlphaRange` must be within `(0, 1)` (e.g., `[0.001, 0.999]`).
- `MaxSignalStrength` is in signal units (the same units as x), **not** k units. It must be set explicitly; defaulting to `AlphaRange(2) < 1` is almost certainly wrong for a physical signal strength axis.
- The prior parameters `AlphaPriorMean` and `AlphaPriorStd` also refer to k, not to signal strength. A prior mean of k = 0.5 means you expect ~50% reduction per unit signal; adjust based on your knowledge of the task.

### Performance considerations

| Default grid | Cells | Approximate time per refresh |
|---|---|---|
| 21 × 10 × 5 (default) | 1,050 | < 5 ms |
| 41 × 20 × 10 (fine) | 8,200 | < 30 ms |
| 101 × 50 × 20 (very fine) | 101,000 | ~200 ms |

For **online experiments** the default grid is well within the inter-trial interval budget for any realistic paradigm. Fine grids are appropriate for **offline re-analysis** of saved data where compute time is not time-critical.

The sweet-point grid (`SweetPointGridResolution`, default 1000) is swept 4 times per `refresh()` call (two alpha-perturbed and two beta-perturbed evaluations over the x grid). Reducing it to 200–300 cuts that cost with negligible impact on sweet-point precision.
