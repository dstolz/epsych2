# Two-Alternative Forced Choice: Which Side Was Brighter?

The companion to [examples/first_experiment/](../first_experiment/), for the
other half of psychophysics. Two lamps flash together, one brighter than the
other; you report which side by clicking **LEFT** / **RIGHT** or pressing the
arrow keys. Every trial demands a choice — there is no withhold response — so
guessing scores 50%, not 0%, and the interesting measures become **accuracy**,
**the choice curve**, and **bias**.

Full walkthrough for new users:
**[Two-AFC Task](https://github.com/dstolz/epsych2/wiki/Two-AFC-Task)** on the wiki.

## Quick start

```matlab
addpath('examples/two_afc')

run_2afc_experiment            % builds the protocol if needed, opens the GUI,
                               % runs 64 trials, saves your data automatically
explore_2afc_data              % decode + plot the session you just ran
```

## Files

| File | Purpose |
|---|---|
| `create_2afc_protocol.m` | Builds `TwoAFC.eprot`: side **crossed** with difficulty (8 conditions), randomized ITI, read-back parameters, the three core triggers |
| `TwoAFCBehaviorGUI.m` | `gui.BehaviorGUI` subclass: two stimulus lamps, LEFT/RIGHT buttons plus arrow-key input, a live `psychophysics.NAFC` choice plot (right-click for proportion correct, the confusion matrix, or a pop-out window), and the rig role — trial timeline, 2AFC scoring, and `x_TrialComplete_1` |
| `run_2afc_experiment.m` | One-command session on the **real** timer loop (`ep_TimerFcn_Start`/`RunTime`/`Stop`); auto-saves at the trial quota or when the GUI closes |
| `explore_2afc_data.m` | Decodes `RespCode`, fits the choice curve, reports PSE / JND / accuracy / d′ / criterion, and cross-checks against `psychophysics.SessionMetrics` |

Generated at runtime (not checked in): `TwoAFC.eprot`, `data/*`.

## What is different from the first experiment

| | First experiment (Go/No-Go) | This example (2AFC) |
|---|---|---|
| Response | One button, press or withhold | Two buttons (or arrow keys); a choice is compulsory |
| Conditions | Paired parameters (5 conditions) | **Crossed** parameters: side × difficulty (8 conditions) |
| No response | Scored as Miss / Correct Reject | Scored as **Abort** — excluded from accuracy |
| Chance level | 0% | 50% |
| Key measures | Hit rate, d′ | Accuracy, choice curve, **PSE** (bias), JND |

## The bit encoding (the part worth copying)

A 2AFC has no "signal absent" trial, so the detection outcome names are recast
by treating **one alternative — left — as the yes-response**:

| Trial | Response | `RespCode` bits |
|---|---|---|
| `TrialType` 0 (left correct) | chose left | `Hit, Reward, Choice_0, TrialType_0` |
| `TrialType` 0 | chose right | `Miss, Punish, Choice_1, TrialType_0` |
| `TrialType` 1 (right correct) | chose right | `CorrectReject, Reward, Choice_1, TrialType_1` |
| `TrialType` 1 | chose left | `FalseAlarm, Punish, Choice_0, TrialType_1` |
| either | no answer | `Abort, TrialType_n` — no `Choice_*` bit |

`Choice_0` = left and `Choice_1` = right record **what was chosen**
independently of whether it was right, which is what the choice curve needs.
Keeping `Hit` on `TrialType_0` trials is deliberate: it matches the default
stimulus/catch settings of `psychophysics.Detection` and
`psychophysics.SessionMetrics`, so the shipped analysis works with **no
arguments** — `PercentCorrect` becomes 2AFC accuracy and `Criterion` becomes
the side bias (negative toward left).

> Do **not** score both correct outcomes as `Hit`. `SessionMetrics` counts hits
> only over stimulus trials, so the catch denominator collapses and false-alarm
> rate, d′, and percent correct all break. Note that
> `teensy.Templates.twoAFC_` currently does exactly that — its `@TrialType`
> variable is declared but never wired into scoring, so it is a skeleton, not a
> working contingency.

## A parameter cannot hold NaN

Both examples mark "no response" with **-1**, never `NaN`. Every numeric write
is clamped by `hw.Parameter.clamp_value_` with `max(value, Min)`, and MATLAB's
`max` ignores `NaN` — so a `NaN` silently arrives as `Min`, which is `-Inf` by
default. Any missing-data marker has to be a real number you choose.

## Related

- [examples/first_experiment/](../first_experiment/) — the tutorial to do first
- [examples/detection_task/](../detection_task/) — custom trial selector and a
  simulated observer
- Validation: `tmp/smoke_test_two_afc.m` (headless;
  `matlab -batch "run('tmp/smoke_test_two_afc.m')"`) — drives the real timer
  loop with a psychometric observer and checks that the fitted PSE recovers the
  injected bias
