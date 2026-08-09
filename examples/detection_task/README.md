# Worked Example: Simulated Go/No-Go Tone Detection

A complete EPsych experiment that runs entirely in software — protocol design,
a custom trial selector, a behavior-box GUI, a simulated session, and offline
analysis of the saved data. Each file is the example for one stage of the
[walkthrough series](../../documentation/examples/Detection_Task_Walkthrough.md).

## Quick start

```matlab
addpath('examples/detection_task')

create_detection_protocol      % writes DetectionExample.eprot
run_detection_session          % simulated session driving DetectionBoxGUI
explore_saved_data             % decode + plot the session just saved
```

## Files

| File | Purpose | Walkthrough |
|---|---|---|
| `create_detection_protocol.m` | Builds and saves the `.eprot` in code: paired conditions, randomized ITI, an expression parameter, read-backs, triggers | [1 — Protocol](../../documentation/examples/Detection_Task_1_Protocol.md) |
| `ExampleDetectionSelector.m` | `epsych.TrialSelector` subclass: catch-trial probability, run cap, balanced levels | [2 — Trial selector](../../documentation/examples/Detection_Task_2_TrialSelector.md) |
| `DetectionBoxGUI.m` | `gui.BoxGUI` subclass wired to `psychophysics.Detection` and `gui.PsychPlot`, using every event hook | [3 — Box GUI](../../documentation/examples/Detection_Task_3_BoxGUI.md) |
| `run_detection_session.m` | Hardware-free session: mirrors the real runtime loop with a simulated observer; saves a session file | [4 — Running](../../documentation/examples/Detection_Task_4_Running.md) |
| `explore_saved_data.m` | Loads the saved file, decodes `RespCode` via `epsych.BitMask`, reports hit rate / FA / d', plots the session | [5 — Data](../../documentation/examples/Detection_Task_5_Data.md) |

Generated at runtime (not checked in): `DetectionExample.eprot`, `data/*.mat`.

## Related

- [examples/customgui/](../customgui/) — minimal `gui.BoxGUI` starter template
- [documentation/gui/gui_BoxGUI.md](../../documentation/gui/gui_BoxGUI.md)
- [documentation/epsych/epsych_TrialSelector.md](../../documentation/epsych/epsych_TrialSelector.md)
- Validation: `tmp/smoke_test_detection_example.m` (headless;
  `matlab -batch "run('tmp/smoke_test_detection_example.m')"`)
