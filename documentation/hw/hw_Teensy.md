# `hw.Teensy`

`hw.Teensy` connects EPsych to a Teensy 4.0/4.1 microcontroller running the
[EPsychTeensy firmware](../../firmware/EPsychTeensy/README.md) over USB serial.

It is the backend to reach for when a paradigm needs millisecond-accurate
behavioral I/O — debounced lick or poke detection, reward valve timing,
optogenetic pulse trains, TTL sync out to the ephys rig — without a TDT system.
The board runs the trial contingency itself, so response-to-reward latency is
bounded by the firmware's 100 µs scheduler tick rather than by MATLAB timer
jitter.

```matlab
iface = hw.Teensy('COM6');
iface = hw.Teensy('', AutoDetect=true);        % scan ports for the board
iface = hw.Teensy('COM6', Connect=false);      % offline, for ProtocolDesigner
```

> **Status: under development.** `hw.Teensy` and the
> [EPsychTeensy firmware](../../firmware/EPsychTeensy/README.md) it pairs with
> are still being validated and their APIs may change without notice.

---

## Construction

| Option | Default | Meaning |
|---|---|---|
| `port` (positional) | `''` | Serial port, e.g. `'COM6'` or `'/dev/ttyACM0'`. Empty requires `AutoDetect`. |
| `BaudRate` | `115200` | Nominal only. Teensy native USB ignores it and always runs at full USB speed. |
| `Timeout` | `1` | Transaction timeout in seconds. |
| `Connect` | `true` | Connect on construction. `false` yields a fully usable offline object. |
| `AutoDetect` | `false` | Scan available ports for a board answering `ID?`. |
| `DeviceSerial` | `''` | Accept only this board's serial during `AutoDetect` — the way to keep two Teensys in one rig from being swapped. |

The COM port is machine-specific. A protocol authored on one rig may name a
port that does not exist on another; `AutoDetect` (optionally pinned with
`DeviceSerial`) is the robust choice for a shared protocol.

---

## Parameters

Parameters are discovered from the board rather than declared in MATLAB. At
connect, and whenever ProtocolDesigner's **Read HW Params** button is pressed,
the interface issues `DESC?` and converts the reply into `hw.Parameter`
objects. Both paths run through the same
`populateModuleParametersFromDescriptor` helper, so they cannot drift.

All parameters live on a single module named `Teensy`, whose `Fs` is the
firmware's scheduler rate.

### Names EPsych requires

`epsych.Runtime` will not start a session without these three, where `<N>` is
the firmware's `BOX_ID`:

| Name | Kind | Role |
|---|---|---|
| `x_NewTrial_<N>` | trigger | Starts the trial. |
| `x_ResetTrig_<N>` | trigger | Aborts, clears `TrialComplete`, latches, and the event queue. |
| `x_TrialComplete_<N>` | read | Polled every timer tick; nonzero ends the trial. |

Triggers are published with `Access='Any'`, never `'Write'`. This is not
cosmetic: `Runtime.all_parameters` defaults to `Access='Read'`, which drops
write-only parameters, so a `'Write'` trigger is simply never found and the
session aborts with `epsych:RunExpt:MissingTrigger`.

### Names the shipped GUIs and analyses expect

`RespCode` (uint32 `epsych.BitMask`), `RespLatency` (ms, `-1` for no response),
`InTrial`, `TrialType`, and the hidden `_TrigState~<N>` / `_TrialNum~<N>` pair
that `gui.OnlinePlot` uses for trial-onset detection. Because the firmware
emits a real `epsych.BitMask` value, `psychophysics.Detection` and
`gui.History` work with no translation layer.

### Name prefixes

The repository's conventions are honored, so GUI behavior matches the TDT
backends: `!` marks a trigger, `~` is hidden and renders as a *toggle* in
`gui.BehaviorGUI`, `_` and `#` are hidden, and `%` is dropped entirely.

---

## Performance

The runtime timer ticks every 10 ms and reads `mode` on every interface plus
`x_TrialComplete_<N>` on every tick, then sweeps every readable parameter when
a trial completes. Done naively over a serial link that would dominate the
tick. Three mechanisms prevent it:

**Batched reads.** `get_parameter` serves from a snapshot cache refreshed by a
single `SNAP` command that returns every readable value at once. A
15-parameter trial-end sweep costs one round-trip instead of fifteen.
`SnapshotInterval` (default 5 ms) is the cache TTL; `snapshotInvalidate()`
forces a fresh read.

**Cached mode.** `mode` is throttled to `ModePollInterval` (default 0.25 s). A
garbled or timed-out reply returns the cached value and never fabricates
`Idle`, because `RunExpt` reads `Idle` as "stop the session".

**Coalesced writes.** With `CoalesceWrites=true` (the default),
`set_parameter` buffers the write and the buffer is flushed as one `SETM` line
at the next trigger or read. Since `dispatchNextTrial` is contractually
reset → writes → trigger, a trial's *k* parameter writes collapse into one
round-trip that lands exactly where it should. `flushWrites()` forces it early.

---

## Offline behavior

With no connection, `set_parameter` returns true, `get_parameter` serves the
locally cached value, and `trigger` returns a timestamp. This is what lets
`epsych.ProtocolDesigner` edit a protocol with no board attached. Note that
`set_parameter` does **not** store the value itself —
`hw.Parameter.set.Value` already did that before delegating, and storing it
again would be redundant (`hw.Software` makes the same point).

---

## Diagnostics

`selfTest(Invasive=false)` confirms the configured port exists, making no
hardware calls at all, so it is safe against a live session.
`selfTest(Invasive=true)` opens the port, handshakes, verifies the protocol
version, and restores the connection state it found. Neither ever throws.

`syncClock` estimates the offset between the board's microsecond clock and host
time by bracketing `SYNC` exchanges and keeping the sample with the smallest
round-trip. The result is stored in `module.Info.ClockOffset` (which
`Protocol.toStruct` serializes), so saved event timestamps stay interpretable.

`drainEvents` returns the board's timestamped event queue as an Nx3
`[boardMicros, channelIndex, value]` array.

---

## Testing without hardware

`tmp/Teensy_Mock.m` simulates the firmware in process by overriding only
`hw.Teensy`'s five transport methods, so every line of protocol logic runs as
it would against a real board — with no serial port and no hardware support
package. It mirrors `tmp/Intan_RHX_Mock` for the TCP backend.

```matlab
run('tmp/smoke_test_teensy.m')                    % backend behavior
run('tmp/smoke_test_teensy_protocol.m')           % .eprot round-trip
run('tmp/smoke_test_teensy_firmware_contract.m')  % firmware/host agreement
```

The third is worth understanding: it parses the firmware source and checks the
agreements neither a compiler nor a MATLAB test can see on its own — bit
indices against `epsych.BitMask`, protocol version, buffer sizes, required
parameter names, and `DESC` field order. Every one of those fails *silently*
when it drifts.

---

## Related files

- [obj/+hw/@Teensy/Teensy.m](../../obj/+hw/@Teensy/Teensy.m): class implementation.
- [obj/+hw/@Teensy/setup_interface.m](../../obj/+hw/@Teensy/setup_interface.m): connect and discovery.
- [firmware/EPsychTeensy/README.md](../../firmware/EPsychTeensy/README.md): firmware, wiring, and command grammar.
- [hw_Interface.md](hw_Interface.md): the base contract.
- [hw_Interface_Tutorial.md](hw_Interface_Tutorial.md): authoring a backend.
