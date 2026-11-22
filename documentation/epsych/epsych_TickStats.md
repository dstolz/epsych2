# epsych.TickStats

Timing of the trial loop, recorded only when a session asks for it.

The trial loop shares one MATLAB thread with every GUI timer, listener and
redraw. `epsych.TickStats` records how long each timer tick took and how long
each trial boundary took, split by phase, so an overrun or a slow boundary is
visible instead of guessed at.

It is **off by default**. `epsych.Runtime.TickStats` is empty unless something
creates one, and every call site tests `isempty` first.

## Turning it on

For sessions run from `epsych.RunExpt`, set the preference once on the rig:

```matlab
setpref('EPsych', 'TickStats', true)    % record and report every session
setpref('EPsych', 'TickStats', false)   % stop
```

RunExpt creates the recorder at Run and logs a summary at Stop (level 1, so it
reaches the command window at the default verbosity). The recorder stays on
`RUNTIME.TickStats` afterwards.

From a script:

```matlab
RUNTIME.TickStats = epsych.TickStats(Period = 0.01);
% ... run ...
S = RUNTIME.TickStats.summary();
RUNTIME.TickStats.report()
```

## What is recorded

**Ticks.** The duration of every timer tick, in a ring of `TickCapacity`
(200000 by default, about half an hour at 10 ms). A tick longer than `Period`
is counted in `Overruns`.

**Trial boundaries.** From the moment a trial is found complete to the end of
the `NewTrial` listeners, split into the phases in `epsych.TickStats.PHASES`:

| Phase | What it covers |
|---|---|
| `sweep` | reading every readable parameter into the trial record |
| `journal` | appending the record to the trial journal |
| `onComplete` | `selector.onComplete` |
| `newData` | every `NewData` listener: analysis and displays |
| `recompile` | a pending operator recompile, when there is one |
| `select` | `selector.selectNext` |
| `reset` | the ResetTrig pulse |
| `writes` | the per-trial parameter writes |
| `trigger` | the NewTrial pulse; the next trial starts when it ends |
| `render` | deferred display work flushed after the trigger |
| `newTrial` | every `NewTrial` listener |

The phases up to and including `trigger` are time the subject waits through.
`summary().Waited` reports that sum; `summary().Boundary` reports all phases.

## Methods

| Method | Purpose |
|---|---|
| `tickBegin`, `tickEnd` | bracket one timer tick |
| `boundaryBegin`, `mark(phase)`, `boundaryEnd` | bracket a boundary and close each phase |
| `summary` | struct of medians, 95th percentiles and maxima, in ms |
| `report` | log the summary |
| `tickDurations` | recorded tick durations, in seconds |
| `phaseTable` | one row per boundary, one variable per phase, in seconds |

A `mark` outside an open boundary, or for a name not in `PHASES`, is ignored,
so the first dispatch of a session and a regenerated trial cost nothing.

## Measuring without a rig

`tmp/bench_trial_boundary.m` drives the real trial loop against a counting
stand-in for the device and reports device calls, log records and time per
phase. Its counts are deterministic; pass `CallDelay` to predict a rig whose
per-call latency `hw.benchmarkIO` has measured.

Two things about MATLAB that the benchmark depends on, both measured on R2024b:

- Code running in a **timer callback is never interrupted by another timer**,
  not even at a `pause` or a `drawnow`. Top-level code is interrupted by any
  running timer between statements. The benchmark therefore runs the loop
  inside a timer callback, as a session does.
- A `pause` or `drawnow` inside a timer callback **does render pending
  graphics**. A `pause(0.001)` after a table change measured about 24 ms; a
  1 ms busy wait measured 1 ms and left the render for later.
