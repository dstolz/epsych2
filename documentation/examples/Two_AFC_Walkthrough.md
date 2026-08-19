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
explore_2afc_data              % choice curve, accuracy, PSE, choice bias
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
2. **Two ways to fail a trial, and they are different.** Letting the response
   window lapse means the subject never chose: no outcome bit at all —
   **Undefined**. Answering *before* the window opens is an
   `epsych.BitMask.Abort`. Neither is a `Miss`, which in a forced choice means
   the subject chose and chose wrong.
3. **Choice bits carry the side.** `Choice_0` (left) and `Choice_1` (right)
   record *what was chosen* independently of whether it was correct — and they
   are the only bits that do. The choice curve, the defining 2AFC analysis,
   needs exactly that separation; `psychophysics.NAFC` and
   `epsych.BitMask.decode` both read them.
4. **Bias as a measurable quantity.** P(chose left) re the 50% chance level is
   the side bias, and the fitted point of subjective equality measures the same
   thing from the choice curve.

## The bit encoding

A 2AFC has no signal-absent trial and no yes-response, so the **side is
carried by the `Choice` bit** and the outcome bit says only whether that
choice was right:

| `TrialType` | Choice | `RespCode` bits |
|---|---|---|
| 0 (left correct) | left | `Choice_0, Hit, Reward, TrialType_0` |
| 0 | right | `Choice_1, Miss, Punish, TrialType_0` |
| 1 (right correct) | right | `Choice_1, Hit, Reward, TrialType_1` |
| 1 | left | `Choice_0, Miss, Punish, TrialType_1` |
| either | none (window lapsed) | `TrialType_n` only — **Undefined**: no outcome bit, no `Choice` bit |
| either | answered too early | `Abort, TrialType_n` |

Correct is `Hit` and only `Hit`, which is what makes this reading identical
for a 2AFC and a 4AFC. `CorrectReject` and `FalseAlarm` name what a subject
does when there is nothing to respond to; they belong to detection and are
never set here. `Reward` / `Punish` record the contingency the paradigm
delivered — experimental design, not scoring, and a paradigm that gives
neither simply omits them.

> **`psychophysics.SessionMetrics` does not apply to a forced choice.** Its
> hit rate, false-alarm rate, d′ and criterion are built on a stimulus/catch
> split that a 2AFC does not have. `psychophysics.NAFC` is the analysis for
> this task: proportion correct against 1/N, the choice functions, the
> confusion matrix, and the per-alternative choice bias. That is also why
> `TwoAFCBehaviorGUI` has no `gui.SessionPerformance` panel.

`TrialType_0` / `TrialType_1` name the trial's **category**. In this task the
category and the correct alternative are the same thing — a left-target trial
or a right-target trial — which is why `psychophysics.NAFC` can recover the
correct side from the bits alone. A paradigm whose categories are
stimulus / catch / remind keeps those for the category and records the correct
alternative in a field of its own, named through `CorrectField`.

The DATA field must also be *named* `TrialType` unless you say otherwise:
that is the field `psychophysics.NAFC` reads by default for the correct
alternative, and the Teensy 2AFC template uses the same 0/1 convention.

`teensy.Templates.twoAFC_` records only the `Choice_*` bit (plus `Reward`) and
deliberately claims no `Hit`: the condition language has no variable
comparison, so the board cannot check the choice against `@TrialType`.
`psychophysics.NAFC` scores correctness from the choice and the correct
alternative rather than from the outcome bits, which is exactly the case that
leaves the board nothing to lie about.

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
- **Through the toolbox** — `psychophysics.NAFC(DATA, 'SignedContrast', ...)`,
  printing percent correct against the 50% chance level, the per-alternative
  choice bias, and the no-response / abort split.

No shipped class computes P(choice) against a signed value or a PSE, which is
why the fit lives in the example. For a live display, `gui.ParameterScatter`
(X = a signed parameter, Y = a numeric choice column, colour = outcome) is the
closest ready-made equivalent.

## Validation

`tmp/smoke_test_two_afc.m` (headless;
`matlab -batch "run('tmp/smoke_test_two_afc.m')"`) drives a full session
through the real timer loop with a psychometric observer carrying a known
leftward bias, then asserts the whole encoding table above — including that no trial ever
carries `CorrectReject` or `FalseAlarm`, and that an early answer and a lapsed
window are told apart — that `psychophysics.NAFC` percent correct matches a
hand count, and that the fitted PSE recovers the injected bias.

## Next steps

- [First_Experiment_Walkthrough.md](First_Experiment_Walkthrough.md) — the
  Go/No-Go tutorial to do first
- [Detection_Task_Walkthrough.md](Detection_Task_Walkthrough.md) — custom
  trial selectors and online psychometrics
- [psychophysics_NAFC.md](../psychophysics/psychophysics_NAFC.md)
  — the analysis for a forced choice, and the bit encoding it reads
- [psychophysics_SessionMetrics.md](../psychophysics/psychophysics_SessionMetrics.md)
  — the DETECTION summary: every metric, and how the windows and denominators work
