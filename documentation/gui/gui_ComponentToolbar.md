# gui.ComponentToolbar — one toolbar for a GUI's separate windows

`gui.ComponentToolbar` is an icon toolbar across the top of a behavior GUI, one
tool per display, that opens that display in a window of its own. It answers
two things at once: it gives the pop-out windows of
[`gui.PopOut`](gui_PopOut.md) a place an operator can find without knowing
which display to right-click, and it lets a paradigm offer a display it does
**not** put on screen — the toolbar builds that one the first time its tool is
clicked.

Source: `obj/+gui/@ComponentToolbar/`

It is entirely optional. A GUI that never calls `addComponentToolbar` gets no
toolbar and behaves exactly as before.

## Using it

Call `addComponentToolbar` at the **top** of `build`, then declare anything the
GUI does not display:

```matlab
function build(obj, fig)
    tb = obj.addComponentToolbar(fig);

    % Not on screen; built the first time its tool is clicked.
    tb.addLazyComponent('Performance', ...
        @(c) gui.SessionPerformance(obj.RUNTIME, c), ...
        Icon='sessionperformance', WindowSize=[420 260]);

    g = uigridlayout(fig, [2 1]);
    obj.Scatter  = obj.register(gui.ParameterScatter(obj.RUNTIME, uipanel(g)));
    obj.Upcoming = obj.register(gui.NextTrial(obj.RUNTIME, uipanel(g)), 'Upcoming');
end
```

That produces three tools: **Performance** (declared), then, after a separator,
**Parameter Scatter** and **Upcoming** — discovered automatically because both
adopt `gui.PopOut`. Calling the toolbar first and still getting the components
built after it is the point: the list is collected once `build` has returned,
not when the toolbar is made.

`addComponentToolbar(fig, Style=, Exclude=, AutoDiscover=)`:

| Option | Meaning |
|---|---|
| `Style` | `"push"` (default) or `"toggle"` — see [Styles](#styles) |
| `Exclude` | class names (packaged or not) or register names to leave off |
| `AutoDiscover` | `false` lists only what `addLazyComponent` declares |

Asking a second time logs at debug level and returns the toolbar already made,
so a GUI cannot accidentally grow two.

## The two kinds of entry

They differ in **who owns the window**, which is what decides the rest.

| | automatic | lazy |
|---|---|---|
| Comes from | a `gui.PopOut` component registered in `build`, plus the psych object | `addLazyComponent` |
| Exists before the first click | yes, embedded in the GUI | no |
| Clicking calls | the component's `popOut()` | the factory, into a new window |
| Window owned by | the component (`gui.PopOut`) | the toolbar |
| Closing the window | deletes the pop-out instance | deletes the component |
| Clicking again | raises the same window | builds a fresh component |
| Position remembered under | `<GUITag>_<Class>_PopOut` | `<GUITag>_<Name>_Tool` |

An automatic tool is a second way in to the window that component's right-click
menu already offers — same window, same instance, nothing new.

The GUI's psych object is discovered too, last, when it can pop out — which in
practice means a `psychophysics.Staircase`. It is `createPsych`'s return value
rather than something `build` registered, so nothing else would find it; a
subclass that registers it as well gets one tool, not two.

A lazy entry costs nothing until it is clicked, which is the reason to use one:
a `gui.Parameter_Monitor` starts a polling timer and a `gui.ParameterScatter`
attaches event listeners the moment they are constructed, so a display that
is only wanted occasionally is better declared than embedded and hidden.

### The factory contract

```matlab
h = factory(container)
```

`container` is a borderless `uipanel` filling a fresh `uifigure` — a panel and
not a `uigridlayout`, because components that place themselves with normalized
`Units` warn inside a layout cell. Return the component, or `[]` to cancel the
window. Anything the factory throws is logged and the window discarded, so a
broken factory costs a click, not the session.

The component is deleted when the window closes and built again on the next
click, so one that remembers its own settings by `PreferenceTag` reopens
showing what it was showing.

Constructor shapes worth knowing when writing one:

```matlab
@(c) gui.SessionPerformance(obj.RUNTIME, c)                 % container required
@(c) gui.NextTrial(obj.RUNTIME, c, Fields=["Freq" "Level"]) % container required
@(c) gui.History(obj.Psych, c)
@(c) gui.ParameterScatter(obj.RUNTIME, c, XParameter='Trial Number')
@(c) gui.Parameter_Monitor(c, [obj.P.Level obj.P.InTrial], pollPeriod=1)
@(c) gui.PsychPlot(obj.Psych, axes(c))                      % a CLASSIC axes
@(c) gui.SyringePump(obj.RUNTIME, c)
@(c) psychophysics.Staircase(obj.RUNTIME, obj.P.Depth, Plot=true, PlotAxes=axes(c))
```

`gui.PsychPlot` and `psychophysics.Staircase` want a classic `axes`, not a
`uiaxes` — `axes(container)` is what their own `createPopOut_` does.

## Styles

`Style="push"` (default) makes momentary `uipushtool`s: click opens the window,
or raises it if it is already open. Nothing to keep in sync.

`Style="toggle"` makes `uitoggletool`s whose pressed state shows which windows
are open, and clicking a pressed tool closes its window. A toggle decides what
to do by asking whether the window is **actually** open rather than by reading
the state the click just put it in, so a window opened from a right-click menu —
which the toolbar is never told about — still closes on the first click rather
than needing two. Each open window carries an `ObjectBeingDestroyed` listener,
so a toggle also releases when its window is closed by its own close box, by
`closePopOut`, or by the GUI shutting down.

A single entry can override the toolbar default: `addLazyComponent(...,
Style="toggle")`.

## Naming and ordering

A tool is labelled by the name the component was **registered** under, and by
its class name split at camelCase boundaries when there is none:

```matlab
obj.register(gui.ParameterScatter(...))            % -> "Parameter Scatter"
obj.register(gui.ParameterScatter(...), 'Left Box') % -> "Left Box"
```

Register a name whenever one GUI holds two components of the same class, or the
two tools are told apart only by position. Names are made unique automatically
if they collide, and a collision is logged at info level.

Order is lazy entries in declaration order, then the discovered ones after a
separator. Discovered entries cannot come first: they are not known until
`build` has returned.

## Adding an icon for a new component

The toolbar asks `gui.toolbarIcon` for a glyph named after the component's
class: **the class name without its package, lowercased, with underscores
removed**.

| Class | Icon name |
|---|---|
| `gui.ParameterScatter` | `parameterscatter` |
| `gui.Parameter_Monitor` | `parametermonitor` |
| `psychophysics.Staircase` | `staircase` |

All eight `gui.PopOut` adopters have one. A component with no case in
`gui.toolbarIcon` falls back to `component`, the generic two-window glyph, so a
new adopter reaches the toolbar working — drawing its icon is a separate,
optional step:

1. Open `obj/+gui/toolbarIcon.m` and find the
   `% ---- behavior GUI component toolbar` section.
2. Add a `case "<iconname>"` there, in the same place the class sits
   alphabetically among its neighbours.
3. `rows` is 16 strings of 16 characters. Each character keys the palette
   `C` at the top of the file (`k` outline, `w` white, `s` steel, `b` blue,
   `g` green, `r` red, `o` orange, `y`/`Y` amber, `t` wood); `.` is
   transparent, which the toolbar renders as its own background.
4. Check it: `image(gui.toolbarIcon("<iconname>"))`, or run
   `tmp/smoke_test_component_toolbar.m`, whose last section asserts every
   adopter has both a label and a glyph.

Icons are drawn rather than shipped as image files so the toolbox carries no
binary assets, and are cached per name after the first call.

## Preferences

A lazy window remembers its position under a preference group named
`<GUIPreferenceTag>_<EntryName>_Tool`, alongside the way `gui.BehaviorGUI`
remembers its own and `gui.PopOut` remembers a pop-out's — including whether
the operator left the window pinned on top, since a toolbar-owned window holds
one component and so carries the same **Keep Window on Top** right-click item a
pop-out does (see [gui_PopOut.md](gui_PopOut.md)). The component inside
it keeps its own settings under whatever `PreferenceTag` the factory gives it —
give it one, or it will fall back to the window's `Tag` and read as a different
component each session.

Automatic entries store nothing of their own: the window belongs to the
component, so its position is `gui.PopOut`'s to remember.

A GUI built with `RestorePopOuts=true` also remembers **which** of these
windows were open and reopens them next session — lazy entries included, by
entry name, so a display the GUI never shows on its own can still be one the
operator always has up. A lazy window reports itself to the parent GUI as it
opens and closes; the toolbar's own teardown deliberately does not, which is
what keeps closing the GUI from reading as the operator closing its windows.
An entry that has since been renamed or dropped is skipped with a message and
left in the remembered list. See
[gui_BehaviorGUI.md](gui_BehaviorGUI.md#remembering-the-display-windows).

## Lifecycle

The toolbar is added to the GUI's teardown registry by `addComponentToolbar`,
so closing the GUI takes it down. Because it is registered first — from the top
of `build` — reverse-order teardown deletes it **last**, after the components
it points at; every handle it touches is checked for validity for that reason.

On teardown it drops its listeners first, then saves the position of and closes
every window it owns. Automatic entries need nothing: those windows belong to
the components, which the registry has already destroyed, taking their pop-outs
with them.

## Validation

`tmp/smoke_test_component_toolbar.m` covers deferred discovery, labelling,
ordering, push and toggle behaviour, lazy construction and rebuild, position
persistence, `Exclude`/`AutoDiscover`, the icon fallback, and full teardown:

```
matlab -batch "run('tmp/smoke_test_component_toolbar.m')"
```

`tmp/smoke_test_popout_restore.m` covers a lazy window taking part in a GUI's
`RestorePopOuts` memory: recorded as it opens, reopened at the size it was
left, and skipped without complaint once its entry is gone.

## See also

- [gui_PopOut.md](gui_PopOut.md) — the mixin the automatic entries drive
- [gui_BehaviorGUI.md](gui_BehaviorGUI.md) — the base class and its registry
