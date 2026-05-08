# stimgen.calibration

The `stimgen.calibration` package contains the calibration engine and hardware adapter layer used by stimulus calibration workflows.

Source package:

- `obj/+stimgen/+calibration/`

## Main Components

- `Engine.m`: calibration orchestration, result storage, save/load, and voltage lookup.
- `HwAdapter.m`: abstract adapter contract.
- `InterfaceAdapter.m`: adapter for `hw.Interface`-based hardware.
- `WindowsSoundCardAdapter.m`: adapter for Windows audio device workflows.
- `CalibrationGui.m`: UI wrapper around engine operations.

## Engine Summary

`stimgen.calibration.Engine` manages:

- microphone reference calibration (`calibrate_reference`)
- tone sweep calibration (`calibrate_tones`)
- click-duration calibration (`calibrate_clicks`)
- swept-sine transfer calibration (`calibrate_swept_sine`)
- equalization filter design (`design_filter`)
- adjusted voltage lookup (`compute_adjusted_voltage`)

It also tracks measurement diagnostics such as SNR, THD, harmonic content, and headroom statistics.

## CalibrationData Structure

`CalibrationData` is empty until a successful calibration run. On success, it contains structs for available calibration modes:

- `tone`
- `click`
- `sweptSine`
- `filter`
- `filterGrpDelay`

Each mode stores mode-specific vectors/tables (for example frequency or duration, measured values, SPL estimates, and required voltages).

## Adapters

### HwAdapter

Defines two required methods:

- `sample_rate()`
- `play_and_record(signal)`

### InterfaceAdapter

Wraps an `hw.Interface` and uses buffer/trigger parameters for play-record cycles.

### WindowsSoundCardAdapter

Provides a host-audio pathway for calibration when a direct hardware interface is not used.

## Typical Workflow

```matlab
adapter = stimgen.calibration.InterfaceAdapter(RUNTIME.HW);
eng = stimgen.calibration.Engine(adapter);

eng.calibrate_reference();
eng.calibrate_tones();
eng.calibrate_clicks();
eng.calibrate_swept_sine();
eng.design_filter();

eng.save('my_cal.esgc');
```

Offline lookup:

```matlab
eng = stimgen.calibration.Engine.load('my_cal.esgc');
V = eng.compute_adjusted_voltage("tone", 4000, 70);
```

## Integration Notes

- `stimgen.StimCalibration` and calibration UI tooling drive this engine.
- `stimgen.StimType.apply_calibration` consumes calibration results (including optional filter and delay compensation).

## Related Documentation

- `documentation/stimgen/stimgen_CalibrationGui.md`
- `documentation/stimgen/stimgen_SweptSineCalibration.md`
- `documentation/stimgen/stimgen_StimType.md`
