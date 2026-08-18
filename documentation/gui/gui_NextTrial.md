# gui.NextTrial

A generic "upcoming trial" display for custom behavior GUIs, showing the
compiled parameter values of the trial about to be presented.

Source: `obj/+gui/@NextTrial/`

## What it does

- **Live updates**: a `NewTrial` listener refreshes the table after every
  trial dispatch (`epsych.Runtime.dispatchNextTrial`), reading directly from
  the `epsych.TrialsData` payload — `writeparams`, `parameters`,
  `writeParamIdx`, `trials`, and `NextTrialID`.
- **Parameter | Value table**: one row per shown field, so any number of
  fields can be selected without redesigning the layout.
- **Programmatic selection**: pass `Fields=["Depth","TrialType"]` at
  construction, or call `setFields(...)` at any time. Field names are
  `validName`s, matching `TrialsData.Data.writeParamIdx`.
- **User selection**: right-click the table for a **Show Field** menu — one
  checkable entry per field the current protocol declares — plus **Show
  All** and **Reset to Default**.
- **Pop-out**: the same menu offers **Open in Separate Window** (the
  `gui.PopOut` mixin), which repeats the display in a window of its own with
  its own field selection — a large across-the-room readout while the
  embedded table stays compact. See [gui_PopOut.md](gui_PopOut.md).
- **Custom formatting**: a `Formatters` map (`validName -> function_handle
  (rawValue) -> char/string`) overrides the default `num2str`/`string`
  rendering for a field, e.g. to decode a numeric trial-type code into a
  label.
- **Font size**: set it programmatically (`obj.FontSize = 24`, or
  `setFontSize(24)`), or from the right-click **Font Size** menu — the
  `FontPresets` sizes, **Larger**/**Smaller** in 2 pt steps, and
  **Custom...**. Sizes outside 6–72 pt are clamped rather than refused, so a
  scripted value cannot leave the table unreadable.
- **Persistence**: the selected field set and the font size are saved with
  `setpref`/`getpref` (group `epsych2_gui_NextTrial`), keyed to the hosting
  figure `Tag`/`Name` or an explicit `PreferenceTag`, and restored the next
  session. A saved value takes precedence over the constructor's `Fields`
  and `FontSize` defaults.
- **Zero-config default**: with no `Fields` and nothing saved, every field
  the protocol declares is shown once the first trial is compiled.

## Usage

```matlab
% Minimal: show every declared field
obj.NextTrialPanel = gui.NextTrial(RUNTIME, panelNextTrial);

% Programmatic default plus a custom label for TrialType
fmt = containers.Map({'TrialType'}, {@myTrialTypeLabel});
obj.NextTrialPanel = gui.NextTrial(RUNTIME, panelNextTrial, ...
    Fields=["Depth","TrialType"], Formatters=fmt, FontSize=20);

% From a gui.BehaviorGUI subclass's build(fig) (preferred: registers for teardown)
obj.NextTrialPanel = obj.addNextTrial(panelNextTrial, ...
    Fields=["Depth","TrialType"], Formatters=fmt, FontSize=20);

% Programmatic control at any time
obj.NextTrialPanel.setFields(["Depth","TrialType","ITIDur"]);
obj.NextTrialPanel.FontSize = 28;   % readable from across the room
```

### Constructor

```matlab
obj = gui.NextTrial(source, container, options)
```

| Input | Description |
|-------|-------------|
| `source` | `epsych.Runtime` (listens on `RUNTIME.EVENTS`) or an `epsych.EventHub` directly |
| `container` | Figure, panel, tab, or layout host for the table |
| `Fields` | Programmatic default field names (`validName`); used only when nothing is saved for this `PreferenceTag` |
| `Formatters` | `containers.Map`, `validName -> function_handle(rawValue) -> char/string` |
| `FontSize` | Table font size. Default `16`; a size saved for this `PreferenceTag` takes precedence |
| `PreferenceTag` | Optional key for saved preferences (defaults to the hosting figure `Tag`/`Name`) |

### Key properties and methods

| Member | Description |
|--------|-------------|
| `SelectedFields` | `validName`s currently displayed (read-only; set via `setFields`) |
| `AvailableFields` | `validName`s declared by the most recent `NewTrial` event |
| `ContextMenu` | The right-click menu; a host GUI can append its own items with `uimenu(obj.ContextMenu, ...)` |
| `setFields(fields)` | Programmatically choose which fields are displayed; persists like a menu selection |
| `FontSize` | Table font size in points; assigning routes through `setFontSize` |
| `setFontSize(points)` | Set the font size (clamped to 6–72 pt); persists like a menu selection |
| `FontPresets` | Sizes offered as one-click entries on the **Font Size** menu. Default `[10 12 14 16 20 24 28 36]` |

## gui.BehaviorGUI integration

`gui.BehaviorGUI.addNextTrial(parent, ...)` constructs a `gui.NextTrial` bound to
`obj.RUNTIME` and registers it for teardown, matching `addMonitor`:

```matlab
function build(obj, fig)
    ...
    p = uipanel(g, 'Title', 'Next Trial'); p.Layout.Row = 1; p.Layout.Column = 2;
    obj.NextTrialPanel = obj.addNextTrial(p, Fields=["Depth","TrialType"]);
end
```

## Cleanup

Registered through `gui.BehaviorGUI.register` (via `addNextTrial`), it is deleted
automatically with the rest of the GUI. Constructed standalone, `delete(obj)`
releases the `NewTrial` listener and context menu; the table graphics are
left for the hosting figure to tear down.

## Example: appetitive detection Next Trial panel

`paradigms/BehaviorGUIs/@cl_AppetitiveDetection_BehaviorGUI/build.m` shows Depth and the
protocol's own text label for TrialType:

```matlab
obj.NextTrialPanel = obj.addNextTrial(layoutNextTrial, ...
    Fields=["Depth","TrialTypeNames"], FontSize=20);
```

`TrialTypeNames` is a protocol parameter that already carries the decoded
label (`'STIM'`/`'CATCH'`/`'REMIND'`) per trial, so no `Formatters` entry is
needed here — a numeric-only field (like the raw `TrialType` code) would
need one to render as anything other than its raw number.

## See also

- [gui.Parameter_Monitor](Parameter_Monitor.md) — the closest structural
  analog: right-click show/hide, `getpref`/`setpref` persistence keyed by
  parameter name
- [gui.ParameterScatter](gui_ParameterScatter.md) — the same persistence
  pattern applied to plot axis selections
- [gui.BehaviorGUI](gui_BehaviorGUI.md), [../epsych/Event_Notifications.md](../epsych/Event_Notifications.md)
