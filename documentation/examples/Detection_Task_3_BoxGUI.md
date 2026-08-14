# Detection Task 3 — Building a Behavior-Box GUI

Part of the [detection task worked example](Detection_Task_Walkthrough.md).
Example file: [DetectionBoxGUI.m](../../examples/detection_task/DetectionBoxGUI.m).
Base-class reference: [gui.BoxGUI](../gui/gui_BoxGUI.md).

The starter template [examples/customgui/ExampleBoxGUI.m](../../examples/customgui/ExampleBoxGUI.m)
shows the layout helpers (`addButton`, `addControl`, `controlColumn`,
`addMonitor`, `addUpdateButton`). This example builds on it with the parts a
real task GUI needs: a live analysis pipeline and the event hooks.

## The analysis pipeline: createPsych and the Helper chain

```matlab
function p = createPsych(obj, R)
    p = [];
    if isfield(obj.P, 'ToneLevel')
        p = psychophysics.Detection(R, obj.P.ToneLevel, epsych.BitMask.TrialType_0);
    end
end
```

`createPsych` runs before the figure exists. Returning a psychophysics object
changes where the GUI's `NewData` events come from:

```
RUNTIME.HELPER ── NewData ──▶ psychophysics.Detection (ingests the trial)
                                     │
                              Psych.Helper ── NewData ──▶ this GUI's onNewData
                                                     └──▶ gui.PsychPlot
```

`psychophysics.Detection` listens to `RUNTIME.HELPER`, decodes each trial's
`RespCode`, and re-broadcasts `NewData` on its own `Helper`. Because
`gui.BoxGUI` subscribes to `Psych.Helper` when `createPsych` returns an object,
`onNewData` is guaranteed to run *after* the Detection object has processed the
trial — its dependent properties (`NumTrials`, `Hit_Rate`, `DPrime`, `Count`)
are always current inside the hook. `gui.PsychPlot` hangs off the same Helper
and redraws itself; the GUI never touches it after construction.

Guarding on `isfield(obj.P, 'ToneLevel')` keeps the class loadable against
protocols that lack the parameter — `obj.P` holds every runtime parameter
keyed by `validName`.

One layout note: `gui.PsychPlot` requires a classic `axes` (its argument
validation rejects `uiaxes`); `axes(panel)` inside a uifigure panel provides
one. Non-BoxGUI components are wrapped with `obj.register(...)` so the base
class tears them down (listeners included) when the figure closes.

## The hooks

All hooks are optional overrides with no-op defaults, and every invocation is
wrapped in try/catch by the base class, so a plotting bug never kills a
session. What the example does with each:

| Hook | Fires | Used here to |
|---|---|---|
| `onNewTrial(obj, src, event)` | After each trial is dispatched | Announce the upcoming trial: `event.Data` is the TRIALS struct, so `event.Data.trials{event.Data.NextTrialID, event.Data.writeParamIdx.ToneLevel}` reads the level just sent to the hardware |
| `onNewData(obj, src, event)` | After each completed trial is analyzed | Refresh the per-level performance table and the session tally from `obj.Psych` |
| `onModeChange(obj, src, event)` | Run / Preview / Pause / Stop | Show `event.NewMode` (an `hw.DeviceState`) in the header |
| `onFirstTrial(obj, src, event)` | Once, at the first NewTrial after `build` | Session-start bookkeeping |

The per-level table in `onNewData` is a compact template for any summary
readout driven by `psychophysics.Detection`:

```matlab
P = obj.Psych;
P.targetTrialType = epsych.BitMask.TrialType_0;   % analyze go trials
uv = P.uniqueValues;                              % levels seen so far
S = [compose("%g", uv(:)), ...
     compose("%d", [P.Count.TrialType_0].'), ...
     compose("%.0f", 100 * P.Hit_Rate(:)), ...
     compose("%.2f", P.DPrime(:))];
obj.SummaryTable.Data = flipud(S);
```

## Launching it

**Without hardware** — the point of the worked example:

```matlab
run_detection_session          % builds a software runtime and drives the GUI
```

**In a real session** — the GUI belongs to the project, not to the protocol and
not to the rig. In [RunExpt](../overviews/RunExpt_GUI_Overview.md), open
**Subjects > Subjects & Projects**, then **Project > Edit Project...**, and set
**Box GUI** to `DetectionBoxGUI`; it lands on the session when that project's
subjects are added. At session start RunExpt calls
`feval('DetectionBoxGUI', RUNTIME)` — which is why the constructor takes
exactly one argument — and the runtime's timer drives the same three events the
simulation does. The class must be on the MATLAB path.

Validation: `tmp/smoke_test_detection_example.m` (headless;
`matlab -batch "run('tmp/smoke_test_detection_example.m')"`).

Next: [Detection_Task_4_Running.md](Detection_Task_4_Running.md)
