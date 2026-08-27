# gui.BehaviorGUI — Base class for custom experiment GUIs

`gui.BehaviorGUI` is the recommended starting point for a custom experiment GUI. It owns everything a paradigm GUI needs besides its layout: single-instance enforcement, figure creation with position persistence, runtime event listeners, a teardown-guaranteed component registry, and automatic `gui.components.Parameter_Update` wiring. A subclass implements one required method — `build(fig)` — and optionally overrides a handful of protected hooks.

A complete, runnable template lives at [examples/customgui/ExampleBehaviorGUI.m](../../examples/customgui/ExampleBehaviorGUI.m); launch it without hardware via [examples/customgui/run_example.m](../../examples/customgui/run_example.m).

## The BehaviorGUI contract

`epsych.RunExpt` launches the configured behavior GUI at session start as `feval(FUNCS.BehaviorGUI, RUNTIME)` — one input, no outputs, opens a window. A `gui.BehaviorGUI` subclass satisfies this automatically as long as its constructor accepts the runtime and forwards it to the base:

```matlab
function obj = MyTaskGUI(RUNTIME)
    obj@gui.BehaviorGUI(RUNTIME, Name='My Task');
    if nargout == 0, clear obj; end
end
```

Name the class on the **project** that runs it: **Subjects > Subjects & Projects**, then **Project > Edit Project... > Session Defaults** and the **Behavior GUI** field. `epsych.SubjectRoster.assignToSession` puts it on `FUNCS.BehaviorGUI` when that project's subjects are added to the session, so a rig alternating between two paradigms picks up the right GUI from the animals it is running rather than from a per-rig setting. (It used to be Customize's **Behavior GUI Function** field; see [`gui.SubjectManager`](gui_SubjectManager.md#the-project-dialog).) The GUI is created *after* the runtime timer starts, so parameters already carry live values; it must nonetheless open against a runtime with **no** interfaces (the pre-flight self-test launches it that way), which the base guarantees: `addControl`/`addButton` silently skip parameter names that do not resolve.

## Minimal subclass

```matlab
classdef MyTaskGUI < gui.BehaviorGUI
    methods
        function obj = MyTaskGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='My Task', DefaultPosition=[100 100 1100 650]);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)
        function p = createPsych(obj, R)
            p = psychophysics.Staircase(R, obj.P.Depth);
        end

        function build(obj, fig)
            g = uigridlayout(fig, [2 2]);
            row = uigridlayout(g, [1 4]); row.Layout.Row = 1; row.Layout.Column = [1 2];
            obj.addButton(row, 'DropPellet', Text='Pellet');
            obj.addButton(row, '~TrialDelivery', Text='Deliver Trials');

            col = obj.controlColumn(g, Title='Trial Controls', Row=2, Column=1);
            obj.addControl(col, 'ITIDur', Text='Intertrial Interval (s)');
            obj.addControl(col, 'Depth',  Text='Modulation Depth (%)');
            obj.addUpdateButton(col);

            p = uipanel(g, 'Title', 'Monitor'); p.Layout.Row = 2; p.Layout.Column = 2;
            obj.add('gui.components.Parameter_Monitor', p, ...
                'Parameters', {'InTrial','RespCode'}, pollPeriod=0.5);
        end

        function onNewData(obj, src, event)
            % per-trial updates; obj.Psych has already processed the trial
        end
    end
end
```

No destructor, no closeGUI, no single-instance code, no position prefs, no listener plumbing, no watchedHandles wiring, no isfield guards.

## Constructor options

`obj@gui.BehaviorGUI(RUNTIME, ...)` accepts:

| Option | Default | Meaning |
|---|---|---|
| `Name` | `'Behavior Box'` | Figure title |
| `DefaultPosition` | `[100 100 1100 680]` | `[x y w h]` used when no saved position exists |
| `PreferenceTag` | class name | Figure `Tag`, single-instance key, and `getpref`/`setpref` group for the saved position |
| `Visible` | `true` | Set `false` to build hidden (useful in tests) |
| `RestorePopOuts` | `false` | Reopen the display windows the operator had open last time — see [Remembering the display windows](#remembering-the-display-windows) |

Constructor sequence: single-instance replacement → cache `obj.P = RUNTIME.all_parameters(asStruct=true, includeTriggers=true)` → `createPsych` → create the `uifigure` → `build(fig)` → wire `Parameter_Update.watchedHandles` from the registry → attach `NewTrial`/`NewData`/`ModeChange` listeners → reopen remembered display windows.

## Remembering the display windows

An operator who works with the history on a second monitor and the scatter
pinned over the rig software has to reopen both, every session, from the
right-click menus. `RestorePopOuts=true` makes the GUI remember which
display windows were open and bring them back:

```matlab
obj@gui.BehaviorGUI(RUNTIME, Name='My Task', RestorePopOuts=true);
```

What each window *shows* is not part of this. Every component already saves
its own position, size, font size, column and field selection, sort order,
trial window, and **Keep Window on Top** state under its pop-out preference
key, so a restored window comes back exactly as it was left — this option
only adds the list of *which* windows to open. Both kinds are covered: a
component's own pop-out, and a window `gui.components.ComponentToolbar` opened for a
lazy entry the GUI does not display at all.

The list is rewritten **the moment a window opens or closes**, not at
teardown, so a MATLAB that was killed rather than closed still remembers.
It lives under the GUI's own `PreferenceTag`, as `OpenPopOuts`.

An entry the GUI cannot resolve — a display renamed, a paradigm changed, a
protocol that does not define the parameter behind it — is skipped with a
debug message and **left in the list**, so running one protocol that shows
less than another does not quietly erase the fuller layout. Clearing the
list is explicit:

```matlab
n = obj.restorePopOutLayout();  % reopen now; returns how many opened
obj.savePopOutLayout();         % record what is open (automatic; call after
                                % turning RestorePopOuts on mid-session)
obj.forgetPopOutLayout();       % forget which were open, not how they look
```

Components are identified the way `gui.components.ComponentToolbar` labels them: the
name passed to `register(comp, name)`, else the class name split into words.
A GUI holding two components of one class tells them apart by registration
order, so **name them in `register`** if their order in `build` might change.

## Protected hooks (all optional except build)

| Hook | When it runs |
|---|---|
| `build(obj, fig)` | **Required.** Once, after the figure exists. Create layout and components here. |
| `createPsych(obj, RUNTIME)` | Before the figure. Return a psychophysics object or `[]`. When non-empty, **NewData is listened on `Psych.Events`**, so the psych object has already processed the trial when `onNewData` runs. Errors are logged, never fatal. |
| `onNewTrial(obj, src, event)` | Every `NewTrial` event. |
| `onNewData(obj, src, event)` | Every `NewData` event. |
| `onModeChange(obj, src, event)` | Every `ModeChange`; `event.NewMode` is an `hw.DeviceState`. The base stops registered `Parameter_Monitor` polling on `Stop` before calling this hook. |
| `onFirstTrial(obj, src, event)` | Exactly once, at the first `NewTrial`, after deferred closures run. |

Hook errors are caught and logged with `vprintf(0,1,ME)` so a display bug never kills the event chain.

## Placing components

Every reusable component is placed with **one** method:

```matlab
h = obj.add('gui.components.NextTrial', pnl, FontSize=14);
```

`add` builds the class into `parent`, wires it to the runtime, the analysis
object or the key bindings as the component's own `gui.ComponentSpec` says,
and registers it for teardown. Nothing per-component lives in
`gui.BehaviorGUI` any more.

It **never throws**. When the session cannot support the component — a
parameter name that does not resolve, an analysis that was never built, a
class that is not on the path — it returns `[]` and says why in the log, so
the GUI still opens against a runtime with no interfaces (`epsych.SelfTest`
check I6). A class name that does not resolve and a `getComponentSpec` that
throws are logged at level 1, not 2: a typo in a paradigm's `build` must be
visible at default verbosity, or SelfTest passes over a GUI quietly missing a
display.

Options are forwarded **verbatim**. An option you do not name is not passed at
all, which is what lets a component fall back to the operator's own saved
preference rather than being handed a default nobody chose. Three names are
consumed by `add` and never forwarded:

| Option | Effect |
|---|---|
| `Variant` | Select a non-primary variant of a class that declares several (`gui.components.Parameter_Control` is both the Control and the Button). |
| `KeyBinding` | Replace the component's default chord, or drop it with `'none'`. |
| `RegisterName` | Name this instance for the component toolbar and the pop-out memory. |

A class from **outside this toolbox** works the same way, with no registration
of any kind — its constructor signature is enough:

```matlab
obj.add('mylab.RasterPlot', pnl, Channel=3);
```

### The stock components

Each takes the options its own class documents; the pages below are the
reference for what they do.

| `add` line | What it is |
|---|---|
| `obj.add('gui.components.Parameter_Monitor', p, 'Parameters', {'InTrial','RespCode'}, pollPeriod=0.5)` | Read-only live values. Registered monitors stop polling when the session stops. |
| `obj.add('gui.components.NextTrial', p, Fields=["Depth" "TrialType"])` | The upcoming trial's parameters, bound to `obj.RUNTIME`. |
| `obj.add('gui.components.SessionPerformance', p, TrialWindow=…)` | Hit / false-alarm / abort rates, d', counts, through a `psychophysics.SessionMetrics` over `obj.Psych` when there is one — see [gui_SessionPerformance.md](gui_SessionPerformance.md). |
| `obj.add('gui.components.History', p)` | Per-trial outcome table over `obj.Psych`; `[]` when `createPsych` produced nothing — see [gui_History.md](gui_History.md). |
| `obj.add('gui.components.ParameterScatter', p, XParameter=…, YParameter=…)` | Any two recorded trial parameters. Its source is `obj.RUNTIME`, so it works with no analysis at all — see [gui_ParameterScatter.md](gui_ParameterScatter.md). |
| `obj.add('gui.components.OnlinePlot', p, Source={'Lick','StimOn'})` | Live hardware traces. Makes a **classic** axes inside `parent`, so pass a panel or grid cell. `Source` left empty returns `[]` rather than putting a dialog in front of a starting session; `TimeWindow` applies only when nothing was remembered — see [gui_OnlinePlot.md](gui_OnlinePlot.md). |
| `obj.add('gui.components.BufferPlot', p, Buffers="Waveform~1", SampleRate="auto")` | Buffer CONTENTS, redrawn once per completed trial, taken from the trial record the runtime already read — see [gui_BufferPlot.md](gui_BufferPlot.md). |
| `obj.add('gui.components.PsychPlot', p)` | Psychometric curve over `obj.Psych`, `[]` when there is none. Also a **classic** axes: pass a panel, not an axes of your own. |
| `obj.add('gui.components.SessionClock', p)` | Session and inter-trial elapsed time. Builds its own panel — place it through the returned object: `c.PanelH.Layout.Row = 1`. |
| `obj.add('gui.components.ElapsedTrialTimer', p)` | Time since the last completed trial. |
| `obj.add('gui.components.ModeIndicator', p)` | Lamp showing the session's run mode. |
| `obj.add('gui.components.Notes', g)` | The operator's note pad — entry line over a trial-stamped log. Notes reach `Info.Notes` in every subject's data file and are journaled as committed — see [gui_Notes.md](gui_Notes.md). |
| `obj.add('gui.components.Notes', row, ButtonOnly=true)` | The same notes as a single button, for a GUI with no room for a log. |
| `obj.add('gui.components.SyringePump', p, Sections=["Volume" "Status"])` | Panel over this session's `hw.NE1000`, or a standalone one when the protocol has no pump, so the GUI still opens — see [gui_SyringePump.md](gui_SyringePump.md). |
| `obj.add('gui.components.ScreenCapture', row)` | Camera button; copies the whole window to the clipboard. `Ctrl+Shift+C` too — see [gui_ScreenCapture.md](gui_ScreenCapture.md). |
| `obj.add('gui.components.SessionGate', g)` | **Begin Experiment** button. Only half of it: `waitForSessionGate` in your constructor is what holds the session — see [gui_SessionGate.md](gui_SessionGate.md). |
| `obj.add('gui.components.RegenerateTrial', g)` | Dispatches the pending trial again. Dead until Ctrl+Alt+Shift are held; **interrupts the trial in progress and asks nothing first** — see [gui_RegenerateTrial.md](gui_RegenerateTrial.md). |
| `obj.add('gui.components.ComponentToolbar', fig)` | Icon toolbar, one tool per display. Call it **first** in `build` — see below. |
| `obj.add('gui.components.PhaseSelector', p)` | Phase load / save — see [PhaseSelector.md](PhaseSelector.md). |
| `obj.add('gui.components.StatusBar', p)` | Session status strip. |

`gui.components.ComponentToolbar` is collected **after** `build` returns, so
calling it on the first line of `build` still lists everything created below
it. Displays the GUI does not show are declared on the returned toolbar and
built the first time their tool is clicked:

```matlab
tb = obj.add('gui.components.ComponentToolbar', fig);
tb.addLazyComponent('Performance', ...
    @(c) gui.components.SessionPerformance(obj.RUNTIME, c), ...
    Icon='sessionperformance', WindowSize=[420 260]);
```

### The short names that survive

These are sugar over `add`, kept because they read better at their call sites,
plus three methods that build something which is not a component at all.

The stock commit paths make **session-record notes** standard for every
subclass: a `gui.components.Parameter_Update` commit, an `autoCommit`
`addControl` edit, and a `gui.components.PhaseSelector` phase load or save each
record a trial-stamped entry into `RUNTIME.NOTES` via
`epsych.SessionNotes.log`. Those entries reach `Info.Notes` and the trial
journal in every subject's data file, whether or not the GUI includes a
`gui.components.Notes` component. Per-trial automatic writes and `addButton`'s
toggles/triggers deliberately record nothing — see
[gui_Notes.md](gui_Notes.md#automatic-entries).

- `h = addControl(parent, param, ...)` — a `gui.components.Parameter_Control`. `param` is an `hw.Parameter` **or a name** resolved against `obj.P` (trigger prefixes `~`/`!` tolerated). Unresolved names log at debug level and return `[]` — no `isfield` guards needed, and one build method serves protocols with differing parameter sets. Options: `Type` (default `'auto'`), `BoundProperty` (default unset — the control type picks it: `Type='range'` binds the `[Min Max]` pair on one row, everything else binds `Value`), `autoCommit`, `Text` (defaults to `Name (Unit)`), `EnabledBy`/`DisabledBy`, `PostUpdateFcn`/`PostUpdateFcnArgs`, `EvaluatorFcn`/`EvaluatorArgs`. Because it routes through `add`, options are forwarded verbatim: anything `gui.components.Parameter_Control` accepts works here. The control gets `obj.RUNTIME`, so an `autoCommit` Value edit also lands in the trial table instead of being reverted by the next dispatch or misrecorded by a phase save (see that class's `Runtime` option).
- `h = addButton(parent, param, ...)` — the Button **variant** of the same class: an auto-committing button. `~`-prefixed parameters become toggles, others momentary (`Type` overrides). Rotating accent colors, bold text, prefix stripped from the label. Stored in `obj.hButtons.(validName)`, which is derived from the registry rather than accumulated, so it cannot drift from what was actually built. Buttons deliberately do **not** sync the trial table: session-control toggles rely on the table re-assert to self-clear.
- `lay = controlColumn(parent, Title=, Row=, Column=, Rows=, RowHeight=)` — titled panel with a scrollable fixed-row grid, ready for a stack of `addControl` calls. It builds layout, not a component, so nothing is registered.
- `h = addUpdateButton(parent, KeyBinding=)` — a `gui.components.Parameter_Update` commit button. Its `watchedHandles` are filled automatically after `build` with every registered non-trigger, non-autoCommit control, regardless of creation order. `Ctrl+Enter` commits as well, and is inert when nothing is pending; `KeyBinding='none'` drops the shortcut.
- `ax = addStaircasePlot(parent)` — plots `obj.Psych`'s staircase track, reversals and threshold into a new `uiaxes` and returns the axes. There is no component to register: a `psychophysics.Staircase` draws itself and owns its own listener. Returns `[]` with no staircase.
- `h = addPopOutButton(parent, component, Text=, Tooltip=)` — a button that opens a poppable display in a window of its own, for something the operator only wants to see occasionally. `component` is any `gui.PopOut` component; one that is not poppable is skipped with a message. The embedded component stays exactly where it is — see [gui_PopOut.md](gui_PopOut.md).
- `tf = waitForSessionGate(timeout)` — hold the session until the gate opens, returning whether it did. Call it from the **subclass constructor**, after the base constructor has returned and the window exists to be clicked. Returns `true` immediately with no gate in the GUI, and in `ReviewMode`.
- `register(comp, name)` — add **any** component built with its native API, or a secondary figure, to the teardown registry. The optional `name` is what a component toolbar calls it; without one the tool is labelled from the class name, which is only ambiguous when one GUI holds two components of the same class.
- `defer(fcn)` — queue a closure until the first `NewTrial`, when trial data and late-bound parameters exist. Runs immediately if the first trial already happened.

### ComponentSpec: what a component declares

A component declares one static method, and `add`, the
[builder](gui_BehaviorBuilder.md) palette and its code generator all read that
one declaration:

```matlab
methods (Static)
    function s = getComponentSpec()
        s = gui.ComponentSpec();
        s.shape    = ["runtime","parent"];
        s.category = 'Displays';
    end
end
```

This mirrors `hw.Interface.getCreationSpec` / `hw.InterfaceSpec`, which does
the same job for hardware backends. `shape` is the positional argument list as
tokens — `parent`, `figure`, `host`, `runtime`, `psych`, `psychOrRuntime`,
`keys`, `canvas`, or `arg:Name` for a named option consumed positionally.

A class that declares **nothing** still works: `gui.ComponentSpec.forClass`
infers a spec from the constructor's argument *names*, read from the `function`
line rather than `meta.method.InputNames`, which collapses every
arguments-block signature to `{'varargin'}`. `runtime`/`rt`, `pObj`/`psychObj`,
`source`/`src`, `parent`/`container`/`hParent`, `fig`/`hFig`, `ax`/`haxes` and
`options`/`varargin` are all recognized. A constructor whose container is
called something unlisted (`hostPanel`) will **not** receive it: declare a
spec, or rename the argument.

Two conventions a new component should follow:

- Declare a `PreferenceTag` option (with no default) if it remembers anything
  by tag. The builder unique-tags a component placed twice **only** when its
  spec declares that option.
- Give an option a `defaultValue` only when the component has a real one. An
  option with none stays unstated, so a saved preference can still win.

Specs are memoized, so editing one mid-session needs
`gui.ComponentSpec.flushCache`. A class that is not on the path yet is **not**
cached as a miss, so a GUI built before a lab folder was added to the path can
still find it afterwards.

## Keyboard shortcuts

`obj.Keys` is a [`gui.KeyBindings`](gui_KeyBindings.md) that owns this figure's
key callbacks. Bind from `build`:

```matlab
obj.Keys.bind('leftarrow', @() obj.respondSide(0), Description='Respond LEFT');
```

**Never assign `fig.WindowKeyPressFcn` or `WindowKeyReleaseFcn` on the main
figure.** There is one of each slot, and assigning it takes the keys away from
every component that already asked for one — the bug this centralization
exists to prevent. (A subclass that still does is chained rather than dropped,
but it will take the keys from anything bound after it.)

Three things come with a default chord, each dropped with `KeyBinding='none'`
or replaced with a chord of your own: `addUpdateButton` (`Ctrl+Enter`), the
`ScreenCapture` component (`Ctrl+Shift+C`) and the `Notes` component
(`Ctrl+Shift+N`). `Ctrl+Shift+?` and `F1` list everything bound.

`SessionGate`, `SyringePump`, `RegenerateTrial` and the trigger
helpers deliberately have none: those start sessions, move syringes, or
interrupt the trial in progress, and a keystroke is the wrong way to do any of
them.

A shortcut does not fire while an edit field has focus — a uifigure delivers no
window key event then, which is also what stops one firing mid-note — and a
binding is suppressed during a review unless bound with `EnableInReview=true`.

## Lifecycle and teardown guarantees

- **Single instance**: constructing a second GUI with the same `PreferenceTag` saves the old window's position and fully tears down the old instance first.
- **Close**: the figure's close button routes through `closeGUI`, which saves the window position and maximized state, then deletes the object. The next launch reopens the GUI exactly there — maximized again if it was closed maximized. A window closed maximized deliberately does **not** overwrite the saved position (a maximized figure's `Position` reports the screen-filling bounds), so un-maximizing the reopened window restores the last normal size.
- **Close while running**: if the session driving this GUI is still `PRGMSTATE.RUNNING`, `closeGUI` first raises a modal dialog offering **Close GUI** (leave the session running without its controls), **Halt Experiment** (`RunExpt.halt`, which routes through the same dispatch as the session window's own Stop control, so the mode broadcast, timer stop, and data save all happen while this GUI's listeners are still alive — then close), and **Cancel** (default; the window stays open). The prompt only appears for the session that actually owns this GUI: the open `RunExpt` window's `RUNTIME` must be the same handle as `obj.RUNTIME`, so a window left over from an earlier run, or one opened against the synthetic runtime of SelfTest check I6, closes silently as before.
- **Destructor**: takes the `RestorePopOuts` snapshot first, while every component and window is still intact, then disables and deletes the three event listeners, deletes every registered component in reverse order (this is what prevents leaked listeners and timers — deleting a figure alone only removes graphics, not the component handle objects), deletes the psych object, then the figure.

Because of the registry, a subclass normally needs **no destructor at all**. Only add one if you own resources the registry cannot know about, and call `delete@gui.BehaviorGUI(obj)` at the end.

## Review mode

`epsych.ReviewSession` reopens a **finished** session in the paradigm's own GUI, by attaching it to an offline `epsych.Runtime` and firing real `NewTrial`/`NewData` events out of a real `epsych.EventHub`. Every display therefore works unchanged: the events, the trial data and the parameter reads are all real.

**A GUI that only displays needs no changes at all.**

**A GUI that drives the rig needs one guard.** Some subclasses do more than display — they run their own timer, write parameters, and hand the trial back by raising `x_TrialComplete_*`. Against a finished session that would be scoring trials nobody ran. The base class cannot decide this for you: it does not know which of your methods are display and which are contingency.

`obj.ReviewMode` (dependent, read-only; forwards `RUNTIME.ReviewMode`) is the flag. The rule of thumb: **guard anything that would still be a mistake if the hardware were switched off.**

```matlab
function tf = rigReady_(obj)
    if obj.ReviewMode      % a review has no rig to drive
        tf = false;
        return
    end
    ...
end
```

`TwoAFCBehaviorGUI`, `FirstExperimentBehaviorGUI` and `PumpBehaviorGUI` put it in `rigReady_` — the single gate their trial cycle already passed through — and additionally skip starting their rig timer. `PumpBehaviorGUI` also skips its blocking `waitForBegin`: a constructor that blocks would hang the review inside `feval`, with a half-built window and no way to reach the Begin button.

Two things the review does for you, so no subclass has to:

- **Controls disable themselves.** The review moves its backends `Standby → Idle` *after* `build` returns, and every `gui.components.Parameter_Control` greys out through the `mode` listener it already has.
- **Monitors stop polling.** The review broadcasts `ModeChange(Idle)`, and the base class stops every registered `gui.components.Parameter_Monitor`.

A file saved before the session snapshot existed carries no protocol, so no parameters resolve — `addControl`/`addButton` skip them as they already do, and the GUI opens with its data displays and no control column. See [epsych_ReviewSession.md](../epsych/epsych_ReviewSession.md).

## Utilities

- `gui.BehaviorGUI.classifyParameters(params)` — static; splits an `hw.Parameter` array into trigger-style, writable, and read-only visible groups using the standard rules (`isTrigger` or `~`/`!` name prefix marks a trigger). This is what `ep_GenericGUI` uses to auto-build itself.
- `gui.BehaviorGUI.getSavedFigurePosition(prefTag, default)` / `saveFigurePosition(prefTag, pos)` — static position-preference helpers, keyed by `PreferenceTag`.
- `gui.BehaviorGUI.saveFigureLayout(prefTag, fig)` / `getSavedFigureWindowState(prefTag)` — the maximize-aware layer over those: `saveFigureLayout` records the figure's maximized state and, only when the window is normal, its position (fullscreen is remembered as maximized, minimized as normal). Any window class can use them for the same behavior.
- `gui.fitPositionToMonitor(pos)` — applied by `getSavedFigurePosition` to whatever it returns, so a restored window is on-screen without a `movegui(fig,'onscreen')` after it. This is what makes the GUI reopen on the **monitor it was last on**: `movegui` takes its reference monitor from the first corner of the window it finds inside one, so a window left hanging a little off the edge of a secondary monitor was attributed to a neighbour — usually the primary — and clamped onto it. Choosing the monitor by overlap **area** instead cannot be fooled that way. A rectangle that already fits its monitor is returned untouched, so an unchanged monitor layout restores exactly; a window whose monitor is gone overlaps nothing and falls back to the primary.

The position is written by `closeGUI` on the operator's way out and, for any other teardown path (`delete(obj)` from a script, a review session closing down), by the destructor.

## Reference implementations

- [runtime/guis/@ep_GenericGUI](../../runtime/guis/@ep_GenericGUI/ep_GenericGUI.m) — the default BehaviorGUI, a ~95-line subclass that auto-discovers all parameters.
- [examples/customgui/ExampleBehaviorGUI.m](../../examples/customgui/ExampleBehaviorGUI.m) — the copyable paradigm-GUI template.
- Validation: `tmp/smoke_test_behaviorgui.m` (headless; `matlab -batch "run('tmp/smoke_test_behaviorgui.m')"`); `tmp/smoke_test_popout_restore.m` for the `RestorePopOuts` memory; `tmp/smoke_test_monitor_restore.m` for the monitor a window reopens on.

See also: [Customized_GUI_Instructions.md](../design/Customized_GUI_Instructions.md) for the surrounding concepts (parameters, events, layout strategy), [Parameter_Control.md](Parameter_Control.md), [Parameter_Update.md](Parameter_Update.md), [Parameter_Monitor.md](Parameter_Monitor.md), [gui_NextTrial.md](gui_NextTrial.md), [gui_PopOut.md](gui_PopOut.md), [gui_ComponentToolbar.md](gui_ComponentToolbar.md), [gui_ParameterDebugger.md](gui_ParameterDebugger.md) — for the parameters a behavior GUI does not expose, [../epsych/Event_Notifications.md](../epsych/Event_Notifications.md).
