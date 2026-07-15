# `stimgen.StimCalibration`

`stimgen.StimCalibration` is the calibration controller that stimulus objects talk to. Since the calibration refactor it is a thin wrapper around the `stimgen.calibration` package: [stimgen.calibration.Engine](stimgen_calibration.md) does the measurement and lookup work, and an adapter handles hardware I/O. The wrapper exists so `stimgen.StimType` keeps working unchanged.

This is a developer reference. If you just want to calibrate a rig, follow [stimgen_calibration.md](stimgen_calibration.md).

Source class:

- [obj/+stimgen/@StimCalibration/StimCalibration.m](../../obj/+stimgen/@StimCalibration/StimCalibration.m)

## Two construction modes

### Offline mode

```matlab
cal = stimgen.StimCalibration();
cal.load_calibration('Rig3_earphone.esgc');
```

Without arguments the object holds an offline `Engine`. Load a saved `.esgc` file and attach the object to stimuli; no hardware is required.

### Online (measurement) mode

```matlab
cal = stimgen.StimCalibration(RUNTIME);
```

With a runtime, the constructor builds a `stimgen.calibration.InterfaceAdapter` around the runtime's hardware and launches the calibration GUI so a new calibration can be measured.

## Delegated properties

These proxy directly to the underlying `Engine`:

- `CalibrationData`
- `MicSensitivity`
- `ReferenceLevel`
- `ReferenceFrequency`
- `NormativeValue`
- `ExcitationSignalVoltage`
- `CalibrationTimestamp`

## Key methods

- `gui()` — launch the calibration GUI (`stimgen.calibration.CalibrationGui`).
- `compute_adjusted_voltage(...)` — proxy to the Engine; called by `stimgen.StimType.apply_calibration()` to convert a requested dB SPL level into an output voltage.
- `load_calibration(filename)` / `save_calibration(filename)` — read/write `.esgc` files (legacy `.sgc` files can still be loaded).

## Attaching calibration to stimuli

```matlab
tone = stimgen.Tone;
tone.Frequency = 4000;
tone.SoundLevel = 60;
tone.Calibration = cal;      % also settable via StimPlay/StimPlayer
tone.ApplyCalibration = true;
tone.update_signal();
```

Assigning `Calibration` on a `stimgen.StimPlay` wrapper forwards the object to the wrapped stimulus; `stimgen.StimPlayer` exposes the same through its **File > Calibration** menu.

## Caveats for developers

- Calibration behavior is coupled to the `CalibrationType` constant on each stimulus class; adding a new calibration mode usually requires coordinated changes in the `stimgen.calibration` package and `StimType.apply_calibration()`.
- The `CalibrationData` schema is defined by the Engine (see [stimgen_calibration.md](stimgen_calibration.md) for the structure reference).

## Related documentation

- [stimgen_calibration.md](stimgen_calibration.md) — calibration concepts, GUI walkthrough, programmatic workflow, and data structure reference
- [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md) — GUI reference
- [stimgen_SweptSineCalibration.md](stimgen_SweptSineCalibration.md) — swept-sine method
- [stimgen_StimType.md](stimgen_StimType.md) — how stimuli consume calibration
