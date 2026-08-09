# `teensy` package — developer reference

The data model, compiler and simulator behind [teensy.TrialDesigner](teensy_TrialDesigner_UserGuide.md).

`obj/+teensy/` has no dependency on the GUI: a program can be built, validated, compiled and
simulated entirely from the command line, which is what makes the whole feature testable
headlessly (`tmp/smoke_test_teensy_designer.m`).

---

## Classes

| Class | Kind | Role |
|---|---|---|
| `teensy.Program` | handle | The document: channels, variables, states, timers, counters |
| `teensy.Channel` | value | One logical I/O binding and its electrical settings |
| `teensy.Variable` | value | A named quantity that becomes an `hw.Parameter` |
| `teensy.State` | value | One phase of a trial |
| `teensy.Transition` | value | Condition + target + transition actions |
| `teensy.Condition` | value | A leaf test, or an And/Or/Not node over other conditions |
| `teensy.Action` | value | Something that happens: output, timer, counter, response code |
| `teensy.BoardProfile` | value | Pin capabilities of a Teensy 4.0 or 4.1 |
| `teensy.Compiler` | handle | Program → wire records, with capacity checks |
| `teensy.Simulator` | handle | Reference implementation of the firmware semantics |
| `teensy.Templates` | static | Ready-made paradigms |

Everything except `Program`, `Compiler`, `Simulator` and the GUI is a **value class**. That is
the design decision the rest follows from: value semantics make `toStruct`/`fromStruct` an exact
round trip, which makes the undo stack exact, and make a program snapshot cheap to take.

Package functions: `teensy.issue`, `teensy.isVarRef`, `teensy.varRef`, `teensy.getFieldOr`.

---

## Literals and variable references

Any numeric field in a `State`, `Action` or `Condition` may hold either a literal `double` or a
string `"@Name"` referring to a `teensy.Variable`. One pair of functions decides which:

```matlab
[tf, name] = teensy.isVarRef(value);   % "@HoldTime" -> true, "HoldTime"
ref = teensy.varRef("HoldTime");       % -> "@HoldTime"
value = program.resolve(ref);          % -> the variable's current value, or NaN
```

`resolve` returns `NaN` and logs rather than throwing, so a half-built program still renders and
simulates.

This is the mechanism that lets a protocol vary a duration or a threshold per trial: the
reference compiles to `#<varIdx>`, and the host writes the variable by name with an ordinary
`SET` between trials.

---

## Building a program

```matlab
p = teensy.Program(Name = "Detect", BoxID = 1);
p.Channels = teensy.Channel.defaultSet();

p.addVariable(teensy.Variable("RespWinDur", Value = 2000, Min = 100, Max = 9000, Units = "ms"));

p.addState(teensy.State("ITI", DurationMs = 3000));
p.addState(teensy.State("Wait", DurationMs = "@RespWinDur"));
p.addState(teensy.State("Hit", IsTerminal = true, ...
    RespCodeBits = [epsych.BitMask.Hit, epsych.BitMask.Reward]));
p.StartState = "ITI";

p.States(1).Transitions(end+1) = teensy.Transition.to("Wait", teensy.Condition.timerElapsed());
p.States(2).Transitions(end+1) = teensy.Transition.to("Hit", ...
    teensy.Condition.digitalEdge("Poke", "Rising"));
p.States(3).EntryActions(end+1) = teensy.Action.markLatency();
p.States(3).EntryActions(end+1) = teensy.Action.pulse("Reward", 40);

p.autoLayout();
```

### Renames cascade

`renameState`, `renameChannel` and `renameVariable` rewrite every reference to the old name —
transition targets, condition channels, action channels, counter sources, and `@Name`
references inside every numeric field, including operands nested inside And/Or/Not trees.

One private traversal (`Program.applyRename_`) knows where names can hide. Splitting that
knowledge across the mutators is how a cascading rename quietly misses a nested operand.

---

## Validation

`program.validate()` returns a struct array of issues, each with `Severity`
(`"error" | "warning" | "info"`), `Category`, `Message`, `Where` and `Remedy`. Build them with
`teensy.issue`, and call `teensy.issue()` with no arguments for the correctly-shaped empty array
to grow.

Program-level checks — duplicate names, pin conflicts, reachability, terminal reachability,
counter and timer wiring — live in `@Program/validate.m`. Everything that can be judged about
one object on its own lives on that object's own `validate`, so the inspector panels can
validate a single item as it is edited.

Test a report with `teensy.Compiler.hasError(report)` rather than indexing `[report.Severity]`
directly: on an empty report that expression is a `double []`, and comparing it to a string
throws.

`Where` is written as `State 'Cue' transition 2` or `Channel 'Poke'`, which is what lets the
Compile tab's **Go To Issue** route back to the offending object.

---

## Compiling

```matlab
c = teensy.Compiler();
result = c.compile(program);
```

`result` carries `Ok`, `Lines` (the framed record stream), `Text`, `Report` and `Stats`.
Compilation always returns a report, including when it refuses to emit — "what is wrong with it"
is more useful than "it failed".

`teensy.Compiler.LIMITS` mirrors the fixed array sizes in `firmware/EPsychTeensy/Config.h`.
Changing one means changing both. `MAX_LINE_CHARS` must equal `hw.Teensy.MAX_LINE_LENGTH`.

The emitted format is documented in [the wire protocol reference](../hw/hw_Teensy_Program_Protocol.md).
`hw.Teensy.sendProgramBlock` sends it; `hw.Teensy.readProgramBlock` reads it back as text.

---

## Simulating

`teensy.Simulator` is the normative reference for the firmware's execution semantics. Its class
help enumerates the decisions — tick ordering, first-match-wins, timer reset on entry, debounce,
hysteresis, terminal latching. When the firmware and this file disagree, this file is right.

```matlab
sim = teensy.Simulator(program, TimeStepMs = 0.5, Seed = 42);
T = sim.runTrial([800 1 1; 900 1 0]);        % [timeMs, inputIndex, value]
decoded = epsych.BitMask.decode(sim.RespCode);
```

`runTrial` also accepts a struct array, or a function handle for closed-loop responding.
`teensy.Simulator.Responder` builds stochastic subjects; `teensy.Simulator.monteCarlo` runs many
trials and returns a decoded table plus summary rates including d′.

Probability branches draw from a `RandStream` seeded by the `Seed` property, never from `rand`,
so a run replays identically.

---

## Mapping onto EPsych

`program.parameterSpecs()` describes the `hw.Parameter` set without needing a live `hw.Module`,
which is what makes it previewable in the GUI and testable headlessly.
`program.applyToModule(module)` turns those specs into real parameters, skipping names the module
already has so applying twice is idempotent.

Every channel — input *and* output — is emitted as a readable parameter, so the per-trial DATA
record carries what each sensor and each output was doing. That is also what makes phase flags
work: a digital output held high for the duration of a state shows up as a readable parameter of
that name, which `gui.Parameter_Monitor` renders as a lamp. The `AppetitiveDetection` template
uses this for `DelayPeriod` and `RespWindow`.

Three details that will silently break a session if changed:

- Triggers use `Access='Any'`, never `'Write'`. `hw.Interface.all_parameters` excludes `'Write'`
  from a `'Read'` filter, so `epsych.Runtime.resolveCoreParameters` would not find a `'Write'`
  trigger and the run would abort with `epsych:RunExpt:MissingTrigger`.
- `UpdateEveryTrial` is assigned **after** `add_parameter` returns, because `add_parameter` has
  no such option and setting `isTrigger` rewrites the flag.
- `_TrigState~<BoxID>` and `_TrialNum~<BoxID>` use a `~<BoxID>` suffix, not the `x_*_<BoxID>`
  form the triggers use. `gui.OnlinePlot` looks up both literally; the inconsistency is
  historical and must be preserved.

Response codes are `epsych.BitMask` values, which are **1-based bit indices**. A mask sets bit
`b` as `bitshift(uint32(1), b - 1)`, so `Hit` (1) sets `0x1`. `State.respMask()` does this; the
firmware's `BitMask.h` must match.

---

## Adding a condition or action kind

1. Add the name to `teensy.Condition.LeafKinds` or `teensy.Action.Kinds`. The wire opcode is the
   0-based position in that array, so **append rather than insert** — inserting renumbers every
   opcode after it and silently invalidates programs already on a board.
2. Add its fields to the class, and to `describe`, `validate`, `toStruct`/`fromStruct`, and
   `toPostfix` or `toArgs`.
3. Add a case to `teensy.Simulator.evaluate_` or `runAction_`.
4. Add a row to `localFieldsFor_` in the designer's `editCondition_.m` or `editAction_.m`, and a
   label in `localKindItems_` for a condition.
5. Add the matching case to the firmware evaluator.

---

## See also

- [User guide](teensy_TrialDesigner_UserGuide.md)
- [Wire protocol](../hw/hw_Teensy_Program_Protocol.md)
- [hw.Parameter](../hw/hw_Parameter.md), [hw.Module](../hw/hw_Module.md)
- [epsych.Runtime](../epsych/epsych_Runtime.md), [Trial lifecycle](../epsych/epsych_TrialLifecycle.md)
