# Worked Example: A Complete Detection Task

A single, coherent example that threads through the whole EPsych workflow — from
designing a protocol in code to analyzing the saved data — using a simulated
Go/No-Go tone detection task that runs entirely in software. Every file lives in
[examples/detection_task/](../../examples/detection_task/) and every step works
without hardware, so you can run, break, and modify each piece freely before
adapting it to a real rig.

This guide is the index; each stage has its own walkthrough:

| Stage | Walkthrough | Example file |
|---|---|---|
| 1. Design a protocol in code | [Detection_Task_1_Protocol.md](Detection_Task_1_Protocol.md) | [create_detection_protocol.m](../../examples/detection_task/create_detection_protocol.m) |
| 2. Write a custom trial selector | [Detection_Task_2_TrialSelector.md](Detection_Task_2_TrialSelector.md) | [ExampleDetectionSelector.m](../../examples/detection_task/ExampleDetectionSelector.m) |
| 3. Build a behavior-box GUI | [Detection_Task_3_BoxGUI.md](Detection_Task_3_BoxGUI.md) | [DetectionBoxGUI.m](../../examples/detection_task/DetectionBoxGUI.m) |
| 4. Run a session | [Detection_Task_4_Running.md](Detection_Task_4_Running.md) | [run_detection_session.m](../../examples/detection_task/run_detection_session.m) |
| 5. Load and analyze the data | [Detection_Task_5_Data.md](Detection_Task_5_Data.md) | [explore_saved_data.m](../../examples/detection_task/explore_saved_data.m) |

## The task

On **go** trials a tone is presented at one of five levels (20–60 dB SPL); the
subject should respond. On silent **catch** trials the subject should withhold.
Outcomes are encoded as [epsych.BitMask](../epsych/epsych_BitMask.md) response
codes (Hit / Miss / FalseAlarm / CorrectReject plus the trial type), which is
what the online analysis (`psychophysics.Detection`) and the offline analysis
both decode.

## Quick start

```matlab
addpath('examples/detection_task')

create_detection_protocol      % writes DetectionExample.eprot
run_detection_session          % simulated session; watch DetectionBoxGUI fill in
explore_saved_data             % decode + plot the session that was just saved
```

`run_detection_session(TrialPause=0.1)` slows the loop enough to watch the GUI
update trial by trial.

## How the pieces fit

```
create_detection_protocol.m ──▶ DetectionExample.eprot
                                      │  epsych.Protocol.load + compile
                                      ▼
run_detection_session.m  ──▶ epsych.Runtime ──▶ dispatch / NewTrial / NewData
        │                         │                        │
        │ simulated observer      │ ExampleDetectionSelector picks each trial
        │ sets RespCode           ▼                        ▼
        │                  DetectionBoxGUI          psychophysics.Detection
        ▼
ExampleSubject_<timestamp>.mat ──▶ explore_saved_data.m
```

In a real experiment, stages 1–3 are unchanged (pointed at real hardware
interfaces instead of `hw.Software`), and stage 4 is performed by the
[RunExpt GUI](../overviews/RunExpt_GUI_Overview.md) rather than the simulation
driver — [Detection_Task_4_Running.md](Detection_Task_4_Running.md) covers both
paths.

Validation: `tmp/smoke_test_detection_example.m` (headless;
`matlab -batch "run('tmp/smoke_test_detection_example.m')"`) exercises all five
stages.
