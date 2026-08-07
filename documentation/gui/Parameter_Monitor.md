# gui.Parameter_Monitor

A drop-in, timer-driven display for watching `hw.Parameter` values in a custom
experiment GUI. Attach it to any graphics parent (uifigure, uipanel,
uigridlayout, or legacy figure for text mode), hand it an array of parameters,
and it polls and renders them for you.

Source: `obj/+gui/@Parameter_Monitor/`

## Display types

| `type` | Rendering | Best for |
|--------|-----------|----------|
| `"table"` (default) | Sortable, rearrangeable `uitable` with Parameter/Value plus optional property columns | Many parameters, compact overview |
| `"graphical"` | Per-parameter widget dashboard: lamps, value labels, gauges in a configurable grid | At-a-glance state monitoring (trial state, sensors, counters) |
| `"text"` | Plain text block, one `Name: Value` line per parameter | Legacy figures, minimal displays |

Every display type carries a right-click menu for choosing which parameters
are shown and in what order — see
[Choosing and ordering parameters](#choosing-and-ordering-parameters).

All display types refresh efficiently: values are compared against what is
already on screen and graphics properties are only touched when something
changed, so fast polling (e.g. `pollPeriod=0.1`) does not continuously redraw
an idle display.

## Quick start

```matlab
f = uifigure;
M = gui.Parameter_Monitor(f, params, pollPeriod=0.5);            % live table

M = gui.Parameter_Monitor(f, params, type="graphical", ...       % dashboard
        LayoutColumns=2, FontSize=14, ...
        Styles=struct(InTrial="lamp", Platform="lamp", Level="gauge"));
```

## Graphical mode

Each parameter renders as a (label, widget) pair inside a scrollable
`uigridlayout`. Parameters fill down each column first, preserving the order
they were supplied in.

### Widget styles

- **`"lamp"`** — a `uilamp` that shows `LampOnColor` when `Value ~= 0` and
  `LampOffColor` otherwise. Ideal for booleans and binary hardware state tags
  (in-trial flags, sensor states, response windows).
- **`"label"`** — a bold `uilabel` showing `Parameter.ValueStr` (format and
  unit included). The label flashes `HighlightColor` when the value changes
  and clears once the value is stable (`HighlightOnChange`, on by default).
- **`"gauge"`** — a semicircular `uigauge` spanning `[Min, Max]`. Requires
  finite bounds; falls back to a label otherwise.
- **`"auto"`** (default) — parameters with `Type='Boolean'` use `BooleanStyle`
  (`"lamp"` by default); everything else uses `"label"`.

Styles are assigned per parameter with the `Styles` option, a struct keyed by
parameter name (`Name` or `validName`, case-insensitive):

```matlab
Styles = struct(InTrial="lamp", Depth="gauge", RespCode="label")
```

Parameter `Description` text becomes each widget's tooltip automatically.

### Layout options

| Option | Default | Effect |
|--------|---------|--------|
| `LayoutColumns` | 1 | Number of parameter columns in the grid |
| `LabelPosition` | `"left"` | `"left"`, `"above"`, or `"none"` (tooltip still names the parameter) |
| `FontSize` | component default (12 graphical) | Applied to labels/values (and to table/text displays) |
| `LampOnColor` / `LampOffColor` | green / gray | Lamp state colors (RGB triplet or hex) |
| `HighlightOnChange` | `true` | Flash value labels when the value changes |
| `HighlightColor` | soft yellow | Flash color |

Individual widgets can be tweaked after construction through the read-only
`Widgets` struct array — one entry per *visible* parameter, in display order,
with fields `Parameter`, `Style`, `ValueHandle`, `LabelHandle`, and
`CellHandle` (the component occupying the grid cell, which differs from
`ValueHandle` only for lamps):

```matlab
M.Widgets(3).ValueHandle.FontColor = 'b';
```

## Table mode

- Columns beyond Parameter/Value are requested via
  `Columns=["Type","Min","Max","isRandom", ...]` (any subset of
  `gui.Parameter_Monitor.SUPPORTED_COLUMNS`).
- Header clicks sort (toggling ascend/descend); headers can be dragged to
  rearrange. Both persist across sessions via `getpref`/`setpref`, keyed to
  the hosting figure's Tag/Name or an explicit `PreferenceTag`.

## Choosing and ordering parameters

Right-clicking anywhere on the display — a table row, a graphical widget, or
the panel background — opens a menu that decides what the monitor shows:

| Item | Effect |
|------|--------|
| **Show Parameter ▸** | One checkable entry per monitored parameter, in display order, plus **Show All**. Clicking one toggles it. |
| **Move Up** / **Move Down** | Repositions the parameter that was right-clicked. Disabled when the click landed on no parameter, or when the parameter is already at an edge. |

`type="text"` has no per-line hit testing, so its menu offers show/hide only;
reorder those displays with `move_parameter` instead.

Hidden parameters are skipped by the poll entirely, so hiding a parameter
removes its per-poll hardware read as well as its row or widget — worth doing
on a fast `pollPeriod` when only a few values matter. `Parameters` keeps the
full monitored set; `VisibleParameters` is what is displayed and polled.

Moves swap a parameter with its neighbour *among the visible parameters*, so
hidden entries never silently absorb a move. Because a manual arrangement and
a column sort contradict each other, moving a row clears the table's active
sort.

Both the visible set and the order persist across sessions in the same
preference entry as the table sort/arrangement, keyed to the hosting figure's
Tag/Name or an explicit `PreferenceTag`. Parameters are remembered by
`FullName` (falling back to `Name`), so a saved layout also applies to a
parameter added later with `add_parameter` — it lands in its remembered
position, and stays hidden if the user had hidden it.

The menu itself is exposed as `M.ContextMenu`, so a host GUI can append its
own items with `uimenu(M.ContextMenu, ...)`. Append rather than replace: the
built-in items are rebuilt each time the menu opens.

## Runtime API

```matlab
M.add_parameter(p)       % append parameter(s); the saved layout is reapplied
M.remove_parameter(p)    % remove by handle or by name
M.set_parameter_visible("RespLatency", false)   % hide (or show) by name
M.show_all_parameters()  % unhide everything
M.move_parameter("InTrial", -1)                 % -1 = earlier, +1 = later
M.stop(); M.start();     % pause/resume polling (display freezes while stopped)
M.setPollPeriod(0.25)    % change poll rate on the fly
M.poll_parameters()      % force an immediate refresh
```

## Lifecycle

- Each monitor owns a uniquely named timer, so any number of monitors can
  coexist in one session.
- The monitor deletes itself — stopping its timer — when its display is
  destroyed (e.g. the hosting figure closes). No explicit cleanup is required,
  though calling `delete(M)` early is still fine: it stops polling and leaves
  the last-rendered display in place.
- Poll errors (e.g. a transient hardware read failure) are logged at debug
  verbosity and do not kill the timer.

## Example: appetitive detection info panel

`cl/@cl_AppetitiveDetection_GUI_B/create_gui.m` monitors ten runtime
parameters at 10 Hz in its "Trial State" panel — lamps for the binary state
monitors, labels for the numeric readouts. The five lamp parameters are listed
first so they group together at the top of the panel:

```matlab
p = [P.Platform, P.Trough, P.InTrial, P.DelayPeriod, P.RespWindow, ...
    P.PelletTotal, P.StimDelay, P.RespWinDelay, P.RespLatency, P.RespCode];

obj.ParameterMonitor = gui.Parameter_Monitor(panelMonitor, p, pollPeriod=0.1, ...
    type="graphical", FontSize=14, ...
    Styles=struct( ...
        Platform="lamp", Trough="lamp", InTrial="lamp", ...
        DelayPeriod="lamp", RespWindow="lamp"));
```

Its `onModeChange` handler pauses polling when the session stops and resumes
it on Preview/Record, so the final trial state stays readable without the
timer running:

```matlab
case hw.DeviceState.Stop
    obj.ParameterMonitor.stop();
case {hw.DeviceState.Preview, hw.DeviceState.Record}
    obj.ParameterMonitor.start();
```

See also: [Parameter_Control.md](Parameter_Control.md),
[Parameter_Update.md](Parameter_Update.md),
[Customized GUI instructions](../design/Customized_GUI_Instructions.md)
