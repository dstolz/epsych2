# NanoMotorControl

`peripherals.NanoMotorControl` provides the serial interface for the Arduino Nano DM320T stepper controller, and `peripherals.NanoMotorControlGUI` adds a compact UI for jogging, speed control, and position moves.

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

## Notes

- Continuous commands operate in motor direction and motor RPM.
- `moveDeg` and `positionDeg` use output-shaft degrees derived from the configured gear ratio.
- `RunExpt.LaunchCommutatorGUI` now launches `peripherals.NanoMotorControlGUI` directly.