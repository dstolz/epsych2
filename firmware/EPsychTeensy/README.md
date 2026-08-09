# EPsychTeensy firmware

Behavioral I/O firmware for a Teensy 4.0/4.1, paired with the `hw.Teensy`
backend in `obj/+hw/@Teensy/`.

The board owns the millisecond-scale parts of a trial: debounced response
detection, reward and punishment timing, TTL sync out to the ephys rig, and
the trial contingency itself. MATLAB configures a trial and collects its
result; it is never in the timing path. A lick opens the reward valve within
one scheduler tick (100 µs) no matter what the host is doing.

---

## Build and flash

1. Install the [Arduino IDE](https://www.arduino.cc/en/software) and
   [Teensyduino](https://www.pjrc.com/teensy/td_download.html).
2. Open `EPsychTeensy.ino`.
3. **Tools → Board** → Teensy 4.1 (or 4.0).
4. **Tools → USB Type** → *Serial*. This is required; any other USB type will
   not enumerate as a COM port.
5. **Tools → CPU Speed** → 600 MHz (the default).
6. Upload.

On boot the board prints `EPsychTeensy ready` once, which is how
`hw.Teensy.findBoardPort` recognizes it while scanning ports.

## Configure for your rig

Everything rig-specific lives in [`Config.h`](Config.h). Nothing else in the
firmware hard-codes a pin.

| Setting | Meaning |
|---|---|
| `BOX_ID` | Appears in the `x_NewTrial_<N>` / `x_ResetTrig_<N>` / `x_TrialComplete_<N>` names EPsych requires. One board serves one box. |
| `TICK_HZ` | Scheduler rate (default 10 kHz). Sets the resolution of every timestamp and pulse edge, and becomes the module's `Fs` in MATLAB. |
| `PIN_*` | Pin assignments. |
| `RESPONSE_ACTIVE_LOW` | `1` for a sensor that shorts the pin to ground (the `INPUT_PULLUP` default); `0` for one that drives the pin high. |
| `DEFAULT_*` | Startup values for the trial timing and contingency parameters. All are writable at runtime from MATLAB. |

### Default wiring

Inputs use `INPUT_PULLUP`, so a lickometer, switch, or open-collector sensor
just shorts the pin to ground.

| Pin | Direction | Purpose |
|---|---|---|
| 2 | in | Primary response (lick spout, nose poke, lever) |
| 3 | in | Second response channel, or a beam break |
| 4 | out | Reward valve / pump gate |
| 5 | out | Punishment (air puff, shock gate) |
| 6 | out | Cue LED or stimulus gate |
| 7 | out | TTL sync pulse to the ephys system |
| 8 | out | House light |
| 13 | out | Onboard LED, mirrors `InTrial` |

Outputs are 3.3 V logic and **not** power drivers. Valves, pumps, and lights
need a MOSFET, relay, or driver board. The Teensy 4.x pins are also **not**
5 V tolerant — level-shift any 5 V input.

---

## How a trial runs

The handshake is the one `epsych.Runtime` already implements, so no custom
runtime code is needed:

```
MATLAB dispatchNextTrial      Teensy
------------------------      ----------------------------------------
TRG x_ResetTrig_1        -->  abort, clear TrialComplete + latches + events
SETM TrialType=0 ...     -->  apply this trial's parameters
TRG x_NewTrial_1         -->  sync pulse, then run the state machine

every 10 ms:
SNAP                     -->  ...TrialComplete=0...      (keep waiting)
SNAP                     -->  ...TrialComplete=1 RespCode=33 RespLatency=187...
```

The **device owns clearing `TrialComplete`.** Nothing in MATLAB writes it back
to zero — the only mechanism is the `ResetTrig` pulse at the *front* of the
next dispatch. That is why reset comes before the parameter writes.

Trial results are latched when `TrialComplete` goes high and held until the
next `ResetTrig`, so it is safe for the host to read them across more than one
device snapshot.

### State machine

```
Idle -> PreWindow -> Cue -> RespDelay -> RespWindow -> PostWindow
                                            |              |
                                      (threshold met       v
                                       ends the window)  Outcome -> [Timeout] -> ITI -> Idle
```

Each phase's duration is a writable parameter in milliseconds; setting one to
`0` skips that phase. Reaching `RespCountThresh` responses inside the response
window ends it immediately rather than waiting it out — waiting would add up to
`RespWinDur` to the reward latency and throw away the precision this firmware
exists to provide.

`RespLatency` is measured from **cue onset** and is `-1` when there was no
response, which distinguishes a Miss from a genuine 0 ms latency.

### Contingency

`TrialType` 0 is the signal/Go condition; anything else is a catch/NoGo.

| TrialType | Responded | Outcome | Output |
|---|---|---|---|
| 0 (Go) | yes | `Hit` | Reward pulse, if `AutoReward` |
| 0 (Go) | no | `Miss` | — |
| ≥1 (NoGo) | yes | `FalseAlarm` | Punish pulse, then `TimeoutDur` |
| ≥1 (NoGo) | no | `CorrectReject` | — |

`RespCode` is a `uint32` bitmask built from the indices in
[`BitMask.h`](BitMask.h), which mirrors `epsych.BitMask`. It decodes directly
through `epsych.BitMask.decode` and feeds `psychophysics.Detection` and
`gui.History` with no translation. To change the paradigm, edit
`resolveOutcome()` in [`TrialFSM.cpp`](TrialFSM.cpp) — it is deliberately the
only place the contingency is expressed.

---

## Command grammar

ASCII, LF-terminated. One reply line per command, or one `BEGIN`/`END` block.
Once running, the firmware emits nothing it was not asked for, which is what
keeps the host's request/response model valid.

| Command | Reply |
|---|---|
| `ID?` | `ID EPsychTeensy PROTO=1 FW=… BOARD=… SN=… BOXES=… TICKHZ=…` |
| `DESC?` | `DESC BEGIN` / `P <name> <acc> <type> <flags> <min> <max> <unit>` … / `DESC END` |
| `GET <name>` | `VAL <name> <value>` |
| `SET <name> <v>` | `OK` |
| `SETM <n>=<v> …` | `OK` — batched write; where a trial's parameters land |
| `SNAP` | `SNAP <us> MODE=<n> NEVT=<k> OVF=<0\|1> <name>=<v> …` |
| `TRG <name>` | `OK <us>` |
| `MODE <n>` / `MODE?` | `OK` / `MODE <n>` — `hw.DeviceState` integers |
| `EVT?` | `EVT BEGIN` / `E <us> <name> <value>` … / `EVT END` |
| `SYNC` | `SYNC <us>` |
| `RESET` | `OK` |
| `HELP` | `HELP BEGIN` / … / `HELP END` |

Errors are always `ERR <code> <text>`: `1` parse, `2` unknown parameter,
`3` access violation, `4` bad value.

`SNAP` is why the backend is fast: it returns every readable value in one line,
so the runtime's trial-end sweep over all readable parameters costs one
round-trip instead of one per parameter.

### Events: latched state *and* a timestamped queue

Input edges are stamped on-device with microsecond resolution; only their
*delivery* is polled. Two views of the same events:

- **Latched state**, carried in every `SNAP`: `Resp` (current debounced level),
  `RespLatch` (sticky since the last reset), `RespCount` (count since reset).
  Cheap enough for the 10 ms poll.
- **The queue**, drained with `EVT?`: every edge with its `micros64()`
  timestamp. Use `hw.Teensy.syncClock` to map board microseconds onto host
  time.

A full queue drops the *oldest* event and sets `OVF=1` in `SNAP`, because when
a queue backs up the recent past explains the current state better than a stale
prefix does.

You can drive all of this from any serial terminal at 115200 baud — the whole
protocol is human-typeable, which is the main reason it is ASCII.

---

## Design notes

**Rollover.** `micros()` wraps every ~71.6 minutes and a session outlives that.
Every timestamp comes from `clk::micros64()` ([`Clock.h`](Clock.h)) instead.
Getting this wrong corrupts timestamps mid-session with nothing logged.

**Critical sections.** Anything reachable from the scheduler ISR uses
`critEnter`/`critExit` ([`Critical.h`](Critical.h)), which save and restore
`PRIMASK`. Arduino's `noInterrupts()`/`interrupts()` pair would re-enable
interrupts partway through and let the 10 kHz ISR re-enter itself.

**One ISR.** A single 10 kHz `IntervalTimer` samples inputs, advances output
pulses, and steps the state machine, in that order — so a response lands in the
state it actually occurred in. It never allocates, blocks, or touches `Serial`.
`loop()` does only serial. A per-output timer design would burn all four
hardware timers and scale no further.

**No `String`.** Fixed char buffers throughout, to avoid heap fragmentation
over a multi-hour session.

**Teensy 4.x has no true DAC**, unlike the 3.x line. Analog output (a later
phase) means PWM plus an RC filter, MQS on pins 10/12, or an external SPI DAC.
Do not assume `analogWrite` to `A14` works.

---

## Verifying without a rig

```matlab
run('tmp/smoke_test_teensy_firmware_contract.m')
```

Checks the agreements between this firmware and the MATLAB backend that no
compiler can see: bit indices against `epsych.BitMask`, protocol version,
buffer sizes, required parameter names, `DESC` field order, and that no
ISR-reachable code uses `noInterrupts()`. Each of those fails silently when it
drifts.

On the bench, jumper pin 7 (sync out) to pin 2 (response in), then:

```
TRG !SyncPulse
EVT?
```

should report a `Resp` edge with a plausible timestamp.
