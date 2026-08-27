# gui.components.SessionGate

A "Begin Experiment" button that holds a session until the operator is
actually at the rig. Nothing dispatches until it is pressed; once it is, the
button retires into a status line that says which kind of run is going.

Source: `obj/+gui/+components/@SessionGate/`

## What it does

- **Holds the session.** `wait` blocks until the button is pressed, the
  timeout expires, or the window closes.
- **Retires the button** rather than leaving a dead control on screen: after
  the press it reads `Experiment Running`, `Preview Running`, or
  `Session Complete`, greyed and disabled.
- **Catches up on its own.** With `attachRuntime`, a run mode arriving
  without a press (a script, a headless test, a session started elsewhere)
  opens the gate and retires the button, so an armed button never stands in
  front of a running trial loop.
- **Tells Preview from Record.** They are distinct `hw.DeviceState`s, and an
  operator who cannot see that a run is a preview will believe data is being
  saved.
- **Fires `GateOpened` exactly once**, however many times `release` is
  called, so a host arming a rig off the event cannot arm twice.

## Usage

The button and the wait are two halves in two places, because `build` runs
from inside the base constructor — before the window is shown. Blocking there
would hold the session at a window nobody can click.

```matlab
classdef MyGUI < gui.BehaviorGUI
    methods
        function obj = MyGUI(RUNTIME, options)
            arguments
                RUNTIME (1,1)
                options.WaitForBegin (1,1) logical = true
            end
            obj@gui.BehaviorGUI(RUNTIME, Name='My Task');
            if options.WaitForBegin
                obj.waitForSessionGate();   % <- the hold
            end
            if nargout == 0, clear obj; end
        end
    end
    methods (Access = protected)
        function build(obj, fig)
            g = uigridlayout(fig, [2 1]);
            obj.add('gui.components.SessionGate', g);          % <- the button
            % ... the rest of the layout ...
        end
    end
end
```

`waitForSessionGate` returns `true` immediately when the GUI has no gate, so
a paradigm can drop the button without touching its constructor.

Standalone, in any container:

```matlab
gate = gui.components.SessionGate(panel, Text='Start When Ready');
gate.attachRuntime(RUNTIME);
if ~gate.wait(300), return; end   % five minutes, then give up
```

| Option | Default | Meaning |
|--------|---------|---------|
| `Text` | `'Begin Experiment'` | Button label while the gate is shut. |
| `RunningText` | `'Experiment Running'` | Retired label after a Record run starts. |
| `PreviewText` | `'Preview Running'` | Retired label after a Preview run starts. |
| `CompleteText` | `'Session Complete'` | Retired label once a run has finished. |
| `Tooltip` | see source | Hover text. |
| `FontSize` | `14` | Label font size. |
| `FontWeight` | `'bold'` | `'bold'` or `'normal'`. |
| `BackgroundColor` | `[0.45 0.75 0.45]` | Button color while it is live. |

| Member | Meaning |
|--------|---------|
| `Released` | Whether the gate has opened. |
| `ButtonH` | The `uibutton`, for a caller that wants to restyle it. |
| `release()` | Open the gate from code, as the button's click does. |
| `wait(timeout)` | Block until it opens; returns whether it did. |
| `attachRuntime(RUNTIME)` | Watch `ModeChange` for the catch-up above. |
| `GateOpened` | Event fired once, when the gate opens. |

## Why it is built this way

**Why blocking works.** `epsych.RunExpt` builds the behavior GUI from the
PsychTimer's `StartFcn`. `start()` does not return until that callback does,
and a MATLAB timer will not fire its `TimerFcn` during another of its own
callbacks — so blocking inside the constructor holds the entire trial loop,
without the runtime needing to know a gate exists at all.

**The wait pauses rather than spins.** Everything else in the window has to
keep working while it holds: for the syringe-pump paradigm this gate came
from, priming the line through the pump panel's manual controls is most of
what the operator is doing during the hold.

**Never in a review.** `epsych.ReviewSession` has no session to hold, and
blocking would hang it inside `feval` with a half-built window and no
reachable button. `gui.BehaviorGUI.waitForSessionGate` returns immediately in
`ReviewMode`; a caller driving `gui.components.SessionGate` directly must make the same
check.

**The button retires instead of disappearing.** Removing it would reflow the
layout mid-session, and merely greying it would leave the operator unable to
tell a Record run from a Preview or a finished one. Reusing the space it
already occupies as a status line answers all three.

**An idle mode before the start is not a finished session.** `Session
Complete` is only written once something actually ran; otherwise a session
sitting at `Idle` waiting to be released would advertise itself as over.

## See also

- `gui.BehaviorGUI` — `add`, `waitForSessionGate`
  (`documentation/gui/gui_BehaviorGUI.md`)
- `examples/syringepump/PumpBehaviorGUI.m` — the paradigm this was extracted
  from, and the worked example of the two-halves pattern
- `gui.components.ModeIndicator` — the lamp for showing run mode when nothing is gated
- `tmp/smoke_test_sessiongate.m` — the standing proof
