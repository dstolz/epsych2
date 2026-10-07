# Weighted-Staircase Threshold for `psychophysics.Staircase`

## Overview

A **weighted** up-down staircase (Kaernbach 1991) targets an arbitrary
probability of response by stepping a different distance after a "yes" than
after a "no". `psychophysics.Staircase` has always been able to *run* one —
`cl_AppetitiveStimDetect` steps `Depth` by two independent, signed parameters,
`Depth_StepOnHit` and `Depth_StepOnMiss`, and whenever their magnitudes differ
that is a weighted staircase — but its `Results.Threshold`, the mean of the
last N reversals, is not the right estimate for one. Two things are wrong
with it:

1. **The reversal mean is biased.** García-Pérez (1998, 2011) showed the error
   is signed, proportional to step size, and always *toward the tail* of the
   psychometric function. Hoover (2025) gives a correction that removes it.
2. **The reversals must be balanced.** The threshold is defined as the mean of
   an *equal number* of ascending and descending reversals. The last N taken
   with no balance guarantee is biased on its own: on a ψ = 0.75 track the
   peaks alone average near p = 0.86 and the troughs near 0.60, so one surplus
   reversal in twelve moves the estimate by roughly 0.02 in probability —
   comparable to the bias the correction removes.

`S.weightedThreshold()` returns the corrected threshold together with the
quantities needed to audit it, including the response probability the steps
the session *actually* took target. Four files implement it, all in
`obj/+psychophysics/@Staircase/`:

| Entry point | What it is |
|---|---|
| `S.weightedThreshold(...)` | The session-level seam: finds the steps and the reversals, returns the result. |
| `psychophysics.Staircase.correctedReversalMean(values, isAscending, stepAfterYes, stepAfterNo, ...)` | The estimator. Pure — no object, no runtime, no figure. |
| `selectBalancedReversals_` | The balance rule, shared by both (private). |
| `emptyWeightedThreshold_` | The result skeleton, so every return path has the same fields (private). |

This mirrors the split between `fitPsychometric` and `fitProportions`
([psychometric fitting](psychophysics_StaircaseFit.md)): the arithmetic is
testable with nothing but numbers, and the seam only turns a session into
its inputs.

## Quick start

```matlab
S = psychophysics.Staircase(DATA, 'Depth');   % Depth in dB re 100%
T = S.weightedThreshold(StepFieldYes='Depth_StepOnHit', StepFieldNo='Depth_StepOnMiss');

if T.Valid
    fprintf('corrected %.2f dB (reversal mean %.2f), targets p = %.3f\n', ...
        T.Threshold, T.ReversalMean, T.TargetProbability);
else
    fprintf('no corrected threshold: %s\n', T.Message);
end
```

With `Depth_StepOnHit = -2` and `Depth_StepOnMiss = +6` dB — the configuration
`tmp/smoke_test_reminder_trial.m` uses — the track targets ψ = 0.75 and the
correction is −1.0 dB, so a result reads, for example:

```matlab
T.Threshold           % -21.0    corrected, dB re 100%
T.ReversalMean        % -20.0    what Results.Threshold reports without the correction
T.Correction          %  -1.0    = (delta_- - delta_+)/4 = (2 - 6)/4
T.StepAfterYes        %  -2      signed, parameter units
T.StepAfterNo         %   6
T.StepRatio           %   0.3333 r = delta_- / delta_+
T.TargetProbability   %   0.75   psi = 1/(r+1)  <- the point on the PF this IS
T.NumAscending        %   6
T.NumDescending       %   6
T.StepConsistency     %  [1 1]
T.StepSource          %  "field"
```

To make the plot and `Results.Threshold` report the corrected value instead:

```matlab
S.WeightedStepFieldYes = "Depth_StepOnHit";
S.WeightedStepFieldNo  = "Depth_StepOnMiss";
S.ApplyWeightedCorrection = true;
S.refresh_history();
```

On a plot, the right-click **Apply Weighted Correction** does the last two
lines and is remembered. With the flag on, every threshold estimate the plot
shows is corrected — the title and its sliding-block min/median/mean/max, the
threshold line (dashed, **Corrected Threshold**), the sliding-threshold line,
and the sliding-threshold distribution — so turning it off and on compares the
two directly.

## The equations

Hoover (2025), p. 201: *"Calculation of threshold using the proposed
correction simply requires obtaining the mean of an equal number of ascending
and descending reversals and then adding (δ₋ − δ₊)/4."* Eq. (3):

```
x_psi  ~=  x_R + (delta_- - delta_+)/4
```

| Symbol | Meaning | Result field |
|---|---|---|
| δ₋ | step taken **down** after a single "yes" | `StepDown` |
| δ₊ | step taken **up** after a single "no" | `StepUp` |
| x_R | mean of an equal number of ascending and descending reversals | `ReversalMean` |
| r = δ₋/δ₊ | step-size ratio | `StepRatio` |
| ψ = 1/(r + 1) | targeted probability of response at threshold | `TargetProbability` |

An *ascending* reversal is an increase followed by a decrease (a peak); a
*descending* reversal is a decrease followed by an increase (a trough).

### No direction to configure

The paper's axis assumes the probability of a yes increases with the level.
EPsych tracks a parameter that may run either way — an AM depth re 100 %, an
attenuation, a masker level. Write `d_yes` and `d_no` for the **signed** change
in the parameter after a yes and after a no:

- probability rising with the parameter: `d_yes = −δ₋`, `d_no = +δ₊`, so the
  correction is `−(d_yes + d_no)/4`;
- probability falling with it: the axis flips, and so does the correction —
  which is again `−(d_yes + d_no)/4`.

Both collapse to the same expression:

```
Threshold = mean(balanced reversal values) - (d_yes + d_no)/4
```

Naming each step by the *response that preceded it* rather than by the
direction it goes is what makes this convention-free. So there is no
`Direction` option, and a paradigm that steps "up to make it harder" needs no
special handling. The balance rule is symmetric too — mirroring the axis turns
peaks into troughs but selects the same reversals — and
`StaircaseDirection` (a plotting convention) changes nothing.

## Where the steps come from

Each step is found independently, from the first of these that applies, and
`T.StepSource` says which (`"stated"`, `"field"`, `"inferred"`, or
`"<yes>/<no>"` when the two sides differ, e.g. `"stated/inferred"`).

1. **Stated** — `StepAfterYes` / `StepAfterNo`, signed, in the parameter's
   units. `NaN` means "find it", so one side can be stated and the other found.
2. **Read from a DATA field** — `StepFieldYes` / `StepFieldNo` name per-trial
   fields holding the steps. `ep_TimerFcn_RunTime` saves every readable
   `hw.Parameter` on every trial, so `cl_AppetitiveStimDetect`'s
   `Depth_StepOnHit` and `Depth_StepOnMiss` are already there. This is exact
   where inference is an estimate, and it is the only way to see an operator
   editing a step mid-session through the behavior GUI's `autoCommit` control.
   The field's value is read on each trial whose response selected that step,
   since parameters are read at trial completion, before the next trial is
   chosen. Field names are **never guessed** — a guessed name is how you
   silently read the wrong column.
3. **Inferred from the track** — the fallback, so the bare
   `S.weightedThreshold()` works on any saved session. The step leaving each
   stimulus trial is the change to the next stimulus trial's level, attributed
   to that trial's response. The nominal step is the **most common non-zero
   value**: exact for a fixed-step staircase, and a step clamped at a
   parameter's `Min`/`Max` cannot drag it the way a mean would.

"Yes" is `Hit` without `Miss`, and "no" is `Miss` without `Hit` — the scoring
`fitPsychometric` uses. An abort is neither and moves nothing. A step pending
across catch trials is attributed correctly, because only stimulus trials are
compared (`cl_AppetitiveStimDetect` writes a Hit/Miss step into every STIM row
of the trial table, so it survives intervening catch trials).

### Only the steps behind the reversals used

Sources 2 and 3 read only the steps that produced the reversals the threshold
is computed from — from the step *into* the first used reversal to the step
*out of* the last. That is what makes a coarse-then-fine track work: the
threshold comes from the final phase, so the step sizes must too.

### Near-equal steps

`StepTolerance` groups step samples within an absolute distance of one another
(`uniquetol` with `DataScale = 1`, the idiom `fitPsychometric`'s
`LevelTolerance` uses). Its default, `NaN`, is one millionth of the largest step
seen: enough to absorb the floating-point drift of a decimal step (0.15 − 0.1 is
not exactly 0.05) and of levels read back from single-precision hardware, and
far below any step a paradigm would mean.

## What it refuses, and what it flags

A threshold that cannot be computed returns `T.Valid = false` with a `Message`
saying why, and `T.Threshold = NaN`. It never throws for a situation in the
data — only for malformed input (reversal vectors of different lengths).

**Refused** — the number is impossible:

| Situation | Message contains |
|---|---|
| No trials | `no trials` |
| No stimulus trial (all catch, no `TrialType` or response codes, or all excluded) | `No trial is a stimulus trial` |
| No stimulus trial recorded a level | `No stimulus trial recorded a level` |
| No reversals yet (one or two trials, a monotone track, all aborts) | `no reversals` |
| Reversals in one direction only (a single reversal) | `one direction only (0 ascending, 1 descending)` |
| `NumReversals = 1` | `NumReversals = 1 leaves too few reversals to balance` |
| A step is zero or not finite | `zero or not finite` |
| Both steps have the same sign | `same sign` — the track only moves one way |
| No response code on every trial, and a step neither stated nor named | `no response code on every trial` |
| No scored yes (or no) among the steps behind the reversals | `No step after a yes falls within` |
| A named field is missing from DATA | `has no field` |
| A named field is not one number per trial (empty on a trial, text) | `does not hold one number per trial` |
| A named field has no defined value where it applied | `has no defined value` |

### Too little data

The least that gives a threshold is **one ascending and one descending
reversal** — four stimulus trials, such as `-10 -12 -6 -8` with Hit, Miss,
Hit. Short of that, and while a session is starting, every path answers with
a refusal naming the cause: the method, the static, and a refresh with
`ApplyWeightedCorrection` on, which runs from the `NewData` listener on every
trial. Under the flag an empty session still gets a `Results.Weighted` struct
(never `[]`), and a refused correction leaves `Results.Threshold` *and*
`Results.ThresholdStd` `NaN`, so no spread is ever drawn beside a missing
threshold.

Two data faults are handled rather than propagated:

- **A trial that recorded no level** (an empty `Depth`) reads as `NaN`, which
  reversal detection already treats as "not recorded". `[DATA.Depth]` silently
  drops such a trial, which used to slide every later level onto the wrong
  trial — and, for a stimulus trial, made the `Staircase` constructor throw.
  This fix is in `stimulusValues`, so the plain reversal threshold and the plot
  get it too.
- **A trial with no response code** is refused for inference ("no response code
  on every trial") rather than attributed: the same concatenation would pair
  every later code with the wrong trial's step. Stated steps and a named DATA
  field still work.

The static's inputs may be empty (`[]`, `0x1`) or columns. `reversalIsAscending`
must be logical or numeric 0/1; a `NaN` or a `2` is a bug upstream and throws
`psychophysics:Staircase:WeightedInvalidAscending`, as a length mismatch throws
`WeightedSizeMismatch`.

**Flagged, still valid** — the threshold is returned and `Valid` stays true:

- **Inconsistent steps.** `StepConsistency` is a 1×2 giving the fraction of
  samples at the nominal value, `[yes no]` (`NaN` for a stated step, which is
  not measured); `StepsConsistent` is `false` when any measured fraction is
  below 1; `Message` names the values seen and their proportions. A zero step
  counts against consistency: a clamp at a parameter bound produces one, and so
  does a transformed (n-down) rule after a yes — and the correction is for a
  1-up-1-down weighted staircase.
- **An unexpected target.** `ExpectedTarget` is an **assertion, not an input**:
  say which ψ you meant, and the result compares it with the ψ implied by the
  steps actually found. Inverting the ratio — targeting 0.25 when you meant
  0.75 — is the easy mistake, and a mismatch sets `TargetMatchesExpected =
  false` and says so (naming the swap when exchanging the steps would match).
  It does **not** change the threshold: the number is right, it just names a
  different point on the psychometric function.
- **`ThresholdFormula = "GeometricMean"`.** The correction is additive in the
  units the steps are in, so this method always uses the arithmetic mean and
  says so, rather than letting `Results.Threshold` and `T.Threshold` be
  computed on different scales.

## When the correction does not apply

The correction is Hoover's *"rule-of-thumb"* — Monte Carlo evidence, not a
proof — and its domain matters:

- It is effective when the psychometric function is **symmetric about 0.5 and
  spans (0, 1)**: Gaussian, logistic, arctangent. Not Weibull, log-Weibull or
  Poisson.
- *"The correction should not be used for mAFC tasks with few response
  alternatives."* It was good at a guess rate of 1/9 and harmful at 1/2 and 1/3.
- It is effective for lapse rates up to 1/10, and ineffective at 1/5.
- Residual error grows with step size, and when targeting far into the tails.
- It is for a **1-up-1-down weighted** rule. A transformed rule (2-down-1-up)
  targets a different ψ than 1/(r + 1); its zero steps after a yes show up as
  low `StepConsistency`.

`gui.AdaptiveTraining` is not a candidate either. Its `StepUp`/`StepDown` are
unsigned magnitudes whose sign comes from the direction, its defaults bind
`"Hit"`/`"Abort"` rather than Hit/Miss, and its non-linear `ScaleType`s
(`logarithmic`, `power`, `piecewise`) make steps that are not fixed in
parameter units — so there is no fixed δ₋/δ₊ to correct with. Inferring steps
from such a ladder shows it as low `StepConsistency`.

## Driving `Results.Threshold` and the plot

Five properties, all `SetObservable` and all off or empty by default, so no
existing session changes its numbers. Like `ThresholdFromLastNReversals` and
`ThresholdFormula`, they are not constructor options: set them, then call
`refresh_history()`.

| Property | Default | Meaning |
|---|---|---|
| `ApplyWeightedCorrection` | `false` | Route `Results.Threshold` and the sliding-block thresholds through `weightedThreshold`. Also the plot's right-click **Apply Weighted Correction**. |
| `WeightedStepAfterYes` | `NaN` | Stated step after a yes; `NaN` = find it. |
| `WeightedStepAfterNo` | `NaN` | Stated step after a no. |
| `WeightedStepFieldYes` | `""` | DATA field holding the step after a yes; `""` = none. |
| `WeightedStepFieldNo` | `""` | DATA field holding the step after a no. |

These are also `weightedThreshold`'s defaults, so with the flag on,
`S.weightedThreshold()` with no arguments returns exactly `Results.Weighted`.

With the flag on:

- `Results.Threshold` is the **corrected, balanced** value, and `NaN` while it
  cannot be computed — never a silent fall-back to the uncorrected mean, which
  would be the wrong number under a flag that says otherwise. The plot and the
  title already read `NaN` as "no threshold". A refusal is logged once per
  episode at debug level, since a session's first trials have no reversals yet.
- `Results.ThresholdStd` is the standard deviation of the balanced reversals.
- `Results.Weighted` holds the full result struct; `Results.Weighted.Message`
  carries any advisory. With the flag off it is `[]`.
- The plot title reads `Corrected threshold (10/12 rev, -1.00): -21.00`, so a
  screenshot pasted into a notebook says what it shows, and the ±1 SD band
  spans exactly the reversals the corrected threshold used.
- **Open in Separate Window** copies all five settings to the pop-out's own
  staircase, so the two windows never disagree about which threshold they show.

The weighted path runs from the `NewData` listener on every trial, so it never
throws for a data problem.

## Options

### `weightedThreshold`

| Option | Default | Meaning |
|---|---|---|
| `StepAfterYes` | `WeightedStepAfterYes` | Stated step after a yes, signed; `NaN` = find it. |
| `StepAfterNo` | `WeightedStepAfterNo` | Stated step after a no, signed. |
| `StepFieldYes` | `WeightedStepFieldYes` | DATA field holding the step after a yes. |
| `StepFieldNo` | `WeightedStepFieldNo` | DATA field holding the step after a no. |
| `NumReversals` | `ThresholdFromLastNReversals` | Start from the last N reversals, then balance. `Inf` for all. |
| `LastReversal` | `Inf` | Treat the session as ending at this reversal. How the sliding-block thresholds are corrected: block k is `NumReversals=N, LastReversal=k+N-1`, with steps read from behind its own reversals. |
| `StepTolerance` | `NaN` | Absolute grouping distance for step samples; `NaN` = 1e-6 of the largest step. |
| `ExpectedTarget` | `NaN` | The ψ the steps were meant to target, checked, never used. |
| `TargetTolerance` | `0.01` | How far `TargetProbability` may sit from `ExpectedTarget`. |

### `correctedReversalMean`

```matlab
T = psychophysics.Staircase.correctedReversalMean(values, isAscending, stepAfterYes, stepAfterNo, ...)
```

`values` are the reversal levels in chronological order; `isAscending` marks
the peaks, in the parameter's own units. The steps are signed.

| Option | Default | Meaning |
|---|---|---|
| `NumReversals` | `Inf` | Start from the last N defined reversals, then balance. |
| `ExpectedTarget` | `NaN` | As above. |
| `TargetTolerance` | `0.01` | As above. |

### The balance rule

Non-finite reversal values are dropped first and counted in
`NumUndefinedReversals`. Of the rest, the last `NumReversals` are taken; the
most recent k of each direction are kept, where k is the smaller count; and the
result is in chronological order. A staircase's reversals alternate, so in
practice this drops at most the oldest — an odd `NumReversals` drops one — but
the rule does not rely on alternation, because a dropped value can break it.

## The result struct

Every return path — refusals included — hands back the same fields in the same
order, so no caller needs `isfield`.

| Field | Meaning |
|---|---|
| `Threshold` | `ReversalMean + Correction`; `NaN` unless `Valid`. |
| `ReversalMean` | Mean of the balanced reversals — the uncorrected x_R. |
| `Correction` | `-(StepAfterYes + StepAfterNo)/4` = (δ₋ − δ₊)/4 in the paper's axis. |
| `ReversalStd` | Standard deviation of the balanced reversals. |
| `StepAfterYes`, `StepAfterNo` | The steps used, signed, in the parameter's units. |
| `StepSource` | `"stated"`, `"field"`, `"inferred"`, or `"<yes>/<no>"`. |
| `StepConsistency` | `[yes no]` fraction of samples at the nominal step; `NaN` if stated. |
| `StepsConsistent` | Every measured fraction is 1. |
| `NumStepsYes`, `NumStepsNo` | Step samples examined; 0 for a stated step. |
| `StepDown`, `StepUp` | δ₋ and δ₊, the magnitudes. |
| `StepRatio` | r = δ₋/δ₊. |
| `TargetProbability` | ψ = 1/(r + 1), from the steps actually found. |
| `ExpectedTarget` | As passed. |
| `TargetMatchesExpected` | `true` when it matches, or when none was stated. |
| `NumReversals` | Reversals used, `NumAscending + NumDescending`. |
| `NumAscending`, `NumDescending` | Peaks and troughs used, in the parameter's own units. |
| `NumUndefinedReversals` | Reversals with a non-finite value, never used. |
| `ReversalValues` | Every reversal's level. |
| `ReversalUsed` | Logical, the same size: which ones the threshold used. |
| `ReversalIdx` | Trial indices of the reversals (`weightedThreshold` only). |
| `ParameterName` | The tracked parameter (`weightedThreshold` only). |
| `Valid` | The threshold could be computed. |
| `Message` | Why `Valid` is false; otherwise any advisory, or `""`. |

`StepDown`, `StepUp`, `StepRatio` and `TargetProbability` are the paper's δ₋,
δ₊, r and ψ, so a result reads straight against the article.

**Nothing is stored** by `weightedThreshold`. Only `ApplyWeightedCorrection`
writes a result onto `S.Results`, and it recomputes it with every refresh —
except the sliding blocks before the latest, which are memoized while the
settings and the trials they read are unchanged
(`tmp/smoke_test_staircase_weighted_toggle.m` checks the memo against a fresh
object trial by trial, seeking backward, and after a mid-session edit).

## Standing proof

```matlab
run(fullfile(epsychRoot,'tmp','smoke_test_weighted_staircase.m'))
```

Headless — no figure, no hardware. Eleven groups: the correction to floating-point
equality and zero for a symmetric staircase; direction invariance, for a
mirrored track and for `StaircaseDirection`; ψ and r against the paper's ratios
(3/4 → 0.571, 2/1 → 1/3, 1/40 → 0.976); the balance rule; every refusal by its
message; inconsistent steps flagged rather than refused, inferred and from a
field, and a clamp that cannot move the nominal step; `ExpectedTarget` as an
assertion; the three step sources through catch trials and aborts, and a
coarse-then-fine track reporting the fine steps; `ApplyWeightedCorrection` —
off changes nothing, on routes the threshold, a refusal is `NaN` and never
throws trial by trial, and the pop-out copies the settings; the bias it
exists to remove; and no data and too little data — every short, empty or
malformed session above, through the method and the per-trial flag path, a
session grown one trial at a time from nothing, and the static's smallest
and oddest inputs.

That last group is a Monte Carlo of 400 tracks of 120 trials against a Gaussian
psychometric function with a 98 % width of 20 dB (Hoover's), each started at a
random level within ±8 dB of the target, using the last 12 reversals:

| Target ψ | δ₋, δ₊ | Uncorrected lands at | Corrected lands at |
|---|---|---|---|
| 0.75 | 1, 3 dB | p = 0.794 | p = 0.759 |
| 0.20 | 4, 1 dB | p = 0.156 | p = 0.201 |

## See also

- [`psychophysics.Staircase`](psychophysics_Staircase.md) — reversals, the reversal threshold, and the plot
- [Psychometric fitting](psychophysics_StaircaseFit.md) — the other threshold the same trials can give
- [`cl_AppetitiveStimDetect`](../paradigms/cl_AppetitiveStimDetect.md) — a paradigm that runs a weighted staircase on `Depth`
- [`psychophysics.Metrics`](psychophysics_Metrics.md) — the aborts convention

## References

- Hoover, E. C. (2025). Target an arbitrary probability of response using weighted staircase procedures. *The Journal of the Acoustical Society of America*, 157(1), 191–202. doi:10.1121/10.0034861
- Kaernbach, C. (1991). Simple adaptive testing with the weighted up-down method. *Perception & Psychophysics*, 49(3), 227–229. doi:10.3758/BF03214307
- García-Pérez, M. A. (1998). Forced-choice staircases with fixed step sizes: asymptotic and small-sample properties. *Vision Research*, 38(12), 1861–1881. doi:10.1016/S0042-6989(97)00340-4
- García-Pérez, M. A. (2011). A cautionary note on the use of the adaptive up–down method. *The Journal of the Acoustical Society of America*, 130(4), 2098–2107. doi:10.1121/1.3628334
