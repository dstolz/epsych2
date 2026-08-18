# gui.PopOut — open a display in a window of its own

`gui.PopOut` is the mixin behind the **Open in Separate Window** item that
appears in the right-click menu of every graphical component a `gui.BehaviorGUI`
hosts. Choosing it builds a **second instance** of that component over the
same data source, in a window of its own.

Source: `obj/+gui/@PopOut/`

The embedded component is never reparented, resized, hidden, or otherwise
touched. The pop-out is a separate object with its own graphics, its own
event listeners, and its own saved preferences, so changing what it shows —
or closing it — cannot disturb the GUI it came from. Closing the host GUI
*does* close the pop-out, so no orphan window is left listening to the
runtime.

## Components that adopt it

| Component | The pop-out is | Independent of the host in |
|---|---|---|
| `gui.ParameterScatter` | a second scatter on the same source | X/Y/color selection, marker style, colormap, log scales, grid |
| `gui.History` | a second trial table on the same psych object | shown columns, column order, sort column/direction, row block size |
| `gui.SessionPerformance` | a second summary with **its own `psychophysics.SessionMetrics`** | trial window, metric selection |
| `gui.NextTrial` | a second upcoming-trial display on the same event source | field selection |
| `gui.Parameter_Monitor` | a second monitor with **its own polling timer** | which parameters are shown, their order, colors, sort |
| `gui.SyringePump` | a second panel over the same pump, with **its own readout timer**, built with `ApplyOnStart=false` so it never re-asserts settings | selected port, displayed settings |
| `gui.PsychPlot` | a second psychometric plot on the same psych object | plot type, log-x, colors |
| `psychophysics.Staircase` | a second `Staircase` over the same trials, plotted in the new window | threshold reversals/formula, dB axis, step and reversal overlays |

Two notes on cost, because a pop-out is a real second instance:

- `gui.Parameter_Monitor` polls the hardware on its own timer. While the
  window is open, every parameter shown in both places is read twice per
  poll period.
- `psychophysics.Staircase` pops out as a sibling analysis object, not a
  second view of the same one, because its plot settings (reversal count,
  threshold formula, dB conversion) *are* analysis settings — sharing the
  object would make a change in the pop-out rewrite the embedded plot too.
  It carries its own copy of the session's trials and recomputes on each
  `NewData`.

## Using it

From the operator's side there is nothing to configure: right-click the
display and choose **Open in Separate Window**. Choosing it again while the
window is open raises that window rather than opening another.

From a GUI's side:

```matlab
h = component.popOut();     % open it, or raise it if already open
tf = component.hasPopOut(); % true while the window is open
component.closePopOut();    % close it; the embedded component is untouched
```

### A button that opens a display on demand

For a display an operator only wants occasionally, `gui.BehaviorGUI` provides a
button that opens the pop-out, so the GUI does not have to give the display
permanent screen space:

```matlab
function build(obj, fig)
    g = uigridlayout(fig, [2 1]);
    g.RowHeight = {30, '1x'};

    panel = uipanel(g);
    panel.Layout.Row = 2;
    obj.Scatter = obj.register(gui.ParameterScatter(obj.RUNTIME, panel));

    b = obj.addPopOutButton(g, obj.Scatter, Text='Scatter...');
    b.Layout.Row = 1;
end
```

`addPopOutButton(parent, component, Text=, Tooltip=)` skips components that
are not poppable with a debug-level message, matching `addControl`'s
tolerance of parameter names a protocol does not define.

### A toolbar of them

For more than one or two, `gui.BehaviorGUI.addComponentToolbar` puts every
poppable component the GUI registered onto one icon toolbar, without naming
them: it collects them after `build` returns. It can also open displays the
GUI does not host at all, building them on first click. See
[gui_ComponentToolbar.md](gui_ComponentToolbar.md).

## Preferences

A pop-out saves its layout under its own key, so its choices never overwrite
the embedded component's. The key is the hosting figure's `Tag` (else its
`Name`), the component's class, and a `_PopOut` suffix — e.g. a
`gui.History` inside a BehaviorGUI tagged `cl_AppetitiveDetection_BehaviorGUI` pops out
under `cl_AppetitiveDetection_BehaviorGUI_History_PopOut`, in the same
`epsych2_gui_History` preference group. The pop-out **window position** is
remembered under a preference group of that same name, the way
`gui.BehaviorGUI` remembers its own.

The consequence worth knowing: a pop-out mirrors its host's current settings
only the *first* time it is opened. After that it restores what it was last
showing, exactly like every other component in the toolbox.

## Adding the mixin to a component

Three steps:

```matlab
classdef MyDisplay < gui.PopOut          % 1. inherit

    methods (Access = protected)
        function c = popOutHostContainer_(obj)
            c = obj.ContainerH;          % 2. where this instance was built
        end

        function h = createPopOut_(obj, container)
            % 3. a sibling over the same source, seeded from this one
            h = gui.MyDisplay(obj.Source_, container, ...
                PreferenceTag = obj.popOutPreferenceTag_());
        end
    end
end
```

and one line where the context menu is built:

```matlab
obj.addPopOutMenu_(cm);   % appends "Open in Separate Window"
```

`createPopOut_` receives a borderless `uipanel` filling the new window — not
a `uigridlayout`, because components that place themselves with normalized
`Units` warn inside a layout cell. Return `[]` to cancel; an error is logged
and the window is discarded rather than left blank.

Two details to get right in `createPopOut_`:

- **Seed from the host**, but only when the pop-out has nothing saved of its
  own (`ispref(obj.PREF_GROUP, tag)`), otherwise the restored preferences
  are immediately overwritten by the host's current state.
- **Share the data, not the display state.** Pass the same source object,
  event broadcaster, or `hw.Parameter` array; never pass a settings-bearing
  object the host is also using, or the two windows stop being independent.
  `gui.SessionPerformance` is the worked example: given a caller-supplied
  `SessionMetrics`, it builds a fresh one over the same trials for the
  pop-out and takes ownership of it.

The mixin provides `PopOutSize` (default `[780 560]`) and `PopOutLabel`
(default derived from the class name) as protected properties a component
can set in its constructor to change the window's first-open size and title.

## Lifecycle

- The pop-out figure's close button deletes the pop-out component, saves the
  window position, and deletes the window.
- The host's destruction is caught by an `ObjectBeingDestroyed` listener, not
  a `delete` method, so a component can adopt the mixin without disturbing
  its own destructor — and so `psychophysics.Staircase` can inherit both
  `psychophysics.Psych` and `gui.PopOut` without a `delete` conflict.
- Popping out a pop-out is allowed and yields a third independent window,
  which is how a second view of the same data is obtained.

## Validation

`tmp/smoke_test_popout.m` (headless) covers every adopting component: the
pop-out is a separate instance, its edits do not reach the host, `popOut`
raises an open window instead of duplicating it, `closePopOut` removes only
the pop-out, destroying the host closes the window, and
`gui.BehaviorGUI.addPopOutButton` opens and closes with the GUI.

```
matlab -batch "run('tmp/smoke_test_popout.m')"
```

See also: [gui_BehaviorGUI.md](gui_BehaviorGUI.md),
[gui_ParameterScatter.md](gui_ParameterScatter.md),
[gui_History.md](gui_History.md),
[gui_SessionPerformance.md](gui_SessionPerformance.md),
[gui_NextTrial.md](gui_NextTrial.md),
[Parameter_Monitor.md](Parameter_Monitor.md),
[gui_SyringePump.md](gui_SyringePump.md),
[../psychophysics/psychophysics_Staircase.md](../psychophysics/psychophysics_Staircase.md).
