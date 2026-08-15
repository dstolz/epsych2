# Your First Experiment: Be the Subject

A complete EPsych experiment in which **the human at the keyboard is the
subject**. On go trials the behavior GUI's stimulus lamp flashes for a few tens of
milliseconds; on silent catch trials nothing happens. Press **RESPOND** during
the response window if you saw the flash, withhold if you did not. Every trial
is scored as an [epsych.BitMask](../epsych/epsych_BitMask.md) response code
(Hit / Miss / FalseAlarm / CorrectReject), journaled crash-safe, and saved —
through the same runtime machinery a real rig uses.

All files live in [examples/first_experiment/](../../examples/first_experiment/)
and everything runs with no hardware. The expanded, step-by-step version of
this walkthrough — written for someone running EPsych for the first time — is
the wiki's dedicated tutorial section, starting at
[Your First Experiment](https://github.com/dstolz/epsych2/wiki/Your-First-Experiment).

| Stage | Example file |
|---|---|
| 1. Build the protocol in code | [create_first_protocol.m](../../examples/first_experiment/create_first_protocol.m) |
| 2. The behavior GUI you respond in | [FirstExperimentBehaviorGUI.m](../../examples/first_experiment/FirstExperimentBehaviorGUI.m) |
| 3. Run a session | [run_first_experiment.m](../../examples/first_experiment/run_first_experiment.m) (scripted) or the [RunExpt GUI](../overviews/RunExpt_GUI_Overview.md) |
| 4. Decode and plot your data | [explore_first_data.m](../../examples/first_experiment/explore_first_data.m) |

## Quick start

```matlab
addpath('examples/first_experiment')

run_first_experiment           % builds the protocol if needed, opens the GUI,
                               % runs 40 trials, saves your data automatically
explore_first_data             % decode + plot the session you just ran
```

## Why this example exists

The [detection task worked example](Detection_Task_Walkthrough.md) replays the
runtime's trial loop in a plain script with a simulated observer. This example
does the opposite, and it is the only one in the repository that does: it runs
the **real timer loop** — `ep_TimerFcn_Start`, then `ep_TimerFcn_RunTime` on a
live MATLAB timer, then `ep_TimerFcn_Stop` — against the `hw.Software`
backend, with a human completing the trials.

That works because of how minimal the runtime's hardware contract is.
`ep_TimerFcn_RunTime` polls exactly one thing per tick:
`x_TrialComplete_<BoxID>.Value` (cached at startup by
`epsych.Runtime.resolveCoreParameters`). Everything else about a trial — the
stimulus timeline, the response window, the scoring — is the rig's business.
On a TDT rig it lives in the RPvds circuit; on a Teensy it lives in the
compiled trial program; here it lives in `FirstExperimentBehaviorGUI`, which:

1. on `NewTrial`, clears `x_TrialComplete_1` and starts the trial timeline
   (ITI → flash → response window) on its own 20 ms rig timer;
2. arms the RESPOND button only while the response window is open;
3. scores the outcome by the task contingency, packs it with
   `epsych.BitMask.Bits2Mask`, and writes the `RespCode` and `RT_ms`
   read-back parameters (widening `Access='Read'` for the write — the
   simulation-only trick, needed because `hw.Software` stores values in the
   parameter object itself);
4. raises `x_TrialComplete_1.Value = 1`, handing the trial to the runtime,
   which collects every readable parameter into a DATA record, appends it to
   the crash-safe [trial journal](../epsych/epsych_TrialJournal.md),
   broadcasts `NewData`, selects the next condition, and dispatches it —
   firing `NewTrial`, which starts the next timeline.

Swap the software interface for real hardware and steps 1–4 move into the
device. The parameter names are the contract, not where they are set.

Two details that bite anyone reimplementing this:

- **Seed the trigger values.** `add_parameter` stores design-time `Values` but
  not a live `Value`; an unset `x_TrialComplete_1.Value` makes the first
  runtime tick misread the trial as complete. `create_first_protocol` seeds
  all three core triggers to 0.
- **The GUI misses trial 1's `NewTrial`.** The first dispatch happens inside
  `ep_TimerFcn_Start` (the `TRIALS` setter), before the behavior GUI exists.
  `FirstExperimentBehaviorGUI` therefore starts the current trial's timeline from
  `onModeChange` when the session mode goes to Record/Preview and its rig is
  still idle.

## The protocol

`create_first_protocol.m` builds `FirstExperiment.eprot`: `TrialType` and
`FlashDur` share a `UserData.Pair` group, so four flash durations plus one
silent catch compile to five conditions (not crossed); `ITI` uses `isRandom`
with `[Min, Max]`; `RespWinDelay`/`RespWinDur` are single-value operator
knobs; `RespCode`, `RT_ms`, and `InTrial` are `Access='Read'` read-backs that
land in every DATA record. Trial selection is the default
`epsych.DefaultTrialSelector` (least-presented condition, random ties). The
response window opens at a fixed delay after trial onset on go and catch
trials alike, so its timing never reveals a catch trial.

## Running through RunExpt

The scripted driver is the fastest path, but the identical session runs
through the real session GUI — that path is the point of the wiki tutorial:

1. `addpath('examples/first_experiment')` — the GUI class must be resolvable.
2. `epsych.RunExpt` → **Subjects** (Ctrl+B) → new project with **Behavior GUI** =
   `FirstExperimentBehaviorGUI` and **Default Protocol** = `FirstExperiment.eprot`
   (Session Defaults tab), add a subject, **Add Checked to Session**.
3. **View Trials** to preview the five compiled conditions, then **Run**
   (or **Preview** for data marked as a test).
4. Do the task. **Stop**, then **Save Data**.

## The data

Each DATA record carries the read-backs (`RespCode`, `RT_ms`, `InTrial`),
every dispatched parameter (`FlashDur`, `TrialType`, `ITI`, ...), and the
runtime's bookkeeping (`TrialIndex`, `TrialID`, `computerTimestamp`,
`isTest`). `explore_first_data.m` decodes `RespCode` with
`epsych.BitMask.decode`, prints hit rate and d' per flash duration against
the catch false-alarm rate, and plots the trial timeline, psychometric
function, and reaction times. The DATA array index is chronological order;
`TrialID` is the condition row, not the presentation order.

## Validation

`tmp/smoke_test_first_experiment.m` (headless;
`matlab -batch "run('tmp/smoke_test_first_experiment.m')"`) runs the whole
example under an auto-clicker: real timer loop, GUI-completed trials, outcome
and RT assertions, journal-merge check, and offline analysis.

## Next steps

- [Two_AFC_Walkthrough.md](Two_AFC_Walkthrough.md) — the companion tutorial:
  a two-alternative forced choice with crossed conditions, a real Abort
  outcome, choice bits, and bias as a measurable quantity
- [Detection_Task_Walkthrough.md](Detection_Task_Walkthrough.md) — a custom
  trial selector, online psychometrics, and a simulated observer replacing
  the human
- [gui_BehaviorGUI.md](../gui/gui_BehaviorGUI.md) — the base class behind the GUI
- [epsych_TrialLifecycle.md](../epsych/epsych_TrialLifecycle.md) — the full
  trial lifecycle reference
