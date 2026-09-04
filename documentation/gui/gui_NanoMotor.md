# `gui.components.NanoMotor`

An operator panel for the Arduino Nano DM320T stepper controller — the
motorized commutator — built to sit *inside* a behavior GUI rather than in a
window of its own. It is
[`peripherals.NanoMotorControlGUI`](../peripherals/peripherals_NanoMotorControl.md)
in a component's shape: jog either way, set a speed, send a move in degrees or
rotations, stop, and watch the position.

```matlab
% Inside a gui.BehaviorGUI build method
obj.add('gui.components.NanoMotor', panelRig);

% Just a button; the panel lives in the window it opens
obj.add('gui.components.NanoMotor', toolRow, ButtonOnly = true);

% Only the link and the jog controls, on a known port
obj.add('gui.components.NanoMotor', panelRig, ...
    Port = 'COM6', Sections = ["Link","Status","Speed","Jog","Stop"]);

% Standalone, no session
f = uifigure(Name = 'Commutator');
m = gui.components.NanoMotor([], f);
```

![The panel](images/NanoMotor.png)

> **Status: under development**, like the
> [`peripherals.NanoMotorControl`](../peripherals/peripherals_NanoMotorControl.md)
> driver it wraps. Exercised headlessly by
> `tmp/smoke_test_nanomotor_component.m` with no controller attached; the
> connected paths have not been run against a board from this component.

---

## Why it exists beside `NanoMotorControlGUI`

Three differences, and the first is the reason for the other two.

**It never opens the serial port on its own.** The constructor makes the
driver object and stops there — a `peripherals.NanoMotorControl` costs no port
until something calls `connect()` on it — and the link opens when the operator
presses **Connect**, or when a paradigm calls `connect`. The old window
connected from its constructor and *rethrew*, so a commutator that was
switched off, unplugged, renumbered, or already being polled by another MATLAB
took the window with it. A component that behaved that way would take the
whole behavior GUI.

A failed connect is reported in the panel's own status line and logged; it is
never thrown out of a button callback. Every motion command is inert without a
link: it says "no controller connected" and returns.

**The layout has no label column.** The units live inside the fields
(`60 RPM`), the buttons say what they do, and the port row doubles as the
connection control. The whole panel is about 150 px tall against the old
window's 320, which is what lets it share a column with the controls a
paradigm actually cares about.

**It is a [`gui.PopOut`](gui_PopOut.md).** The same panel opens in a window of
its own from the right-click menu, from
`gui.BehaviorGUI.addPopOutButton`, or from the
[component toolbar](gui_ComponentToolbar.md) — and with `ButtonOnly = true` it
*is* just that button, for a GUI with no room to spare.

---

## What it is built over

`gui.components.NanoMotor(source, container)` takes any of three sources:

| `source` | The panel drives |
|---|---|
| a `peripherals.NanoMotorControl` | that controller, borrowed |
| an `epsych.Runtime` (what `gui.BehaviorGUI` passes) | a controller it constructs itself |
| `[]` | the same, so the panel opens with no session at all |

The runtime is kept for two things, neither of them hardware: what the
operator does here is written into the session notes (below), and a session in
[review](../epsych/epsych_ReviewSession.md) stands the whole panel down — a
reviewed session has no rig behind it, and its panel is a record rather than a
control.

A panel closes and deletes the controller on teardown **only when it created
it**. One handed in — from a session, or from the panel a pop-out came from —
outlives the window, which is what lets a pop-out and its host drive one link.

Two `add` calls therefore make **two** drivers, and only the first to connect
gets the port. A GUI that wants a panel and a button over one controller
should hand the second the first's:

```matlab
p = obj.add('gui.components.NanoMotor', panelRig);
obj.register(gui.components.NanoMotor(p.Motor, toolRow, ButtonOnly = true));
```

---

## The rows

| Row | Sections | What it holds |
|---|---|---|
| Link | `Link`, `Detect` | Port dropdown, **Detect**, **Connect/Disconnect** |
| Status | `Status` | Lamp and one line of state |
| Position | `Position`, `Zero` | Output-shaft degrees (`POSD?`), **Zero** |
| Jog | `Speed`, `Jog`, `Stop` | Speed in RPM, **CCW**, **CW**, **STOP** |
| Move | `Move` | Amount, `deg`/`rot`, **Move** |

`Sections` says which are shown; assigning it, or calling `show`/`hide`,
reflows the panel at any time and no control loses its state. Group aliases —
`Connection`, `Readout`, `Motion`, plus `All` and `None` — are expanded on
assignment. A name that is not a section is reported and skipped, so a typo in
a build method cannot stop the GUI opening.

```matlab
m.Sections = ["Link","Status","Position"];   % readout only
m.hide("Detect")                             % the port is known; never probe
m.show("Motion")
```

Every action stays reachable from the right-click menu when its row is hidden
— the port list, connect/disconnect, detect, zero, and the driver's message
level all live there too. That is what makes hiding a row safe.

The layout, the port, the speed, the move amount and its units are remembered
per `PreferenceTag` (the hosting figure's `Tag`/`Name` by default), but **only
when the operator was the one who changed them**: a value a paradigm assigned
is the paradigm's to reassert, not something to resurrect a session later.
*Reset to Default* in the Show menu comes back to the layout the build method
asked for and forgets the operator's.

---

## Driving it

| Method | What it sends |
|---|---|
| `connect` / `disconnect` | Opens the link on the staged port, `MODE USB`, `EN 1` |
| `detectPort` | Probes every serial port for a controller, then connects |
| `jog(±1)` / `jog('cw')` | `RPM ±SpeedRPM`; calling it for the running direction stops the jog |
| `stopJog` | `RPM 0` |
| `stopMotion` | `STOP` — the jog *and* any move |
| `move` | `MOVEDEG` for `MoveAmount` in `MoveUnits`, at `SpeedRPM` |
| `zeroPosition` | `ZERO`, after stopping |

`SpeedRPM` is motor RPM; `MoveAmount` is output-shaft degrees (or whole
revolutions), which the firmware converts through the configured gear ratio.
Changing `MoveUnits` converts the amount with it — 90 deg becomes 0.25 rot —
so the move stays the same size. Zero is a real answer for a move (it means
"the controller's own speed") but not for a jog, which is sent at 1 RPM
instead: a button that turns nothing reads as a broken link rather than as a
speed of zero.

A jog already running follows the speed field, which is the one setting an
operator expects to act immediately. Nothing else is written until the button
for it is pressed.

Only one thing may talk to the controller at a time — the driver reads one
reply per command, and two readers consume each other's, which surfaces as
`NanoMotorControl:Timeout` on both. Every command therefore goes out behind a
busy flag, and one issued while another is in flight is skipped rather than
queued.

---

## Which way is CW?

A jog commands the **motor**, while the position readout and a move are
output-shaft quantities the firmware has already corrected with its gear
`OutputDirSign`. On a drive that reverses, the jog buttons are therefore the
half that reads backwards — the button marked CW turns the commutator
counter-clockwise, and nothing else in the panel is wrong. The full account is
under [*Which way is CW?*](../peripherals/peripherals_NanoMotorControl.md) in
the driver's documentation.

`SwapDirectionLabels`, and **Swap CW / CCW Labels** in the right-click menu,
exchange what the two buttons *say*. Each keeps commanding the motor direction
it always did — their `Tag`s (`NanoMotorJogNeg`, `NanoMotorJogPos`) name that
direction, and so does `jog(±1)`, which a swap does not touch.

Where the setting comes from, most specific first:

1. `SwapDirectionLabels = true` at construction, or an assignment afterwards.
2. The choice last made from that menu, remembered **machine-wide** — and in
   `peripherals.NanoMotorControlGUI`'s preference group rather than this
   panel's per-tag one, since a gearbox is a fact about the bench and the two
   windows must not disagree about the same rig.
3. Otherwise the controller's own `OutputDirSign`, read by `connect()`, which
   is right whenever the firmware's gear configuration matches the hardware.

---

## The readout

The position comes from `POSD?` on the panel's own timer, 0.5 s by default
(`UpdatePeriod`), and **only while the link is open** and a `Status` or
`Position` section is on screen — a disconnected panel costs the controller no
serial traffic at all. `MOVE?` is asked for only while a move the panel sent
is believed to be still running; a jog is something the panel started itself,
so it needs no query to know about it.

Two failure modes are told apart. `NanoMotorControl:DeviceBusy` is the
firmware protecting its step timing (`SERQUIET`) and is reported as motion,
not as an error. Anything else counts: after three consecutive failures the
readout stops and says so, because each failure costs a serial timeout (2 s by
default) and a controller that has gone away would otherwise stall the GUI
once per period for as long as the window is open. The same message is logged
once, not once per tick.

---

## What reaches the data file

With a session behind it, every operator action here is written to
[`RUNTIME.NOTES`](gui_Notes.md) through `epsych.SessionNotes.log` — connect,
disconnect, each jog and its direction and speed, `STOP`, each move, and a
zero. A commutator turned mid-session is then in every subject's data file
rather than only in somebody's memory. The readout is not: a position polled
twice a second is not a note.

---

## See also

- [`peripherals.NanoMotorControl`](../peripherals/peripherals_NanoMotorControl.md) — the driver and its firmware
- [`gui.components.SyringePump`](gui_SyringePump.md) — the same shape for the reward pump
- [`gui.PopOut`](gui_PopOut.md), [`gui.components.ComponentToolbar`](gui_ComponentToolbar.md)
- [`gui.BehaviorGUI`](gui_BehaviorGUI.md) — `add`, and the component spec
