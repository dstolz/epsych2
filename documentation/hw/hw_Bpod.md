# `hw.Bpod`

`hw.Bpod` connects EPsych to a [Bpod](https://sanworks.io) 0.5/0.6 behavioral
state machine over USB serial, speaking the Arduino Due firmware's byte protocol
directly.

It is the backend to reach for when a paradigm's contingency is naturally a
finite state machine — poke, wait, respond, reward, ITI — and you want that
machine executing on-device at a 100 µs tick rather than at MATLAB timer
resolution. The board owns the trial; MATLAB builds the matrix, starts it, and
listens.

```matlab
iface = hw.Bpod('COM3');
iface = hw.Bpod('', AutoDetect=true, BoxID=1);          % probe ports for a board
iface = hw.Bpod('COM3', Connect=false);                  % offline, for ProtocolDesigner
iface = hw.Bpod('COM3', StateMatrixFcn='myTrialMatrix'); % run a state matrix per trial
```

> **Status: under development.** `hw.Bpod` is still being validated and its
> API may change without notice. In particular, the state-matrix encoder has
> not yet been verified against real hardware — see
> [Known gaps](#known-gaps) below before running it with an animal.

---

## What this backend deliberately does not do

The Bpod distribution at `c:\src\Bpod` ships a complete MATLAB layer. **None of
it is loaded, and it must never be put on the MATLAB path.** Specifically,
`hw.Bpod` never:

- **loads any file under `c:\src\Bpod`.** Every behavior it needs — the state
  matrix assembler, the encoder, the event decoder — is transcribed into
  `obj/+hw/@Bpod/`.
- **touches `global BpodSystem`.** Bpod's layer keeps hardware state, GUI
  handles, and input configuration in one global struct. A session with two
  interfaces, or a second MATLAB figure, would silently share it.
- **opens a figure.** `Bpod.m` shows a splash screen and an 800×400 console;
  `SendStateMatrix` ends by writing `BpodSystem.GUIHandles.CxnDisplay`.
- **calls `RunStateMatrix`.** It writes `'R'` and then spins in
  `while BpodSystem.InStateMatrix … drawnow`, blocking MATLAB for the length of
  the trial. See the next section for why that is fatal here and why it is also
  unnecessary.
- **uses `ManualOverride`.** Bpod's override is toggle-based, mutates
  `HardwareState` as a side effect, disables sibling GUI buttons, and reads
  three of its data bytes out of console edit boxes. `hw.Bpod` keeps its own
  absolute output shadow (`valves_`, `pwm_`, `bncOut_`, `wireOut_`) and always
  emits a complete mask.

What *is* preserved is the authoring API. `newStateMatrix`, `addState`,
`setGlobalTimer`, `setGlobalCounter` and `sendStateMatrix` are line-by-line
transcriptions with Bpod's positional-label syntax intact, so a paradigm ported
from Bpod usually needs nothing but a leading `iface.`:

```matlab
sma = iface.newStateMatrix();
sma = iface.addState(sma, ...
    'Name', 'WaitForPoke', ...
    'Timer', 5, ...
    'StateChangeConditions', {'Port1In', 'Reward', 'Tup', 'Miss'}, ...
    'OutputActions', {'LED', 1});
```

---

## The architectural crux: a push stream, not a blocking loop

EPsych drives everything from one non-blocking MATLAB timer that fires every
10 ms. Bpod's own MATLAB layer runs one **blocking** state matrix per trial.
Those two facts look irreconcilable, and reconciling them is most of what this
backend is.

They are reconcilable because **after `'R'` the device is a push stream.** The
firmware's 100 µs timer ISR emits framed messages `[1 nEvents ev…]`
*unsolicited*; nothing in the protocol asks the host to be present, let alone
blocked. `RunStateMatrix`'s `while` loop is a **consumer convention**, not a
hardware requirement.

So the loop is deleted and its body is kept. [`pump_.m`](../../obj/+hw/@Bpod/pump_.m)
is `RunStateMatrix`'s loop body — event decoding, state walking, 32-bit clock
rollover correction, timestamp scaling — made *resumable*: bytes accumulate in
`rxBuf_` and are consumed greedily from the front, one complete message at a
time. The instant a partial message is at the head, the parser returns and waits
for more. A message split at any byte boundary decodes identically to the same
bytes arriving at once.

The loop itself is replaced by the runtime's timer tick. `pump()` is called from
`get.mode` and from `get_parameter`, both of which `ep_TimerFcn_RunTime` touches
on every tick, so the trial advances without anything scheduling it.
[`pump.m`](../../obj/+hw/@Bpod/pump.m) is also public, so a custom `gui.BehaviorGUI`
or a hardware-free smoke test can drive the engine explicitly.

### What this costs, honestly

| | Cost |
|---|---|
| Trial onset | Roughly **one tick**. `trigger` writes `'R'` synchronously, so nothing is deferred — but `dispatchNextTrial` itself runs on a tick, so trial start is quantized to the tick that noticed the previous trial finishing. When the compiled matrix differs from the last one, the `'P'` upload and its one-byte acknowledgement are added: the **only** blocking read in the backend, bounded by `Timeout`. An unchanged matrix is memoized and trial start reduces to a single byte. |
| Trial end / ITI | The matrix-end sentinel is noticed on the next `pump()` call, and the 10-byte epilogue header plus `uint32 × nEvents` timestamps may need another tick or two to arrive and parse. Together with the onset quantization above, budget **~10–30 ms of added ITI**. |
| Within-trial timing | **Zero.** The contingency runs on the device at its 100 µs tick. Host latency never enters a response-to-reward path that lives inside the state matrix. |

What you get in exchange is a session that never freezes: the Stop button
responds mid-trial, `gui.OnlinePlot` and every other listener redraw while the
matrix runs, other interfaces (Intan, TDT, a video recorder) keep being polled,
and an error in one component does not strand a subject inside a blocked
`while` loop with a valve open.

### The `'I'` interlock

The firmware answers `'I' <'P'|'B'|'W'> <channel>` with a **bare, unframed
byte**, written from the same ISR that streams framed messages. An `'I'` issued
while a matrix is live therefore drops a naked byte into the middle of the event
stream, where the parser reads it as an opcode. The protocol has **no CRC, no
sequence number, and no resync marker**, so the entire trial from that point on
is unrecoverable.

[`readInput_.m`](../../obj/+hw/@Bpod/readInput_.m) is interlocked against this:
while `matrixRunning_` or `awaitingEpilogue_` it puts nothing on the wire and
serves the cached value. Outside a trial it still caches for `SnapshotInterval`
(default 5 ms, sized under one tick), so a per-tick sweep across 14 input
parameters does not become 14 USB round trips. It also refuses to read while
`rxBuf_` holds unparsed bytes, for the same reason.

`pump_` keeps a backstop: an opcode that is neither 1 nor 2 at the head of the
stream is reported at level 0 as a desynchronization, the buffer is discarded,
and the trial is closed with `Aborted = true` rather than allowed to produce
plausible-looking wrong data.

---

## Construction

| Option | Default | Meaning |
|---|---|---|
| `port` (positional) | `''` | Serial port, e.g. `'COM3'` or `'/dev/ttyACM0'`. Empty requires `AutoDetect`. |
| `Connect` | `true` | Connect on construction. `false` yields a fully usable offline object. |
| `AutoDetect` | `false` | Probe every available port with the `'6'` handshake and keep the one that answers byte 53. |
| `BoxID` | `1` | Subject box served. Names the `x_NewTrial_<N>` / `x_ResetTrig_<N>` / `x_TrialComplete_<N>` parameters. |
| `StateMatrixFcn` | `''` | Function **name** on the MATLAB path with signature `sma = f(iface, P)`. Blank runs the interface in immediate I/O mode. |
| `Timeout` | `1` | Transaction timeout in seconds. |
| `BootDelay` | `1.5` | Settle time after opening the port; the Due re-enumerates its native USB and swallows anything sent during it. |

There is deliberately **no baud rate option**. The main module's SerialUSB is
fixed at 115200, carried as the constant `hw.Bpod.BAUD_RATE`. Exposing it would
only let a rig be configured into a link that cannot handshake.

`AutoDetect` costs one `BootDelay` per candidate port, so it is slower than a
named port, but it survives the port number changing between sessions. Note that
`findBoardPort` sends `'Z'` after a successful probe, returning the board to its
disconnected state before the real connect re-handshakes.

### Connect sequence

`setup_interface` opens the port, waits out `BootDelay`, flushes, clears all
pump state, then handshakes: `'6'` must answer with byte 53 or it raises
`hw:Bpod:BadHandshake` and closes the port. It then reads the firmware build
with `'F'` (non-fatal — a missing reply leaves `FirmwareBuild = 0`), builds or
reuses the `Bpod` module, populates the parameter table by **merge**, and
finally calls `resetShadow_` + `writeOutputs_(Force=true)` so every output line
is provably low and the shadow provably matches the hardware.

The module is reused rather than rebuilt when one already exists, because
`Protocol.createInterfaceFromStruct_` and ProtocolDesigner's Modify both install
authored modules via `setModules` *before* connecting. Overwriting them would
throw away the operator's trial levels without raising anything.

---

## The state-matrix builder contract

When `StateMatrixFcn` names a function, `hw.Bpod` calls it once per trial:

```matlab
function sma = myTrialMatrix(iface, P)
% sma = myTrialMatrix(iface, P)
%   iface - the hw.Bpod instance (for newStateMatrix/addState/constants)
%   P     - struct of every parameter's Value, keyed by hw.Parameter.validName

sma = iface.newStateMatrix();

sma = iface.addState(sma, ...
    'Name', 'Stimulus', ...
    'Timer', P.TrialDuration, ...
    'StateChangeConditions', {'Port1In', 'Hit', 'Tup', 'Miss'}, ...
    'OutputActions', {'BNCState', 1});

sma = iface.addState(sma, ...
    'Name', 'Hit', 'Timer', 0.05, ...
    'StateChangeConditions', {'Tup', 'exit'}, ...
    'OutputActions', {'Valve', 1});

sma = iface.addState(sma, ...
    'Name', 'Miss', 'Timer', 0, ...
    'StateChangeConditions', {'Tup', 'exit'}, ...
    'OutputActions', {});
end
```

`P` comes from [`parameterStruct`](../../obj/+hw/@Bpod/parameterStruct.m) and
includes **invisible parameters and triggers** — the immediate-I/O lines are
invisible by design, and a builder needs them as much as it needs the visible
trial configuration. Two display names that sanitize to the same `validName`
collide, with the later one winning; that is logged at level 2.

The builder is invoked from the `x_NewTrial_<N>` trigger, which
`dispatchNextTrial` fires **after** the trial's parameter values are written, so
`P` holds this trial's values. Building at `x_ResetTrig_` instead would produce
a one-trial lag that silently corrupts staircases and go/no-go assignment.

**A failing builder is rethrown, not swallowed**, after logging the builder name
and the trial number. The timer's `ErrorFcn` then stops the session and
`close_interface` drives the outputs low — which is the correct outcome with an
animal in the box.

### Optional outcome annotations

`resolveResponse_` derives `RespCode` (an `epsych.BitMask` mask) and
`RespLatency` from, in priority order:

1. `sma.OutcomeMask` — a numeric mask per manifest state, if the builder sets it.
2. `sma.OutcomeTags` (or `sma.StateTags`) — an `epsych.BitMask` member name per
   manifest state.
3. **State names.** An exact case-insensitive match against any `epsych.BitMask`
   member wins; failing that, only `Hit`, `Miss`, `CorrectReject`, `FalseAlarm`,
   `Abort`, `Reward`, `Punish` are matched as substrings — so `DeliverReward`
   scores as `Reward` while `Choice_1_Delay` cannot be misread as a trial-type
   flag.

With none of the three, the mask is `0` (Undefined). Guessing was rejected
deliberately: a wrong mask mis-scores trials silently, an empty one leaves a
visible gap.

### State order is *manifest* order

`addState` keeps two orderings: `StateNames` in the order states were first
**referenced** (a forward reference in `StateChangeConditions` creates the name
before the state is defined) and `Manifest` in the order they were **added**.
`sendStateMatrix` permutes everything into manifest order before upload, and
**that permuted order is what the device's event stream indexes.**
`obj.StateNames` is written from it, and it is the only thing state indices may
be resolved against.

---

## Parameters

Bpod 0.5/0.6 has no descriptor opcode — unlike the Teensy, the firmware cannot
be asked what it exposes. The table in
[`populateModule_.m`](../../obj/+hw/@Bpod/populateModule_.m) is therefore a
literal transcription of the board's fixed complement, built entirely offline.
All 58 parameters live on a single module named `Bpod`, whose `Fs` is
`hw.Bpod.TICK_HZ` (10 kHz, the firmware's Timer3 tick).

### The Visible / Access matrix

This is the least obvious part of the backend, because two shipped consumers
read the same table through two different filters. Flipping a `Visible` flag
moves a parameter between them **silently**.

| | Filter | Effect |
|---|---|---|
| **Trial table** | `Visible == true && Access ~= 'Read'` (`Protocol.compile_internal`) | Becomes a column of the compiled trial table. |
| **DATA sweep** | `epsych.Runtime.all_parameters(Access='Read')`, whose defaults are `includeInvisible=false`, `includeTriggers=false`, `includeArray=true` — i.e. `Visible == true && ~isTrigger && Access ~= 'Write'` (`ep_TimerFcn_RunTime`) | Becomes a field of each saved trial's `DATA`. |

Which yields three roles:

| Role | Declaration | Lands in |
|---|---|---|
| Operator-facing I/O | `Visible=false` | Neither. Moves only through explicit `set_parameter` / `trigger` / `get_parameter` calls. |
| Trial **configuration** | `Visible=true, Access='Any'` | Trial table **and** DATA. |
| Trial **result** | `Visible=true, Access='Read'` | DATA only — `'Read'` is what keeps it out of the trial table. |

### Full table

**Immediate outputs** — `Visible=false`, `Access='Any'`, 22 parameters:
`Valve1…8` (Boolean), `PWM1…8` (0–255 port LED duty), `BNCOut1…2`,
`WireOut1…4`. Every write updates the absolute shadow and re-emits the full
mask via `writeOutputs_`.

**Hardware serial** — `Visible=false`, `Access='Write'`: `Serial1Byte`,
`Serial2Byte`. Momentary; writing emits `['H' ch byte]` and retains nothing.
`'Write'` excludes them from the DATA sweep on its own.

**Immediate inputs** — `Visible=false`, `Access='Read'`, 14 parameters:
`Port1In…Port8In`, `BNCIn1…2`, `WireIn1…4`. Served through `readInput_` and its
interlock.

**Trial control** — `Visible=false`, named for the configured `BoxID`.
`epsych.Runtime.resolveTriggerParameters` looks these three names up literally and
aborts the run if any is missing:

| Name | Kind | Role |
|---|---|---|
| `x_ResetTrig_<N>` | trigger | Fired **before** the trial's parameter writes. Drains any burst still in flight, flushes, clears the trial record, and re-asserts the output shadow. Never compiles a matrix. |
| `x_NewTrial_<N>` | trigger | Fired **after** the writes. Builds the matrix, uploads it if it changed, sends `'R'`, returns immediately. |
| `x_TrialComplete_<N>` | read | Never fired. Polled every tick; raised once the matrix-end sentinel *and* the epilogue have both been consumed. |

Access on the triggers is `'Any'`, never `'Write'` — the resolver filters with
`Access='Read'`, which drops write-only parameters, so a `'Write'` trigger is
simply never found and the session dies with `epsych:RunExpt:MissingTrigger`.

**Shipped-GUI literals** — `Visible=false`, `Access='Read'`: `_TrigState~<N>`
and `_TrialNum~<N>`, which `gui.OnlinePlot` resolves with
`includeInvisible=true, silenceParameterNotFound=true`. The `~<BoxID>` suffix is
not a typo and does not follow the `x_*_<BoxID>` form; OnlinePlot looks them up
exactly as written.

**Trial configuration** — `Visible=true`, `Access='Any'`. The only two columns
of the trial table:

| Name | Type | Meaning |
|---|---|---|
| `TrialDuration` | Float, s, 0–3600 | Nominal duration, passed to the builder. In immediate mode it is the host-side trial timeout. |
| `TrialType` | Integer, ≥0 | Condition label. `psychophysics.Detection` groups by this, separately from `RespCode`. |

**Trial results** — `Visible=true`, `Access='Read'`, 13 parameters:

| Name | Type | Meaning |
|---|---|---|
| `RespCode` | Integer | `epsych.BitMask` mask. Decode with `epsych.BitMask.decode`. |
| `RespLatency` | Float, s | Entry time of the first outcome-tagged state, else the first port/BNC/wire event; `NaN` for no response. |
| `nStatesVisited` | Integer | Number of state entries recorded. |
| `LastStateCode` | Integer | Manifest index of the final state. |
| `LastStateName` | String | Final state's name, resolved through `StateNames`; `'None'` when nothing was recorded. |
| `TrialStartTimestamp` | Float, s | Device trial-start time from the epilogue header. |
| `TrialDuration_Actual` | Float, s | Measured duration, as distinct from the requested `TrialDuration`. |
| `Aborted` | Boolean | True when the trial ended by `abortMatrix`, by the epilogue watchdog, or by the `MaxTrialSeconds` ceiling. |
| `LastSoftCode` | Integer | Most recent soft code seen during the trial; 0 for none. |
| `StateCodes` | Integer array | Manifest indices of every state entered, in order. |
| `StateTimestamps` | Float array, s | Entry time of each element of `StateCodes`. |
| `EventCodes` | Integer array | Every event code streamed, in order. Index into `hw.Bpod.EVENT_NAMES`. |
| `EventTimestamps` | Float array, s | Time of each element of `EventCodes`. |

Per-state and per-event onsets are additionally available as `State_<Name>` and
`Event_<Name>` reads, returning first-entry time or `NaN`.

### The result field set is frozen

`ep_TimerFcn_RunTime` stores each trial with
`RUNTIME.TRIALS(i).DATA(trialIdx) = data`, which throws **"Subscripted
assignment between dissimilar structures"** the moment one trial reports a
different set of fields than another — taking the whole session down at a trial
boundary, with an animal in the box.

Three rules follow, and all three are load-bearing:

1. Every result parameter exists on **every** trial and reports `NaN`/`0` when
   the matrix never visited the state that would have produced it. Results are
   never added or removed to match what a trial happened to do.
2. **No `Min` is set on any result.** `hw.Parameter.clamp_value_` uses
   `max(value, Min)`, and `max(NaN, 0)` is `0` — a `Min=0` would silently turn
   the "never visited" sentinel into a real zero.
3. The result set `pump_` publishes is deliberately **matrix-independent** (no
   per-state fields). A mid-session recompile can change `StateNames`; a field
   set derived from it would change with it.

---

## Immediate I/O mode

With `StateMatrixFcn` blank, `usesStateMatrix()` is false and there is no
device-side trial at all. `x_NewTrial_` only stamps `trialTic_` and increments
the trial counter; nothing is uploaded and no `'R'` is written. Valves, port
LEDs, BNC and wire lines are driven directly through `set_parameter` and
`flushOutputs`, at timer-tick resolution.

The host then owns trial timing. `pump_`'s `immediateModeTick_` completes the
trial when the elapsed time reaches a **writable** trial-duration parameter
(`ImmediateTrialDuration`, else `TrialDuration`). If no writable candidate
exists it returns `Inf` — meaning completion is left to a custom GUI, a
`TrialSelector`, or `FORCE_TRIAL`, bounded only by `MaxTrialSeconds`. It
deliberately does not invent a duration.

---

## Runtime knobs

All are public properties so tests and unusual rigs can shorten them.

| Property | Default | Purpose |
|---|---|---|
| `SnapshotInterval` | `0.005` s | TTL on cached input reads. Sized under the 10 ms tick so a fresh tick always re-polls. |
| `MaxMessagesPerPump` | `64` | Bounded work per tick. A trial that floods events must not let one pump call starve the session. |
| `EpilogueTimeout` | `2` s | Watchdog on the end-of-trial epilogue. |
| `MaxTrialSeconds` | `3600` s | Hard ceiling on a single trial. |
| `BootDelay` | `1.5` s | Due USB re-enumeration settle time. |
| `Timeout` | `1` s | Per-transaction timeout. |

The two watchdogs are not defensive decoration. The epilogue is
length-prefixed but **unframed** — a single lost byte would otherwise leave the
parser waiting for timestamps that never arrive, with `x_TrialComplete_` stuck
at 0 and the session frozen at a trial boundary with no error, no log line, and
no trial advance. Both timeouts close the trial with `Aborted = true` instead.

`checkBacklog_` reports once (level 1) when more than 4 kB of unparsed event
stream is queued, which is the only symptom a starved pump produces — otherwise
it degrades invisibly, with messages simply parsing a tick later.

---

## Limitations and safety

Read this section before running an animal.

### ⚠ Animal welfare: the firmware only clears outputs on a clean end or `'X'`

The Bpod firmware resets valves, PWM, BNC and wire lines **only** when a state
matrix reaches its exit state or when it receives an `'X'` abort. It has no
watchdog of its own. Therefore:

- A MATLAB **error** mid-trial leaves outputs energized until something forces
  them low.
- `close_interface` and `delete` both do exactly that: `abortMatrix` → drain the
  burst → `resetShadow_` + `writeOutputs_(Force=true)` → `'Z'`. Each of the four
  steps has its own `try/catch`, so a failure to abort can never skip the step
  that closes the valves. All four run **while `linkReady_` is still true**,
  because the write path is gated on it.
- **A hard MATLAB crash, a killed process, or a yanked USB cable bypasses all of
  it.** A valve can stay open. There is no host-side fix for this; a
  firmware-side watchdog that closes outputs when the host stops talking is the
  only complete answer, and it is out of scope for this backend.
- Practical mitigation: do not leave a rig unattended with an animal in it, and
  prefer state matrices whose reward states have short, bounded timers rather
  than states that hold a valve open awaiting a host command.

### ⚠ One box per protocol

Bpod 0.5 has exactly **one** state machine and **one** `'R'` opcode.
`epsych.Protocol.addInterface` rejects a second interface of the same `Type`
with only a `vprintf` and a bare `return` — no error — so a two-subject
configuration would have subject 2's `dispatchNextTrial` clobber subject 1's
in-flight matrix with nothing raised anywhere.

`prepareRecording` therefore makes it a **hard error**:

```
hw:Bpod:MultipleSubjects — hw.Bpod serves one box: the device has a single
state machine. This session has N subjects, whose trials would overwrite each
other silently. Run one subject per Bpod.
```

Two Bpods in one session is not supported. Run one subject per Bpod, in
separate MATLAB sessions.

### No immediate input reads while a matrix is live

Covered above under [the `'I'` interlock](#the-i-interlock). Reads of
`Port*In`, `BNCIn*`, `WireIn*` during a trial return the last cached value,
which may be up to a whole trial stale. If a paradigm needs an input tested
mid-trial, that test belongs **in the state matrix**, which is where it will
also be resolved at 100 µs instead of 10 ms.

### Device→host soft codes are recorded, not dispatched

The firmware can push `[2 softCode]` when a state's `SoftCode` output column
fires. `hw.Bpod` records it in `lastSoftCode_` (published as `LastSoftCode`) and
does nothing else.

Bpod's own `HandleSoftCode` `eval`s a handler function name synchronously inside
its polling loop. Doing that inside a timer callback would reintroduce exactly
the blocking this backend exists to remove, and would `eval` an arbitrary
function name in the middle of a trial. **Put mid-trial contingencies in the
state matrix.** Host→device injection is supported and is the intended
direction: `sendSoftCode(n)` emits `['V' 'S' n]`, which the running matrix sees
as the event `SoftCode<n>`.

Note the wire byte is **one-based**: `sendSoftCode(1)` produces `SoftCode1`.
This is verified against the firmware (`CurrentEvent = SoftEvent + Ev - 1` with
`Ev == 28`) and against Bpod's own `SendBpodSoftCode.m`. Sending `code-1` would
emit event 27 = `Wire4Low` — a plausible-looking wrong transition rather than an
error.

### The device silently stops recording timestamps past 10 000 events

`MAX_TIMESTAMPS` is a firmware ceiling. Past it the state machine **keeps
running and keeps streaming events**, but no more timestamps are recorded. So
`EventCodes` can legitimately be longer than `EventTimestamps` on a long or
noisy trial. `finalizeTrial_` pads `EventTimestamps` with `NaN` to keep the two
index-aligned, logs at level 0, and flags the trial. A lost byte looks exactly
the same, which is why the message names both possibilities.

### ⚠ The state-matrix encoder is transcribed, not verified against hardware

**`compileMatrix_` has never been compared against the output of Bpod's own
`SendStateMatrix` on a real device, and cannot be until someone does it on a
rig.** The original reads `BpodSystem.InputsEnabled` (a GUI-backed struct loaded
from `Settings Files/BpodInputConfig.mat`) and ends by writing
`BpodSystem.GUIHandles.CxnDisplay`, so it cannot be executed without starting
the Bpod console — which is the thing this backend exists to avoid.

This matters more than a usual "untested" note, because **a wrong matrix is not
a loud failure.** The firmware performs no validation of the `'P'` payload: it
reads a fixed byte count derived from `nStates` and runs whatever that decodes
to. A single off-by-one in the base-0 conversion, the row-major transpose, or
the `nStates+1` exit substitution yields a matrix the device accepts and runs
**wrongly**, with no error anywhere and no way to tell from the event stream.

**The check that closes this gap** (one capture, once, is enough):

1. On a rig with the Bpod GUI running, build a representative `sma` — several
   states, at least one forward reference, an `'exit'`, a global timer, a global
   counter, a `Valve` and an `LED` output.
2. Capture the byte string Bpod's `SendStateMatrix` hands to `BpodSerialWrite`.
3. Build the identical matrix through `hw.Bpod` and compare against
   `obj.compileMatrix_()`.

`compileMatrix_` is kept **pure** — struct in, bytes out, no I/O, no state
mutation — precisely so that comparison is a one-liner. Do not add a read, a
write, or a property assignment to it.

Two related transcription notes, both already resolved in code:

- `newStateMatrix` uses `GlobalCounterEvents = ones(1,5)*255`, from
  `BpodObject.m`. `GenerateBlankStateMatrix.m`'s `254` is a bug: the encoder
  transmits `GlobalCounterEvents-1` and the firmware treats a counter as
  attached when its byte is `< 254`, so `254` would silently attach every unused
  counter to event code 253.
- `sma.PortsEnabled` / `sma.WiresEnabled` are **additions** to Bpod's blank
  matrix, defaulting to all-enabled. Bpod reads this from `BpodSystem.InputsEnabled`;
  `hw.Bpod` carries it on the matrix instead. All-enabled is deliberate: the
  firmware's own default is all-**disabled**, and a disabled port simply never
  produces `Port*In`/`Port*Out` events, with no error anywhere.

---

## Known gaps

Two things remain genuinely unverified. Both need a rig, neither can be settled
offline, and both are listed so nobody rediscovers them on a bench with an animal
waiting.

### 1. The state-matrix encoder has never run against a device

Detailed under [the encoder warning](#-the-state-matrix-encoder-is-transcribed-not-verified-against-hardware)
above, and the highest-risk item in the backend: a single off-by-one in the
manifest permutation, the base-0 conversion, the transpose, or the `nStates + 1`
exit substitution produces a matrix the firmware accepts and runs *wrongly*, with
no error anywhere. `compileMatrix_` is kept pure precisely so a one-time golden
vector captured from the real `SendStateMatrix` can be diffed against it.

### 2. Absolute IR beam polarity

The *protocol* half is settled: `Bpod_MainModule_0_6.ino:386-388` raises the
`Port<N>In` event on a LOW→HIGH edge, so `readInput_` reporting raw HIGH as
active agrees with the trial event stream by construction. That is the property
that matters for correctness, and it is asserted offline.

What a bench check still has to establish is the *wiring* fact: whether HIGH
means an occluded or an unoccluded beam on a given rig's photogates. Every
polarity decision lives in one local function in `readInput_.m`, so a
lab-specific flip is a one-line change.

---

## Invariants that were once defects

Each of these was a real bug during development, caught by the offline suite.
They are recorded because the code now reads as obviously correct, which is
exactly what makes them easy to reintroduce. Each has a guard in
`tmp/smoke_test_bpod.m`.

- **One result vocabulary, not three.** `hw.Bpod.RESULT_PARAMETERS`,
  `populateModule_`, `finalizeTrial_` and `get_parameter` must name the frozen
  result set identically. They once diverged (`nStatesVisited` vs `NStates`,
  `StateTimestamps` vs `StateTimes`), and the failure mode is silent in the worst
  way: the parameter still exists, the DATA sweep still finds it, and every trial
  records the constant seed value. A `RespCode` stuck at its seed means
  `psychophysics.Detection`, `BestPEST` and `MLP` score nothing at all, and the
  session looks normal throughout.
- **`TrialDuration` is configuration; `TrialDuration_Actual` is the measurement.**
  `get_parameter` must not classify `TrialDuration` as a result. When it did, a
  builder's `P.TrialDuration` was the elapsed time of the *previous* trial.
- **The matrix is compiled at `x_NewTrial_`, never at `x_ResetTrig_`.**
  `dispatchNextTrial` orders ResetTrig → parameter writes → NewTrial, so
  compiling at ResetTrig bakes in the previous trial's parameter values on every
  trial — a silent one-trial lag that corrupts staircases and go/no-go stimulus
  assignment. Relatedly, `startTrial_` must not pre-compile in order to decide
  whether to upload: `compileMatrix_` reads the *permuted* matrix and only
  `sendStateMatrix` permutes, so calling it first raises
  `hw:Bpod:MatrixShapeMismatch` on the very first trial. `sendStateMatrix`
  already owns the skip-if-unchanged memo.
- **Only `finalizeTrial_` may publish the result set.** See below.

### 3. Smaller items
- `finalizeTrial_` is a protected method in its own file, not a local function
  in `pump_.m`, because `abortMatrix` ends trials too. Every end-of-trial path —
  clean epilogue, epilogue watchdog, matrix overrun, immediate-mode timeout, and
  `'X'` — routes through it, and callers set `trialAborted_` first. When it was
  local to `pump_.m`, `abortMatrix` latched `trialComplete_` on its own and left
  the PREVIOUS trial's frozen result set in `obj.inputCache_`, so every aborted
  trial was saved with that trial's states and `Aborted = false`. Do not add a
  second writer of the result vocabulary. `tmp/smoke_test_bpod.m` §12b guards
  this.
- `tmp/Bpod_Mock` simulates the `Bpod_MainModule_0_6` firmware in process by
  overriding **only** the seven transport-seam methods (`openPort_`,
  `closePort_`, `write_`, `readNow_`, `readExactly_`, `bytesAvailable_`,
  `flushInput_`). That is what makes the offline suite meaningful: every protocol
  path it exercises — handshake, output shadow, `'I'` cache and interlock, state
  matrix encoder, resumable pump, epilogue decoder — is the same code a real
  board runs. Keep new device I/O inside the seam or the mock stops being
  representative. Note `findBoardPort` is `static` and calls `serialport`
  directly, so it bypasses the seam; a mock must set `Port` explicitly with
  `AutoDetect = false`.

---

## Diagnostics

`selfTest(Invasive=false)` issues **zero** transport calls — it reports on
configuration only (port, box ID, builder resolution, parameter count, and an
informational note about the one-box limit). That is not politeness:
`epsych.SelfTest` can be run from RunExpt's Help menu while a session is live,
and a single stray probe byte would corrupt the trial. For the same reason it
never reads `obj.mode`, whose getter drives the pump.

`selfTest(Invasive=true)` adds a handshake check, restores the connection state
it found, and warns (rather than passes) on firmware builds below 6, whose
timestamps use a different scale factor and would be silently mis-scaled.

Neither form ever throws.

`canReadHardwareParameters` accepts the interface's own first module (by handle
identity) or any module whose `Name`/`Label` contains `bpod` case-insensitively;
`readHardwareParameters` then delegates to `populateModule_`. `Mode='merge'`
(the default) is idempotent and preserves operator-authored trial levels;
`Mode='replace'` rebuilds the table from scratch.

---

## Verifying on real hardware

Nothing in this backend has been run against a Bpod. This is the bench
checklist that turns it from transcribed to trusted. Run it with a
**multimeter or scope on a valve line and no animal in the box.**

1. **Connect and enumerate.** `iface = hw.Bpod('COMn')`. Confirm
   `FirmwareBuild >= 6` and that `selfTest(Invasive=true)` passes. Confirm
   `numel(iface.Module(1).Parameters) == 58`.
2. **Outputs, offline.** With no matrix running, toggle `Valve1`, `PWM1`,
   `BNCOut1`, `WireOut1` through `set_parameter` and confirm each line follows on
   a scope. Confirm `flushOutputs` re-asserts them. Confirm they all drop on
   `disconnect()`.
3. **Input polarity — settles known gap 2.** Break the Port 1 beam by hand. Confirm
   `get_parameter('Port1In')` reads `true` while broken, and confirm the same
   physical state produces a `Port1In` event in a running matrix. **If those two
   disagree, `readInput_.local_lineActive` is the single place to fix it.**
4. **Golden encoder vector — settles the biggest gap.** On a machine with the
   Bpod GUI available, capture the bytes Bpod's `SendStateMatrix` writes for a
   representative matrix (several states, a forward reference, an `'exit'`, a
   global timer, a global counter, a `Valve` and an `LED`) and compare against
   `iface.compileMatrix_()` for the identical matrix built through `hw.Bpod`.
   They must be byte-identical. **Do this before any real subject runs.**
5. **20-trial session, fixed 1 s matrix.** Configure `StateMatrixFcn` to build
   a two-state matrix with a fixed 1 s timer and an immediate exit. Run 20
   trials and check:
   - Every trial completes; `x_TrialComplete_<N>` never sticks.
   - `TrialDuration_Actual` clusters at 1.000 s with sub-millisecond spread —
     device timing, not host jitter.
   - **ITI overhead:** host-clock trial-to-trial interval minus 1 s should be
     ~10–30 ms. More than ~100 ms means the pump is not being called every tick;
     check for a level-1 backlog warning.
   - `StateCodes`/`StateTimestamps` and `EventCodes`/`EventTimestamps` are
     present, equal length, and index-aligned.
   - Fire `sendSoftCode(3)` mid-trial in one trial and confirm the matrix takes
     the `SoftCode3` transition (not `Wire4Low`).
6. **Stop mid-trial.** Start a trial with a 30 s state timer. Press RunExpt's
   Stop button while it runs. The GUI must respond **within one 10 ms tick** —
   not 30 s later. Confirm `'X'` went out, that the post-abort sentinel +
   epilogue burst was drained (no desync warning on the next run), and that the
   next session starts cleanly on the same port.
7. **Valves drop on abort.** Start a matrix in a state that holds `Valve1` open
   with a long timer. Abort it (Stop, or `abortMatrix`). Confirm on the scope
   that the valve line goes low, and that it *stays* low through
   `close_interface`.
8. **Crash path — know the failure.** With the valve state above, `clear all` or
   kill MATLAB outright while the matrix runs. Confirm for yourself what the
   hardware does. This is the case the safety section says is unfixable from the
   host; measure it once so the risk is understood rather than assumed.
9. **Watchdogs.** Set `EpilogueTimeout = 0.2` and unplug the USB mid-trial.
   Confirm the trial force-completes with `Aborted = true` and the session
   advances rather than freezing.

---

## Related files

- [obj/+hw/@Bpod/Bpod.m](../../obj/+hw/@Bpod/Bpod.m): class implementation and property contract.
- [obj/+hw/@Bpod/pump_.m](../../obj/+hw/@Bpod/pump_.m): the resumable trial engine.
- [obj/+hw/@Bpod/sendStateMatrix.m](../../obj/+hw/@Bpod/sendStateMatrix.m): validation, manifest permutation, upload, and the verification note.
- [obj/+hw/@Bpod/compileMatrix_.m](../../obj/+hw/@Bpod/compileMatrix_.m): the pure byte encoder.
- [obj/+hw/@Bpod/populateModule_.m](../../obj/+hw/@Bpod/populateModule_.m): the parameter table.
- [obj/+hw/@Bpod/close_interface.m](../../obj/+hw/@Bpod/close_interface.m): the animal-welfare shutdown path.
- `c:\src\Bpod\Firmware\Bpod_MainModule_0_6\Bpod_MainModule_0_6.ino`: the firmware this backend speaks to. Read-only reference; never added to the MATLAB path.
- [hw_Interface.md](hw_Interface.md): the base contract.
- [hw_Teensy.md](hw_Teensy.md): the other on-device state machine backend.
- [hw_Interface_Tutorial.md](hw_Interface_Tutorial.md): authoring a backend.
