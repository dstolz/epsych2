# Detection Task 4 — Running a Session

Part of the [detection task worked example](Detection_Task_Walkthrough.md).
Example file: [run_detection_session.m](../../examples/detection_task/run_detection_session.m).

There are two ways to run the example task: the real path through the
[RunExpt GUI](../overviews/RunExpt_GUI_Overview.md), and the simulation driver,
which replays the same runtime machinery in a plain loop so you can watch — and
step through — everything a session does.

## Path A: the RunExpt GUI

This is how a real experiment runs, and the example protocol works here too
(it just produces no sound — the software interface accepts every parameter
write silently).

1. `addpath('examples/detection_task')` — the selector and GUI classes must be
   resolvable by name.
2. Launch `epsych.RunExpt`.
3. **Customize > Customize...**, tab **Functions**: set **Box GUI Function:** to
   `DetectionBoxGUI`. Leave **Saving Function:** at `ep_SaveDataFcn` (prompts
   for a filename at session end) or point it at your lab's function — it must
   take exactly one input (`RUNTIME`) and return nothing.
4. **Add Subject**, fill in the dialog, and when prompted locate
   `DetectionExample.eprot`.
5. **View Trials** previews the compiled condition list before anything runs.
6. **Preview** runs the session without marking it as real data
   (`RUNTIME.isTest = true`); **Run** records. Watch the state line walk
   NOCONFIG → READY → RUNNING → STOP as described in the
   [RunExpt overview](../overviews/RunExpt_GUI_Overview.md).

During the run, the timer fires `ep_TimerFcn_RunTime` continuously; data
accumulate per completed trial. Two files result:

- A **crash-recovery file** (`RUNTIME_DATA_<subject>_Box_XX_<timestamp>.mat` in
  `RUNTIME.TempDataDir`) appended one variable per trial while the session runs.
- The **session file** written by the saving function at stop — this is what
  [Detection_Task_5_Data.md](Detection_Task_5_Data.md) analyzes.

## Path B: the simulation driver

`run_detection_session` reproduces the trial loop of `ep_TimerFcn_RunTime`
without the timer, the GUI dialogs, or hardware. The mapping is one-to-one:

| Real session | Driver |
|---|---|
| `ExptDispatch` connects interfaces, creates `HELPER` | `RUNTIME.Interfaces = P.Interfaces`, `RUNTIME.HELPER = epsych.Helper` |
| `ep_TimerFcn_Start` builds TRIALS, creates the selector, dispatches trial 1 | Hand-built TRIALS struct; `RUNTIME.TRIALS = T` (the setter resolves the core triggers and dispatches trial 1) |
| RunExpt launches `FUNCS.BoxFig`, broadcasts the session mode | `DetectionBoxGUI(RUNTIME)`, then a `ModeChange(Record)` notify |
| Rig sets `RespCode` when the animal responds | A simulated observer answers from a psychometric function |
| `ep_TimerFcn_RunTime` per completed trial: collect Read parameters into a DATA record, `selector.onComplete`, broadcast `NewData`, `selector.selectNext`, `dispatchNextTrial` | The same five calls, verbatim, once per loop iteration |
| Saving function at stop | `save(dataFile, 'Data', 'Info')` in the layout of `cl_SaveDataFcn` |

Because the event traffic is identical, everything downstream — the box GUI,
`psychophysics.Detection`, the trial selector — cannot tell it is not a real
session. That makes the driver a workbench: set a breakpoint in
`ExampleDetectionSelector.selectNext` or `DetectionBoxGUI.onNewData` and run it
to see the machinery move.

### The simulated observer

Go-trial responses come from a cumulative-Gaussian psychometric function
(`Threshold` 35 dB SPL, `Slope` 8 dB), catch trials from a flat `GuessRate`;
outcomes are packed into `RespCode` with `bitset`:

```matlab
bits = [epsych.BitMask.Hit, epsych.BitMask.Reward, epsych.BitMask.TrialType_0];
rc = uint32(0);
for b = bits, rc = bitset(rc, uint32(b)); end
```

Real rigs compute the same kind of code in hardware (RPvds) or in a trial
program; the encoding contract is the point, not where it runs.

### One simulation-only trick

The driver writes `RespCode`/`InTrial` by temporarily widening `Access`,
because `hw.Parameter` blocks writes to `Access='Read'` parameters. On real
hardware these values come from the device, so nothing like this appears in
production code — it exists solely because the software backend stores values
in the parameter object itself.

### Useful options

```matlab
run_detection_session(TrialPause = 0.1)   % slow down to watch the GUI
run_detection_session(Seed = 1)           % reproducible session
run_detection_session(NumTrials = 300, Threshold = 45)  % different observer
```

The function returns the `epsych.Runtime`, so the full session state is
inspectable afterward: `rt.TRIALS.DATA`, `rt.TRIALS.selector`, `rt.P`, and the
saved-file path printed at the end.

Validation: `tmp/smoke_test_detection_example.m` (headless;
`matlab -batch "run('tmp/smoke_test_detection_example.m')"`).

Next: [Detection_Task_5_Data.md](Detection_Task_5_Data.md)
