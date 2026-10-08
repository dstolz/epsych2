# Psychometric Fitting for `psychophysics.Staircase`

## Overview

`psychophysics.Staircase` reports a threshold from the **reversals** of an
adaptive track. This page documents the second answer it can give: a
maximum-likelihood **psychometric fit** to the responses themselves, which
yields a threshold at a criterion you name, a slope, the shape of the
function, and a statement of how well it describes the session.

The two answers are different, and the difference is informative rather than
a discrepancy. A reversal mean is a running average of where the *step rule*
put the stimulus; it converges on whatever proportion the rule targets — a
symmetric 2-down-1-up settles near 70.7 %, not 50 %. A fit uses every scored
trial at every level the session visited, and reports the location parameter
of the function together with the level at any criterion you choose.

Five files implement it, all in `obj/+psychophysics/@Staircase/`:

| Entry point | What it is |
|---|---|
| `S.psychometricCounts(...)` | The staircase's scored trials as per-level counts (and the catch-trial false-alarm rate). What every fit takes: `fitPsychometric` fits it, and `[Levels' NumYes' NumTotal']` is exactly the data matrix psignifit takes (`behavior.fit.Psignifit`). |
| `S.fitPsychometric(...)` | The session-level helper: pulls the staircase's trials, counts them per level, fits, returns. |
| `psychophysics.Staircase.fitProportions(levels, numYes, numTotal, ...)` | The estimator. Pure — counts in, fit out. No object, no runtime, no figure. |
| `psychophysics.Staircase.psychometricFunction(x, alpha, beta, ...)` | The function being fitted. |
| `psychophysics.Staircase.psychometricLevel(P, alpha, beta, ...)` | Its inverse — how a threshold is read off a fit. |

The optimizer is `fminsearch`; the normal CDF and its inverse are `normcdf`
and `norminv`, the χ² tail is `chi2cdf`, the bootstrap resamples with
`binornd` and summarizes with `prctile` — the Statistics Toolbox throughout,
rather than expansions of `erfc` and `gammainc` maintained here.

## Quick start

```matlab
S = psychophysics.Staircase(DATA, 'Depth');
F = S.fitPsychometric();

if F.Converged && F.Identifiable
    fprintf('threshold %.2f, slope %.3f\n', F.Threshold, F.Beta);
else
    fprintf('no usable fit: %s\n', F.Message);
end
```

Plotting the fit over the data it was made from is two lines, because the
result carries both:

```matlab
plot(F.Curve.x, F.Curve.P, 'LineWidth', 1.5); hold on
scatter(F.Levels, F.Proportion, 12*F.NumTotal, 'filled');   % area = trials
xline(F.Threshold, '--');
```

## The function

```
P(x) = gamma + (1 - gamma - lambda) * F(x; alpha, beta)
```

| `Shape` | Base CDF `F` | Notes |
|---|---|---|
| `"Logistic"` (default) | `1 ./ (1 + exp(-beta*(x - alpha)))` | `alpha` is the midpoint. |
| `"Normal"` | `Phi((x - alpha)*beta)` | `beta = 1/sigma`. |
| `"Weibull"` | `1 - exp(-(x/alpha)^beta)` | `alpha > 0`, `x > 0`; `alpha` is the 63.2 % point of the base CDF, not the midpoint. |

`gamma` is the lower asymptote (the guess rate) and `lambda` the offset of the
upper one (the lapse rate). These are the same three shapes with the same
parameterization that [`psychophysics.BestPEST`](psychophysics_BestPEST.md)
uses, so a threshold from either is directly comparable.

A **negative `beta`** gives a decreasing function for the Logistic and Normal
shapes, with `alpha` still the midpoint. That is how `Direction="decreasing"`
is represented — for a parameter where a higher level means *worse*
performance, such as a masker level.

Weibull is defined on `x > 0` only. A nonpositive `x` returns `NaN` rather
than the complex number a fractional power of a negative number would
otherwise produce silently.

## Where the counts come from

`fitPsychometric` (through `psychometricCounts`, which any other fit of the
same trials calls too) scores the staircase's **stimulus** trials — the ones
`StimulusTrialType` selects — with `ExcludedTrials` already removed, so the
fit is always in the units the staircase plot is showing: the parameter's own.

| Response code carries | Counted as |
|---|---|
| `Hit` (and not `Miss`) | yes |
| `Miss` (and not `Hit`) | no |
| `Abort` | left out; `IncludeAborts=true` counts it as a failure to respond (a "no") |
| anything else, including both `Hit` and `Miss` | unscored, and reported in `F.NumUnscored` |

Leaving aborts out is the convention
[`psychophysics.Metrics.rateDenominator`](psychophysics_Metrics.md) states for
every rate in the toolbox: an abort is a lapse of engagement rather than a
wrong answer. `IncludeAborts` changes it, and an included abort never becomes
a yes.

Catch trials are never in the counts. They can, however, supply the lower
asymptote: `GuessFromCatchTrials=true` sets `gamma` to the false alarm rate
on the trials `CatchTrialType` selects, which is the right lower asymptote
for a yes/no detection task where the subject sometimes responds to nothing.
`F.GuessRateSource` says which was used, and a session with no scored catch
trial falls back to `GuessRate` and logs it.

Levels are grouped **exactly** by default: two trials share a level only when
their values are equal. `LevelTolerance` merges levels within an absolute
distance of one another, for a rig whose level accumulates floating-point
drift; the merged level is the mean of the values it stands for.

A level of `NaN` — a trial whose value was not recorded — is dropped and
counted in `F.NumUndefinedLevel`, never treated as zero.

## The threshold criterion is a choice

`ThresholdCriterion` is read on the **between-asymptote** scale by default
(`CriterionScale="relative"`): `0.5` means halfway from `gamma` to
`1 - lambda`. For the Logistic and Normal shapes that is `alpha` itself,
whatever the asymptotes are, and it is always reachable.

`CriterionScale="absolute"` reads it as a raw response proportion instead —
"the 70.7 % level" — and returns `NaN` when that proportion lies outside the
asymptotes rather than extrapolating to it. That NaN is the point: on a 2AFC
task with `GuessRate=0.5`, an absolute criterion of 0.5 is not a threshold at
the midpoint, it is unreachable.

```matlab
F = S.fitPsychometric(ThresholdCriterion=0.707, CriterionScale="absolute");
```

`F.ThresholdCriterionAbsolute` always reports the absolute proportion that
was used, whichever scale it was named on.

## What the fit refuses, and what it flags

An unfittable dataset returns a result whose `Converged` or `Identifiable`
field is `false` and whose `Message` says why. It never returns a
plausible-looking number for data that cannot support one, and it never
throws for a data situation — only for malformed input (`numYes > numTotal`,
mismatched lengths, a matrix where a vector was meant).

**Refused before any optimization**, each an exact statement about the data:

| Situation | Why |
|---|---|
| Fewer than two distinct levels | `alpha` and `beta` are not jointly identified. |
| Every scored trial the same outcome | The likelihood pushes `alpha` to ±∞. |
| Weibull with a nonpositive level | Outside the shape's domain. |
| Weibull with `Direction="decreasing"` | Not a supported combination. |
| `GuessRate` and `LapseRate` leaving no span | There is no function to fit. |

**Fitted, then flagged `Identifiable = false`:**

- **Complete separation** — every level with a "no" lies below every level
  with a "yes" (or above, going the other way). The likelihood then rises
  without bound as the slope steepens, so whatever the optimizer stopped at
  is an artifact of where it ran out of iterations. `F.Separated` says so;
  read the slope as a lower bound on steepness, not an estimate.
- **A flat fit** — the fitted curve varies by less than `MinResponseRange`
  (default 0.05) across the levels actually tested. When the observed
  proportion runs the *other way*, the message says so and names
  `Direction`, which turns a silent non-result into a signpost.

Separately, `F.ThresholdInRange` is `false` when the threshold falls outside
the levels the session tested. That is not a refusal — extrapolating a little
is ordinary — but it is reported, and logged, so it is never invisible.

## Read the slope with care

The levels a staircase visits are chosen *in response to the subject*, so the
trials are not an independent sample of the psychometric function. A
maximum-likelihood fit to adaptive data recovers the **threshold** with
little bias but tends to **overstate the slope** — by a few percent for a
long track and more for a short one (Leek, Hanna & Marshall 1992; Treutwein &
Strasburger 1999; Kaernbach 2001). A slope worth quoting comes from the
method of constant stimuli.

The same caveat applies to the goodness-of-fit statistics. `Deviance` and its
χ² `DeviancePValue` assume enough trials at each level for the χ²
approximation to hold; with one or two trials at most levels — which is what
an adaptive track produces — the p-value is not trustworthy. `F.NumTotal`
shows how many trials stand behind each level, so it is visible.

## Uncertainty

`Bootstrap=N` adds a parametric bootstrap (Wichmann & Hill 2001): binomial
counts are resampled from the fitted curve at the observed levels and refitted
N times, and `F.CI` reports percentile intervals for `Alpha`, `Beta` and
`Threshold`. It is off by default because it costs N complete refits.

```matlab
F = S.fitPsychometric(Bootstrap=1000, ConfidenceLevel=0.95, RandomSeed=7);
fprintf('threshold %.2f [%.2f %.2f]\n', F.Threshold, F.CI.Threshold);
```

Two things to know about that interval. It **conditions on the levels the
session happened to run**: on adaptive data those levels are themselves a
response to the subject, and the interval does not carry that. And
`RandomSeed` leaves the global random stream **exactly as it found it** — a
trial selector may be drawing from it. `binornd` takes no `RandStream`, as no
Statistics Toolbox generator does, so a seeded bootstrap saves the stream
state, seeds, and restores it through an `onCleanup`.

No Hessian-based standard error is offered. Its asymptotic assumptions are
exactly the ones adaptive sampling breaks, and a number with a hidden
assumption is worse than no number.

## Options

`fitPsychometric` accepts three options of its own and forwards every
`fitProportions` option unchanged.

### `fitPsychometric` only

| Option | Default | Meaning |
|---|---|---|
| `IncludeAborts` | `false` | Count aborted stimulus trials as failures to respond. |
| `GuessFromCatchTrials` | `false` | Take `gamma` from the catch-trial false alarm rate. |
| `LevelTolerance` | `0` | Absolute distance within which levels are merged. |

### `fitProportions`

| Option | Default | Meaning |
|---|---|---|
| `Shape` | `"Logistic"` | `"Logistic"`, `"Normal"` or `"Weibull"`. |
| `Direction` | `"increasing"` | `"decreasing"` for a parameter where higher means worse. |
| `GuessRate` | `0` | Lower asymptote `gamma`; `0.5` for 2AFC. |
| `LapseRate` | `0` | Fixed upper-asymptote offset `lambda`. |
| `EstimateLapse` | `false` | Fit `lambda` as a third free parameter. |
| `MaxLapse` | `0.05` | Upper bound on a fitted `lambda`. |
| `ThresholdCriterion` | `0.5` | Proportion the threshold is read at. |
| `CriterionScale` | `"relative"` | `"relative"` (between the asymptotes) or `"absolute"`. |
| `StartAlpha` | `NaN` | An *additional* optimizer start, tried alongside the data-derived one. |
| `StartBeta` | `NaN` | The same, for the slope. |
| `Bootstrap` | `0` | Parametric bootstrap replicates. |
| `ConfidenceLevel` | `0.95` | Bootstrap interval coverage. |
| `RandomSeed` | `[]` | Seed for a private RNG stream. |
| `CurvePoints` | `200` | Samples in `F.Curve`; `0` to skip it. |
| `MinResponseRange` | `0.05` | Smallest fitted variation across the tested levels that counts as identifiable. |
| `MaxIterations` | `2000` | `fminsearch` iteration and evaluation cap. |
| `Quiet` | `false` | Suppress the per-fit log messages. Not forwarded by `fitPsychometric`; the bootstrap sets it on its own replicates, since a thousand refits of resampled counts would otherwise write a thousand log records about resampled counts. |

MATLAB cannot inherit an `arguments` block, so `fitPsychometric` repeats
these declarations. `tmp/smoke_test_staircase_fit.m` parses both files and
fails when the two lists drift apart.

## The result struct

Every return path — refusals included — hands back the same fields, so no
caller needs `isfield`.

| Field | Meaning |
|---|---|
| `Alpha`, `Beta` | Location and slope parameters. |
| `Threshold` | Level at `ThresholdCriterion`; `NaN` when unreachable. |
| `ThresholdCriterionAbsolute` | The absolute proportion actually used. |
| `ThresholdInRange` | Whether `Threshold` is inside the tested levels. |
| `Shape`, `Direction`, `GuessRate`, `LapseRate`, `LapseEstimated` | The model that was fitted. |
| `Levels`, `NumYes`, `NumTotal`, `Proportion` | The counts the fit was made from. |
| `NumLevels`, `NumTrials`, `NumParameters` | Sizes. |
| `Curve.x`, `Curve.P` | The fitted function, for plotting. |
| `LogLikelihood`, `NegLogLik`, `AIC` | Fit quality. The log-likelihood omits the binomial coefficients, which do not depend on the parameters. |
| `Deviance`, `DevianceDF`, `DeviancePValue` | Likelihood-ratio test against the saturated model. |
| `Converged` | The optimizer terminated normally. |
| `Identifiable` | The data determine the parameters. |
| `Separated` | Complete separation was detected. |
| `ResponseRange` | How much the fitted curve varies across the tested levels. |
| `Message` | Why `Converged` or `Identifiable` is false; `""` otherwise. |
| `CI` | Bootstrap interval: `Level`, `Requested`, `Replicates`, `Alpha`, `Beta`, `Threshold`. |

`fitPsychometric` adds where the counts came from: `ParameterName`,
`NumScored`, `NumAborted`, `NumUnscored`, `NumUndefinedLevel`,
`GuessRateSource`.

**Nothing is stored on the staircase.** The fit is returned, never written
onto `S.Results`, so it can never be a stale number sitting beside live
trials. Call it again after more data arrive.

## How the estimator works

1. Levels with no scored trials are dropped and the rest sorted.
2. The refusals above are checked, exactly.
3. Starting values are derived from the data: `alpha0` by interpolating where
   the observed proportion crosses the middle of the asymptotes, `beta0` from
   a trial-weighted least-squares fit of the transform that linearizes the
   shape (logit, probit, or log-log).
4. The parameters are optimized in an unconstrained space — `log(|beta|)`
   always, `log(alpha)` for Weibull, and a logistic transform of `MaxLapse`
   for a fitted lapse — so every point the simplex visits is legal without a
   constrained solver.
5. `fminsearch` runs from several slope magnitudes (`beta0 × [0.25 1 4]`,
   plus any `StartAlpha`/`StartBeta` the caller supplied) and the highest
   likelihood wins, because a psychometric likelihood is flat in the slope
   when the levels are sparse. One restart from the winner confirms it.
6. The threshold, the identifiability flags, the goodness of fit, the curve
   and (if asked) the bootstrap are computed from the winner.

`fitPsychometric` passes the staircase's own reversal threshold as an
*additional* start. It only ever adds a starting point — the likelihood still
decides — so a staircase with few reversals cannot drag the estimate anywhere.

## Standing proof

```matlab
run(fullfile(epsychRoot,'tmp','smoke_test_staircase_fit.m'))
```

Headless — no figure, no hardware. Nine groups: the function/inverse
round trip for every shape and asymptote; parameter recovery against known
`alpha` and `beta`; the criterion scales including the 2AFC trap; every
refusal by its message; the identifiability flags; the goodness-of-fit
invariants; the bootstrap's reproducibility and its hands-off treatment of
the global RNG; an end-to-end fit of a simulated session coded with
`epsych.BitMask`; and the option-default drift check.

## See also

- [`psychophysics.Staircase`](psychophysics_Staircase.md) — reversals, the reversal threshold, and the plot
- [`psychophysics.BestPEST`](psychophysics_BestPEST.md) — maximum-likelihood threshold tracking *during* a session
- [`psychophysics.MLP`](psychophysics_MLP.md) — Bayesian estimation of threshold, slope and lapse during a session
- [`psychophysics.Metrics`](psychophysics_Metrics.md) — the signal-detection arithmetic, and the aborts convention
- [`psychophysics.Detection`](psychophysics_APrime.md) — hit and false alarm rates grouped by stimulus value

## References

- Wichmann, F. A. & Hill, N. J. (2001). The psychometric function: II. Bootstrap-based confidence intervals and sampling. *Perception & Psychophysics*, 63, 1314–1329.
- Leek, M. R., Hanna, T. E. & Marshall, L. (1992). Estimation of psychometric functions from adaptive tracking procedures. *Perception & Psychophysics*, 51, 247–256.
- Treutwein, B. & Strasburger, H. (1999). Fitting the psychometric function. *Perception & Psychophysics*, 61, 87–106.
- Kaernbach, C. (2001). Slope bias of psychometric functions derived from adaptive data. *Perception & Psychophysics*, 63, 1389–1398.
