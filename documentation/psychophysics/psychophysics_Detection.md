# psychophysics.Detection — Yes/No Detection by Stimulus Value

`psychophysics.Detection` analyses a Go/No-Go (yes/no) task one stimulus value at a time.
Stimulus trials are grouped by the value they recorded for `Parameter` — a tone level, a
flash duration, a deviant sound's ID — and every catch trial goes into **one pool**,
whatever value it recorded. Each stimulus value then gets its hit rate and, against the
pooled false-alarm rate, d′, A′, criterion c and B″.

Source: `obj/+psychophysics/@Detection/Detection.m`. Standing proof:
`tmp/smoke_test_detection.m`.

It is a [`psychophysics.Psych`](psychophysics_Psych.md) subclass (since 2026-11-17), so it
runs **online** — constructed with a runtime, it follows `NewData` — or **offline** over a
saved `DATA` struct array, honours `ExcludedTrials`, and changes trials offline through
`setData`. [`psychophysics.SessionMetrics`](psychophysics_SessionMetrics.md) is the same
arithmetic collapsed over every stimulus value; both hand the formulas to
[`psychophysics.Metrics`](psychophysics_Metrics.md), so for a session with one stimulus
value the two agree exactly.

## Construction

```matlab
D = psychophysics.Detection(RUNTIME, RUNTIME.find_parameter('ToneLevel'));   % online
D = psychophysics.Detection(RUNTIME, "ToneLevel");                           % online, by field name
D = psychophysics.Detection(S.Data, "ToneLevel");                            % offline
D = psychophysics.Detection(S.Data, "ToneLevel", TrialWindow = "last 100", IncludeAborts = true);
```

| Option | Default | Meaning |
|---|---|---|
| `StimulusTrialType` | `TrialType_0` | Trials grouped by value |
| `CatchTrialType` | `TrialType_1` | Trials pooled for the false-alarm rate |
| `TrialWindow` | all | Anything `psychophysics.TrialWindow.parse` takes: `"last 20"`, `50`, `[20 100]` |
| `ExcludedTrials` | none | Logical mask or 1-based trial indices |
| `IncludeAborts` | `false` | Count aborts against both rates as failures to respond |
| `CorrectionMode` | `"clamp"` | Handling of rates of 0 and 1 before the z-transform: `"none"`, `"clamp"`, `"halfcell"`, `"loglinear"` |
| `infCorrection` | `[0.05 0.95]` | Bounds for `"clamp"` |
| `BoxID` | `[]` | Follow only this box's `NewData`; empty follows every box |
| `Subject` | `""` | Title label; empty uses the subject the session names |

`Parameter` may be an `hw.Parameter` or a `DATA` field name, **online as well as offline**:
the analysis reads only the field. (The base class refuses a name online because a
Staircase needs the parameter object; Detection overrides `normalizeParameter_`.)

## Results

Recomputed on every trial and every setting change; a read never changes anything.

| Field | Shape | Meaning |
|---|---|---|
| `Parameter` | string | The `DATA` field grouped by |
| `Values` | 1×K | Stimulus values, ascending |
| `N.Trials`, `N.Hit`, `N.Miss`, `N.Abort` | 1×K | Per value |
| `N.Scored` | 1×K | The hit rate's denominator: `Hit+Miss`, plus `Abort` under `IncludeAborts` |
| `Catch.Trials`, `.FalseAlarm`, `.CorrectReject`, `.Abort`, `.Scored` | scalars | The pooled catch trials |
| `Rate.Hit`, `Rate.Miss` | 1×K | Over `N.Scored` |
| `Rate.FalseAlarm`, `Rate.CorrectReject` | scalars | Over `Catch.Scored` |
| `DPrime`, `APrime`, `Criterion`, `BPrimePrime` | 1×K | Each value's hit rate against the pooled false-alarm rate |
| `NumNoValue` | scalar | Stimulus trials left out: they recorded no numeric value for `Parameter` |
| `TrialIndex` | 1×n | Trials included (`TrialWindow` minus `ExcludedTrials`) |
| `Window` | TrialWindow | The window applied |
| `Message` | string | Why `Values` is empty (no trials, no `Parameter`, no such field, no stimulus trial yet), or `""` |

With no catch trials the false-alarm rate is `NaN`, and so are d′ and c — the hit rates are
still defined. With no stimulus trials `Values` is empty and `Message` says so; the
false-alarm rate is still computed.

## Methods

```matlab
y = D.metric("DPrime")        % one metric as a row over Results.Values, for plotting
T = D.summary()               % one row per value: Trials, Hits, Misses, Aborts, HitRate, DPrime, APrime, Criterion
W = D.windowed(50)            % every metric as a curve over trials (0 = cumulative)
f = D.candidateParameters()   % DATA fields that could be the independent variable
s = D.sourceLabel()           % "M7 [2]" for a title
names = psychophysics.Detection.metricNames()
```

`metric` accepts `HitRate`, `MissRate`, `FARate`, `CRRate`, `DPrime`, `APrime`,
`Criterion`, `BPrimePrime`; the pooled false-alarm and correct-reject rates are repeated
once per value so every metric lines up with `Values`.

`windowed(w)` returns, for every trial t, the metrics over the window ending at t — all
trials so far when `w` is 0, else the last `w`. It is built from running sums, so the whole
curve costs one pass whatever the session length, and it respects `ExcludedTrials` but not
`TrialWindow` (the window is its own). Fields: `TrialIndex` (n×1), `Values` (1×K),
`HitRate`, `DPrime`, `APrime`, `Criterion`, `BPrimePrime`, `NScored` (n×K), `FARate`,
`CatchScored` (n×1). A value with no trials in a window reads `NaN` there.

## Settings recompute and broadcast

`Parameter`, `StimulusTrialType`, `CatchTrialType` (declared by the base class, so caught
with a `PostSet` listener), `TrialWindow`, `ExcludedTrials`, `IncludeAborts`,
`CorrectionMode` and `infCorrection` each recompute `Results` and broadcast
`Events.NewData` **once** when set, so every display over the analysis follows. That is how
`gui.components.PsychPlot`'s abscissa picker works: it sets `Parameter`, and the plot, the
sliding-window curve and the history table over the same object all move together.

Changing `BoxID` on an online analysis takes that box's trials from the runtime at once.

## Trial types

From `DATA.TrialType` when present, else from the `TrialType_*` bits in the response codes
— the base class's rule, so the field and the bits give identical results. A trial that
recorded no value for the field reads as neither type. A paradigm that labels **neither**
is analysed as all stimulus trials, with false alarms counted wherever they were scored —
the rule `SessionMetrics` applies.

## Online

- **One box.** On a multi-box rig `NewData` arrives for every box. `BoxID` restricts the
  analysis to one; empty follows every box, which is right for a single-box rig and mixes
  subjects on a multi-box one (the `gui.components.ParameterScatter` convention).
- **Seeding.** An online analysis constructed mid-session — a pop-out, a review, a second
  analysis built after the first trials — takes its box's trials from `RUNTIME.TRIALS` at
  once rather than reading empty until the next trial. With no `BoxID` only a single-subject
  runtime is unambiguous.
- `SourceSubject` / `SourceBoxID` record what the last accepted `NewData` named, and feed
  `sourceLabel`.

## Displays

| Component | Reads |
|---|---|
| `gui.components.PsychPlot` | `Results.Values` and `metric(PlotType)` in one read; click the x label to choose `Parameter` from `candidateParameters`, the y label for the metric |
| `gui.components.SlidingWindowPerformancePlot` | `windowed(windowSize)`, redrawn whole on every update; right-click for the metric and the window |
| `gui.components.Performance` | `Results` — one row per value |
| `gui.components.History` | `DATA`, `responseCodes`, `BitColors` (pastel rows: `Detection.ROW_COLORS`) |
| `gui.components.SessionPerformance` | builds a `SessionMetrics` over the same source and trial types |

The three plot/table components declare `psychTypes = "psychophysics.Detection"`, so a
behavior GUI whose analysis is a Staircase skips them at debug level instead of failing.

## Changes from the pre-Psych class (2026-11-17)

Nothing was kept for compatibility. What replaced what:

| Before | Now |
|---|---|
| `Detection(RUNTIME, P, epsych.BitMask.TrialType_0)` | `Detection(RUNTIME, P)` — the stimulus trial type is the `StimulusTrialType` option |
| `uniqueValues`, `Count`, `countUniqueValues` | `Results.Values`, `Results.N` |
| `Hit_Rate`, `FA_Rate`, `Miss_Rate`, `CR_Rate` | `Results.Rate`, or `metric("HitRate")` … |
| `DPrime`, `APrime`, `Bias` | `Results.DPrime`, `.APrime`, `.Criterion` |
| `Rate` (proportion of all trials at a value) | gone: every rate uses the aborts policy |
| `Hit_Ind`, `FA_Ind`, … | `epsych.BitMask.decode(D.responseCodes)` |
| `NumTrials`, `Trial_Index`, `trialIndex` | `trialCount` |
| `targetTrialType`, `ttStimulus`, `ttCatch` | `StimulusTrialType`, `CatchTrialType` |
| `ParameterName = …`, `ValidParameters` | `Parameter = "Field"`, `candidateParameters()` |
| `TRIALS`, `SUBJECT`, `M`, `N` | `DATA`, `sourceLabel()` |
| statics `d_prime`, `a_prime`, `bias`, `norminv` | `psychophysics.Metrics.dprime`, `.aprime`, `.criterion`, `.z` |
| `PsychPlot.PlotType` `'Hit_Rate'`, `'FA_Rate'`, `'Bias'` | `'HitRate'`, `'FARate'`, `'Criterion'` (and `'BPrimePrime'`) |
| `SlidingWindowPerformancePlot.plotType` `"dPrime"`, `"aPrime"`, `"Bias"` | `"DPrime"`, `"APrime"`, `"Criterion"` |
| `Performance.TargetTrialType` | the analysis's `StimulusTrialType` |

Defects this fixed, each checked by `tmp/smoke_test_detection.m`:

- **Reading changed state.** `Hit_Rate`, `FA_Rate`, `DPrime`, `APrime` and `Bias` assigned
  `targetTrialType`, so a read changed what the next read meant. A `PsychPlot` sharing the
  object with a sliding-window plot then read its values over one set of trials and its
  rates over another, and drew mismatched or empty data.
- **The false-alarm rate behind d′, A′ and bias was the first catch value's.** They took
  `Rate(1).FalseAlarm` over the catch trials, i.e. the rate at the lowest catch-trial value
  only — wrong whenever catch trials carry more than one value.
- **d′, A′ and bias ignored the aborts policy**, dividing by every trial at a value while
  `Hit_Rate` and `FA_Rate` left aborts out — one session, two hit rates.
- **The constructor's default trial type was `Undefined`**, pooling catch trials into the
  stimulus counts until some rate getter happened to reset it.
- **An empty value slid every later value onto the wrong trial** (`[DATA.(f)]` drops it).
- **No `TrialType` field threw**, instead of falling back to the bits; **no response-code
  field threw** at the first count.
- **`Miss_Rate` and `CR_Rate` were `1 − x`**, wrong under `IncludeAborts`.
- **An empty d′ became `+Inf`.**
- **Every Detection shared one `Events` hub** (a handle as a property default), so each
  one's `NewData` fired every other's listeners — the base class had the same defect for
  every `Psych`; both now make the hub in the constructor.
- **No offline mode, no `ExcludedTrials`, no box filter, no seeding** — all now inherited
  or added.
