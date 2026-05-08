# stimgen.calibration

## What Is Calibration And Why Do You Need It

Calibration measures the relationship between the voltage your hardware outputs and the actual sound pressure level (SPL) it produces at the speaker or earphone. Without calibration, there is no reliable way to know what level a stimulus will be in dB SPL.

The result of a calibration session is a `.esgc` file. When your experiment loads that file, the software automatically scales stimulus voltages so that tones, clicks, or other signals are delivered at the levels you request.

## What You Need Before Starting

### Hardware

- A **measurement microphone** positioned at the location where sound levels matter (e.g. at the animal's ear, or inside a sound delivery tube).
- A **calibration source** (pistonphone or sound level calibrator) that produces a known SPL at a known frequency — most commonly 94 dB SPL at 1000 Hz. This is used to measure how sensitive your microphone is.
- The **speaker or earphone** you will use in experiments, connected to your data acquisition hardware and driven through the same amplifier chain you use experimentally.

### Software

- If using TDT or similar hardware: an epsych **protocol file** (`.eprot`) that includes the calibration-capable hardware interface. See [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md) for exact interface requirements.
- If using a Windows sound card: no protocol file is needed — use `WindowsSoundCardAdapter` directly.

---

## Workflow 1: GUI (Recommended For New Users)

The calibration GUI is the easiest starting point. It walks you through each step interactively.

### Step 1 — Open the GUI

In the MATLAB command window:

```matlab
stimgen.calibration.CalibrationGui()
```

The GUI opens. All calibration buttons will be disabled until hardware is connected.

### Step 2 — Connect Hardware

In the GUI menu: **File > Initialize Runtime From Protocol...**

Select your `.eprot` protocol file. The GUI will connect to the hardware interface defined in that file and attempt to attach a calibration adapter automatically.

When successful, the status bar at the bottom of the GUI will say something like *"Adapter attached. Ready for live calibration."* and the calibration buttons will become active.

If the buttons stay disabled, the protocol does not meet the hardware requirements — see [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md) for troubleshooting.

> **No protocol file?** If you are using a Windows sound card, see [Workflow 2](#workflow-2-programmatic) below. The GUI currently does not support `WindowsSoundCardAdapter` through the menu; use the programmatic path instead.

### Step 3 — Set Parameters

Before measuring, fill in the fields on the left side of the GUI:

| Field | What it means | Typical value |
|---|---|---|
| Reference Level | SPL your calibrator produces | 94 dB |
| Reference Frequency | Frequency your calibrator uses | 1000 Hz |
| Mic Sensitivity | Will be measured automatically in the next step | leave as-is |
| Normative Level | Target SPL your system should be calibrated to reach | 80 dB |
| Excitation Voltage | Voltage amplitude used during calibration sweeps | 1 V |

### Step 4 — Measure Reference

Place the calibrator on the microphone and turn it on.

Click **Measure Reference**. The software plays a tone at the reference frequency, records the microphone output, and computes the microphone sensitivity (V/Pa). The *Mic Sensitivity* field will update automatically.

Remove the calibrator after this step and position the microphone at your experimental measurement point.

### Step 5 — Calibrate Tones

Click **Calibrate Tones**. A dialog will ask for:

- **Frequency vector** — the frequencies to sweep (e.g. `logspace(2, 4, 50)` for 50 points from 100 Hz to 10 kHz). Leave blank for the default 50-point log sweep to Nyquist.
- **Repeat count** — how many measurements to average per frequency (default 1; use 3–5 for noisy environments).

The sweep runs automatically. Progress is shown in the MATLAB command window. A transfer curve appears on the right plot when complete.

### Step 6 — Optional Additional Calibrations

These are not required for basic tone delivery but improve accuracy for specialized stimuli:

- **Calibrate Clicks** — sweep across click durations. Dialog collects a duration vector and repeat count.
- **Calibrate Swept Sine** — broadband transfer function measurement. Dialog collects chirp duration and repeat count.
- **Design Filter** — designs an equalization FIR filter from the tone LUT. Requires tone calibration to have already completed.

### Step 7 — Save

**File > Save .esgc** — save the calibration to disk. Use a descriptive filename that identifies the rig and date, e.g. `Rig3_earphone_2026-05-08.esgc`.

---

## Workflow 2: Programmatic

Use this path when you want to script calibration, run it headlessly, or use a Windows sound card.

### Step 1 — Create An Adapter

Choose the adapter that matches your hardware:

**Windows sound card** (simplest — no epsych hardware interface needed):

```matlab
adapter = stimgen.calibration.WindowsSoundCardAdapter( ...
    SampleRate=48000, ...   % must match your device's native rate
    Device="", ...          % empty string uses the system default device
    InputChannel=1);        % microphone input channel index
```

**TDT/hardware interface** (when you have an `hw.Interface` object, e.g. from a loaded protocol):

```matlab
protocol = epsych.Protocol.load('MyProtocol.eprot');
protocol.Interfaces(1).connect();
adapter = stimgen.calibration.InterfaceAdapter(protocol.Interfaces(1));
```

### Step 2 — Create An Engine

```matlab
eng = stimgen.calibration.Engine(adapter);
```

### Step 3 — Configure The Engine

Set parameters before running any measurements. All parameters have defaults; only change what differs from the defaults:

```matlab
eng.set_configuration( ...
    ReferenceLevel=94, ...      % dB SPL your calibrator produces (default 94)
    ReferenceFrequency=1000, ...% Hz (default 1000)
    NormativeValue=80, ...      % target SPL for the experiment (default 80)
    ExcitationVoltage=1, ...    % volts; reduce if clipping warnings appear (default 1)
    ShowLivePlots=true);        % show plots during sweeps (default false)
```

### Step 4 — Measure The Microphone Reference

Place the calibrator on the microphone and turn it on, then:

```matlab
eng.calibrate_reference();
```

This plays a tone at `ReferenceFrequency` and uses the recorded level plus `ReferenceLevel` to compute `MicSensitivity`. Remove the calibrator after this step.

### Step 5 — Calibrate Tones

```matlab
% Default: 50-point log sweep from 100 Hz to Nyquist, 1 average per point:
eng.calibrate_tones();

% Custom frequency vector, 3 averages per point:
freqs = logspace(log10(500), log10(20000), 40);
eng.calibrate_tones(freqs, 3);
```

### Step 6 — Optional Additional Calibrations

```matlab
% Click calibration (sweep over durations in seconds):
durs = [0.05 0.1 0.2 0.5 1.0] ./ 1000;  % 50 µs to 1 ms
eng.calibrate_clicks(durs, 3);

% Swept-sine (broadband transfer function, 1-second chirp, 4 averages):
eng.calibrate_swept_sine(1, [], 4);

% Equalization filter design (requires tone calibration):
eng.design_filter();
```

### Step 7 — Save

```matlab
eng.save('Rig3_earphone_2026-05-08.esgc');
```

---

## Using Calibration Data In Experiments

Load the `.esgc` file and ask the engine what voltage to use for a given stimulus:

```matlab
eng = stimgen.calibration.Engine.load('Rig3_earphone_2026-05-08.esgc');

% Voltage needed to produce a 4 kHz tone at 70 dB SPL:
V = eng.compute_adjusted_voltage("tone", 4000, 70);

% Voltage for a 0.1 ms click at 80 dB SPL:
V = eng.compute_adjusted_voltage("click", 0.0001, 80);
```

In practice, `stimgen.StimType.apply_calibration` calls this for you when a `.esgc` file is assigned to a stimulus generator — you do not need to call it manually during an experiment.

---

## Reference: Engine Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `MicSensitivity` | 1 V/Pa | Updated by `calibrate_reference`; can also be set manually if known |
| `ReferenceLevel` | 94 dB | SPL produced by your calibrator |
| `ReferenceFrequency` | 1000 Hz | Frequency used by your calibrator |
| `NormativeValue` | 80 dB | Target SPL for the voltage lookup table |
| `ExcitationVoltage` | 1 V | Amplitude of signals played during calibration sweeps |
| `ShowLivePlots` | false | Show waveform and spectrum plots during sweeps |

---

## Reference: CalibrationData Structure

`eng.CalibrationData` is empty (`[]`) until a successful run completes. After a run it is a struct with these fields:

| Field | Populated by | Contents |
|---|---|---|
| `tone` | `calibrate_tones` | frequency, measurement, spl_db, voltage (Nx1); metrics sub-struct |
| `click` | `calibrate_clicks` | duration, measurement, spl_db, voltage (Nx1); metrics sub-struct |
| `swept_sine` | `calibrate_swept_sine` | frequency, measurement, spl_db, voltage (Nx1); metrics sub-struct |
| `filter` | `design_filter` | `digitalFilter` object, or `[]` |
| `filterGrpDelay` | `design_filter` | filter group delay in samples (0 until filter is designed) |

The `metrics` sub-struct in `tone` and `swept_sine` contains per-frequency diagnostics: `noise_floor_db`, `snr_db`, `thd_db`, `h2_db`, `h3_db`, `repeatability`, and `clipping_headroom`.

---

## Reference: Package Components

Source: `obj/+stimgen/+calibration/`

- `Engine.m` — calibration orchestration, result storage, save/load, and voltage lookup.
- `HwAdapter.m` — abstract base class defining the adapter contract (`sample_rate`, `play_and_record`).
- `InterfaceAdapter.m` — concrete adapter wrapping an `hw.Interface` (TDT and similar hardware).
- `WindowsSoundCardAdapter.m` — concrete adapter using Windows Audio Toolbox (`audioPlayerRecorder`).
- `CalibrationGui.m` — interactive GUI wrapper around all engine operations.

---

## Related Documentation

- [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md) — GUI reference, protocol compatibility requirements, and error troubleshooting
- [stimgen_SweptSineCalibration.md](stimgen_SweptSineCalibration.md) — swept-sine calibration details
- [stimgen_StimType.md](stimgen_StimType.md) — how calibration is applied during stimulus generation
