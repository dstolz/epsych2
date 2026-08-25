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
| `gui.OnlinePlot` | a second plot of the same box, with **its own sample timer, read plan and buffers** | which traces, their y-axis order, palette and per-trace colours, line width, time window, redraw rate |
| `gui.BufferPlot` | a second buffer plot on the same source, with **its own envelope caches** | which buffers, sample rate and x units, layout, trial depth, palette and per-trace colours, resolution, y limits |
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

## Keeping a window on top

A pop-out's right-click menu carries a second item, **Keep Window on Top**,
which pins that window above every other window on the desktop
(`WindowStyle = 'alwaysontop'`). It is for watching a display while working
somewhere else — a notebook, the Synapse window, another rig's session —
without the plot disappearing behind whatever was clicked last. Choosing it
again unpins.

The item appears **only in a window holding a single component**: a pop-out,
or one `gui.ComponentToolbar` opened for a lazy component. The embedded copy
does not offer it, because the window it would pin is the behavior GUI's,
shared with everything else the paradigm shows — pinning that is a decision
about the GUI, not about one display.

The tick is refreshed when the item is used, but the *action* always reads
the window rather than the tick, so the first click after something else
changed the window style still does the obvious thing.

For a window built outside the mixin, the two statics that make this work
are public:

```matlab
gui.PopOut.markStandaloneWindow(fig, prefTag);  % before the component is built
tf = gui.PopOut.isAlwaysOnTop(fig);
gui.PopOut.setAlwaysOnTop(fig, true);           % pin, and remember it
```

`markStandaloneWindow` both declares the window a one-component window — which
is what makes the menu item appear — and restores the pinned state it was last
left in, so it must run before the component's constructor builds its context
menu. `gui.ComponentToolbar` calls it for the windows it owns; a release or
platform that will not honour `WindowStyle` leaves the window as it is and logs,
rather than taking the click down with it.

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
`gui.BehaviorGUI` remembers its own. **Keep Window on Top** is saved in that
same group, as `AlwaysOnTop`, so a pop-out left pinned reopens pinned.

The consequence worth knowing: a pop-out mirrors its host's current settings
only the *first* time it is opened. After that it restores what it was last
showing, exactly like every other component in the toolbox.

## Reopening them next session

Those preferences make each window come back as it was — but only once
something reopens it. `gui.BehaviorGUI` will, given
`RestorePopOuts=true`:

```matlab
obj@gui.BehaviorGUI(RUNTIME, Name='My Task', RestorePopOuts=true);
```

The GUI then remembers **which** displays were open and reopens them at the
end of its construction, each in the position, size, font and pinned state
its own preference key already held. Windows `gui.ComponentToolbar` opened
for lazy entries are remembered the same way. See
[gui_BehaviorGUI.md](gui_BehaviorGUI.md#remembering-the-display-windows).

The seam it uses is an event on this mixin:

```matlab
listener(component, 'PopOutStateChanged', @(~,~) disp('opened or closed'));
```

`PopOutStateChanged` fires when the window opens and when it closes. Raising
an already-open window is not a change and does not notify, and neither does
the teardown that follows the host component's own destruction — which is
what keeps closing a GUI from being mistaken for the operator closing its
windows.

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
obj.addPopOutMenu_(cm);   % appends "Open in Separate Window", and
                          % "Keep Window on Top" in a window of its own
```

`createPopOut_` receives a borderless `uipanel` filling the new window — not
a `uigridlayout`, because components that place themselves with normalized
`Units` warn inside a layout cell. That panel is *parented* to a 1×1 layout
all the same (`gui.PopOut.makeContentPanel`), because a `uipanel` given
`Position [0 0 1 1]` in normalized units inside a `uifigure` is sized by what
it contains rather than by the window: shrink the window past what a
scrollable layout inside asks for and the panel keeps the taller size, with
the window showing its bottom — the top rows clipped away and empty space
below. In a layout cell the panel is sized by the window, and a component
that outgrows it scrolls from the top instead. Return `[]` to cancel; an
error is logged and the window is discarded rather than left blank.

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

`tmp/smoke_test_popout_alwaysontop.m` covers the pinning: the embedded
component gets no such item, the pop-out's toggles the window both ways, the
choice is saved under the pop-out's own key and reopens with it, and a
toolbar-owned window offers the item too.

```
matlab -batch "run('tmp/smoke_test_popout_alwaysontop.m')"
```

`tmp/smoke_test_popout_restore.m` covers the reopening: a window is recorded
as it opens rather than at teardown, both kinds come back sized and pinned as
they were left, one the operator closed stays closed, a remembered display
the GUI does not have is skipped but not erased, and `RestorePopOuts=false`
neither reopens nor records anything.

```
matlab -batch "run('tmp/smoke_test_popout_restore.m')"
```

See also: [gui_BehaviorGUI.md](gui_BehaviorGUI.md),
[gui_ParameterScatter.md](gui_ParameterScatter.md),
[gui_History.md](gui_History.md),
[gui_SessionPerformance.md](gui_SessionPerformance.md),
[gui_NextTrial.md](gui_NextTrial.md),
[Parameter_Monitor.md](Parameter_Monitor.md),
[gui_SyringePump.md](gui_SyringePump.md),
[../psychophysics/psychophysics_Staircase.md](../psychophysics/psychophysics_Staircase.md).
