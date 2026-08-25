# gui.BehaviorGUI — Base class for custom experiment GUIs

`gui.BehaviorGUI` is the recommended starting point for a custom experiment GUI. It owns everything a paradigm GUI needs besides its layout: single-instance enforcement, figure creation with position persistence, runtime event listeners, a teardown-guaranteed component registry, and automatic `gui.Parameter_Update` wiring. A subclass implements one required method — `build(fig)` — and optionally overrides a handful of protected hooks.

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
component's own pop-out, and a window `gui.ComponentToolbar` opened for a
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

Components are identified the way `gui.ComponentToolbar` labels them: the
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
- `h = addNotes(parent, Subject=, TimeStamp=, Editable=, FontSize=, Placeholder=, ButtonOnly=, Text=, PreferenceTag=)` — a `gui.Notes` panel: an entry line the operator types a note into (Enter, or the button beside it, commits) over a log of everything typed, each line stamped with the trial it was typed on. The notes go into this session's store, which means they are saved with the data — the `Info` variable every saving function writes carries them — and journaled as they are committed, so a crash keeps them. The log box fills whatever row the layout gives it and is read-only until the right-click **Editable** is ticked — see [gui_Notes.md](gui_Notes.md).
- `h = addNotesButton(parent, Text=, Subject=, TimeStamp=, FontSize=, PreferenceTag=)` — the same notes as a single button, for a GUI with no room for a log. It opens them in a window of its own, over the same store: the window shows every note the session has and anything typed there is saved with the data just the same.
- `h = addHistory(parent, ColumnFormats=, BitColors=, PreferenceTag=)` — a `gui.History` per-trial outcome table over `obj.Psych`. Returns `[]` when `createPsych` produced nothing, so a GUI still opens against a runtime with no interfaces — see [gui_History.md](gui_History.md).
- `h = addScatter(parent, XParameter=, YParameter=, ColorParameter=, BoxID=, PreferenceTag=)` — a `gui.ParameterScatter` over any two recorded trial parameters. Its source is `obj.RUNTIME` rather than `obj.Psych`, so it works in a paradigm with no analysis at all — see [gui_ParameterScatter.md](gui_ParameterScatter.md).
- `h = addOnlinePlot(parent, Source=, BoxID=, TimeWindow=, PreferenceTag=)` — a `gui.OnlinePlot` of live hardware activity. Like `addPsychPlot` it makes a **classic** axes inside `parent`, so pass a panel or grid cell. `Source` names the traces (parameter names, `hw.Parameter` handles, or a bitmask bank name); left empty it returns `[]` and logs, rather than putting a list dialog in front of a starting session. `TimeWindow` applies only when nothing was remembered under `PreferenceTag` — see [gui_OnlinePlot.md](gui_OnlinePlot.md).
- `h = addPsychPlot(parent)` — a `gui.PsychPlot` psychometric curve over `obj.Psych`, `[]` when there is none. `gui.PsychPlot` draws into a **classic** axes rather than a `uiaxes`, so one is created inside `parent`: pass a panel or grid cell, not an axes of your own.
- `ax = addStaircasePlot(parent)` — plots `obj.Psych`'s staircase track, reversals and threshold into a new `uiaxes` and returns the axes. There is no component to register: a `psychophysics.Staircase` draws itself and owns its own listener. Returns `[]` with no staircase.
- `h = addSessionClock(parent, UpdatePeriod=, FontSize=, FontColor=, ShowTimeSinceLastTrial=, ShowTimeSinceFirstTrial=, ShowSessionDuration=, ShowClockTime=, PreferenceTag=)` — a `gui.SessionClock`, wired to the runtime and started. It builds its own panel, so place it through the returned object: `c.PanelH.Layout.Row = 1`.
- `h = addTrialTimer(parent, UpdatePeriod=, Format=, FontSize=, FontColor=, FontWeight=, Prefix=)` — a `gui.ElapsedTrialTimer` showing time since the last completed trial, wired to the runtime.
- `h = addModeIndicator(parent, FontSize=)` — a `gui.ModeIndicator` lamp showing the session's run mode, wired to the runtime.
- `h = addSessionGate(parent, Text=, RunningText=, PreviewText=, CompleteText=, Tooltip=, FontSize=, FontWeight=, BackgroundColor=)` — a `gui.SessionGate` **Begin Experiment** button, for a rig that must not start dispatching until the animal is placed and the line is primed. This is only half of it: `waitForSessionGate` in your constructor is what actually holds the session, and it cannot be called from `build` — see [gui_SessionGate.md](gui_SessionGate.md).
- `tf = waitForSessionGate(timeout)` — hold the session until the gate opens, returning whether it did. Call it from the **subclass constructor**, after the base constructor has returned and the window exists to be clicked. Returns `true` immediately with no gate in the GUI, and in `ReviewMode`.
- `h = addScreenCapture(parent, Target=, Text=, Tooltip=, FontSize=, FlashDuration=)` — a `gui.ScreenCapture` camera button. One click copies a picture of the whole window — controls, plots and all — to the system clipboard, for pasting into a notebook entry; the button flashes a check to confirm, since the clipboard gives no feedback of its own. `Target` defaults to this GUI's figure. A failed capture is logged and flashed, never thrown — see [gui_ScreenCapture.md](gui_ScreenCapture.md).
- `h = addRegenerateTrial(parent, Text=, Tooltip=, SubjectIndex=, Reselect=, Note=, EnableWhenIdle=, RequireArming=, ShowIcon=, FontSize=, FontWeight=, BackgroundColor=)` — a `gui.RegenerateTrial` button that dispatches the pending trial again, so randomized parameters redraw and committed edits reach the hardware without waiting for the next trial. The button is **dead until Ctrl+Alt+Shift are all held** — the same gesture `gui.Parameter_Update` uses — and dies again the moment one is released; `RequireArming=false` removes that. It chains the figure's key callbacks rather than claiming them, and re-installs on the first `ModeChange`, so it coexists with the Update button whichever order `build` creates them in. Once armed, **it interrupts the trial in progress and asks nothing first**: the reset and new-trial triggers go out whether the rig is in an ITI or the animal is part way through a response, and the `DATA` record for that trial ends up describing the last dispatch rather than the first. Each press is written into the session notes, which is the only trace the trial data keeps. Live only during Preview or Record, never in a review. Add it for an operator who wants it, and not into a row of trigger buttons a mis-click can reach — see [gui_RegenerateTrial.md](gui_RegenerateTrial.md).
- `h = addPopOutButton(parent, component, Text=, Tooltip=)` — a button that opens a poppable display in a window of its own, for something the operator only wants to see occasionally. `component` is any `gui.PopOut` component (scatter, history, performance, next-trial, monitor, plot, a plotted `psychophysics.Staircase`); one that is not poppable is skipped with a message. The embedded component stays exactly where it is — see [gui_PopOut.md](gui_PopOut.md).
- `tb = addComponentToolbar(parent, Style=, Exclude=, AutoDiscover=)` — an optional icon toolbar that opens displays in windows of their own, one tool each. Call it **first** in `build`: every `gui.PopOut` component registered anywhere in `build` gets a tool, because the list is collected after `build` returns. Displays the GUI does *not* show are declared on the returned toolbar with `tb.addLazyComponent(name, factory, Icon=, WindowSize=, Style=)` and built the first time their tool is clicked, so an occasional display costs no listeners or polling timer up front. `Style="toggle"` makes the tools show which windows are open. A GUI that never calls this has no toolbar — see [gui_ComponentToolbar.md](gui_ComponentToolbar.md).
- `register(comp, name)` — add **any** component built with its native API (`gui.PhaseSelector`, `gui.StatusBar`, `gui.OnlinePlot`, a secondary figure, ...) to the teardown registry. The optional `name` is what a component toolbar calls it; without one the tool is labelled from the class name, which is only ambiguous when one GUI holds two components of the same class.
- `defer(fcn)` — queue a closure until the first `NewTrial`, when trial data and late-bound parameters exist. Runs immediately if the first trial already happened.

## Lifecycle and teardown guarantees

- **Single instance**: constructing a second GUI with the same `PreferenceTag` saves the old window's position and fully tears down the old instance first.
- **Close**: the figure's close button routes through `closeGUI`, which saves the window position and deletes the object.
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

- **Controls disable themselves.** The review moves its backends `Standby → Idle` *after* `build` returns, and every `gui.Parameter_Control` greys out through the `mode` listener it already has.
- **Monitors stop polling.** The review broadcasts `ModeChange(Idle)`, and the base class stops every registered `gui.Parameter_Monitor`.

A file saved before the session snapshot existed carries no protocol, so no parameters resolve — `addControl`/`addButton` skip them as they already do, and the GUI opens with its data displays and no control column. See [epsych_ReviewSession.md](../epsych/epsych_ReviewSession.md).

## Utilities

- `gui.BehaviorGUI.classifyParameters(params)` — static; splits an `hw.Parameter` array into trigger-style, writable, and read-only visible groups using the standard rules (`isTrigger` or `~`/`!` name prefix marks a trigger). This is what `ep_GenericGUI` uses to auto-build itself.
- `gui.BehaviorGUI.getSavedFigurePosition(prefTag, default)` / `saveFigurePosition(prefTag, pos)` — static position-preference helpers, keyed by `PreferenceTag`.

## Reference implementations

- [runtime/guis/@ep_GenericGUI](../../runtime/guis/@ep_GenericGUI/ep_GenericGUI.m) — the default BehaviorGUI, a ~95-line subclass that auto-discovers all parameters.
- [examples/customgui/ExampleBehaviorGUI.m](../../examples/customgui/ExampleBehaviorGUI.m) — the copyable paradigm-GUI template.
- Validation: `tmp/smoke_test_behaviorgui.m` (headless; `matlab -batch "run('tmp/smoke_test_behaviorgui.m')"`); `tmp/smoke_test_popout_restore.m` for the `RestorePopOuts` memory.

See also: [Customized_GUI_Instructions.md](../design/Customized_GUI_Instructions.md) for the surrounding concepts (parameters, events, layout strategy), [Parameter_Control.md](Parameter_Control.md), [Parameter_Update.md](Parameter_Update.md), [Parameter_Monitor.md](Parameter_Monitor.md), [gui_NextTrial.md](gui_NextTrial.md), [gui_PopOut.md](gui_PopOut.md), [gui_ComponentToolbar.md](gui_ComponentToolbar.md), [gui_ParameterDebugger.md](gui_ParameterDebugger.md) — for the parameters a behavior GUI does not expose, [../epsych/Event_Notifications.md](../epsych/Event_Notifications.md).
