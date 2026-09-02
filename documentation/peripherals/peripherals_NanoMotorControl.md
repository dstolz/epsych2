# NanoMotorControl

`peripherals.NanoMotorControl` provides the serial interface for the Arduino Nano DM320T stepper controller, and `peripherals.NanoMotorControlGUI` adds a compact UI for jogging, speed control, and position moves.

For a rig that wants those controls **inside** its behavior GUI rather than in
a window of their own, [`gui.components.NanoMotor`](../gui/gui_NanoMotor.md) is
the same panel as a component: half the height, every row hideable, a pop-out
(or a single button that opens one), and — the reason it exists — it opens no
serial port until the operator presses Connect.

## Overview

The controller class wraps the sketch's newline-terminated serial protocol and exposes synchronous command helpers for connect, enable, speed, movement, and position/status queries.

The GUI class builds a small `uifigure`-based panel around the same controller so the commutator can be driven interactively without writing a script.

## Constructors

```matlab
motor = peripherals.NanoMotorControl(Port="COM6", AutoDetect=true)
gui = peripherals.NanoMotorControlGUI(Port="COM6")
```

Key name-value options:

- `Port`: serial port identifier such as `"COM6"`
- `AutoDetect`: whether to scan available ports when the preferred port is unavailable
- `Verbosity`: controller logging level
- `UpdatePeriod`: GUI polling interval in seconds
- `SwapDirectionLabels`: exchange the GUI's CW and CCW jog labels (see below)

## Example

```matlab
motor = peripherals.NanoMotorControl(Port="COM6", AutoDetect=true);
motor.connect();
motor.mode("USB");
motor.enable(true);
motor.moveDeg(90, 120);
positionDeg = motor.positionDeg();
motor.stop();
motor.disconnect();

gui = peripherals.NanoMotorControlGUI(Port="COM6");
```

## Firmware

The sketch is `obj/+peripherals/@NanoMotorControl/sketch_NanoMotorControl/`, and there
is **one** of it: the Arduino IDE concatenates every `.ino` in a sketch folder, so a
second variant beside it does not build. Two rules in it exist because of this class,
and both were once broken:

- **Floats are rendered with `dtostrf`, never `%f`.** The Arduino AVR core links
  avr-libc's integer-only `vfprintf`, which emits a bare `?` for a float conversion
  and consumes the argument. A sketch that formats `POSD`/`STATUS` with
  `snprintf("%.6f", ...)` therefore answers `POSD ?`, and every `positionDeg()` --
  including the GUI's 4 Hz poll -- raises `NanoMotorControl:ParseError`.
- **`SERQUIET` defaults to 0.** With it on, the firmware answers `BUSY` to
  `POS?`/`POSD?`/`STATUS?`/`MOVE?`/`GEAR?`/`HELP` while the motor is moving, so serial
  traffic cannot disturb step timing. That is the opposite of what a polling host
  wants, so `connect()` sends `SERQUIET 0` (`DisableSerialQuietOnConnect`, tolerant of
  firmware that predates the command). Ask for it with `setSerialQuiet(true)` when
  timing beats telemetry; queries then raise `NanoMotorControl:DeviceBusy`, which is
  a distinct identifier so a caller can retry rather than treat it as a bad reply.

Replies are formatted directly into the outbound queue with PROGMEM format strings,
which is what keeps a board with 2 KB of RAM clear of its stack.

`tmp/smoke_test_nanomotor_protocol.m` is the standing proof, run against canned
replies through `tmp/NanoMotorControl_Mock` -- no Nano attached.

## Which way is CW?

Jog (`DIR`/`SPD`/`RPM`) commands the **motor**, while `moveDeg` and `positionDeg` are
output-shaft degrees the firmware already corrects with its gear `OutputDirSign`. On a
drive that reverses, the jog buttons are therefore the half that reads backwards -- the
button marked CW turns the commutator counter-clockwise, and nothing else in the GUI is
wrong.

`NanoMotorControlGUI` fixes that end rather than the wiring. **NanoMotor > Direction >
Swap CW / CCW labels** exchanges the two labels, their rotation icons, their tooltips and
the "Jogging CCW @ ..." status line. Each button keeps commanding the motor direction it
always did: a swap changes what the panel *says*, never what it sends, and `MOVE` and the
position readout are untouched.

Where the setting comes from, most specific first:

1. `peripherals.NanoMotorControlGUI(SwapDirectionLabels=true)`, or an assignment to the
   property afterwards.
2. The choice last made from that menu, remembered per machine (`setpref`), since a
   gearbox is a fact about the bench rather than about one session.
3. Otherwise the controller's own `OutputDirSign`, read by `connect()`, which is right
   whenever the firmware's gear configuration matches the hardware.

The circular-arrow icon on each jog button is drawn by the class rather than shipped as
an image file, for the same reason as `gui.toolbarIcon`'s glyphs. Its soft edge is
blended against the button it sits on, so it is redrawn when a button turns green for an
active jog.

## Notes

- Continuous commands operate in motor direction and motor RPM.
- `moveDeg` and `positionDeg` use output-shaft degrees derived from the configured gear ratio.
- `RunExpt.LaunchCommutatorGUI` now launches `peripherals.NanoMotorControlGUI` directly.
- `enableQuery` returns two values: `[permitted, actual]`. The firmware answers
  `EN <permitted> ACTUAL <driverEnabled>`, and the two differ because the driver
  auto-enables only around motion.
- [`gui.components.NanoMotor`](../gui/gui_NanoMotor.md) is the embeddable panel.
  It shares the label-swap preference with this window, so flipping CW/CCW in
  either place settles it for the bench; unlike this window it never connects
  on its own.
