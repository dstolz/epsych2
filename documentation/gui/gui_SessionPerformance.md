# gui.components.SessionPerformance

A generic session performance summary for custom behavior GUIs: the numbers
an experimenter watches while a session runs — trial counts, hit / false
alarm / abort rates, percent correct, d' and criterion — over a trial window
the operator controls.

Source: `obj/+gui/+components/@SessionPerformance/`

This is the reusable replacement for the hand-rolled performance labels that
each paradigm GUI used to build (a `uilabel` with `sprintf` and inline
bitmask arithmetic in `onNewData`).

## What it does

- **The psychophysics object computes, the panel displays.** Every number
  comes from a [`psychophysics.SessionMetrics`](../psychophysics/psychophysics_SessionMetrics.md),
  so the same metrics are available headlessly, offline, and in logs — not
  only on screen.
- **The trial window is visible and controllable.** The header always states
  which trials are being summarized (`Last 20 trials (28-47)`), and the
  window can be changed programmatically or by right-clicking the panel.
- **Metric selection**: any subset of the catalogue, in any combination,
  chosen programmatically or from the right-click **Show Metric** menu.
- **Metric order**: the rows are rearrangeable — **Reorder Metrics...** on
  the same menu, or `setMetricOrder` from code — so the metric being watched
  can be moved to the top.
- **Color-coded values**: green hits, red misses, blue correct rejects,
  orange false alarms, olive aborts, teal sensitivity measures — the same
  semantic hues `gui.components.History` uses for response rows.
- **Trial counts beside every value**: each row states the trials its value
  rests on (`Hit Rate  72.7%  8/11`), so a rate computed from three trials
  never reads like a rate computed from three hundred. The denominator is
  what the metric was actually divided by, which is *not* the number of trials
  in the window — a hit rate is over the stimulus trials the subject
  **answered** (aborts are left out unless `IncludeAborts`), a false alarm
  rate over answered catch trials, and only the abort rate over every
  included trial. A sensitivity index (d', A', criterion, B'') rests on both
  a hit and a false alarm rate, so it shows both fractions
  (`H 8/11  FA 2/8`). See [Trial counts](#trial-counts) below.
- **Aligned columns**: captions, values, and counts each have a column of
  their own; numerators are right-aligned against the slash and denominators
  left-aligned after it, so every slash stands on one vertical line and the
  digits stack by place value.
- **Pop-out**: right-click → **Open in Separate Window** (the `gui.PopOut`
  mixin) repeats the summary in a window of its own, with its own analysis
  object — so watching the last 20 trials there leaves the embedded panel
  showing the whole session.
- **Font size**: one setting scales the panel — captions at `FontSize`,
  values 2 pt larger, supporting counts 2 pt smaller, the header 1 pt
  smaller. Set it programmatically (`P.FontSize = 16`, or `setFontSize(16)`)
  or from the right-click **Font Size** menu: the `FontPresets` sizes,
  **Larger**/**Smaller** in 2 pt steps, and **Custom...**. Sizes outside
  6–72 pt are clamped rather than refused.
- **Persistence**: window, metric selection, metric order, and font size are
  saved with `setpref`/`getpref` (group `epsych2_gui_SessionPerformance`),
  keyed to the hosting figure `Tag`/`Name` or an explicit `PreferenceTag`.
- **Live updates**: refreshes from the analysis object's `NewData`
  rebroadcast, which fires *after* it has recomputed, so the panel never
  depends on listener ordering.

Requires a uifigure-based container (`uipanel`, `uigridlayout`, or
`uifigure`) — it installs its own grid layout in the container it is given.

## Usage

```matlab
% From a gui.BehaviorGUI subclass's build(fig) — preferred: registers for teardown
panelPerf = uipanel(layoutMain,'Title','Session Performance');
obj.Performance = obj.add('gui.components.SessionPerformance', panelPerf, ...
    Metrics=["HitRate","FARate","AbortRate","DPrime"], FontSize=11);

% Standalone, over a runtime or an existing psychophysics object
P = gui.components.SessionPerformance(RUNTIME, panel);
P = gui.components.SessionPerformance(obj.Psych, panel);   % reuses its trial-type conventions

% Offline review of a saved session
P = gui.components.SessionPerformance(Data, panel);
```

### Choosing which trials to summarize

```matlab
P.TrialWindow = "all";        % every trial (the default)
P.TrialWindow = 50;           % the last 50 trials
P.TrialWindow = [20 100];     % trials 20 through 100
P.TrialWindow = "last 20";    % same as 20
P.TrialWindow = "first 10";
P.TrialWindow = "20-end";
P.setTrialWindow(psychophysics.TrialWindow.lastN(20));
```

The operator gets the same choices from the right-click **Trials Included**
menu: **All Trials**, one-click **Last 10 / 20 / 50 / 100** presets (see
`WindowPresets`), and prompts for a custom **Last N**, **First N**, or
**Trial Range**. The menu's last entry restates the window currently in
effect. Every change is saved.

### Choosing which metrics to show

```matlab
P.setMetrics(["Trials","HitRate","FARate","AbortRate","DPrime"]);
P.Metrics = ["Hits","Misses","PercentCorrect"];
```

Unknown names are dropped with a message rather than throwing, so a saved
selection from an older catalogue cannot stop a GUI from opening. See
[psychophysics.SessionMetrics](../psychophysics/psychophysics_SessionMetrics.md)
for the full metric list and the denominators each rate uses.

### Choosing the order they appear in

The metric being watched belongs at the top, and which one that is changes
with the experiment, so the row order is the operator's:
**Reorder Metrics...** on the right-click menu opens a small modal list —
top of the list is the top of the panel — with **Move Up** / **Move Down**.
It rearranges only what is already displayed; **Show Metric** is still what
decides *which* metrics those are. From code:

```matlab
P.setMetricOrder(["DPrime","HitRate"]);   % these two lead; the rest follow
P.setMetricOrder([4 3 2 1]);              % or a permutation of the selection
```

Names the panel is not showing are ignored, and a displayed metric the order
never named keeps its relative place at the end — which is what lets a
remembered order survive a change of selection.

Until an order is chosen by hand the display is kept in catalogue order, so
a metric switched on from **Show Metric** appears where the panel has always
shown it. Afterwards a newly shown metric is appended instead: re-sorting
would silently discard the arrangement the operator just made. **Reset to
Defaults** returns to catalogue order. The order persists per GUI like every
other choice here, and a pop-out opens showing the host's arrangement.

### Trial counts

Every metric has a count, not only the rates:

| Metric | Shows | Out of |
|--------|-------|--------|
| Hit Rate, Hits, Miss Rate, Misses | hits (misses) | answered stimulus trials |
| False Alarm Rate, False Alarms, Correct Reject Rate, Correct Rejects | false alarms (correct rejects) | answered catch trials |
| Abort Rate, Aborts | aborts | every included trial |
| Percent Correct | hits + correct rejects | answered stimulus + catch trials |
| d', A', Criterion, B'' | `H` hits/answered stimulus, `FA` false alarms/answered catch | — |
| Trials | trials in the window | trials in the session, so `Last 20` reads `20/150` |
| Stimulus Trials, Catch Trials | that trial type | trials in the window |

An empty count reads `0/0`, which is the reason the value beside it is `--`.

The operator turns the counts off from the right-click **Show Trial Counts**
item; from code, `P.ShowDetail = false` or `P.setShowDetail(false)`. The
choice persists per GUI like the window and metric selection, and a
pop-out opens with the host's setting. **Reset to Defaults** turns them back
on.

The counts come from `psychophysics.SessionMetrics.metric`'s fourth output,
`support`, which the panel lays out in columns instead of parsing the text
form (`detail`). The headless summary and the clipboard copy use that text.

### Constructor

```matlab
obj = gui.components.SessionPerformance(source, container, options)
```

| Input | Description |
|-------|-------------|
| `source` | `psychophysics.SessionMetrics` (used as is), any other psychophysics object (its runtime or `DATA` is reused, along with its stimulus/catch trial-type settings), an `epsych.Runtime`, or a per-trial `DATA` struct array |
| `container` | `uipanel`, `uigridlayout`, or `uifigure` host |
| `Metrics` | Metric names to display. Default `psychophysics.SessionMetrics.defaultMetrics` |
| `TrialWindow` | Trials to summarize; any form `psychophysics.TrialWindow.parse` accepts. Default: all |
| `FontSize` | Caption font size; values render 2 pt larger. Default `12`; a size saved for this `PreferenceTag` takes precedence |
| `ShowHeader` | Show the trial-window header. Default `true` |
| `ShowDetail` | Show the trial counts beside each value. Default `true`; a choice saved for this `PreferenceTag` takes precedence |
| `PreferenceTag` | Key for saved preferences (defaults to the hosting figure `Tag`/`Name`) |

A saved selection takes precedence over the constructor's `Metrics`,
`TrialWindow`, and `FontSize` defaults, matching `gui.components.NextTrial`.

### Key properties and methods

| Member | Description |
|--------|-------------|
| `Analysis` | The `psychophysics.SessionMetrics` doing the computation (read-only) |
| `TrialWindow` | Trials included; assignable with any `TrialWindow.parse` shorthand |
| `Metrics` | Metric names displayed, in display order |
| `ValueColors` | Struct mapping metric `Kind` → hex color; assign to restyle |
| `LabelColor`, `HeaderColor` | Caption and header colors |
| `FontSize` | Caption font size in points; assigning routes through `setFontSize` |
| `ShowDetail` | Trial counts beside each value; assigning routes through `setShowDetail` |
| `WindowPresets` | Trial counts offered as one-click **Last N** menu entries. Default `[10 20 50 100]` |
| `FontPresets` | Sizes offered as one-click **Font Size** menu entries. Default `[10 12 14 16 20 24]` |
| `ContextMenu` | The right-click menu; host GUIs may append with `uimenu(obj.ContextMenu, ...)` |
| `setTrialWindow(w)` | Choose the trials summarized; persists like a menu selection |
| `setMetrics(names)` | Choose the metrics displayed; persists like a menu selection |
| `setMetricOrder(order)` | Rearrange the displayed metrics (names or a permutation), top row first; persists like a menu selection |
| `reorderMetrics()` | The **Reorder Metrics...** dialog behind `setMetricOrder` |
| `setFontSize(points)` | Set the caption size (clamped to 6–72 pt); persists like a menu selection |
| `setShowDetail(tf)` | Show or hide the trial counts; persists like a menu selection |
| `refresh()` | Redraw from the current results |
| `summaryText()` | Plain-text summary of what is displayed (also on **Copy Summary**) |
| `popOut()` / `closePopOut()` / `hasPopOut()` | Open, close, and query the separate-window copy (`gui.PopOut`) |

## Cleanup

Registered through `gui.BehaviorGUI.register` (via `add`), it is
deleted with the rest of the GUI. `delete(obj)` releases the listeners and
the context menu, deletes the `SessionMetrics` **it created** (an analysis
object supplied by the caller is left alone), closes any pop-out window, and
deletes the grid layout it installed — a container accepts only one layout
manager, so leaving it behind would block a replacement panel.

## Example: appetitive detection

`paradigms/BehaviorGUIs/@cl_AppetitiveDetection_BehaviorGUI/build.m`:

```matlab
panelPerformance = uipanel(layoutMain, 'Title', 'Session Performance');
panelPerformance.Layout.Row    = [1 2];
panelPerformance.Layout.Column = 7;

obj.Performance = obj.add('gui.components.SessionPerformance', panelPerformance, ...
    Metrics=["HitRate","FARate","AbortRate","DPrime"], ...
    FontSize=11);
```

The GUI's `onNewData` no longer computes rates: the panel owns its own
`SessionMetrics` and follows `NewData` itself. The trial counts are shown
(the GUI used to pass `ShowDetail=false`); the operator can hide them from
the right-click menu.

## See also

- [psychophysics.SessionMetrics](../psychophysics/psychophysics_SessionMetrics.md) — the metrics and the trial-window semantics
- `gui.PopOut` (`obj/+gui/@PopOut/`) — the separate-window mixin
- [gui.components.NextTrial](gui_NextTrial.md) — the same right-click + persistence pattern
- [gui.components.History](gui_History.md) — trial-by-trial detail behind these totals
- [gui.BehaviorGUI](gui_BehaviorGUI.md)
