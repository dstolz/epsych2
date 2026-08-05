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
`Widgets` struct array (fields `Parameter`, `Style`, `ValueHandle`,
`LabelHandle`):

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

## Runtime API

```matlab
M.add_parameter(p)       % append parameter(s); graphical displays rebuild
M.remove_parameter(p)    % remove by handle or by name
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
