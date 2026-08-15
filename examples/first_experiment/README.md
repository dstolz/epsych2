# Your First Experiment: Be the Subject

A complete EPsych experiment in which **you play the subject**: on go trials
the box GUI's lamp flashes briefly; press **RESPOND** if you saw it, withhold
if you did not. The GUI scores each trial (Hit / Miss / False Alarm / Correct
Reject), and your data are journaled and saved through the same runtime
machinery a real rig uses — the only thing missing is the hardware.

Full step-by-step walkthrough for new users:
**[Your First Experiment](https://github.com/dstolz/epsych2/wiki/Your-First-Experiment)** on the wiki.

## Quick start

```matlab
addpath('examples/first_experiment')

run_first_experiment           % builds the protocol if needed, opens the GUI,
                               % runs 40 trials, saves your data automatically
explore_first_data             % decode + plot the session you just ran
```

Prefer the real session GUI? The wiki walkthrough runs the identical
experiment through `epsych.RunExpt` (subjects, projects, Run/Stop/Save Data).

## Files

| File | Purpose |
|---|---|
| `create_first_protocol.m` | Builds and saves `FirstExperiment.eprot` in code: paired go/catch conditions, randomized ITI, read-back parameters, the three core triggers |
| `FirstExperimentBoxGUI.m` | `gui.BoxGUI` subclass with a subject panel (stimulus lamp + RESPOND button), manual-scoring buttons, and the trial timeline. It plays the rig: scores the outcome, writes `RespCode`/`RT_ms`, and raises `x_TrialComplete_1` — the flag the runtime polls |
| `run_first_experiment.m` | One-command session on the **real** timer loop (`ep_TimerFcn_Start`/`RunTime`/`Stop`) without RunExpt; auto-saves at the trial quota or when the GUI closes |
| `explore_first_data.m` | Loads the saved file, decodes `RespCode` via `epsych.BitMask`, reports hit rate / FA / d' / reaction time, plots the session |

Generated at runtime (not checked in): `FirstExperiment.eprot`, `data/*`.

## How a trial completes (the point of the example)

`ep_TimerFcn_RunTime` polls exactly one thing per timer tick:
`x_TrialComplete_<BoxID>.Value`. On a TDT or Teensy rig the device raises it;
here the GUI does, after you respond or the response window lapses. The
runtime then collects every readable parameter into a DATA record, journals
it, broadcasts `NewData`, selects the next condition, and dispatches it —
which fires `NewTrial`, and the GUI starts the next trial's timeline. Swap the
software interface for real hardware and the box GUI's rig role moves into the
device; nothing else changes.

## Related

- [examples/detection_task/](../detection_task/) — the next step: a worked
  example with a custom trial selector, online psychometrics, and a simulated
  observer instead of a human
- [examples/customgui/](../customgui/) — minimal `gui.BoxGUI` starter template
- [documentation/gui/gui_BoxGUI.md](../../documentation/gui/gui_BoxGUI.md)
- Validation: `tmp/smoke_test_first_experiment.m` (headless;
  `matlab -batch "run('tmp/smoke_test_first_experiment.m')"`)
