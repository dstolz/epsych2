# Teensy Trial-Program Protocol

How a trial contingency designed in `teensy.TrialDesigner` is carried to an EPsychTeensy board
and executed there.

This document is the **contract for the firmware**. The MATLAB side (`teensy.Compiler`,
`hw.Teensy.sendProgramBlock`, `hw.Teensy.readProgramBlock`) is implemented; the firmware side
lives in `firmware/EPsychTeensy/` and must match what is written here exactly.

- Reference implementation of the execution semantics: `obj/+teensy/@Simulator/`
- Format emitter and parser: `obj/+teensy/@Compiler/`
- Model being compiled: `obj/+teensy/@Program/`

---

## Why upload a program at all

The base EPsychTeensy design configures a *fixed* trial phase sequence through registry
parameters — `PreWindowDur`, `CueDur`, `RespWinDur`, and so on. That covers a go/no-go detection
task and little else. Every new paradigm otherwise means new firmware.

Uploading a state table instead moves the paradigm from firmware into data. The board keeps
owning the millisecond-scale work — debounce, pulse timing, threshold detection, response
latency — while *what counts as a response* becomes something a researcher edits in a GUI and
saves in a file. A `.etsm` program is portable across rigs and versionable alongside the
protocol.

The cost is a small interpreter on the board: a state table, a fixed-depth expression evaluator,
and a per-tick scheduler. All three are bounded and allocation-free, which is what keeps the
timing guarantees intact.

---

## Transport and framing

Program upload rides the same ASCII, LF-terminated, one-reply-per-command line protocol as the
rest of the interface. It does **not** introduce a binary mode or an unsolicited-output mode,
because both would break the synchronous transaction model the 10 ms runtime tick depends on.

```
host                                board
----                                -----
PROG BEGIN                    ->
                              <-    OK
V 1 7 6 5 2 1                 ->
                              <-    OK
C 0 Poke IN DIG 2 1 5 0 0 0   ->
                              <-    OK
... one record per line ...
PROG END                      ->
                              <-    OK 7
```

**Every record is acknowledged individually.** A block-level ack would be cheaper, but a
per-record ack keeps the one-reply-per-command invariant true and — more usefully — tells the
host exactly which record was rejected. At USB CDC's ~1 ms frame rate a 200-record program
uploads in about a fifth of a second, which is irrelevant for a design-time operation.

- Any record may be rejected with `ERR <code> <text>`. The host abandons the upload on the first
  error and reports the offending record. The board must then discard the partial table and keep
  running whatever program it already had — a half-loaded state machine is worse than a stale one.
- The final `PROG END` ack carries the accepted state count: `OK <nStates>`.
- Records are at most 240 characters, matching `hw.Teensy.MAX_LINE_LENGTH` and the firmware's
  `LINE_BUFFER_LEN`.
- Names match `[A-Za-z_][A-Za-z0-9_]{0,22}` — 23 characters, no spaces. The compiler rejects
  anything else rather than mangling it.

### Commands

| Command | Reply | Purpose |
|---|---|---|
| `PROG BEGIN` | `OK` | Start a program upload; clears the staging table |
| *(record lines)* | `OK` | One acknowledged record each |
| `PROG END` | `OK <nStates>` | Commit the staged table |
| `PROG?` | `PROG BEGIN` … `PROG END` | Read back the running program, as text |
| `PROGCLR` | `OK` | Discard the program; revert to the fixed-phase FSM |
| `STATE?` | `STATE <idx> <name> <elapsedUs>` | Current state, for the live monitor |

`SNAP` gains a `ST=<idx>` field so the designer's live monitor costs no extra round trip during
a session. The MATLAB side of `PROG?` is `hw.Teensy.readProgramBlock`, which returns the record
text for display and diffing; there is no parser that turns a readback into a `teensy.Program`.

---

## Record types

Indices on the wire are **1-based**, matching the positions in `teensy.Program.Channels`,
`.Variables`, `.GlobalTimers`, `.Counters` and `.States`. An index of `0` means "unresolved",
which the compiler treats as an error rather than emitting. Firmware arrays are therefore
indexed as `array[i - 1]`.

Names appear once, in their defining record, and everything downstream refers to them by index —
that keeps records short and parsing allocation-free.

Numeric fields accept either a literal (`1500`, `2.5`) or a variable reference `#<varIdx>`. A
variable reference is what lets `epsych.ProtocolDesigner` vary a duration or threshold per trial
without recompiling and re-uploading the state table.

### `V` — header

```
V <formatVersion> <nStates> <nChannels> <nVariables> <nTimers> <nCounters>
```
Always the first record. The board sizes its staging arrays from it and rejects the upload
immediately if any count exceeds its compiled-in limit.

### `C` — channel

```
C <idx> <name> <dir> <kind> <pin> <flags> <p1> <p2> <p3> <p4>
```
- `<dir>`: `IN` | `OUT`
- `<kind>`: `DIG` | `ANA`
- `<flags>`: bit 0 active-high, bit 1 pull-up, bit 2 pull-down, bit 3 idle-high
- Digital in: `p1` = debounce ms, `p2..p4` unused (`0`)
- Analog in: `p1` = threshold high, `p2` = threshold low, `p3` = scale, `p4` = offset
- Digital out: `p1` = idle state, rest unused
- Analog out: `p1` = mode (`0` PWM, `1` MQS, `2` SPI DAC), `p2` = PWM frequency,
  `p3` = resolution bits

Analog thresholds are given in engineering units; the board converts with `scale`/`offset`, so
recalibrating a sensor is a channel edit rather than a firmware change.

### `K` — variable (constant slot)

```
K <idx> <name> <type> <value> <min> <max>
```
`<type>`: `F` float, `I` integer, `B` boolean. `value` is the default; the host overwrites it at
runtime with an ordinary `SET`/`SETM` on the parameter of the same name, which is what makes
per-trial variation work.

### `G` — global timer

```
G <idx> <name> <durationRef>
```

### `N` — counter

```
N <idx> <name> <channelIdx> <edge>
```
`<edge>`: `0` rising, `1` falling, `2` either. The counter increments in the sampling ISR, not in
`loop()`, so a fast lick train is counted exactly.

### `S` — state

```
S <idx> <name> <durationRef> <flags> <respBits>
```
- `<flags>`: bit 0 terminal, bit 1 is-start
- `<respBits>`: uint32 mask OR-ed into the trial's response code on entry
- `<durationRef>` of `0` means no state timer.

### `A` — action

```
A <stateIdx> <when> <kind> <a1> <a2> <a3> <a4> <a5>
```
- `<when>`: `0` on entry, `1` on exit, `2` on a transition (then `a5` is the transition order)
- `<kind>` is the 0-based index into `teensy.Action.Kinds`, in that declared order:
  `SetOutput` 0, `Pulse` 1, `PulseTrain` 2, `AnalogOut` 3, `StartTimer` 4, `CancelTimer` 5,
  `ResetCounter` 6, `IncrementCounter` 7, `AddRespCode` 8, `MarkLatency` 9, `LogEvent` 10,
  `SetVariable` 11, `Sync` 12, `EndTrial` 13.
- Because `a5` carries the transition order, an action gets **four** operands of its own.
  `teensy.Action.toArgs` documents the layout per kind. One consequence: `PulseTrain` cannot
  also carry a start delay; use a delayed `Pulse`, or a preceding state, when a train needs to
  start late.
- Unused operands are `0`; an operand holding a variable is written `#<varIdx>`.

### `T` — transition

```
T <stateIdx> <order> <targetIdx> <nTokens> <tok1> <tok2> ...
```
Transitions are evaluated in `<order>` and **the first match wins**. A `<targetIdx>` of `-1`
means "stay in this state without resetting its timer", which is how an action-only transition
is expressed.

---

## Condition expressions

A transition condition is a postfix token sequence evaluated on a fixed stack of depth 8. Leaves
push a boolean; `&`, `|`, and `!` pop and push. No allocation, no recursion, bounded time —
which is what makes it safe to evaluate inside the sampling ISR.

A leaf token is written `L<kind>,<a1>,<a2>,<a3>,<a4>` — **four** operands, not three, because an
analog threshold needs all of channel, comparison, threshold and hold time. `<kind>` is the
0-based index into `teensy.Condition.LeafKinds`: `Always` 0, `Never` 1, `StateTimer` 2,
`GlobalTimer` 3, `DigitalEdge` 4, `DigitalLevel` 5, `AnalogThreshold` 6, `Counter` 7,
`Probability` 8. Per-kind operand layouts are documented on `teensy.Condition.toPostfix`.

`And` and `Or` fold left in pairs, so a flat chain of N operands evaluates at stack depth 2
rather than depth N. The evaluator is a single `switch`, so adding a condition kind is one case
in the firmware and one entry in `teensy.Condition`.

`teensy.Condition.toPostfix` emits the sequence and returns the maximum stack depth alongside it;
`teensy.Compiler` refuses to emit anything that would exceed the depth or the per-transition
token cap, so the firmware can trust its bounds without checking at runtime.

---

## Response codes

`RespCode` is a uint32 bitmask using `epsych.BitMask`, whose values are **1-based bit indices**.
Firmware sets a bit with

```c
mask |= (1UL << (bit - 1));
```

`Hit` is bit 1 and therefore sets `0x1`. Getting this off by one silently corrupts every response
code in a session while leaving everything looking plausible, so it is worth a firmware unit test
of its own. The full mapping is in `obj/+epsych/@BitMask/BitMask.m`; `firmware/EPsychTeensy/BitMask.h`
must mirror it.

`RespLatency` is milliseconds from trial start, recorded by a `MarkLatency` action. Placing that
action explicitly — rather than inferring latency from whichever input happened to fire — is what
lets a paradigm define what it considers "the response" when several inputs are live.

---

## Execution semantics the firmware must reproduce

`obj/+teensy/@Simulator/` is the normative reference. The decisions that matter:

1. Per tick, in order: advance the clock; sample and debounce inputs; update edge, level, and
   threshold detectors and counters; advance global timers and pulse generators; evaluate the
   current state's transitions in order.
2. First matching transition wins. When a state timer expires on the same tick as an input edge,
   whichever transition is listed first is taken.
3. On a transition: exit actions, then transition actions, then the target's entry actions.
4. Entering a state resets its state timer. A self-transition resets it; a `-1` target does not.
5. Digital debounce accepts a change only after the raw level has been stable for the channel's
   debounce time. Analog detection is hysteretic: high at `ThresholdHigh`, low at `ThresholdLow`,
   with an optional hold time.
6. Entering a terminal state latches `RespCode` and `RespLatency` and raises `TrialComplete`.
7. `x_ResetTrig_<BoxID>` aborts any running trial, clears `TrialComplete`, clears latches, and
   clears the event log — including mid-trial, which is what the operator's `FORCE_TRIAL` escape
   hatch relies on.

---

## Failure behavior

Never leave the board in a partially configured state:

- A rejected record aborts the upload and leaves the previously committed program running.
- `PROGCLR` reverts to the fixed-phase FSM, so a board can always be returned to a known-good
  configuration without reflashing.
- An uploaded program that references an out-of-range index must be rejected at `PROG END`, not
  discovered at run time.

---

## See also

- [hw.Teensy](hw_Teensy.md) — the MATLAB backend
- [hw.Interface](hw_Interface.md) — the abstract backend contract
- [teensy.TrialDesigner](../gui/teensy_TrialDesigner.md) — the GUI that produces these programs
- [epsych.BitMask](../epsych/epsych_BitMask.md) — response-code encoding
