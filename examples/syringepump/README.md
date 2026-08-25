# Example: Testing the Syringe Pump Panel

The smallest complete session that exercises
[`gui.components.SyringePump`](../../documentation/gui/gui_SyringePump.md) the way a real
paradigm would: a protocol whose reward `Volume` steps through three levels,
a behavior GUI that embeds the pump panel beside the controls that write the same
pump, and a trial loop that dispenses on every trial.

Runs with **no hardware** — with no port given it builds against
`tmp/NE1000_Mock`, the in-process simulated pump the `hw.NE1000` smoke tests
use.

## Quick start

```matlab
addpath('examples/syringepump')

run_pump_session                       % simulated pump, 12 rewards
run_pump_session(Port = 'COM4')        % a real NE-1000 on COM4
create_pump_protocol                   % writes PumpExample.eprot for RunExpt
```

![The behavior GUI](../../documentation/gui/images/SyringePumpBox.png)

The window opens with the session held at **Begin Experiment** — nothing is
dispensed until it is pressed, so the syringe can be seated and the line purged
first. The pump panel is fully live while it waits: connect a port, prime with
**Start**, **Zero** the accumulators, then begin. Closing the window instead
calls the run off before any liquid moves. `run_pump_session(WaitForBegin = false)`
skips the gate for unattended runs, and a session driven from RunExpt's own Run
button retires the button as soon as it sees the Record mode change.

What to watch while it runs:

- the panel's readout climbing after each reward, and its status line turning
  green while the motor is running;
- **Next Trial** showing the reward size the runtime is about to write;
- the scatter and the monitor following `VolumeInfused` as it lands in `DATA`;
- **Start**, **Stop**, **Zero**, the port picker, and the right-click menu all
  still working by hand between trials, on the same pump the session is using.

## Files

| File | Purpose |
|---|---|
| `create_pump_protocol.m` | Builds and compiles the protocol: three reward volumes on the pump's own `Volume` parameter, a randomized ITI, the three core triggers |
| `PumpBehaviorGUI.m` | `gui.BehaviorGUI` subclass: the Begin Experiment gate, the trial cycle, the pump panel, trial controls, next-trial display, a `VolumeInfused` scatter and monitor |
| `run_pump_session.m` | Hardware-free session; waits on the Begin button, then mirrors the real runtime loop and pulses `Start` each trial |

Generated at runtime (not checked in): `PumpExample.eprot`.

## Who runs the trial cycle

The runtime does **not** dispense anything. `ep_TimerFcn_RunTime` writes the
dispatched `Volume` and `Rate` to the pump, then polls `x_TrialComplete_1` and
waits. Something has to pulse `Start` and decide when the trial is over, and on
a software rig that something is the behavior GUI — the same arrangement
`examples/first_experiment` and `examples/two_afc` use, where the GUI plays the
part rig hardware plays in a real experiment.

`PumpBehaviorGUI` does it on its own timer, one pass per dispatched trial:

1. `onNewTrial` clears `x_TrialComplete_1` (the runtime never clears it) and
   pulses the pump's `Start`;
2. it waits out the dispense — the computed duration first, then the pump's own
   `Status`, polled no faster than 4 Hz, since a pump given a non-zero `Volume`
   stops itself and a `Stop` here would truncate the reward;
3. it waits out the interval the dispatch drew into `ITI`;
4. it raises `x_TrialComplete_1`, which is what makes the runtime collect the
   pump's read-back into `DATA` and dispatch the next reward.

Ending the session mid-dispense stops the pump. `run_pump_session` passes
`DriveTrials = false` because its own loop is the trial loop; leaving the
default on would pulse the pump twice per trial.

Two failures this replaced, both of which look like "the experiment does
nothing useful" from the operator's chair:

- **Trials ran ballistically.** `add_parameter` fills `Values`, not `Value`, so
  `x_TrialComplete_1` was never assigned and read back **empty** — and `if ~[]`
  is false, so every timer tick completed a trial. The protocol now seeds all
  three triggers to 0, and the runtime refuses to read anything that is not a
  definite number as "complete" (see
  [epsych_Runtime.md](../../documentation/epsych/epsych_Runtime.md)).
- **The pump never activated.** Nothing pulsed `Start`: `run_pump_session` does
  that in its own loop, and a RunExpt session has no such loop.

## Three things this example exists to pin down

**The pump must be connected at design time.** `hw.NE1000` builds its
parameter table during the connect handshake, so an offline interface has no
`Volume` or `Rate` to compile into a trial table. `create_pump_protocol`
therefore builds against a live pump (real or simulated) and saves the result;
the `.eprot` reloads with an *offline* interface carrying that same table, so
`run_pump_session` rebuilds rather than loads — `epsych.Runtime` asserts that
every interface connects.

**Rate units are the panel's, not the protocol's.** `gui.components.SyringePump` puts the
interface into the units it displays when it attaches, so a protocol has to be
authored in the same ones. This one is in µL/min (`RateUnits = 'UM'` in
`create_pump_protocol`), so `PumpBehaviorGUI` states `RateUnits = 'UM'` on the panel
too rather than leaving it at the panel's mL/min default — otherwise the number
the trial table re-asserts every trial and the number the operator reads in the
panel would be the same value in different units. The operator can still switch
units from the panel's **Units** menu, which converts the rate rather than
reinterpreting it; the trial table's own numbers do not convert, which is the
reason for stating the units here.

**Volume units follow the syringe, not the rate.** The pump reports volumes in
µL below a 14 mm diameter and mL at or above — independent of `RateUnits`.
`hw.NE1000` labels `Volume`, `VolumeInfused`, and `VolumeWithdrawn` from
`RateUnits`, so with µL/min and a 21.59 mm syringe every display fed by those
parameters reads `0.04 uL` for a 40 µL reward. `create_pump_protocol` corrects
the labels from the diameter. The panel's own readout is unaffected: it reads
`hw.NE1000.DispensedUnits`, which records what the pump actually said, and
displays it in whatever `VolumeUnits` the operator chose (`'uL'` here, to match
the rewards this protocol dispenses).

## Known issue this turned up

`hw.NE1000.transact_` is **not reentrancy-safe**, and the panel guarantees a
second agent on the interface: its readout timer issues a `DIS` every 250 ms
while the runtime is writing `Rate` and `Volume` from the trial table. A timer
callback that lands between an outer transaction's write and its read starts
with `flushInput_`, which discards the reply the outer command is waiting for —
so the outer read either times out (`NE1000: timed out waiting for a reply to
"RAT"`) or, worse on a real port, consumes the `DIS` reply and reports it as
the answer to `RAT`.

Measured against the mock with the panel polling at 20 Hz: **14 interleavings
in 548 dispatch cycles (~2.5 %)**, all of the form *outer `RAT`/`VOL`
interrupted by `DIS`*. A guard in `transact_` — serializing transactions and
having a poll that arrives mid-transaction fall back to the cached value —
would close it; the window is wider with a real serial port, not narrower,
because `readline` blocks on I/O.

## Related

- [documentation/gui/gui_SyringePump.md](../../documentation/gui/gui_SyringePump.md) — the panel
- [documentation/hw/hw_NE1000.md](../../documentation/hw/hw_NE1000.md) — the backend
- [examples/customgui/](../customgui/) — minimal `gui.BehaviorGUI` starter template
- [examples/detection_task/](../detection_task/) — the full worked experiment
- Validation: `tmp/smoke_test_syringepump_example.m` (headless;
  `matlab -batch "run('tmp/smoke_test_syringepump_example.m')"`), and
  `tmp/smoke_test_syringepump_gui.m` for the panel itself
