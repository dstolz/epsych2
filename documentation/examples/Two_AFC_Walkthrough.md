# Two-Alternative Forced Choice: Which Side Was Brighter?

The companion example to the
[first-experiment tutorial](First_Experiment_Walkthrough.md), covering the
other major psychophysical task family. Two lamps flash together, one brighter
than the other; the subject — you — reports which side by clicking **LEFT** /
**RIGHT** or pressing an arrow key. A choice is compulsory: there is no
withhold response, so guessing scores 50% rather than 0%, and the measures of
interest change accordingly.

All files live in [examples/two_afc/](../../examples/two_afc/) and everything
runs with no hardware. The step-by-step version for a first-time user is the
wiki's [Two-AFC Task](https://github.com/dstolz/epsych2/wiki/Two-AFC-Task).

| Stage | Example file |
|---|---|
| 1. Build the protocol in code | [create_2afc_protocol.m](../../examples/two_afc/create_2afc_protocol.m) |
| 2. The behavior GUI you respond in | [TwoAFCBehaviorGUI.m](../../examples/two_afc/TwoAFCBehaviorGUI.m) |
| 3. Run a session | [run_2afc_experiment.m](../../examples/two_afc/run_2afc_experiment.m) or the [RunExpt GUI](../overviews/RunExpt_GUI_Overview.md) |
| 4. Decode and plot your data | [explore_2afc_data.m](../../examples/two_afc/explore_2afc_data.m) |

```matlab
addpath('examples/two_afc')
run_2afc_experiment            % 64 trials, then auto-save
explore_2afc_data              % choice curve, accuracy, PSE, d'
```

## What this example teaches that the first one cannot

The runtime mechanics are identical — the GUI plays the rig, raises
`x_TrialComplete_1`, and the real timer loop records the trial (see
[First_Experiment_Walkthrough.md](First_Experiment_Walkthrough.md) for that
machinery). Four things are genuinely new:

1. **Crossed conditions instead of paired ones.** `TrialType` (which side is
   correct) and `Contrast` (difficulty) are left unpaired, so `compile`
   crosses them into 2 × 4 = 8 conditions. That cross *is* the design: it
   counterbalances side against difficulty, so a subject favouring one hand
   cannot inflate performance at any one contrast. The first tutorial's
   `UserData.Pair` group does the opposite, and choosing between them is the
   main design decision in any protocol.
2. **A real Abort outcome.** Letting the response window lapse is scored
   `epsych.BitMask.Abort`, which `psychophysics.SessionMetrics` counts over
   every trial while excluding it from the hit, false-alarm, and
   percent-correct denominators — the correct treatment of a trial the
   subject never answered.
3. **Choice bits.** `Choice_0` (left) and `Choice_1` (right) record *what was
   chosen* independently of whether it was correct. Nothing shipped in the
   toolbox reads them, but the choice curve — the defining 2AFC analysis —
   needs exactly that separation, and `epsych.BitMask.decode` surfaces them.
4. **Bias as a measurable quantity.** With one alternative nominated as the
   yes-response, the criterion *is* the side bias, and the fitted point of
   subjective equality measures the same thing from the choice curve.

## The bit encoding

A 2AFC has no signal-absent trial, so the detection outcome names are recast
by treating **left as the yes-response**:

| `TrialType` | Choice | `RespCode` bits |
|---|---|---|
| 0 (left correct) | left | `Hit, Reward, Choice_0, TrialType_0` |
| 0 | right | `Miss, Punish, Choice_1, TrialType_0` |
| 1 (right correct) | right | `CorrectReject, Reward, Choice_1, TrialType_1` |
| 1 | left | `FalseAlarm, Punish, Choice_0, TrialType_1` |
| either | none | `Abort, TrialType_n` |

Keeping `Hit` on `TrialType_0` is deliberate: it matches the default
stimulus/catch settings of `psychophysics.Detection` and
`psychophysics.SessionMetrics`, so the shipped analysis applies with **no
arguments at all**. `PercentCorrect` — `(Hit + CorrectReject)` over scored
trials — is then literally 2AFC accuracy, and `Criterion` is the side bias,
negative when the subject favours left.

The failure mode to avoid is scoring both correct outcomes as `Hit`.
`SessionMetrics` counts hits only over stimulus trials, so the catch
denominator collapses to zero and false-alarm rate, correct-reject rate, d′,
and percent correct all become `NaN`. `teensy.Templates.twoAFC_` currently
does this (both choice states emit `Hit + Reward`, and its `@TrialType`
variable is never referenced by a transition), so treat that template as a
skeleton rather than a scoring reference.

`TrialType` must also be *named* `TrialType`: `psychophysics.Detection` reads
a numeric `TrialType` field out of each DATA record to label trials, and the
Teensy 2AFC template uses the same 0/1 convention.

## A parameter cannot hold NaN

Both tutorials mark "no response" with **-1**, never `NaN`. Every numeric
write passes through `hw.Parameter.clamp_value_`, which applies
`max(value, Min)`; MATLAB's `max` ignores `NaN`, so a `NaN` silently arrives
as `Min` — `-Inf` by default. This is easy to miss because nothing errors and
the stored value is still "not a number" in spirit. Any missing-data marker
has to be a real number you choose, and the analysis filters on it
(`rt >= 0`) rather than on `isnan`.

## The analysis

[explore_2afc_data.m](../../examples/two_afc/explore_2afc_data.m) runs two
analyses of the same file side by side, and they agree:

- **Hand-rolled from the decoded bits** — accuracy per contrast, P(chose
  right) against *signed* contrast (negative = left brighter), and a
  maximum-likelihood cumulative-Gaussian fit yielding the **point of
  subjective equality** (the 50% point: the stimulus the subject finds
  ambiguous, hence their bias) and the **just-noticeable difference** (the
  fitted σ, the ~84%-correct threshold).
- **Through the toolbox** — `psychophysics.SessionMetrics(DATA)` with no
  arguments, printing percent correct, abort rate, d′, and criterion.

No shipped class computes P(choice) against a signed value or a PSE, which is
why the fit lives in the example. For a live display, `gui.ParameterScatter`
(X = a signed parameter, Y = a numeric choice column, colour = outcome) is the
closest ready-made equivalent.

## Validation

`tmp/smoke_test_two_afc.m` (headless;
`matlab -batch "run('tmp/smoke_test_two_afc.m')"`) drives a full session
through the real timer loop with a psychometric observer carrying a known
leftward bias, then asserts the whole encoding table above, that
`SessionMetrics` percent correct matches a hand count with default settings,
and that the fitted PSE recovers the injected bias.

## Next steps

- [First_Experiment_Walkthrough.md](First_Experiment_Walkthrough.md) — the
  Go/No-Go tutorial to do first
- [Detection_Task_Walkthrough.md](Detection_Task_Walkthrough.md) — custom
  trial selectors and online psychometrics
- [psychophysics_SessionMetrics.md](../psychophysics/psychophysics_SessionMetrics.md)
  — every metric, and how the windows and denominators work
