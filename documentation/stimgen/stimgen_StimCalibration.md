# `stimgen.StimCalibration`

`stimgen.StimCalibration` is the calibration manager for the `stimgen`
package.

It measures the response of the playback chain, stores lookup data in a form
the stimulus classes can reuse, and saves or loads calibration files with the
`.sgc` extension.

## What the class is responsible for

This class handles three related jobs:

- measuring a reference so microphone sensitivity is known
- measuring stimulus-response data for tone and click calibration
- converting requested output levels into hardware voltages later during
  stimulus generation

It is the bridge between acoustic measurements and the `ApplyCalibration`
logic inside `stimgen.StimType`.

## Creating a calibration object

The normal entry point is:

```matlab
cal = stimgen.StimCalibration(RUNTIME);
```

When constructed with a runtime, the class:

- caches the runtime object
- indexes hardware parameters into `PARAMS`
- reads the hardware sample rate from `RUNTIME.HW.HW.FS`
- opens the calibration GUI

You can also load previously saved calibration data from a `.sgc` file using
the GUI menu commands or the load helpers in the class.

## Main properties

The most important editable calibration settings are:

- `ReferenceLevel`: reference calibrator level in dB SPL
- `ReferenceFrequency`: frequency used during reference measurement
- `MicSensitivity`: microphone sensitivity in V/Pa
- `CalibrationMode`: `"rms"`, `"peak"`, or `"specfreq"`
- `NormativeValue`: target reference level used when deriving voltage
  corrections
- `ExcitationSignalVoltage`: playback voltage used during calibration runs

The key stored outputs are:

- `CalibrationData`
- `CalibrationTimestamp`
- `ResponseTHD`

## Workflow

### 1. Measure the reference

The `REFERENCE` state drives a reference-tone measurement so the class can
estimate microphone sensitivity from a known acoustic reference.

### 2. Run calibration

The `CALIBRATE` state measures the response for the active calibration target
and stores the results in `CalibrationData`.

Built-in routines include:

- `calibrate_tones(freqs)`
- `calibrate_clicks(clickdur)`

The GUI wraps these steps and updates the plots as measurements are taken.

### 3. Save the result

Use `save_calibration()` or the GUI `File` menu to store the current object as
a `.sgc` file.

### 4. Attach it to stimuli or playback controllers

```matlab
cal = stimgen.StimCalibration(RUNTIME);
sg  = stimgen.StimGenInterface(RUNTIME);

sg.Calibration = cal;
```

You can also attach the same object directly to a single stimulus:

```matlab
tone = stimgen.Tone('Frequency', 4000, 'SoundLevel', 60);
tone.Calibration = cal;
tone.update_signal();
```

## How the data are used later

`stimgen.StimType.apply_calibration()` calls
`compute_adjusted_voltage(type, value, level)` to convert stimulus parameters
into an output voltage.

The exact lookup path depends on `CalibrationType`.

- Tone-like stimuli look up voltage against a frequency axis.
- Click stimuli look up voltage against click duration.
- Filter-based calibration adds equalization and group-delay compensation for
  noise-like signals.

`create_arbmag()` builds the arbitrary-magnitude filter used for the filter
path and stores both the filter and its group delay in `CalibrationData`.

## File format and persistence

The GUI save/load helpers use the `.sgc` extension and store the calibration
object in MATLAB `.mat` form.

Relevant methods:

- `save_calibration()`
- `load_calibration()`
- `toStruct()`

This makes calibration objects easy to reuse across interfaces such as
`StimGenInterface` and `StimPlayer`.

## Runtime expectations

`StimCalibration` is not a generic offline calibration library. The active
runtime must expose the hardware parameters needed for the measurement path,
and the sample rate comes from the runtime hardware object.

If the runtime does not match the expected stimgen circuit, the GUI may open,
but the calibration run itself will fail when it tries to write buffers or
read responses.

## Caveats for developers

- Calibration behavior is coupled to the `CalibrationType` constant on each
  stimulus class.
- Adding a new calibration mode usually requires coordinated changes in both
  `StimCalibration` and `StimType.apply_calibration()`.
- `CalibrationData` is intentionally flexible, but that also means its schema
  is defined by code convention rather than a strict validator.

## Related files

- `obj/+stimgen/@StimCalibration/StimCalibration.m`
- `obj/+stimgen/@StimCalibration/gui.m`
- `obj/+stimgen/@StimCalibration/calibrate_tones.m`
- `obj/+stimgen/@StimCalibration/calibrate_clicks.m`
- `obj/+stimgen/@StimCalibration/compute_adjusted_voltage.m`
- `obj/+stimgen/@StimCalibration/create_arbmag.m`
- `obj/+stimgen/StimType.m`