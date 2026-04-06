# PumpCom

`peripherals.PumpCom` provides the serial interface used to control a syringe pump for reward delivery.

## Overview

The class opens a `serialport` connection, configures the pump for infusion mode, and keeps a small set of pump settings synchronized with MATLAB properties. Observable property changes are forwarded to the device automatically through property listeners.

The class also exposes lightweight GUI helpers for:

- monitoring dispensed volume
- adjusting pump rate from a numeric edit field

## Constructor

```matlab
pump = peripherals.PumpCom(RUNTIME, "COM4", 19200)
```

Parameters:

- `RUNTIME`: runtime object whose `mode` listener is used to close the pump connection when online operation stops
- `Port`: serial port identifier such as `"COM4"`
- `BaudRate`: serial baud rate, typically `19200`

## Key Properties

- `PumpRate`: infusion rate value sent with the `RAT` command
- `PumpUnits`: two-character pump rate units such as `"MM"` for mL/min
- `PumpOperationalTrigger`: trigger mode code such as `"LE"`
- `SyringeDiameter`: syringe inner diameter in mm
- `VolumeDispensed`: dependent property that queries the pump for dispensed volume
- `PumpFirmwareVersion`: dependent property that queries the pump firmware string

## Example

```matlab
pump = peripherals.PumpCom(RUNTIME, "COM4", 19200);
pump.SyringeDiameter = 21.69;
pump.PumpRate = 0.50;
pump.create_gui();
```

## Notes

- The GUI refresh timer is tagged `PumpComTimer`.
- `create_gui` creates a new `uifigure` when no parent is supplied.
- The serial connection is closed when the runtime mode transitions below online mode.
