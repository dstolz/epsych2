# gui.BoxGUI — Base class for custom experiment GUIs

`gui.BoxGUI` is the recommended starting point for a custom experiment (BoxFig) GUI. It owns everything a paradigm GUI needs besides its layout: single-instance enforcement, figure creation with position persistence, runtime event listeners, a teardown-guaranteed component registry, and automatic `gui.Parameter_Update` wiring. A subclass implements one required method — `build(fig)` — and optionally overrides a handful of protected hooks.

A complete, runnable template lives at [examples/customgui/ExampleBoxGUI.m](../../examples/customgui/ExampleBoxGUI.m); launch it without hardware via [examples/customgui/run_example.m](../../examples/customgui/run_example.m).

## The BoxFig contract

`epsych.RunExpt` launches the configured box GUI at session start as `feval(FUNCS.BoxFig, RUNTIME)` — one input, no outputs, opens a window. A `gui.BoxGUI` subclass satisfies this automatically as long as its constructor accepts the runtime and forwards it to the base:

```matlab
function obj = MyTaskGUI(RUNTIME)
    obj@gui.BoxGUI(RUNTIME, Name='My Task');
    if nargout == 0, clear obj; end
end
```

Name the class on the **project** that runs it: **Subjects > Subjects & Projects**, then **Project > Edit Project... > Session Defaults** and the **Box GUI** field. `epsych.SubjectRoster.assignToSession` puts it on `FUNCS.BoxFig` when that project's subjects are added to the session, so a rig alternating between two paradigms picks up the right GUI from the animals it is running rather than from a per-rig setting. (It used to be Customize's **Box GUI Function** field; see [`gui.SubjectManager`](gui_SubjectManager.md#the-project-dialog).) The GUI is created *after* the runtime timer starts, so parameters already carry live values; it must nonetheless open against a runtime with **no** interfaces (the pre-flight self-test launches it that way), which the base guarantees: `addControl`/`addButton` silently skip parameter names that do not resolve.

## Minimal subclass

```matlab
classdef MyTaskGUI < gui.BoxGUI
    methods
        function obj = MyTaskGUI(RUNTIME)
            obj@gui.BoxGUI(RUNTIME, Name='My Task', DefaultPosition=[100 100 1100 650]);
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
            obj.addMonitor(p, {'InTrial','RespCode'}, pollPeriod=0.5);
        end

        function onNewData(obj, src, event)
            % per-trial updates; obj.Psych has already processed the trial
        end
    end
end
```

No destructor, no closeGUI, no single-instance code, no position prefs, no listener plumbing, no watchedHandles wiring, no isfield guards.

## Constructor options

`obj@gui.BoxGUI(RUNTIME, ...)` accepts:

| Option | Default | Meaning |
|---|---|---|
| `Name` | `'Behavior Box'` | Figure title |
| `DefaultPosition` | `[100 100 1100 680]` | `[x y w h]` used when no saved position exists |
| `PreferenceTag` | class name | Figure `Tag`, single-instance key, and `getpref`/`setpref` group for the saved position |
| `Visible` | `true` | Set `false` to build hidden (useful in tests) |

Constructor sequence: single-instance replacement → cache `obj.P = RUNTIME.all_parameters(asStruct=true, includeTriggers=true)` → `createPsych` → create the `uifigure` → `build(fig)` → wire `Parameter_Update.watchedHandles` from the registry → attach `NewTrial`/`NewData`/`ModeChange` listeners.

## Protected hooks (all optional except build)

| Hook | When it runs |
|---|---|
| `build(obj, fig)` | **Required.** Once, after the figure exists. Create layout and components here. |
| `createPsych(obj, RUNTIME)` | Before the figure. Return a psychophysics object or `[]`. When non-empty, **NewData is listened on `Psych.Helper`**, so the psych object has already processed the trial when `onNewData` runs. Errors are logged, never fatal. |
| `onNewTrial(obj, src, event)` | Every `NewTrial` event. |
| `onNewData(obj, src, event)` | Every `NewData` event. |
| `onModeChange(obj, src, event)` | Every `ModeChange`; `event.NewMode` is an `hw.DeviceState`. The base stops registered `Parameter_Monitor` polling on `Stop` before calling this hook. |
| `onFirstTrial(obj, src, event)` | Exactly once, at the first `NewTrial`, after deferred closures run. |

Hook errors are caught and logged with `vprintf(0,1,ME)` so a display bug never kills the event chain.

## Component helpers

All helpers register what they create, guaranteeing teardown (see below).

- `h = addControl(parent, param, ...)` — a `gui.Parameter_Control`. `param` is an `hw.Parameter` **or a name** resolved against `obj.P` (trigger prefixes `~`/`!` tolerated). Unresolved names log at debug level and return `[]` — no `isfield` guards needed, and one build method serves protocols with differing parameter sets. Options: `Type` (default `'auto'`), `BoundProperty` (default unset — the control type picks it: `Type='range'` binds the `[Min Max]` pair on one row, everything else binds `Value`), `autoCommit`, `Text` (defaults to `Name (Unit)`), `PostUpdateFcn`/`PostUpdateFcnArgs`, `EvaluatorFcn`/`EvaluatorArgs`. The control gets `obj.RUNTIME`, so an `autoCommit` Value edit also lands in the trial table instead of being reverted by the next dispatch or misrecorded by a phase save (see `gui.Parameter_Control`'s `Runtime` option).
- `h = addButton(parent, param, ...)` — an auto-committing button. `~`-prefixed parameters become toggles, others momentary (`Type` overrides). Rotating accent colors, bold text, prefix stripped from the label. Stored in `obj.hButtons.(validName)`. Buttons deliberately do **not** sync the trial table: session-control toggles rely on the table re-assert to self-clear.
- `lay = controlColumn(parent, Title=, Row=, Column=, Rows=, RowHeight=)` — titled panel with a scrollable fixed-row grid, ready for a stack of `addControl` calls.
- `h = addUpdateButton(parent)` — a `gui.Parameter_Update` commit button. Its `watchedHandles` are filled automatically after `build` with every registered non-trigger, non-autoCommit control, regardless of creation order.
- `h = addMonitor(parent, params, pollPeriod=, type=, ...)` — a `gui.Parameter_Monitor` over parameters or resolvable names (missing names skipped). Registered monitors stop polling when the session stops.
- `h = addNextTrial(parent, Fields=, Formatters=, FontSize=, PreferenceTag=)` — a `gui.NextTrial` showing the upcoming trial's parameters, bound to `obj.RUNTIME`. Which fields are shown is programmatic (`Fields`) and/or operator-driven (right-click **Show Field** menu), and persists across sessions.
- `h = addPerformance(parent, Metrics=, TrialWindow=, FontSize=, ShowHeader=, ShowDetail=, PreferenceTag=)` — a `gui.SessionPerformance` summary (hit / false alarm / abort rates, d', counts) computed by a `psychophysics.SessionMetrics` over `obj.Psych`'s data when there is one, the runtime otherwise. Which trials it summarizes is programmatic (`TrialWindow`) and operator-driven (right-click **Trials Included**), and persists across sessions.
- `h = addSyringePump(parent, Diameter=, Rate=, Direction=, RateUnits=, VolumeUnits=, UpdatePeriod=, Port=, ApplyOnStart=, Sections=, FontSize=, PreferenceTag=)` — a `gui.SyringePump` panel over this session's `hw.NE1000`: dispensed-volume readout, port picker, syringe diameter, rate, push/withdraw, and manual Start / Stop / Zero. `Sections` picks which of those appear (`Sections=["Volume" "Status" "Triggers"]` for a readout with buttons and nothing else), and the operator can re-show any of them from the panel's right-click menu, which is remembered across sessions. Rate and readout units (µL or mL, per minute or per hour; mL/min by default) are on that menu too — state `RateUnits` when the protocol owns the rate, since the panel puts the interface into the units it displays. With no pump in the protocol it makes a standalone interface and offers a port to connect on, so the GUI still opens — see [gui_SyringePump.md](gui_SyringePump.md). Options are declared without defaults, so only what the build method states is forwarded; the rest falls back to the operator's remembered configuration.
- `h = addPopOutButton(parent, component, Text=, Tooltip=)` — a button that opens a poppable display in a window of its own, for something the operator only wants to see occasionally. `component` is any `gui.PopOut` component (scatter, history, performance, next-trial, monitor, plot, a plotted `psychophysics.Staircase`); one that is not poppable is skipped with a message. The embedded component stays exactly where it is — see [gui_PopOut.md](gui_PopOut.md).
- `register(comp)` — add **any** component built with its native API (`gui.ParameterScatter`, `gui.History`, `gui.PhaseSelector`, a secondary figure, ...) to the teardown registry.
- `defer(fcn)` — queue a closure until the first `NewTrial`, when trial data and late-bound parameters exist. Runs immediately if the first trial already happened.

## Lifecycle and teardown guarantees

- **Single instance**: constructing a second GUI with the same `PreferenceTag` saves the old window's position and fully tears down the old instance first.
- **Close**: the figure's close button routes through `closeGUI`, which saves the window position and deletes the object.
- **Close while running**: if the session driving this GUI is still `PRGMSTATE.RUNNING`, `closeGUI` first raises a modal dialog offering **Close GUI** (leave the session running without its controls), **Halt Experiment** (`RunExpt.halt`, which routes through the same dispatch as the session window's own Stop control, so the mode broadcast, timer stop, and data save all happen while this GUI's listeners are still alive — then close), and **Cancel** (default; the window stays open). The prompt only appears for the session that actually owns this GUI: the open `RunExpt` window's `RUNTIME` must be the same handle as `obj.RUNTIME`, so a window left over from an earlier run, or one opened against the synthetic runtime of SelfTest check I6, closes silently as before.
- **Destructor**: disables and deletes the three event listeners, deletes every registered component in reverse order (this is what prevents leaked listeners and timers — deleting a figure alone only removes graphics, not the component handle objects), deletes the psych object, then the figure.

Because of the registry, a subclass normally needs **no destructor at all**. Only add one if you own resources the registry cannot know about, and call `delete@gui.BoxGUI(obj)` at the end.

## Utilities

- `gui.BoxGUI.classifyParameters(params)` — static; splits an `hw.Parameter` array into trigger-style, writable, and read-only visible groups using the standard rules (`isTrigger` or `~`/`!` name prefix marks a trigger). This is what `ep_GenericGUI` uses to auto-build itself.
- `gui.BoxGUI.getSavedFigurePosition(prefTag, default)` / `saveFigurePosition(prefTag, pos)` — static position-preference helpers, keyed by `PreferenceTag`.

## Reference implementations

- [runtime/guis/@ep_GenericGUI](../../runtime/guis/@ep_GenericGUI/ep_GenericGUI.m) — the default BoxFig, a ~95-line subclass that auto-discovers all parameters.
- [examples/customgui/ExampleBoxGUI.m](../../examples/customgui/ExampleBoxGUI.m) — the copyable paradigm-GUI template.
- Validation: `tmp/smoke_test_boxgui.m` (headless; `matlab -batch "run('tmp/smoke_test_boxgui.m')"`).

See also: [Customized_GUI_Instructions.md](../design/Customized_GUI_Instructions.md) for the surrounding concepts (parameters, events, layout strategy), [Parameter_Control.md](Parameter_Control.md), [Parameter_Update.md](Parameter_Update.md), [Parameter_Monitor.md](Parameter_Monitor.md), [gui_NextTrial.md](gui_NextTrial.md), [gui_PopOut.md](gui_PopOut.md), [../epsych/Event_Notifications.md](../epsych/Event_Notifications.md).
