# gui.ParameterScatter

A generic scatter plot for custom behavior GUIs that compares any two
per-trial parameters recorded in the current experiment, with an optional
third parameter mapped to marker color.

## What it does

- **X/Y parameter dropdowns**: pick any per-trial parameter for either axis
  at any time; the plot updates immediately.
- **Live updates**: a `NewData` listener refreshes the plot after every
  completed trial.
- **Color-by parameter**: an optional third dropdown maps a parameter to
  marker color with a labeled colorbar (e.g., color by `RespCode` or level).
- **Trial Number**: always offered as a parameter — the chronological DATA
  index (note this differs from `TrialID`, which is the schedule/condition ID).
- **Response**: offered whenever the experiment records a response code (a
  `RespCode` or `ResponseCode` parameter), as a categorical parameter holding
  the outcome name decoded from the raw bitmask via
  `epsych.BitMask.getResponses` — `Hit`, `Miss`, `CorrectReject`,
  `FalseAlarm`, `Abort`, or `Undefined` when no response bit is set. All six
  categories are present from the start, so an outcome keeps the same axis
  position and color across trials and sessions. The raw code remains
  selectable under its own parameter name. `Response` is offered even when
  the response-code parameter itself is `Visible=false`.
- **Populated before the first trial**: when constructed from a runtime, the
  lists are seeded from the parameters the runtime will record, so a GUI built
  at session start is usable immediately rather than offering only
  `Trial Number` until a trial completes.
- **Invisible parameters excluded**: parameters flagged `Visible=false` on
  their `hw.Parameter` never appear in the selectable lists, nor do
  array-valued or write-only parameters. Non-scalar DATA fields are also
  excluded.
- **Categorical (text) parameters**: a scalar char/string DATA field, or a
  runtime parameter with `Type='String'`, is offered in the same dropdowns
  as numeric parameters. On a categorical X/Y axis, points are placed at
  integer positions — one per distinct value seen so far — and the axis
  ticks are labeled with those values (log scale is skipped for that axis).
  As a color-by parameter, each distinct value gets one discrete color and
  the colorbar ticks are labeled instead of showing a continuous scale. A
  value keeps its assigned position/color once seen, even as later trials
  introduce new categories.
- **Aesthetics**: right-click the axes for marker style, size, opacity,
  marker color, colormap (color-by mode), log X/Y, and grid.
- **Pop-out**: right-click → **Open in Separate Window** (the `gui.PopOut`
  mixin, or the `popOut` method) opens a second, independent scatter over the
  same data — its own selections and aesthetics, so a large exploratory view
  never disturbs the one embedded in the GUI. See
  [gui_PopOut.md](gui_PopOut.md).
- **Persistence**: parameter selections and aesthetics are saved with
  `setpref`/`getpref` (group `epsych2_gui_ParameterScatter`), keyed to the
  hosting figure `Tag`/`Name` or an explicit `PreferenceTag`, and restored
  the next session. Selections passed to the constructor are defaults for the
  first session only — once the user picks a parameter, that choice wins on
  every later launch.
- **Any container, resizable**: host it in a `uifigure`, legacy `figure`,
  panel, tab, or `uigridlayout` cell. uifigure-family containers get a
  `uigridlayout`/`uidropdown` control row; legacy figures get equivalent
  `uicontrol` popupmenus with pixel-accurate resize handling.

## Usage

```matlab
% Online, from a psychophysics object (updates via its Events NewData event)
obj.hScatter = gui.ParameterScatter(pObj, parentPanel);

% Online, directly from the runtime (updates via RUNTIME.EVENTS)
obj.hScatter = gui.ParameterScatter(RUNTIME, parentPanel, PreferenceTag='MyTaskGUI');

% Offline, from saved trial data (no listener)
S = gui.ParameterScatter(DATA, uifigure);

% Programmatic control (updates immediately)
S.XParameter = 'FreqHz';
S.YParameter = 'LevelDB';
S.ColorParameter = 'Response';   % decoded outcome name; or 'RespCode', or '(none)'
```

### Constructor

```matlab
obj = gui.ParameterScatter(source, container, options)
```

| Input | Description |
|-------|-------------|
| `source` | `psychophysics.*` object, `epsych.Runtime`, or DATA struct array |
| `container` | Figure, panel, tab, or layout host; empty creates a `uifigure` |
| `PreferenceTag` | Optional key for saved preferences (defaults to hosting figure Tag/Name) |
| `BoxID` | Restrict `NewData` updates to these boxes; empty accepts all |
| `XParameter`, `YParameter`, `ColorParameter` | Initial selections, used only when nothing is saved for this `PreferenceTag`; a selection restored from a previous session takes precedence. Applied as soon as the named parameters appear in the data, so they survive construction before the first trial |

### Key properties

| Property | Description |
|----------|-------------|
| `XParameter`, `YParameter` | Selected DATA field names, or `'Trial Number'` / `'Response'` |
| `ColorParameter` | Third parameter for marker color, or `'(none)'` |
| `Marker`, `MarkerSize`, `MarkerColor`, `MarkerAlpha` | Marker aesthetics |
| `ColormapName` | Colormap used in color-by mode |
| `LogX`, `LogY`, `ShowGrid` | Axes aesthetics |

Programmatic changes to the selection properties redraw immediately; after
changing aesthetics programmatically, call `update` to redraw. All of these
are also reachable from the axes' right-click menu, which persists choices
automatically.

## Update cost

A redraw asks for three parameters (x, y, and color-by), and each trial's value
is read once and kept rather than re-read for every parameter on every trial.
A category also keeps the code it was first assigned, so codes are appended the
same way. The dropdown item lists are written only when they actually change:
rewriting `Items` on every trial closed the list under a user who had it open
mid-selection.

Behavior is covered by `tmp/smoke_test_parameter_scatter.m`, and
`tmp/smoke_test_incremental_render.m` proves that a scatter fed trial by trial
plots exactly what one handed the same trials at once plots.

## Cleanup

Store the object on your GUI class and `delete` it in the GUI destructor —
this releases the `NewData` listener and context menu:

```matlab
delete(obj.hScatter);
```

## See also

- [Customized GUI Instructions](../design/Customized_GUI_Instructions.md)
- [gui.History](gui_History.md) — trial-by-trial history table with the same
  preference-persistence pattern
- [Event notifications](../epsych/Event_Notifications.md)
