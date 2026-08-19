# `gui.ParameterTracker`

A live plot of one or more `hw.Parameter` values against time. Where
[`gui.ParameterDebugger`](gui_ParameterDebugger.md) answers *what is it now*,
this answers *is it moving, and when did it move* — a question a table of
numbers cannot answer at all.

Opened from the debugger's **Track Selected** (`Ctrl+T`, or the right-click
item), or directly against any parameters you already hold.

```matlab
% From the debugger: select rows, then Ctrl+T

% Standalone
gui.ParameterTracker(P)                       % one or more hw.Parameter
gui.ParameterTracker(P, Rate=10)              % 10 reads per second
gui.ParameterTracker(P, Available=allParams)  % what the Add list offers
gui.ParameterTracker(P, Start=false)          % open paused

T = gui.ParameterTracker(P);
S = T.data;    % S.Time, S.Values, S.Names, S.Rate
```

---

## This window polls

That is the one thing the debugger promises never to do, and it is why polling
lives here instead: in a separate window, with its own timer, its own rate, and
a Pause button you can see. Reading a parameter at 5 Hz puts traffic on the
same bus the experiment is using, so the rate is the operator's — 0.1 Hz to
20 Hz, default 5 — and nothing is read while the plot is paused or while
nothing is tracked.

The samples carry the clock, not the sample index: every point is stamped with
`toc` at the moment of the read, so a period the timer could not keep (a slow
backend, a busy MATLAB) shows as a wider gap between points rather than as a
time axis that quietly drifts from real time. `BusyMode` is `drop`, so a read
that takes longer than a period costs a sample rather than queueing.

## What can be tracked

Scalar numbers only: `Float`, `Integer`, `Boolean`, and `Undefined`
parameters that are not write-only. A buffer has no single value to plot, a
string has no position on an axis, and a write-only parameter cannot be read at
all — those are refused when you try to add them, with the reason on the status
line, rather than drawn as a line that never moves.

A read that fails, or that comes back non-scalar, is recorded as `NaN`. The
line breaks, which is an honest picture of a backend that stopped answering.
The reason is logged **once per parameter**, and again only if the message
changes: a disconnected rig would otherwise write five records a second for as
long as it stays disconnected.

## The window

| Control | Does |
|---|---|
| **Start** / **Pause** (`Space`) | run or pause the poll timer |
| **Rate** | reads per second, 0.1–20 |
| **Show** | how much history the time axis shows — 30 s, 2 min, 10 min, 1 hour, or All |
| **Clear** | discard the samples and restart the clock at zero |
| **Tracked** list + **Remove** (`Delete`) | stop tracking the selected parameters |
| **Add** | put another of the offered parameters on the plot |
| `Esc` | close |

Each parameter is one line in its own colour, named `Module.Name` in the
legend. Colours are assigned **per parameter** rather than by position, so
removing one line does not recolour the others while you are watching them.

The x-axis is seconds since tracking started, and it slides with the newest
sample: the trace runs off the right edge rather than compressing as the
session grows. Pausing stops the clock as well as the reads, so a plot left
alone for ten minutes does not come back with a ten-minute gap drawn through
it.

The y-axis is shared. Tracking a 20 kHz frequency alongside a 3-second ITI puts
the second one flat on the bottom of the plot; track them in two windows
(**Track Selected in New Plot**) when the scales are that far apart.

## Adding and removing

**Add** offers the parameters the window was given as `Available` — from the
debugger, every scalar parameter in the selected source, filter or no filter,
because the plot's own list should offer what the protocol has rather than what
the Find box happens to be showing.

A parameter added to a running plot has **no history invented for it**: the
samples taken before it was added are `NaN`, so its line starts where tracking
of it started. Removing one takes its samples with it — keeping them would mean
a recording that no longer matches its legend, and this plot is the only thing
holding them.

## Taking the data away

Right-click the plot for **Assign Data to Command Window**, which puts
everything recorded into the base workspace as `PT`:

```matlab
PT.Time      % 1-by-N seconds since tracking started
PT.Values    % numel(Names)-by-N readings, NaN where a read failed
PT.Names     % one label per row of Values
PT.Rate      % reads per second
```

`T.data` returns the same struct programmatically. Samples are capped at
200 000 — about eleven hours at 5 Hz — after which the oldest half is dropped
and the count on the right says how many.

## What is remembered

Only the window position, under the `epsych2_gui_ParameterTracker` preference
group. What was tracked, at what rate, and everything sampled belong to one
debugging session.

## Testing

Covered by the debugger's smoke test, which drives a tracker against the mock
backend:

```matlab
matlab -batch "run('tmp/smoke_test_parameter_debugger.m')"
```

It asserts that a selection containing a buffer plots only what it can and says
what it left out, that samples arrive on the timer carrying the value the
parameter holds, that a line added to a running plot has `NaN` where it was not
yet tracked, that pausing, clearing, removing, and refusing a write-only
parameter all behave, and — the one that matters for a window that owns a timer
— that closing it stops and deletes that timer.

See also: [gui_ParameterDebugger.md](gui_ParameterDebugger.md) — where this
window is opened from, [Parameter_Monitor.md](Parameter_Monitor.md) — the
polling *text* display of one parameter,
[../hw/hw_Parameter.md](../hw/hw_Parameter.md).
