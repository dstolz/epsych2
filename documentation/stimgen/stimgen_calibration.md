# `stimgen.calibration` — Calibration Engine and Hardware Adapters

> **Package:** `obj/+stimgen/+calibration/`
> **Files:**
> - `HwAdapter.m` — abstract hardware contract
> - `InterfaceAdapter.m` — concrete adapter wrapping `hw.Interface`
> - `Engine.m` — calibration orchestrator, LUT builder, and file I/O
>
> **Related:** [stimgen_StimCalibration.md](stimgen_StimCalibration.md) — thin GUI controller that owns an `Engine`

---

## Overview

The `stimgen.calibration` package separates *what calibration does* from *how hardware I/O is performed*. Three classes work together:

```
stimgen.calibration.HwAdapter        (abstract)
        ↑
stimgen.calibration.InterfaceAdapter  wraps hw.Interface for live measurement
        │
        └── owned by ──→ stimgen.calibration.Engine
                                │
                                ↓
                       stimgen.StimCalibration   (thin GUI wrapper)
```

**`HwAdapter`** defines the minimal contract any hardware backend must fulfil: report a sample rate and exchange one signal with the hardware.

**`InterfaceAdapter`** implements that contract for the existing `hw.Interface` framework, resolving the five required `hw.Parameter` handles at construction time and failing immediately if any are missing.

**`Engine`** does the real work: reference measurement, frequency/duration sweeps, SPL-to-voltage LUT calculation, optional equalization filter design, and `.esgc` file save/load.

---

## Quick-start workflow

```matlab
% 1. Connect to hardware
adapter = stimgen.calibration.InterfaceAdapter(RUNTIME.HW);

% 2. Create and configure the engine
eng = stimgen.calibration.Engine(adapter);
eng.ReferenceFrequency = 1000;   % Hz — tone for reference measurement
eng.NormativeValue     = 80;     % dB SPL target for all stimuli
eng.ExcitationVoltage  = 1.0;    % V — drive level during sweeps

% 3. Measure mic sensitivity (place mic at acoustic reference source first)
eng.calibrate_reference();

% 4. Run tone and click sweeps
eng.calibrate_tones();   % default: 50-point log sweep 100 Hz → Nyquist
eng.calibrate_clicks();  % default: 8 durations, 1–128 samples

% 5. (Optional) Design equalization FIR
eng.design_filter();

% 6. Save
eng.save('C:\data\lab_cal_2026.esgc');

% --- Later, offline ---
eng = stimgen.calibration.Engine.load('C:\data\lab_cal_2026.esgc');
v   = eng.compute_adjusted_voltage("tone", 4000, 70);  % V to play 4 kHz at 70 dB SPL
```

The `stimgen.StimCalibration` GUI class wraps this workflow in a control panel. Use the Engine directly only when scripting or batch-calibrating.

---

## `stimgen.calibration.HwAdapter`

> **Source:** `obj/+stimgen/+calibration/HwAdapter.m`

An abstract `handle` class that defines the two-method contract required by `Engine`.

### Abstract methods

| Method | Signature | Purpose |
|--------|-----------|---------|
| `sample_rate` | `Fs = sample_rate(obj)` | Return hardware sample rate in Hz. |
| `play_and_record` | `response = play_and_record(obj, signal)` | Send `signal` (1-D double, pre-scaled) to the output channel and simultaneously record the microphone input. Return the response vector. |

### Implementing a custom adapter

Create a subclass to support hardware that is not driven through `hw.Interface`:

```matlab
classdef MyAdapter < stimgen.calibration.HwAdapter
    methods
        function Fs = sample_rate(obj)
            Fs = 48000;  % return your device's rate
        end

        function response = play_and_record(obj, signal)
            % write signal to DAC, read from ADC...
            response = myHardwareIO(signal);
        end
    end
end
```

Pass an instance of your adapter to `Engine`:

```matlab
eng = stimgen.calibration.Engine(MyAdapter());
```

---

## `stimgen.calibration.InterfaceAdapter`

> **Source:** `obj/+stimgen/+calibration/InterfaceAdapter.m`

The production adapter used in EPsych. Wraps a connected `hw.Interface` and handles the full play-and-record cycle.

### Hardware requirements

The `hw.Interface` passed to the constructor **must** expose these five named parameters. The adapter errors immediately at construction if any are missing ("fail-fast"):

| Parameter name | Direction | Type | Purpose |
|----------------|-----------|------|---------|
| `BufferSize` | Write | Integer | Number of samples to play and record. |
| `BufferOut` | Write | Buffer | Output waveform data written before triggering. |
| `x_Trigger` | Write | Boolean | Start pulse: set 1, then 0, to fire acquisition. |
| `BufferIndex` | Read | Integer | Acquisition progress counter (advances to `BufferSize` on completion). |
| `BufferIn` | Read | Buffer | Recorded microphone signal retrieved after completion. |

### Sample rate discovery

The adapter reads `Fs` from the first `hw.Module` in `hw.Interface.Module` that reports `Fs > 0`. If the circuit's sample rate is not reported through a module, supply it explicitly:

```matlab
adapter = stimgen.calibration.InterfaceAdapter(RUNTIME.HW, Fs=97656.25);
```

### Constructor

```matlab
adapter = stimgen.calibration.InterfaceAdapter(hwInterface)
adapter = stimgen.calibration.InterfaceAdapter(hwInterface, Fs=value)
```

| Argument | Type | Description |
|----------|------|-------------|
| `hwInterface` | `hw.Interface` | A connected interface exposing the five required parameters. |
| `Fs` | double (optional) | Override the auto-discovered sample rate. |

### `play_and_record`

```matlab
response = adapter.play_and_record(signal)
```

Execution sequence:
1. Write `numel(signal)` to `BufferSize`.
2. Write `signal` to `BufferOut`.
3. Pulse `x_Trigger` (1 → 10 ms pause → 0) to start hardware acquisition.
4. Poll `BufferIndex` every 10 ms until it reaches `numel(signal)` or the timeout (`signal_duration + 1 s`) expires.
5. Read `BufferIn` and return the first `numel(signal)` samples.

---

## `stimgen.calibration.Engine`

> **Source:** `obj/+stimgen/+calibration/Engine.m`

The calibration engine. Manages all measurement logic, the SPL/voltage math model, and file persistence.

### Properties

#### Calibration parameters (SetAccess=protected, SetObservable, AbortSet)

| Property | Default | Units | Description |
|----------|---------|-------|-------------|
| `MicSensitivity` | 1 | V/Pa | Microphone sensitivity. Set automatically by `calibrate_reference()`. |
| `ReferenceLevel` | 94 | dB SPL | Sound level at the reference source (typically a pistonphone). |
| `ReferenceFrequency` | 1000 | Hz | Tone frequency used for the reference measurement. |
| `NormativeValue` | 80 | dB SPL | The output level all stimuli will be normalized to. |
| `ExcitationVoltage` | 1 | V | Drive amplitude for all calibration signals. Keep ≤ 10 V. |
| `ShowLivePlots` | false | — | Enable per-step live signal and transfer plots during sweeps. |
| `CalibrationTimestamp` | `datetime("")` | — | Set automatically when a sweep completes. |

Properties are `SetAccess=protected` so they can only be changed through `StimCalibration.set_prop()` when the GUI is in use. Directly on an `Engine` object, assign them normally:

```matlab
eng.NormativeValue = 70;
```

#### Results (SetAccess=protected)

| Property | Type | Description |
|----------|------|-------------|
| `CalibrationData` | struct \| `[]` | Empty until a successful run; afterwards a struct (see [CalibrationData schema](#calibrationdata-schema)). |
| `Adapter` | `HwAdapter` \| `[]` | The hardware adapter. `[]` for offline engines loaded from file. |
| `ExcitationSignal` | double | The most recently played excitation waveform. |
| `ResponseSignal` | double | The most recently recorded microphone response (trimmed). |
| `ResponseTHD` | double | THD (dB) of the last recorded response. |

#### Dependent properties

| Property | Description |
|----------|-------------|
| `Fs` | Sample rate from `Adapter.sample_rate()`, or `0` if no adapter. |
| `IsCalibrated` | `true` when `CalibrationData` is a non-empty struct. |

---

### Methods

#### `calibrate_reference()`

```matlab
eng.calibrate_reference()
```

Plays a 1-second tone at `ReferenceFrequency` and measures the microphone output via `spectral_rms`. Updates `MicSensitivity` to `measured_V / dv` where `dv = 10^((ReferenceLevel - 94) / 20)`.

Place the microphone at the acoustic reference source (pistonphone or calibrator) before calling this.

---

#### `calibrate_tones(freqs)`

```matlab
eng.calibrate_tones()
eng.calibrate_tones([500 1000 2000 4000 8000 16000])
```

Sweeps through `freqs` (default: 50-point log sweep from 100 Hz to Nyquist), playing a 100 ms tone at each frequency. Measures SPL via `spectral_rms` and computes the output voltage required to reach `NormativeValue` dB SPL. Stores results in `CalibrationData.tone`.

If any step throws an error, any partial `tone` data is cleared and the exception is re-thrown. No partial results are retained.

---

#### `calibrate_clicks(durs)`

```matlab
eng.calibrate_clicks()
eng.calibrate_clicks([1 2 4 8 16] ./ Fs)
```

Sweeps through `durs` (default: 8 durations from 1 to 128 samples, expressed in seconds). Plays a single click per step and measures peak amplitude. Stores results in `CalibrationData.click`.

Same abort-on-error behavior as `calibrate_tones`.

---

#### `design_filter()`

```matlab
eng.design_filter()
```

Designs an arbitrary-magnitude FIR equalization filter from the completed tone LUT using `designfilt('arbmagfir', ...)`. The filter flattens the speaker's frequency response to produce a uniform sound level across frequency.

Stores:
- `CalibrationData.filter` — a `digitalFilter` object
- `CalibrationData.filterGrpDelay` — integer group-delay in samples (used by `StimType.apply_calibration` to compensate for the filter's latency)

After running, the filter object is placed in `ans` and a `fvtool` link is printed to the Command Window so you can inspect the response immediately.

Requires `calibrate_tones()` to have been run first.

---

#### `compute_adjusted_voltage(type, value, level)`

```matlab
v = eng.compute_adjusted_voltage("tone", 4000, 70)    % voltage for 4 kHz at 70 dB SPL
v = eng.compute_adjusted_voltage("click", 1/97000, 80) % voltage for 1-sample click at 80 dB SPL
```

Interpolates the LUT at the requested `value` using `makima`, then scales to `level`:

$$v = v_\text{norm} \cdot 10^{(\text{level} - \text{NormativeValue}) / 20}$$

| Argument | Type | Description |
|----------|------|-------------|
| `type` | `"tone"` \| `"click"` | Which LUT to use. |
| `value` | double | Frequency (Hz) for `"tone"`; duration (s) for `"click"`. |
| `level` | double | Target sound level in dB SPL. |

Returns `v` — the output voltage in volts. Errors if `IsCalibrated` is false.

---

#### `save(ffn)` and `Engine.load(ffn)`

```matlab
eng.save()                    % prompts for file path
eng.save('path\cal.esgc')     % save to specified path

eng = stimgen.calibration.Engine.load()          % prompts
eng = stimgen.calibration.Engine.load('cal.esgc')
```

Files are saved in MATLAB's binary MAT format with a `.esgc` extension ("EPsych Stim Gain Calibration"). Old `.sgc` files from previous EPsych versions are **not** supported — recalibrate and save a new `.esgc`.

The loaded engine has no adapter attached and is suitable for offline `compute_adjusted_voltage` use. To run new calibrations after loading, assign an adapter:

```matlab
eng = stimgen.calibration.Engine.load('cal.esgc');
eng.Adapter = stimgen.calibration.InterfaceAdapter(RUNTIME.HW);
eng.calibrate_tones();   % re-calibrate tones, keeps loaded click data
```

---

### CalibrationData schema

`CalibrationData` is `[]` until a successful sweep, then a struct:

```
CalibrationData
  .tone
    .frequency     (Nx1 double)  Hz
    .measurement   (Nx1 double)  microphone voltage (V)
    .spl_db        (Nx1 double)  measured dB SPL per frequency
    .voltage       (Nx1 double)  output voltage to reach NormativeValue SPL
  .click
    .duration      (Nx1 double)  seconds
    .measurement   (Nx1 double)  peak microphone voltage (V)
    .spl_db        (Nx1 double)  measured dB SPL per duration
    .voltage       (Nx1 double)  output voltage to reach NormativeValue SPL
  .filter          digitalFilter | []   (populated by design_filter)
  .filterGrpDelay  int                  (samples; 0 until design_filter runs)
```

`tone` and `click` are populated independently. You can run one without the other. `design_filter` requires `tone`.

---

### SPL/voltage math model

The same formula is used for both tone and click measurements:

1. **RMS conversion** (peak mode only): $m_\text{rms} = m_\text{peak} / \sqrt{2}$. Spectral and RMS modes use the measured value directly.
2. **dB SPL**: $\text{SPL} = 20 \log_{10}(m_\text{rms} / \text{MicSensitivity}) + \text{ReferenceLevel}$
3. **Normative voltage**: $v = \text{ExcitationVoltage} \cdot 10^{(\text{NormativeValue} - \text{SPL}) / 20}$

This normative voltage is what gets stored in the LUT and interpolated by `compute_adjusted_voltage`.

---

### Live plots

Set `ShowLivePlots = true` before a sweep to see real-time signal and transfer function figures:

```matlab
eng.ShowLivePlots = true;
eng.calibrate_tones();
```

Three named figures are used: `'signal'` (time-domain + power spectrum) and `'transfer'` (SPL vs frequency or duration). Call `eng.plot_reset()` to clear them.

---

## Error handling

All errors from the calibration package use structured error IDs of the form `stimgen:calibration:<ClassName>:<type>`, e.g.:

```
stimgen:calibration:Engine:notCalibrated
stimgen:calibration:InterfaceAdapter:missingParameter
stimgen:calibration:InterfaceAdapter:noSampleRate
```

This makes it straightforward to catch specific failure modes:

```matlab
try
    eng.calibrate_tones();
catch ME
    if strcmp(ME.identifier, 'stimgen:calibration:Engine:noAdapter')
        % handle missing adapter
    else
        rethrow(ME);
    end
end
```

---

## See also

- [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md) — standalone interactive GUI for the calibration package
- [stimgen_StimCalibration.md](stimgen_StimCalibration.md) — GUI wrapper that owns the Engine
- [stimgen_StimType.md](stimgen_StimType.md) — `apply_calibration()` uses `compute_adjusted_voltage` at stimulus generation time
- [hw_Interface.md](../hw/hw_Interface.md) — the `hw.Interface` base class that `InterfaceAdapter` wraps
- [hw_Module.md](../hw/hw_Module.md) — `hw.Module.Fs` used for sample rate discovery
