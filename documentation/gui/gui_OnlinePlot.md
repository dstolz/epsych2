# gui.components.OnlinePlot

Real-time multi-trace plotting of hardware activity for one experimental box.
Each trace is a parameter (or one bit of a bitmask bank) sampled on a timer and
drawn against a scrolling time axis, so the operator can watch lick spouts,
stimulus gates, reward valves and trial flags fire against each other.

```matlab
% From a behavior GUI's build()
obj.Plot = obj.add('gui.components.OnlinePlot', panel, Source={'Lick','StimOn','Reward'});

% Or directly
op = gui.components.OnlinePlot(RUNTIME, {'Lick','StimOn','Reward'}, ax, BoxID);
```

## What it does

- **Two sources.** *Parameter mode* takes `hw.Parameter` handles or parameter
  names, one trace each. *Bitmask-bank mode* takes the name of a bank published
  by the RPvds macros (a `~BMid-<bank>` parameter plus one
  `~BM-<bank>#<bit>^<label>` parameter per bit): the bank is read once per tick
  and decoded into one trace per labelled bit. Omitting the source puts a list
  dialog in front of the operator.
- **Free-running or trial-locked.** Right-click → *Set Plot to Trial-Locked*
  anchors the window on the last trial onset, detected as a rising edge on
  `_TrigState~<BoxID>`. Onsets are marked with a dashed line and the trial
  number from `_TrialNum~<BoxID>`.
- **Configurable by the operator and by a script**, and the arrangement is
  remembered across sessions. See below.
- **Pop-out.** Right-click → *Open in Separate Window* opens a second,
  independent plot of the same box.

## Reads are batched per interface

`hw.Parameter.get.Value` costs an `isprop` probe plus an `IsConnected` probe
before the value read, and on `hw.TDT_RPcox` that connection probe is itself a
`GetStatus` COM call per module. An N-trace plot therefore paid **2N** round
trips a tick where N+1 would do.

Every backend except `hw.Software` and `hw.VlcRecorder` accepts a whole
`hw.Parameter` array in one `get_parameter` call — `hw.Teensy` and `hw.Bpod`
serve the whole batch from a single device snapshot — so `build_read_plan_`
groups the traces by owning interface and issues **one call per interface per
tick**. On a zero-cost backend that alone is ~7x faster than
`[P.Value]` for ten traces; against real hardware the saving is larger, because
the connection probes go too.

Four parameters cannot be batched and stay on the local `.Value` path, because
that is where they are correctly served: write-only ones (which read `NaN`),
`StimType` ones (host-side objects, not device state), any owned by
`hw.Software` (whose `get_parameter` would recurse), and any whose parent
handle has been deleted. A backend that *rejects* an array read is demoted to
per-parameter polling once, for the rest of the session, rather than throwing
or retrying a failing call every tick.

A read that throws leaves `NaN` and is logged **once** per parameter and
message, so a rig unplugged mid-session does not flood the log at the tick
rate. A non-scalar or non-numeric read contributes its first element or `NaN`
rather than derailing the sample column.

## Traces: which, and in what order

Both are settable from code and from the right-click menu; the menu items call
the same public methods, so nothing the operator can do is out of a script's
reach.

| Task | Script | Operator |
|---|---|---|
| Replace the traces | `setWatched(source)` | *Select Traces...* |
| Reorder up the y axis | `setTraceOrder(order)` | *Reorder Traces...* |
| Current labels, bottom-first | `traceNames()` | — |

- `setWatched` accepts `hw.Parameter` handles, parameter names, bank names, or
  — in bitmask mode — **bit labels**, which narrows the bank to those bits.
  Hidden bits come back by naming them again. Per-trace colours and widths are
  reset, because the trace set changed and a colour carried over by position
  would land on a different signal.
- `setTraceOrder` takes a permutation of `1:N` **or** the trace names in the
  order wanted. Names are matched against `traceNames`: a name this plot does
  not have is ignored, and a trace the order never mentioned keeps its relative
  place at the end. Colours and widths travel **with** their traces.
- *Reorder Traces...* lists the traces **top of the axes first**, because the
  operator is rearranging what they see, and reverses the list before it
  reaches `setTraceOrder`, which works bottom-first like `yPositions`.

## Appearance

Programmatic: `lineColors`, `lineWidth`, `yPositions`, `timeWindow`,
`setZeroToNan`, `trialMarker`, `maxTrialMarkers`, `showGrid`, `palette`,
`redrawPeriod`, plus `setTraceColor(trace, rgb)` and
`setTraceWidth(trace, w)` which take a trace index or name.

From the right-click menu: line width, palette, per-trace colour, redraw rate,
grid, blank-zeros, trial markers, time window, and *Reset Appearance* (which
restores the shipped look without disturbing the trace selection).

The default palette is **Okabe-Ito**, the standard colourblind-safe
qualitative set. `lines` — the previous default — puts blue beside cyan and
red beside orange, which on 10 px state traces is the one distinction an
operator has to make at a glance. Past eight traces the palette repeats at
stepped lightness, so trace 9 is a visibly paler trace 1 rather than an exact
duplicate.

`setZeroToNan` (on by default) blanks zero samples so a trace is a row of bars
rather than a continuous line at its own y position.

## Remembered across sessions

Every operator change is written to `getpref`/`setpref` under group
`epsych2_gui_OnlinePlot`, keyed by the explicit `PreferenceTag` if one was
given, else the hosting figure's `Tag` (else `Name`, else `Box<N>`). A script
that set the properties directly can force a save with `saveConfiguration()`;
`forgetConfiguration()` discards the stored arrangement, and
`hasSavedConfiguration()` reports whether one exists.

Two rules keep a remembered layout from fighting the paradigm that built the
plot:

- **Order and per-trace style are always re-applied**, matched by trace
  **name** — which is why a colour follows its signal through a reorder, a
  reselection, or a protocol edit that changes how many traces there are. A
  name that is gone is skipped.
- **The trace SELECTION is re-applied only when the operator chose it by
  hand** (*Select Traces...*, or the constructor's list dialog). A `source`
  passed to the constructor is what a paradigm's `build()` asked for, and a
  stale saved list from a different protocol must not silently replace it.

## Pop-out

`gui.components.OnlinePlot` is a `gui.PopOut` adopter, so it appears on a
`gui.components.ComponentToolbar` and takes part in `gui.BehaviorGUI`'s `RestorePopOuts`.
The pop-out is a **fully independent instance**: its own timer, read plan,
buffers and preference key, and therefore its own trace selection, order and
styling. That is the point — the usual reason to pop one out is to watch a
*different* set of traces large. It opens mirroring the host the first time,
and restores its own arrangement thereafter.

## Implementation notes

- **The ring buffer is sized from the time window and the timer period.** It
  used to be a fixed 1000 samples, which at the 0.05 s bitmask period is 50 s
  of history — so widening the window past that drew a plot that simply
  stopped part way back.
- **Trial markers are recycled from a bounded pool** (`maxTrialMarkers`,
  default 32). One line and one text per onset was an unbounded leak: an hour
  at 4 s a trial left ~900 of each on the axes, every one re-rendered by every
  `drawnow` for the rest of the session.
- **Elapsed time comes from `tic`/`toc`**, not `now`: monotonic, cheaper, and
  immune to a wall-clock change mid-session.
- **All traces are pushed in one `set` call.** The x vector is shared by
  reference through the cell, so replicating it costs no copy, and setting
  `XData` and `YData` together avoids the moment where a Line holds a new X
  against an old Y — HG2 truncates the other array to match.
- **A `Text` object's `Position` is plain numeric even on a duration ruler**
  (whose backing units here are seconds); a `duration` in a `Position` vector
  is rejected outright. The trial-number labels sit inside the y limits, which
  are padded for them — before that they were drawn at `N+0.5`, above the
  limit, and were never visible.
- **One mode listener per interface, not one over the array.** `hw.Interface`
  is `matlab.mixin.Heterogeneous` and `listener` is not sealed, so a rig
  running two different backends — the ordinary case once a pump or a recorder
  joins the TDT device — threw on construction.
- **`reorderTraces` uses no nested functions and deletes its window on every
  path.** A nested callback handle keeps its parent workspace alive for as long
  as the figure holds it, and that workspace held the `onCleanup` meant to
  delete the figure: neither was ever released. Cancelling therefore leaked an
  invisible modal window, and the *next* *Reorder Traces...* blocked in
  `uiwait` forever.
- **Readable means "not write-only"**, not `contains(Access,'Read')`. The
  default `Access` is `'Any'`, which reads and writes but does not contain the
  word, so the old filter offered none of those parameters for selection.

## Standing checks

| Script | Covers |
|---|---|
| `tmp/smoke_test_onlineplot.m` | batched reads, buffering, markers, teardown, a live timer run |
| `tmp/smoke_test_onlineplot_config.m` | selection, order, aesthetics, persistence, pop-out |
| `tmp/smoke_test_onlineplot_dialogs.m` | the two modal dialogs and the `add` path (run via `matlab -batch`) |
| `tmp/bench_onlineplot.m` | read-path and draw-path timings |

## See also

- [gui.PopOut](gui_PopOut.md)
- [gui.BehaviorGUI](gui_BehaviorGUI.md) — `add` and the component DSL
- [gui.components.ComponentToolbar](gui_ComponentToolbar.md)
- [gui.components.ParameterScatter](gui_ParameterScatter.md)
