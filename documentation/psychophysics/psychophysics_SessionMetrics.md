# psychophysics.SessionMetrics

Session-level behavioral summary over a configurable window of trials.

Source: `obj/+psychophysics/@SessionMetrics/`, `obj/+psychophysics/TrialWindow.m`

`SessionMetrics` collapses the trial record to the handful of numbers an
experimenter watches during a session — trial counts, outcome rates, d', A'
and criterion — computed over whichever trials a `TrialWindow` selects. Every
metric comes from the decoded response bitmask and the trial-type masks
`psychophysics.Psych` already provides, so it works for any paradigm that
writes `RespCode`, with no paradigm-specific configuration.

It is a `psychophysics.Psych` subclass, so it works both ways:

```matlab
S = psychophysics.SessionMetrics(RUNTIME);   % online: follows NewData
S = psychophysics.SessionMetrics(Data);      % offline: a saved DATA struct array
```

[`gui.SessionPerformance`](../gui/gui_SessionPerformance.md) is the display
component built on it.

## The trial window

`psychophysics.TrialWindow` is an immutable value object naming a contiguous
span of the trial record. Assigning to `SessionMetrics.TrialWindow` accepts
any shorthand its `parse` method understands:

```matlab
S.TrialWindow = "all";       % every trial (the default)
S.TrialWindow = 50;          % the last 50 trials
S.TrialWindow = [20 100];    % trials 20 through 100
S.TrialWindow = "last 20";
S.TrialWindow = "first 10";
S.TrialWindow = "20-end";    % also "20:100", "20+"
S.TrialWindow = psychophysics.TrialWindow.lastN(20);
```

| Member | Description |
|--------|-------------|
| `Mode` | `"All"`, `"Last"`, `"First"`, or `"Range"` |
| `N` | Trial count for `"Last"` / `"First"` |
| `Range` | `[first last]` for `"Range"`; `last` may be `Inf` |
| `resolve(nTrials)` | 1-based trial indices, clamped to the trials that exist |
| `describe()` | `"Last 20 trials"` |
| `label(nTrials)` | `"Last 20 trials (28-47)"`, or a "no trials in window" note |
| `toStruct()` / `fromStruct(s)` | Round trip for `getpref`/`setpref` |
| `allTrials()`, `lastN(n)`, `firstN(n)`, `range(a,b)` | Static constructors |

A window is resolved against the current trial count every time results are
recomputed, so `"last 20"` keeps meaning the most recent 20 as the session
grows. A window that selects nothing yields undefined (`NaN`) rates rather
than zeros.

`ExcludedTrials` (inherited from `psychophysics.Psych`) is independent of the
window and intersected with it: the window is *what you are looking at*,
exclusions are *trials that should never count*.

## Metrics

`Results` holds the canonical values (rates are fractions, not percentages):

| Field | Contents |
|-------|----------|
| `Window` | The `TrialWindow` the results were computed with |
| `TrialIndex`, `FirstTrial`, `LastTrial` | Trials actually included |
| `N` | `Total`, `Stimulus`, `Catch`, `Hit`, `Miss`, `CorrectReject`, `FalseAlarm`, `Abort`, `AbortStimulus`, `AbortCatch`, `Scored`, `CatchScored` |
| `Rate` | `Hit`, `Miss`, `FalseAlarm`, `CorrectReject`, `Abort`, `Correct` |
| `DPrime`, `Criterion` | Signal-detection measures, `NaN` when either rate is undefined |
| `APrime` | Nonparametric sensitivity A' (chance 0.5), `NaN` when either rate is undefined |
| `BPrimePrime` | Nonparametric response bias B'', −1 (liberal) to +1 (conservative) |

Denominators follow the paradigm:

- **Hit / Miss rate** — scored stimulus trials (`Hit + Miss`), so aborts do
  not dilute the rate. Set `IncludeAborts` to score them as failures to
  respond; `N.AbortStimulus` and `N.AbortCatch` report the split, and
  `N.Scored`/`N.CatchScored` always give the denominator actually used.
- **False alarm / Correct reject rate** — scored catch trials (`FA + CR`),
  with the same aborts policy.
- **Abort rate** — every included trial.
- **Percent correct** — `(Hit + CR) / (Scored + CatchScored)`.
- **d' and criterion** — computed by
  [psychophysics.Metrics](psychophysics_Metrics.md) from the outcome counts.
  Both are `NaN` when either rate is undefined.
- **A' and B''** — computed from the *uncorrected* rates: both are defined at
  rates of 0 and 1, and correcting them would only pull them toward chance.
  See [A' (nonparametric sensitivity)](psychophysics_APrime.md).

### Rates of 0 and 1

A perfect or empty rate sends the z-transform to infinity, and `CorrectionMode`
names what to do about it — `"none"`, `"clamp"` (the default and the historic
behavior), `"halfcell"`, or `"loglinear"`. `infCorrection` (default
`[0.05 0.95]`) supplies the bounds for `"clamp"` only; the last two derive
their own from the trial counts, which is why they are available here and not
on the rate-only entry points:

```matlab
S.CorrectionMode = "loglinear";   % correction shrinks as trials accumulate
S.infCorrection  = [0.01 0.99];   % applies to "clamp" only
```

Counts are passed to `Metrics`, not rates, so no trial number has to be
recovered by un-dividing. See
[psychophysics.Metrics](psychophysics_Metrics.md) for what each mode does and
when to prefer it.

### Aborts

`IncludeAborts` (default `false`) decides whether an aborted trial counts
against the hit and false alarm rates. Leaving it off — the historic behavior
here — means a rate describes the trials the subject answered:

```matlab
S.IncludeAborts = true;    % score aborts as failures to respond
```

The `AbortRate` metric is unaffected either way: it is always aborts over
every included trial.

A paradigm that never labels trial types — no `TrialType` field and no
`TrialType_*` bits in `RespCode` — scores every outcome over the whole
window instead, so single-trial-type paradigms still report sensible rates.

`StimulusTrialType` and `CatchTrialType` (inherited, default `TrialType_0`
and `TrialType_1`) name which trial type is which.

### Display helpers

```matlab
T = S.summary();          % table: Name, Label, Group, Kind, Value, Text, Detail
[v, txt, detail] = S.metric("HitRate");    % 0.727, "72.7%", "18/25"
disp(S.summaryText())                      % window label + one line per metric
```

`Text` is the formatted value (`"--"` when undefined) and `Detail` the
supporting counts. `Kind` names the outcome family (`hit`, `miss`, `cr`,
`fa`, `abort`, `sensitivity`, `count`, `neutral`), which the GUI maps to a
color.

The catalogue — the metric definitions themselves — is a static method, so a
new metric is added in one place:

```matlab
psychophysics.SessionMetrics.metricNames()     % every metric, in display order
psychophysics.SessionMetrics.defaultMetrics()  % Trials, HitRate, FARate, AbortRate, DPrime
psychophysics.SessionMetrics.catalogue()       % Name/Label/Group/Kind/Format definitions
```

Available metrics: `Trials`, `StimulusTrials`, `CatchTrials`, `Hits`,
`Misses`, `CorrectRejects`, `FalseAlarms`, `Aborts`, `HitRate`, `MissRate`,
`FARate`, `CRRate`, `AbortRate`, `PercentCorrect`, `DPrime`, `APrime`,
`Criterion`.

## Example

```matlab
S = psychophysics.SessionMetrics(RUNTIME, TrialWindow="last 20");

% ... trials run; the object follows NewData ...

S.Results.Rate.Hit        % 0.727
S.Results.DPrime          % 1.84
S.TrialWindow = "all";    % recompute over the whole session
S.ExcludedTrials = 1:5;   % ignore the warm-up trials

vprintf(1, S.summaryText())
```

Offline, over a saved session:

```matlab
load('SUBJ_2026-08-12.mat','Data')
S = psychophysics.SessionMetrics(Data);
for w = [10 20 50]
    S.TrialWindow = psychophysics.TrialWindow.lastN(w);
    fprintf('last %3d: d'' = %.2f\n', w, S.Results.DPrime);
end
```

## Verification

`tmp/smoke_test_session_performance.m` is the standing check: window parsing
and resolution, the metric arithmetic over every window mode, exclusions,
the untyped-paradigm fallback, and the GUI paths on top of them.
`tmp/smoke_test_aprime.m` covers the `APrime` metric specifically.

## See also

- [gui.SessionPerformance](../gui/gui_SessionPerformance.md) — the display component
- [psychophysics.Psych](psychophysics_Psych.md) — the base class (`DATA`, `ExcludedTrials`, `NewData`)
- [psychophysics.Metrics](psychophysics_Metrics.md) — the arithmetic behind every metric here, and the corrections `CorrectionMode` selects
- [A' (nonparametric sensitivity)](psychophysics_APrime.md) — the `APrime` and `BPrimePrime` metrics, and when to prefer them to d'
- `psychophysics.Detection` (`obj/+psychophysics/@Detection/`) — per-stimulus-value psychometric analysis
- [epsych.BitMask](../epsych/epsych_BitMask.md) — response codes
