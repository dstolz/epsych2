# psychophysics.Metrics

Stateless signal-detection arithmetic, shared by every analysis class.

Source: `obj/+psychophysics/Metrics.m`

`Metrics` is the single home for the formulas the rest of the toolbox reuses: the
z-transform, d', criterion, likelihood-ratio bias, the nonparametric A' and B'', and
proportion correct. It holds no data, no runtime, and no state — every method is static
and pure, so the same call works online, offline, in a test, or at the command line. It
is not constructible; the class is a namespace.

```matlab
psychophysics.Metrics.dprime(0.9, 0.1)                    % 2.5631
psychophysics.Metrics.fromCounts(18, 7, 3, 22)            % every metric at once
```

Two things follow from being stateless. It never touches `epsych.BitMask`, `DATA`, or
`RUNTIME` — turning a response-code vector into four counts needs the trial window, the
exclusion mask, and an aborts policy, all of which live in
[psychophysics.Psych](psychophysics_Psych.md). And its core needs no Statistics Toolbox:
`z` is built on `erfcinv`, so d' is computable on a rig that has only base MATLAB.

## Corrections for rates of 0 and 1

A hit rate of exactly 1 sends the z-transform to `+Inf`, and what to do about that is a
scientific choice rather than an implementation detail. It is named at every call:

| `Correction` | Rule | Needs counts | Reference |
|---|---|---|---|
| `"none"` | rates as given; 0 → `-Inf`, 1 → `+Inf` | no | — |
| `"clamp"` | pull into `Bounds`, default `[0.01 0.99]` | no | — |
| `"halfcell"` | 0 → `1/(2N)`, 1 → `1-1/(2N)`; interior rates untouched | **yes** | Macmillan & Kaplan (1985) |
| `"loglinear"` | every rate → `(nYes + 0.5)/(N + 1)` | **yes** | Hautus (1995) |

Ten hits out of ten, against a 20% false alarm rate:

| Correction | corrected H | d' |
|---|---|---|
| `"none"` | 1 | `Inf` |
| `"clamp"`, `[0.01 0.99]` | 0.99 | 3.17 |
| `"clamp"`, `[0.05 0.95]` | 0.95 | 2.49 |
| `"halfcell"`, N=10 | 0.95 | 2.49 |
| `"halfcell"`, N=100 | 0.995 | 3.42 |
| `"loglinear"`, N=10 | 0.955 | 2.44 |

The fixed clamp gives the same answer at N=10 and N=100; the N-dependent corrections do
not, which is the whole point of them. Two rates that both read 100% get different d'
when one is backed by 7 trials and the other by 80.

The two N-dependent modes differ in reach. `"halfcell"` touches only the extremes, so an
interior rate is left exactly as observed. `"loglinear"` moves every rate, which is why
its d' here is *lower* than `"halfcell"`'s despite the higher corrected hit rate — the
20% false alarm rate was pulled up to 22.7% as well.

**The N-dependent modes error rather than guess.** Calling
`dprime(H, F, Correction="loglinear")` without `NSignal`/`NNoise` raises
`psychophysics:Metrics:CountsRequired`. A silent fall back to a clamp is precisely how
this toolbox came to have three correction defaults nobody chose. `fromCounts` is the
entry point that always has the counts and never needs to be told them.

`correctRates` is public so that "which rates went in" — the first question asked of a
surprising d' — is answerable without re-deriving it.

## Rates in

| Method | Formula | Notes |
|---|---|---|
| `z(p)` | `-sqrt(2)*erfcinv(2*p)` | Inverse normal CDF. No correction: 0 and 1 give `∓Inf`, NaN and out-of-range give NaN. Named `z`, not `norminv` — an unqualified `norminv(p)` inside a classdef resolves to the toolbox function, not the static method. |
| `zinv(n)` | `0.5*erfc(-n/sqrt(2))` | Forward normal CDF. Generates the rates a known d' and c would produce. |
| `rate(num, den)` | `num./den` | NaN where `den == 0`. No trials of a kind is not a rate of zero. |
| `rateDenominator(nScored, nAbort, include)` | `nScored (+ nAbort)` | The aborts policy, in one place — see below. |
| `correctRates(H, F, ...)` | — | Returns the corrected pair, `[H F]`. |
| `dprime(H, F, ...)` | `z(H) - z(F)` | |
| `criterion(H, F, ...)` | `-(z(H) + z(F))/2` | 0 unbiased, positive conservative. The unambiguous name for what `Detection.bias` returns. |
| `criterionRelative(H, F, ...)` | `c/d'` | Bias comparable across subjects whose d' differ. Undefined at d' = 0. |
| `lnBeta(H, F, ...)` | `(z(F)² - z(H)²)/2` | Equals `c·d'`. Prefer this to `beta` for anything averaged or plotted. |
| `beta(H, F, ...)` | `exp(lnBeta)` | Present because the literature uses the name. |
| `aprime(H, F)` | Grier (1971) | No correction — defined at 0 and 1. Reads as the ROC area through the single observed point. |
| `bprimeprime(H, F)` | Grier (1971) | Nonparametric bias, −1 (liberal) to +1 (conservative). No correction. |
| `percentCorrect(H, F)` | `(H + 1 - F)/2` | *Balanced* proportion correct — see below. |
| `dprime2AFC(pc, ...)` | `sqrt(2)*z(pc)` | Takes `NSignal` (the number of 2AFC trials), not `NNoise`. |

Rates are fractions, not percentages, everywhere in this package.

## Counts in

`fromCounts(nHit, nMiss, nFA, nCR, Correction=, Bounds=)` returns every metric above in
one struct.

| Field | Contents |
|---|---|
| `N` | `Hit`, `Miss`, `FalseAlarm`, `CorrectReject`, `AbortSignal`, `AbortNoise`, `Signal`, `Noise`, `Total`. `Signal` and `Noise` are the denominators actually used |
| `Rate` | `Hit`, `Miss`, `FalseAlarm`, `CorrectReject`, `Correct` — all **observed**, uncorrected |
| `RateCorrected` | `Hit`, `FalseAlarm` as the z-transform actually saw them |
| `Correction`, `Bounds`, `IncludeAborts` | What was applied |
| `DPrime`, `Criterion`, `CriterionRelative`, `LnBeta`, `Beta` | Parametric, from the corrected rates |
| `APrime`, `BPrimePrime` | Nonparametric, from the **observed** rates — correcting these would only bias them toward chance |
| `PercentCorrect` | Observed, `(nHit + nCR)/(nSignal + nNoise)` |
| `PercentCorrectBalanced` | `(H + 1 - F)/2` |

`fromCounts` takes no `NSignal`/`NNoise`: supplying them would be a second, contradictory
source of truth.

## Aborts

An aborted trial is one the subject never answered, and whether it counts against a rate
is the one judgement call in the denominators. `rateDenominator` is where it lives:

```matlab
psychophysics.Metrics.rateDenominator(nHit + nMiss, nAbort, includeAborts)
```

**EPsych excludes aborts by default.** An abort is usually a lapse of engagement rather
than a wrong answer, and counting it makes a distracted session look insensitive rather
than incomplete. So the hit rate is `nHit/(nHit+nMiss)` and the false alarm rate
`nFA/(nFA+nCR)`.

Setting `IncludeAborts` scores them as failures to respond instead, charging each abort
to the side of the trial it happened on:

```matlab
psychophysics.Metrics.fromCounts(8, 2, 3, 7, AbortSignal=5)                    % H = 0.80
psychophysics.Metrics.fromCounts(8, 2, 3, 7, AbortSignal=5, IncludeAborts=true) % H = 0.53
```

`N.Signal` and `N.Noise` always report the denominator actually used, and
`S.IncludeAborts` records the policy, so a result is self-describing. Passing abort
counts while `IncludeAborts` is false changes nothing, so a caller can pass them
unconditionally and flip one option.

Every class that computes a rate takes the same option and routes through the same
function — `psychophysics.SessionMetrics.IncludeAborts`,
`psychophysics.Detection.IncludeAborts` (which `gui.components.SlidingWindowPerformancePlot`
follows from its analysis object) — so the convention is stated once rather than
implied in four places.

> **Changed 2026-08-19.** The toolbox used to disagree with itself: `SessionMetrics`
> excluded aborts while `Detection.Hit_Rate`, the sliding-window plot and the offline
> examples divided by *every* trial at a stimulus value, so one session yielded two
> different d'. They now all exclude aborts. `SessionMetrics` is unchanged; the others
> report higher hit rates than before on any session containing aborts.

## Broadcasting and NaN

Every method broadcasts, so a row of per-level hit rates pairs with a scalar false alarm
rate, and `NSignal` may be a row alongside it:

```matlab
psychophysics.Metrics.dprime([0.6 0.8 1.0], 0.1, ...
    Correction="loglinear", NSignal=[20 20 8], NNoise=40)
```

NaN propagates as NaN. An undefined rate is never turned into a bound — which is the one
behavioral difference from the code this class replaced. MATLAB's two-argument `min` and
`max` treat NaN as missing, so `min(NaN, 0.99)` is `0.99`, and the obvious
`max(min(p,hi),lo)` clamp silently converted "no catch trials" into "99% false alarms".
Three call sites carried a workaround for that and a fourth did not. Comparison is false
at NaN, so `clampKeepNaN_` leaves it alone instead.

A rate with no trials behind it stays undefined under every correction: `0.5/0` is `Inf`,
and log-linear's `(0·0 + 0.5)/(0 + 1)` would report a fabricated 50%.

## Balanced versus observed percent correct

`percentCorrect(H, F)` is the proportion correct an *equal* number of signal and catch
trials would have produced. It is not the observed proportion correct. With 72 hits of 90
stimulus trials and 5 correct rejects of 10 catch trials:

```matlab
S = psychophysics.Metrics.fromCounts(72, 18, 5, 5);
S.PercentCorrect          % 0.77 -- what actually happened
S.PercentCorrectBalanced  % 0.65 -- what a balanced session would have given
```

The gap is the trial mix, not the subject. `fromCounts` returns both, named apart;
`gui.components.SessionPerformance` reports the observed one.

## Relationship to the other classes

| Class | What it adds |
|---|---|
| [psychophysics.SessionMetrics](psychophysics_SessionMetrics.md) | Trial window, exclusions, trial-type classification, counts, display labels and formats |
| `psychophysics.Detection` | Per-stimulus-value grouping, and the `IncludeAborts` the plots follow. Its `d_prime`, `bias`, `a_prime` and `norminv` statics are forwarders kept for compatibility |
| `gui.Helper` | `dprime2AFC`, `criterion`, `percent_correct` are forwarders, kept because out-of-repo lab GUIs inherit the mixin |
| `gui.components.SlidingWindowPerformancePlot` | Per-window rates and d' over a session |
| `teensy.Simulator` | Monte Carlo summaries, using `"halfcell"` |

## Example

```matlab
% Command line, from rates. Both rates are inside the default [0.01 0.99],
% so the clamp has nothing to do and these two agree.
psychophysics.Metrics.dprime(0.9, 0.1)                          % 2.5631
psychophysics.Metrics.dprime(0.9, 0.1, Correction="none")       % 2.5631
psychophysics.Metrics.dprime(1.0, 0.1)                          % 3.6079, clamped
psychophysics.Metrics.dprime(1.0, 0.1, Correction="none")       % Inf
psychophysics.Metrics.criterion(0.6, 0.2, Correction="none")    % 0.2941

% Per stimulus level, count-aware
nGo    = [8 7 7 7 8];
nHit   = [2 3 4 7 8];
hitRate = psychophysics.Metrics.rate(nHit, nGo);
dprime  = psychophysics.Metrics.dprime(hitRate, 0.22, ...
    Correction="loglinear", NSignal=nGo, NNoise=23);

% Offline, everything at once
S = psychophysics.Metrics.fromCounts(24, 13, 5, 18, Correction="loglinear");
S.DPrime, S.Criterion, S.APrime, S.BPrimePrime
```

## Verification

`tmp/smoke_test_metrics.m` is the standing check: published normal quantiles and d'/c
values, agreement with the Statistics Toolbox `norminv`/`normcdf` where it is installed
(and a scan of the source proving the class does not call it), NaN propagation through
every correction and every metric, broadcasting, the correction equivalences — including
that `"halfcell"` leaves interior rates untouched and reproduces the implementation
retired from `teensy.Simulator` — round trips from rates generated at a known d' and c,
the aborts policy on `rateDenominator`, `fromCounts`, `SessionMetrics` and `Detection`,
and that the `Detection` and `gui.Helper` forwarders still return their historic values.
`tmp/smoke_test_aprime.m` and `tmp/smoke_test_session_performance.m` cover the consumers.

## See also

- [psychophysics.SessionMetrics](psychophysics_SessionMetrics.md) — the stateful session-level consumer
- [A' (nonparametric sensitivity)](psychophysics_APrime.md) — A' and B'', and when to prefer them to d'
- [psychophysics.Psych](psychophysics_Psych.md) — where trial classification lives
- [gui.components.SessionPerformance](../gui/gui_SessionPerformance.md) — the display
- [Detection task: working with saved data](../examples/Detection_Task_5_Data.md) — the offline walkthrough

## Changelog

- 2026-08-19: Initial release. Stateless signal-detection arithmetic extracted from
  `psychophysics.Detection`, `gui.Helper` and `teensy.Simulator`, with a toolbox-free
  z-transform, trial-count dependent corrections, correct NaN propagation, and B'' and
  relative criterion added. The aborts denominator became an `IncludeAborts` option
  defaulting to exclusion, settling a disagreement between `SessionMetrics` and the
  per-stimulus-value analyses.
