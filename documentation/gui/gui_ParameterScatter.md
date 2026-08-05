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
- **Invisible parameters excluded**: parameters flagged `Visible=false` on
  their `hw.Parameter` never appear in the selectable lists. Non-scalar and
  non-numeric DATA fields are also excluded.
- **Aesthetics**: right-click the axes for marker style, size, opacity,
  marker color, colormap (color-by mode), log X/Y, and grid.
- **Persistence**: parameter selections and aesthetics are saved with
  `setpref`/`getpref` (group `epsych2_gui_ParameterScatter`), keyed to the
  hosting figure `Tag`/`Name` or an explicit `PreferenceTag`, and restored
  the next session.
- **Any container, resizable**: host it in a `uifigure`, legacy `figure`,
  panel, tab, or `uigridlayout` cell. uifigure-family containers get a
  `uigridlayout`/`uidropdown` control row; legacy figures get equivalent
  `uicontrol` popupmenus with pixel-accurate resize handling.

## Usage

```matlab
% Online, from a psychophysics object (updates via its Helper NewData event)
obj.hScatter = gui.ParameterScatter(pObj, parentPanel);

% Online, directly from the runtime (updates via RUNTIME.HELPER)
obj.hScatter = gui.ParameterScatter(RUNTIME, parentPanel, PreferenceTag='MyTaskGUI');

% Offline, from saved trial data (no listener)
S = gui.ParameterScatter(DATA, uifigure);

% Programmatic control (updates immediately)
S.XParameter = 'FreqHz';
S.YParameter = 'LevelDB';
S.ColorParameter = 'RespCode';   % or '(none)'
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
| `XParameter`, `YParameter`, `ColorParameter` | Initial selections; override saved preferences |

### Key properties

| Property | Description |
|----------|-------------|
| `XParameter`, `YParameter` | Selected DATA field names, or `'Trial Number'` |
| `ColorParameter` | Third parameter for marker color, or `'(none)'` |
| `Marker`, `MarkerSize`, `MarkerColor`, `MarkerAlpha` | Marker aesthetics |
| `ColormapName` | Colormap used in color-by mode |
| `LogX`, `LogY`, `ShowGrid` | Axes aesthetics |

Programmatic changes to the selection properties redraw immediately; after
changing aesthetics programmatically, call `update` to redraw. All of these
are also reachable from the axes' right-click menu, which persists choices
automatically.

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
