# Detection Task 1 — Designing a Protocol in Code

Part of the [detection task worked example](Detection_Task_Walkthrough.md).
Example file: [create_detection_protocol.m](../../examples/detection_task/create_detection_protocol.m).

The [Protocol Designer](../design/ProtocolDesigner_UserGuide.md) builds the same
thing interactively; building a protocol in code instead makes the design
reproducible, diffable, and scriptable. Everything the designer does reduces to
calls on [epsych.Protocol](../epsych/epsych_Protocol.md) and its interfaces'
`add_parameter`, so this walkthrough is also a tour of the protocol data model.

## Start: a Protocol is born with a software interface

```matlab
P = epsych.Protocol(Info = 'Worked example: simulated Go/No-Go tone detection');
sw = P.SoftwareModule;
```

A new `epsych.Protocol` already owns a connected `hw.Software` interface
(`P.SoftwareModule`); for a simulated task no other interface is needed. A real
task would add hardware with `P.addInterface(hw.TDT_Synapse(...))` and put the
stimulus parameters there instead.

## Parameters define the trial structure

`add_parameter(name, value, ...)` stores the value list in the parameter's
**`Values`** property — the design-time levels the protocol steps through. The
live **`Value`** is assigned later, per trial, by the runtime dispatcher. This
distinction matters any time you read `p.Value` outside a running session.

Three parameter roles appear in the example:

**Condition parameters** carry a multi-element value list. At compile time,
unpaired lists are fully crossed; lists that share a `UserData.Pair` group
advance together instead. Here `TrialType` and `ToneLevel` are paired, so six
values each define **6 conditions** (5 go levels + 1 silent catch), not 36:

```matlab
sw.add_parameter('TrialType', [0 0 0 0 0 1], Type = 'Integer', ...
    UserData = struct('Pair', 'StimCondition'));
sw.add_parameter('ToneLevel', [20 30 40 50 60 0], Unit = 'dB SPL', ...
    UserData = struct('Pair', 'StimCondition'));
```

Paired lists must be the same length; `validate()` flags a mismatch as an error.

**Control parameters** have a single value: dispatched every trial, editable
live from the box GUI, but they do not expand the condition list (`ToneFreq`,
`ToneDur`, `RewardVol`). Two variations show per-trial dynamics:

```matlab
p = sw.add_parameter('ITI', 3000, Unit = 'ms');
p.Min = 2000; p.Max = 4000;
p.isRandom = true;              % redrawn uniformly in [Min, Max] every dispatch

p = sw.add_parameter('RespWinDelay', 0, Unit = 'ms');
p.Expression = "ToneDur + 250"; % re-evaluated every dispatch, after ToneDur
```

Expressions reference sibling parameters by name and are dispatched in
dependency order — see [hw.Parameter](../hw/hw_Parameter.md).

**Read-back parameters** use `Access = 'Read'`. They are excluded from compile
and dispatch; instead the runtime collects their `Value` into a DATA record at
every trial end. `RespCode` is the conventional name the analysis tools look
for (an `epsych.BitMask`-encoded outcome). One gotcha: `set.Value` refuses
writes once `Access = 'Read'`, so seed the starting value first:

```matlab
p = sw.add_parameter('RespCode', 0, Type = 'Integer');
p.Value = 0;
p.Access = 'Read';
```

## Triggers

Every protocol must define the three core triggers for each box —
`x_NewTrial_<BoxID>`, `x_ResetTrig_<BoxID>`, `x_TrialComplete_<BoxID>` — or the
runtime refuses to start (`epsych.Runtime.resolveTriggerParameters`). On TDT
hardware these are RPvds tags discovered from the circuit; on a software rig
they are declared directly:

```matlab
sw.add_parameter('x_NewTrial_1',      0, isTrigger = true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger = true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger = true);
```

`isTrigger = true` also sets `UpdateEveryTrial = false`, so triggers are left
out of the per-trial parameter writes. The extra `Reward` trigger exists only
to give the box GUI a manual-reward button.

## Trial selection policy

```matlab
P.setOption('trialFunc', 'ExampleDetectionSelector');
```

`Options.trialFunc` names an [epsych.TrialSelector](../epsych/epsych_TrialSelector.md)
**class** (not a function); empty means `epsych.DefaultTrialSelector`. The class
must be on the MATLAB path both when the protocol validates and when the session
runs — the example script calls `addpath` on its own folder for that reason.
[Detection_Task_2_TrialSelector.md](Detection_Task_2_TrialSelector.md) walks
through the selector itself.

## Validate, compile, save

```matlab
issues = P.validate();          % struct array; severity 2 entries block compile
P.compile();                    % prints errors and returns quietly on failure
assert(P.COMPILED.ntrials > 0)  % so check the result yourself
P.save('DetectionExample.eprot')
```

`compile()` does **not** throw on validation errors — it prints them and leaves
`COMPILED.ntrials` at 0, which is why the example asserts afterward. The saved
`.eprot` is a MAT file holding the protocol as a plain struct;
`epsych.Protocol.load` reconstructs the object, interfaces, and parameters.

To inspect the result interactively, open it in the designer:

```matlab
epsych.ProtocolDesigner
```

and load `DetectionExample.eprot` — the paired condition list, the expression,
and the compiled trial table are all visible there.

Validation: `tmp/smoke_test_detection_example.m` (headless;
`matlab -batch "run('tmp/smoke_test_detection_example.m')"`).

Next: [Detection_Task_2_TrialSelector.md](Detection_Task_2_TrialSelector.md)
