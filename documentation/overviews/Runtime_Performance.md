# Runtime performance

What a running session spends its time on, the settings that change it, and
how to measure it on a rig.

Everything at runtime shares one MATLAB thread: the trial loop (the
PsychTimer, 10 ms, `fixedSpacing`), every GUI polling timer, every event
listener, and all graphics. Timing *inside* a trial lives in the hardware and
is not affected by anything here. What MATLAB controls is the **trial
boundary** — the dead time between one trial ending and the next starting —
and how busy the thread is in between.

## The trial boundary

In order, inside `ep_TimerFcn_RunTime`, for a subject whose trial completed:

| Phase | What happens | `epsych.TickStats` name |
|---|---|---|
| Sweep | every readable parameter is read into the trial record (`Runtime.trialRecord`) | `sweep` |
| Journal | the record is appended to the `.epj` journal | `journal` |
| Selector | `selector.onComplete` | `onComplete` |
| NewData | every listener runs: analysis objects recompute, and displays redraw unless they are deferred | `newData` |
| Recompile | only when a phase load or the operator asked for one | `recompile` |
| Select | `selector.selectNext` | `select` |
| Reset | the `ResetTrig` pulse | `reset` |
| Writes | every per-trial parameter is assigned (`dispatchNextTrial`) | `writes` |
| Trigger | the `NewTrial` pulse — **the next trial starts here** | `trigger` |
| Render | display work that was deferred | `render` |
| NewTrial | the `NewTrial` event | `newTrial` |

The subject waits through everything up to and including `trigger`.

## Measuring it

**On a rig, during a real session.** Turn on trial-loop timing and run a
Preview:

```matlab
setpref('EPsych', 'TickStats', true)
% ... Preview a session, then Stop: the summary is logged at Stop
setpref('EPsych', 'TickStats', false)
```

The report gives the wait per trial (median, 95th percentile, maximum), each
phase, tick durations and overruns. See
[epsych_TickStats.md](../epsych/epsych_TickStats.md).

**On a rig, a whole session with no animal.** `tmp/bench_rig_preview.m` runs a
Preview of one roster subject through `epsych.RunExpt` — its own membership,
protocol, circuit and behavior GUI — with a simulated subject completing the
trials, and reports each boundary's wait, its phases, how long graphics held
the thread after it, and whether any of that grew over the session.

```matlab
addpath(fullfile(EPsychInfo.root, 'tmp'))
bench_rig_preview(Subject="SUBJ-ID-1171", NumTrials=250, ProfileTrials=20)
```

The hardware runs: sound plays and the pellet dispenser fires on about two
trials in three. The lab's roster is only read, and no data file is written.
The simulated subject (`tmp/RigPreviewSubject.m`) drives the appetitive
platform circuit, where the response is *leaving the platform* during the
response window. `ProfileTrials` adds trials under the MATLAB profiler,
reported per function and per line of the toolbox's own files.

**Without hardware.** `tmp/bench_trial_boundary.m` drives the real loop
against a counting stand-in for the device and reports device calls, log
records and milliseconds per phase. The counts do not depend on the machine;
set `CallDelay` to a rig's per-call latency (`hw.benchmarkIO`) to predict that
rig.

```matlab
bench_trial_boundary(NumWrite=40, NumRead=20, NumControls=20, CallDelay=200e-6)
bench_trial_boundary(Displays=true, DeferDisplays=true)
```

**Per call.** [`hw.benchmarkIO`](../hw/hw_benchmarkIO.md) times a backend's
reads, writes and triggers.

Two facts about MATLAB that decide how any of this is measured (R2024b,
measured): code inside a timer callback is never interrupted by another
timer, not even at a `pause` or `drawnow`, while top-level code is
interrupted between statements — so time the loop from inside a timer
callback, as the benchmark does. And a `pause` inside the boundary does not
let other timers in, but it does force every pending graphics update to
render there: 24 ms measured for one table change.

## Settings

Everything that changes what a session does is off unless asked for. The
first column is where to ask.

| Setting | Default | Effect |
|---|---|---|
| `setpref('EPsych','DeferDisplays',true)`, or a behavior GUI's `deferDisplayWork` returning true | off (on for `cl_AppetitiveDetection_BehaviorGUI`) | Displays draw after the `NewTrial` pulse instead of before it. Analysis is never deferred. |
| `hw.Interface.SkipUnchangedStimulus` | **on** | A `StimType` waveform is not uploaded again when the tag was last uploaded the same samples. |
| `setpref('EPsych','SkipUnchangedWrites',true)`, or `iface.SkipUnchangedWrites` | off | In the trial loop's dispatch, a parameter the device was just read back holding is not written again. |
| **Record buffer parameters in every trial**, on the project's Session Defaults tab (Subjects window); `RUNTIME.RecordBuffers` in a script | on (buffers recorded) | Cleared, `Buffer` and `Coefficient Buffer` parameters are left out of the trial-end read and the record. |
| **Record a stimulus as its settings, not the stimulus object**, on the same tab; `RUNTIME.RecordStimulusSettings` in a script | off | Ticked, a `StimType` value is recorded as its settings, not as the live object. |
| `hw.NE1000.SettingsCacheInterval` | 0 (off) | A setting the pump reported answers the next read of it for this many seconds. |
| `setpref('EPsych','StopOnIdleHardware',true)` | off | A multi-interface session stops when an interface reports Idle. |
| `setpref('EPsych','WarmUp',false)` | **on** | Off: the first Run or Preview after MATLAB starts does not rehearse a few trial boundaries on a software-only session first (`epsych.warmUp`, about 2 s). |
| `setpref('EPsych','TickStats',true)` | off | Trial-loop timing, reported at Stop. |
| `GLogVerbosity` | `Inf` | What the log file takes. At 3, trace records cost microseconds instead of being written. |

The two trial-record settings belong to the **study**, not the rig: they
ride each subject's roster membership with the rest of the session
settings and are saved with every session. The rest are rig preferences. A
preference that does not exist changes nothing; read them with `ispref`
first, since `getpref` with a default creates one.

### Turning the opt-in settings on

**For a study**, in the Subjects window: select the project, **Edit...**, the
**Session Defaults (template)** tab, and set the two **Trial Record**
checkboxes. Existing members keep what they were stamped with until
*Project > Re-apply Project Template to Checked*; one subject is set apart
with *Subject > Session Settings...*. What to check first:

- *Record buffer parameters in every trial*: clear it when no analysis reads
  a buffer out of `Data(k)`.
- *Record a stimulus as its settings*: tick it unless an analysis calls
  methods on `Data(k).<StimParameter>`. It becomes a struct of the
  stimulus's settings; field reads (`.Frequency`, `.Duration`) are unchanged.

A batch of subjects has to agree on both, like any session setting. Each
saved session records which was in effect (`Info.RecordBuffers`,
`Info.RecordStimulusSettings`).

**For a rig**, each is one line at the MATLAB prompt, takes effect at the
next Run, and is undone with `rmpref('EPsych', '<name>')`:

```matlab
% No circuit on the rig rewrites its own parameter tags when ResetTrig or
% NewTrial fires, and nothing but EPsych writes the device.
setpref('EPsych', 'SkipUnchangedWrites', true)

% For a behavior GUI that does not opt in by itself.
setpref('EPsych', 'DeferDisplays', true)
```

Run one Preview with `EPsych/TickStats` on before and after to see what each
bought on that rig.

### The first boundaries after MATLAB starts

The first trial boundaries of the first session after MATLAB starts are
several times slower than the rest, because MATLAB is running that code for
the first time. On the rig the subject waited 384, 184, 119 and 126 ms at the
first four boundaries against 75 ms later; a second session in the same MATLAB
started at 167 ms and was at 80 ms by its second trial.

`epsych.warmUp` runs that code beforehand: the real trial loop over a small
`hw.Software` protocol built for the purpose, with a staircase and session
metrics listening, for six boundaries. `epsych.RunExpt` calls it at the first
Run or Preview of a MATLAB session, before the hardware starts; it takes about
2 s and does nothing afterwards. Nothing of the real session is touched. A
paradigm's own trial selector and behavior GUI, and the hardware backend, are
not rehearsed, so the first real boundary is still the slowest.

`epsych.warmUp(Displays=true)` also builds and draws one of each standard
display in a hidden window. That is most of what a first boundary costs the
MATLAB thread, and it takes about 12 s, so `RunExpt` does not do it; call it by
hand, or from a startup file, when there is idle time before a session.

Sessions run at **High process priority**. `RunExpt` sets it at every Run
through .NET; until 2026-11 it used `wmic`, which current Windows no longer
has, and the call failed without a sign.

### Displays after the trigger

A trial's data reaches every display between that trial ending and the next
one starting. With deferral on, a display hands its drawing to the session's
`epsych.EventHub`, which runs it as soon as the `NewTrial` pulse has gone out —
in the same timer tick, in the order asked for, before the `NewTrial` event.
Analysis objects still recompute inside `NewData`, a paradigm's `onNewData`
still runs there, and so does `gui.AdaptiveTraining`'s step: nothing the next
trial depends on moves.

The one thing that changes: code in a `NewData` listener that *reads a
display* (a table's `Data`, a line's `YData`) sees the previous trial's
drawing. Read the analysis object instead.

A display takes part by calling `epsych.EventHub.deferFor(source, obj, tag,
@() ...)`; outside an open boundary (offline, in a review, a hub nobody opted
in) that is a plain call. See
[Event_Notifications.md](../epsych/Event_Notifications.md).

### Stimulus uploads

A `StimType` parameter regenerates its stimulus on every dispatch and used to
upload the whole waveform every time. `hw.TDT_RPcox` and `hw.TDT_Synapse` now
compare what was generated, in single precision, with what the tag was last
uploaded, and leave the transfer out when they match. A stimulus that draws
new samples each time is still uploaded each time.

The backend forgets what it sent on a connect, the circuit reload at the start
of every run, a mode change, a refused write, a COM error, and any other
write to the same tag. Set `SkipUnchangedStimulus = false` for a circuit that
writes into its own stimulus buffer, or a device another program also writes.

### Unchanged parameter writes

The trial-end sweep reads every visible read/write parameter, and the
dispatch that follows writes most of them back unchanged.
`SkipUnchangedWrites` leaves a write out when the backend read that parameter
from the device since the trial ended, nothing has written it or invalidated
the interface since, and the backend says the value read is the value to
write (`hw.Interface.holdsValue`: single precision on the TDT backends; the
four digits sent, and the units for a rate, on the pump).

It rests on one assumption nothing can check: that in the milliseconds
between the trial-end read and the dispatch, only the host changes what a
parameter holds. A circuit whose reset trigger rewrites its own parameter
tags breaks that, which is why it is opt-in. The first dispatch of a run, a
regenerated trial, and every write outside the trial loop are always sent.

### What a trial record holds

A visible buffer tag is read whole into every trial record — megabytes off the
device, into `DATA` and into the journal, on every trial. `RecordBuffers =
false` leaves buffers out; `gui.components.BufferPlot` reads a buffer it plots
off the device itself when the record does not carry it.

A readable `StimType` parameter records the **live stimulus object**. It is a
handle, so every record of the session holds the same one and shows the
stimulus as it is when the file is saved, not as the trial played it; and the
journal serializes it whole on every trial. `RecordStimulusSettings = true`
records `stimgen.StimType.toStruct` instead: the class, the name and every
user property, without the samples. Field access such as
`Data(k).Stim.Frequency` reads the same either way.

Both change what a saved file contains, so both wait to be asked for, and
both are applied at Run: every record of one session must have the same
fields.

Because they decide what a study's data files hold, they are the **study's**
settings: two checkboxes on the project's Session Defaults tab in the Subjects
window, stamped onto each subject's membership like the data path and the
saving function, and handed to the runtime when the session runs. A study
that states nothing gets the defaults at every session, whatever the study
before it on that rig chose. Each saved session records them as
`Info.RecordBuffers` and `Info.RecordStimulusSettings`, so a file says what
its own `Data` holds. See
[epsych_SubjectRoster.md](../epsych/epsych_SubjectRoster.md#what-a-trial-record-holds).

## Measured

**An RZ6 over the GB link**, the repository's benchmark circuit
(`examples/hw_benchmark/HwBenchmark_TDT_RPcox.rcx`), the real trial loop,
medians per trial:

| Session | Subject waits | Journal per trial |
|---|---|---|
| A visible 1e6-sample buffer tag, read into every record | 230 ms | 7.8 MB |
| The same with `RecordBuffers = false` | 6.5 ms | 2 KB |
| A 1 s `StimType` tone, uploaded every trial (as before) | 291 ms | 839 KB |
| The same, unchanged upload skipped (now the default) | 15 ms | 839 KB |
| … plus `SkipUnchangedWrites` and `RecordStimulusSettings` | 12 ms | 10.6 KB |

Per call on that link: a raw RPcoX `GetStatus` is about 19 µs, `ReadTagVEX` 40
µs, `SetTagVal` 42 µs — the device is fast, and what a parameter access costs
is mostly MATLAB. Through `hw.Parameter`: a read went from 362 µs to 122 µs, a
mode read from 122 µs to under 1 µs between refreshes, and an idle tick from
546 µs to 176 µs.

**A whole session** (`tmp/bench_rig_preview.m`, 2026-11-22: the lab's
appetitive platform protocol on the RZ6, 46 parameters,
`cl_AppetitiveDetection_BehaviorGUI` with displays deferred, a 25 ms timer, a
trial every 5.5 s). Medians per trial boundary, after the first five. The
first column is the review's changes alone (250 trials); the second adds the
follow-up of the same day — the kept expression plan, table column weights,
the colorbar label handle, the monitor's name list, the clock's tick, High
process priority (100 trials):

| ms, most boundaries | Review | With the follow-up |
|---|---|---|
| Subject waits | 83 | 64 |
| of which parameter writes | 55 | 39 |
| of which analysis (`newData`) | 10.5 | 9.7 |
| Displays, after the pulse (`render`) | 32 | 26 |
| Graphics holding the thread after the tick | 124 | 94 |
| MATLAB thread taken per boundary | 260 | 197 |
| An idle tick | 0.29 | 0.22 |

- **Nothing grew with the session.** Over the 250 trials, first block of 50
  to last: `render` 35 → 33 ms, `newData` 10 → 11 ms, graphics hold
  121 → 128 ms. The wait went 79 → 91 ms, nearly all of it in the parameter
  writes.
- **Before the review's changes**, the same Preview made the subject wait
  390 ms (two runs of 40 trials each way, alternated).
- **The first boundary** of the first session after MATLAB starts cost the
  subject 380–570 ms without the warm-up and about 300 ms with it (three
  runs), and took the MATLAB thread for 3.1 s and 2.0 s. The few after it are
  dominated by whether they happen to be slow ones, below.

**Some boundaries run 5–7 times slower in every phase at once**, at random,
with MATLAB using about twice the wall time in CPU: 450 ms of wait in place of
83, or 374 in place of 64. It is not from any of these changes — the code
before the review does it too, at about 1.9 s of wait — and it is not the
trial's outcome, a headless session, the Trial State monitor, page faults,
software rendering, the time since the last trial, or process priority. The
share moves about: 20% over the 250-trial run (6% to 28% by block of 50), 8%
to 11% in three later runs of 100, half of all boundaries with two stray
renderer processes pinning cores. The rig that day had 15.7 GB of RAM against
23.5 GB committed. The cause is not known. At 20% it lifts the mean wait from
83 to 160 ms and the 95th percentile to 482 ms.

**Counted on the benchmark** (`bench_trial_boundary(NumControls=20,
CallDelay=200e-6)`: 40 writable parameters, 20 read-only, 2 expressions, 20
on-screen controls, 200 µs per device call):

| | Before | After |
|---|---|---|
| Device calls per trial | 470 | 112 (72 with `SkipUnchangedWrites`) |
| Log records per trial | 56 | 6 |
| Subject waits, median | 180 ms | 47 ms (39 ms with `SkipUnchangedWrites`) |
| Device calls per idle tick | 2 | 1 |

With no connection-probe caching at all, as a backend without `ioReady` behaves,
the same protocol without the controls went from 660 calls per trial to 160.
The TDT backends also held their trigger pulse with `pause(0.001)`, twice per
trial inside the boundary; there is none now.

**Displays, per appended trial** (`tmp/smoke_test_incremental_perf.m`): the
scatter 30 ms → 11 ms; the staircase plot 15 ms → 11 ms at 200 trials and
28 ms → 12 ms at 1000, where it no longer grows with the session.

## What makes a boundary slow

In rough order of what it costs when present:

1. **A stimulus uploaded every trial.** About 280 ms per second of stimulus
   on the RZ6. Now skipped when unchanged.
2. **A buffer tag in the trial record.** About 200 ms per million samples,
   plus the journal. Hide the tag or set `RecordBuffers = false`.
3. **Display work before the trigger.** 25–30 ms for a history table, a
   scatter and a staircase plot (50–70 ms before the display-side guards).
   Defer it.
4. **A serial device in the sweep and the dispatch.** Each pump read or write
   is a blocking transaction.
5. **Many parameters.** Each read or write is about 0.1 ms of MATLAB whatever
   the link; forty writes are several milliseconds.
6. **An `Expression`.** 0.4–0.7 ms more than a plain write, a device read of
   each parameter it names included.

## For a new backend or display

- A backend's connection probe belongs behind `ioReady`, which may answer from
  a short-lived cache; `IsConnected` stays live. Invalidate the cache on
  everything that can change the answer.
- Hold a trigger pulse with `hw.Interface.holdPulse`, never `pause`.
- Leave per-write success records out while `InDispatch` is set: the
  dispatcher writes one summary record for the whole trial.
- Accept an `hw.Parameter` array in `get_parameter`, so `hw.ReadPlan` can read
  a module in one call.
- A display reached by `NewData` hands its drawing to
  `epsych.EventHub.deferFor`, and writes a graphics property only when the
  value changes.
- No `vprintf` per trial in a display: the log takes every level by default,
  and each record is a `dbstack` and a file write.
- Give a `uitable` that is rewritten every trial explicit column widths
  (`ColumnWidth = '1x'`, weights such as `{'5x','13x'}`, or pixels). With the
  default `'auto'`, every `Data` assignment makes MATLAB measure the cell text
  of each column again and resend the column model. `gui.components.History`
  measures its own columns in characters and rewrites the weights only when
  one needs more room.
- Keep a handle to a graphics child that is reached through a getter.
  `ColorBar.Label` runs the colorbar's getter at every read; two reads per
  redraw were over a third of what the parameter scatter cost.
- A polling display rebuilds per poll only what a poll can change. Names,
  visibility and layout follow configuration, not time: the Trial State
  monitor rebuilt its name list ten times a second, and the session clock
  re-applied row visibility, row heights and menu check marks every second.

## Related

- [epsych_TickStats.md](../epsych/epsych_TickStats.md)
- [Event_Notifications.md](../epsych/Event_Notifications.md)
- [hw_benchmarkIO.md](../hw/hw_benchmarkIO.md)
- [plans/runtime-performance-review.md](../../plans/runtime-performance-review.md) — the review these changes came from, and what was not done
