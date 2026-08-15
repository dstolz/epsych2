# gui.SessionPerformance

A generic session performance summary for custom behavior GUIs: the numbers
an experimenter watches while a session runs — trial counts, hit / false
alarm / abort rates, percent correct, d' and criterion — over a trial window
the operator controls.

Source: `obj/+gui/@SessionPerformance/`

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
- **Color-coded values**: green hits, red misses, blue correct rejects,
  orange false alarms, olive aborts, teal sensitivity measures — the same
  semantic hues `gui.History` uses for response rows.
- **Supporting counts**: each rate shows its denominator (`18/25`), so a
  rate computed from three trials never reads like a rate computed from
  three hundred.
- **Pop-out**: right-click → **Open in Separate Window** (the `gui.PopOut`
  mixin) repeats the summary in a window of its own, with its own analysis
  object — so watching the last 20 trials there leaves the embedded panel
  showing the whole session.
- **Persistence**: window and metric selection are saved with
  `setpref`/`getpref` (group `epsych2_gui_SessionPerformance`), keyed to the
  hosting figure `Tag`/`Name` or an explicit `PreferenceTag`.
- **Live updates**: refreshes from the analysis object's `NewData`
  rebroadcast, which fires *after* it has recomputed, so the panel never
  depends on listener ordering.

Requires a uifigure-based container (`uipanel`, `uigridlayout`, or
`uifigure`) — it installs its own grid layout in the container it is given.

## Usage

```matlab
% From a gui.BehaviorGUI subclass's build(fig) — preferred: registers for teardown
panelPerf = uipanel(layoutMain,'Title','Session Performance');
obj.Performance = obj.addPerformance(panelPerf, ...
    Metrics=["HitRate","FARate","AbortRate","DPrime"], FontSize=11);

% Standalone, over a runtime or an existing psychophysics object
P = gui.SessionPerformance(RUNTIME, panel);
P = gui.SessionPerformance(obj.Psych, panel);   % reuses its trial-type conventions

% Offline review of a saved session
P = gui.SessionPerformance(Data, panel);
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
selection from an older catalogue cannot stop a GUI from opening. Toggling
from the **Show Metric** menu keeps the display in catalogue order. See
[psychophysics.SessionMetrics](../psychophysics/psychophysics_SessionMetrics.md)
for the full metric list and the denominators each rate uses.

### Constructor

```matlab
obj = gui.SessionPerformance(source, container, options)
```

| Input | Description |
|-------|-------------|
| `source` | `psychophysics.SessionMetrics` (used as is), any other psychophysics object (its runtime or `DATA` is reused, along with its stimulus/catch trial-type settings), an `epsych.Runtime`, or a per-trial `DATA` struct array |
| `container` | `uipanel`, `uigridlayout`, or `uifigure` host |
| `Metrics` | Metric names to display. Default `psychophysics.SessionMetrics.defaultMetrics` |
| `TrialWindow` | Trials to summarize; any form `psychophysics.TrialWindow.parse` accepts. Default: all |
| `FontSize` | Caption font size; values render 2 pt larger. Default `12` |
| `ShowHeader` | Show the trial-window header. Default `true` |
| `ShowDetail` | Show the supporting-counts column. Default `true` |
| `PreferenceTag` | Key for saved preferences (defaults to the hosting figure `Tag`/`Name`) |

A saved selection takes precedence over the constructor's `Metrics` and
`TrialWindow` defaults, matching `gui.NextTrial`.

### Key properties and methods

| Member | Description |
|--------|-------------|
| `Analysis` | The `psychophysics.SessionMetrics` doing the computation (read-only) |
| `TrialWindow` | Trials included; assignable with any `TrialWindow.parse` shorthand |
| `Metrics` | Metric names displayed, in display order |
| `ValueColors` | Struct mapping metric `Kind` → hex color; assign to restyle |
| `LabelColor`, `HeaderColor` | Caption and header colors |
| `WindowPresets` | Trial counts offered as one-click **Last N** menu entries. Default `[10 20 50 100]` |
| `ContextMenu` | The right-click menu; host GUIs may append with `uimenu(obj.ContextMenu, ...)` |
| `setTrialWindow(w)` | Choose the trials summarized; persists like a menu selection |
| `setMetrics(names)` | Choose the metrics displayed; persists like a menu selection |
| `refresh()` | Redraw from the current results |
| `summaryText()` | Plain-text summary of what is displayed (also on **Copy Summary**) |
| `popOut()` / `closePopOut()` / `hasPopOut()` | Open, close, and query the separate-window copy (`gui.PopOut`) |

## Cleanup

Registered through `gui.BehaviorGUI.register` (via `addPerformance`), it is
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

obj.Performance = obj.addPerformance(panelPerformance, ...
    Metrics=["HitRate","FARate","AbortRate","DPrime"], ...
    FontSize=11, ShowDetail=false);
```

The GUI's `onNewData` no longer computes rates: the panel owns its own
`SessionMetrics` and follows `NewData` itself.

## See also

- [psychophysics.SessionMetrics](../psychophysics/psychophysics_SessionMetrics.md) — the metrics and the trial-window semantics
- `gui.PopOut` (`obj/+gui/@PopOut/`) — the separate-window mixin
- [gui.NextTrial](gui_NextTrial.md) — the same right-click + persistence pattern
- [gui.History](gui_History.md) — trial-by-trial detail behind these totals
- [gui.BehaviorGUI](gui_BehaviorGUI.md)
