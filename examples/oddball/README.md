# Auditory Oddball: Respond to the Odd One Out

An auditory oddball detection task in which **you are the subject**. A stream
of short sounds plays, one every second or two. Most are **standards** (steady
tones); now and then comes a **deviant** (a rising glide). Press **RESPOND**, or
the space bar, inside the response window when you hear a deviant, and let the
standards go by. After every sound the GUI tells you how it was scored:

|                 | you responded   | you withheld       |
|-----------------|-----------------|--------------------|
| **deviant**     | HIT             | MISS               |
| **standard**    | FALSE ALARM     | CORRECT REJECT     |

Everything runs in software through the same runtime a real rig uses: the
behavior GUI plays the sounds and scores the responses, and every trial is
journaled, recorded and saved exactly as in a hardware session.

## Quick start

```matlab
addpath('examples/oddball')

run_oddball_experiment          % opens the GUI; press Start, then listen
explore_oddball_data            % decode + plot the session you just ran
```

The first run writes the default sound banks (`sounds/standards`,
`sounds/deviants`) and the protocol (`Oddball.eprot`). The session runs until
you press **Stop** or close the window; `run_oddball_experiment(NumTrials = 60)`
stops by itself instead. Either way the data file saves automatically.

To run it from `epsych.RunExpt` instead, give a project `Oddball.eprot` as its
protocol and `OddballBehaviorGUI` as its Behavior GUI (Subjects > Subjects &
Projects > Edit Project > Session Defaults); this folder must be on the path.

## The behavior GUI

- **Transport bar** — **Start** (the stock `gui.components.SessionGate`: nothing
  plays until it is pressed), **Pause/Resume**, **Stop**, the run-mode lamp, and
  the running tally of hits, misses, false alarms and correct rejects.
- **Subject panel** — a lamp that lights while each sound plays (the same for
  standards and deviants), the **RESPOND** button, armed only during the
  response window, and the trial-by-trial feedback.
- **Sound Banks** — the standard and deviant `.wav` files. **Choose...** picks a
  new set (any number of files), **Play** auditions the selected one.
- **Trial Structure** — fewest/most standards before a deviant, the silent
  interval before each sound (a Min–Max range, redrawn every trial), when the
  response window opens and how long it stays open. Edits are staged and
  committed together with **Update** (or Ctrl+Enter).
- **Displays** — `gui.components.SessionPerformance` (rates, counts, d′), and in
  tabs: hit rate, false-alarm rate and d′ over trials
  (`gui.components.SlidingWindowPerformancePlot`), hit rate by deviant sound and
  by the number of standards before it (`gui.components.PsychPlot`), reaction
  times (`gui.components.ParameterScatter`); below them the trial history
  (`gui.components.History`). Every one of them is a stock component.

**Pause** takes effect at the next sound: a response window already open is
allowed to finish, and the silent interval starts over on **Resume**. It is the
same run-mode broadcast RunExpt's own Pause button sends, so RunExpt's Pause
pauses this GUI too, and **Resume** here resumes it. **Stop** goes through
RunExpt's own Stop when RunExpt is running the session, and otherwise stops the
session timer; completed trials are kept, the trial in progress is not.
Pauses, resumes, stops and bank changes are written into the session notes,
and so into the data file.

## Files

| File | Purpose |
|---|---|
| `make_oddball_sounds.m` | Writes the default banks: 4 steady tones (standards), 3 octave glides (deviants) |
| `create_oddball_protocol.m` | Builds `Oddball.eprot`: the deviant/standard condition, the trial-structure parameters, the two banks, the read-back parameters, the three core triggers |
| `OddballSelector.m` | `epsych.TrialSelector`: block-randomized run lengths and sounds, recorded per trial |
| `OddballBehaviorGUI.m` | `gui.BehaviorGUI` subclass: the rig (plays, times, scores, completes each trial), the transport, the settings and the displays |
| `run_oddball_experiment.m` | One-command session on the **real** timer loop (`ep_TimerFcn_Start`/`RunTime`/`Stop`); saves when the session ends |
| `explore_oddball_data.m` | Decodes `RespCode`; reports hit/FA rates and d′, hit rate by sound and by run length, FA rate by position, RTs, and checks the block structure |

Generated at runtime (not checked in): `Oddball.eprot`, `sounds/`, `data/`.

## One trial is one sound

Every sound is scored, so the task is a Go/No-Go detection in EPsych's terms:
deviants are the stimulus trials (`TrialType` 0, the `TrialType_0` bit) and
standards the catch trials (`TrialType` 1). That is the encoding
`psychophysics.Detection` and `psychophysics.SessionMetrics` expect, which is
why every display in the GUI is a stock component with no oddball-specific code.

A trial's timeline: the silent interval (`ITI`, redrawn between Min and Max),
then the sound; the response window opens `RespWinDelay` ms after onset
(100 ms by default — faster than any genuine response to the sound) and stays
open `RespWinDur` ms. A press inside it scores the trial at once; otherwise it
is scored when the window closes. A press outside any window is ignored, so a
late response to a deviant is not counted against the next standard.

## Blockwise randomization (the part worth copying)

The stream is built as **runs**: each run is *n* standards and then one
deviant, *n* between `MinStandards` and `MaxStandards`. `OddballSelector`
drives three `epsych.BlockSequence` objects:

| Sequence | Draws from | Indexed by |
|---|---|---|
| run lengths | `MinStandards:MaxStandards` | run number |
| standards | `StandardFiles` | standard number |
| deviants | `DeviantFiles` | deviant number |

A block is one shuffle of the whole list, so with the defaults every six
deviants arrive after exactly one run of each length 1–6, and every sound in a
bank plays once before any plays twice — balanced within every block, not just
on average over a long session as `hw.Parameter.isRandom` would be.

Every decision is a pure function of the trial index: trial *k* lies in run
*r*, is the deviant if it is the run's last trial, and is standard number
*k − (r − 1)* or deviant number *r*. Nothing is advanced by a call, so a second
selection for the same trial returns the same sound, and `preview(k)` can look
ahead or back.

**What each trial played is recorded.** Before a trial is dispatched the
selector writes four read-back parameters, which the runtime then collects into
the trial's DATA record:

| Field | Meaning |
|---|---|
| `StimFile` | The `.wav` played |
| `StimID` | Its position in its bank |
| `RunLength` | Standards in this trial's run — for a deviant, how many preceded it |
| `RunPosition` | 1..`RunLength` for a standard, `RunLength`+1 for the deviant |

The sequences' seeds go into the session notes (so into every data file), and
`run_oddball_experiment` also saves the whole sequences as `Sequences`.

**Live edits.** The banks and the run-length range can change mid-session.
What was already played is frozen; a bank replaced by one of the same size
keeps its shuffled order; any other change starts at that sequence's next whole
block, because a half-old, half-new block would quietly break the balance. The
run in progress always finishes at the length it started with.

**The banks are configuration, not trial data.** `StandardFiles` and
`DeviantFiles` are `File` parameters with `Visible = false`, which keeps them out
of the trial table *and* out of DATA (`Protocol.compile_internal` and
`ep_TimerFcn_RunTime` both filter on it): each trial records the one file it
played instead of the whole list.

## Related

- [examples/first_experiment/](../first_experiment/) — the simplest
  be-the-subject Go/No-Go, with a visual flash
- [examples/two_afc/](../two_afc/) — a forced choice, where chance is 50%
- [examples/detection_task/](../detection_task/) — a custom selector and a
  simulated observer instead of a human
- [documentation/epsych/epsych_BlockSequence.md](../../documentation/epsych/epsych_BlockSequence.md)
- [documentation/gui/gui_SessionGate.md](../../documentation/gui/gui_SessionGate.md)
- Validation: `tmp/smoke_test_oddball_example.m` (headless and silent;
  `matlab -batch "run('tmp/smoke_test_oddball_example.m')"`) — a scripted
  responder drives the real timer loop through all four outcomes, Pause/Resume,
  a mid-session bank change, Stop, the Start gate and a trial quota
