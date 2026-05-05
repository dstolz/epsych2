# `stimgen.calibration.CalibrationGui` — Interactive Calibration GUI

> **Source file:** `obj/+stimgen/+calibration/CalibrationGui.m`  
> **Related:** [stimgen_calibration.md](stimgen_calibration.md) — Engine, HwAdapter, InterfaceAdapter reference

`CalibrationGui` provides a point-and-click interface for running, inspecting, and persisting speaker calibrations. It owns a `stimgen.calibration.Engine` and exposes all of its configurable parameters as editable fields, while showing live signal and spectral plots after every measurement step.

---

## Contents

- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Window layout](#window-layout)
  - [Controls panel (left)](#controls-panel-left)
  - [Visualization panel (right)](#visualization-panel-right)
- [API reference](#api-reference)
  - [Constructor](#constructor)
  - [show](#show)
  - [set_adapter](#set_adapter)
- [Workflow walkthrough](#workflow-walkthrough)
- [Button enable/disable rules](#buttenenable--disable-rules)
- [Status bar](#status-bar)
- [Error handling](#error-handling)
- [See also](#see-also)

---

## Requirements

- MATLAB R2024b (uses `uifigure`, `uigridlayout`, `uiaxes`; `arguments` blocks)
- Signal Processing Toolbox (`periodogram`, `flattopwin`)
- A connected `hw.Interface` if running live calibration — not needed for load/inspect

---

## Quick start

**With live hardware:**

```matlab
adapter = stimgen.calibration.InterfaceAdapter(RUNTIME.HW);
gui = stimgen.calibration.CalibrationGui(Adapter=adapter);
```

**Offline — inspect or re-plot an existing `.esgc` file:**

```matlab
gui = stimgen.calibration.CalibrationGui();
% then click "Load .esgc" in the GUI
```

**With an already-configured Engine:**

```matlab
eng = stimgen.calibration.Engine(adapter);
eng.NormativeValue = 70;
gui = stimgen.calibration.CalibrationGui(Engine=eng);
```

---

## Window layout

The GUI is a 1320 × 760 `uifigure` split into two panels.

### Controls panel (left)

| Row | Control | Purpose |
|-----|---------|---------|
| 1 | Reference Level (dB SPL) | Acoustic level of the calibration reference source — usually 94 dB for a pistonphone. |
| 2 | Reference Frequency (Hz) | Frequency of the reference tone (usually 1000 Hz). |
| 3 | Mic Sensitivity (V/Pa) | Automatically filled after "Measure Reference". Can be set manually when the sensitivity is known. |
| 4 | Normative Value (dB SPL) | Target SPL all calibrated stimuli will be normalized to. |
| 5 | Excitation Voltage (V) | Drive amplitude used during all calibration sweeps (≤ 10 V). |
| 6 | Show Engine Live Plots | When checked, the `Engine` plots each step in separate figures during a sweep. |
| 7–8 | Tone Frequencies (Hz) | Optional comma/space-separated list of frequencies. Leave at the placeholder text to use the default 50-point log sweep. |
| 9 | Click Durations (s) | Optional list of click durations in seconds. Leave at placeholder to use the 8-point default. |
| 10 | **Measure Reference** | Plays a reference tone and computes mic sensitivity. |
| 11 | **Calibrate Tones** | Runs the frequency sweep and builds the tone LUT. |
| 12 | **Calibrate Clicks** | Runs the duration sweep and builds the click LUT. |
| 13 | **Design Filter** | Designs an equalization FIR from the tone LUT. Requires tone data. |
| 14 | **Load / Save .esgc** | Load an existing calibration file or save the current one. |
| 15 | Status bar | One-line feedback about the last action. Shown in red on error. |

### Visualization panel (right)

| Plot | Content |
|------|---------|
| **Temporal Response** (top-left) | The most recently recorded microphone waveform plotted against time. Updated after every calibration step. |
| **Spectral Response** (top-right) | Power spectrum (periodogram with flat-top window) of the same response. Log-log axes. |
| **Calibration Transfer Curves** (bottom, full width) | dB SPL vs frequency for the tone table (blue circles, log x-axis) and dB SPL vs duration (µs) for the click table (red squares). Both series are shown together when both tables are populated. |

---

## API reference

### Constructor

```matlab
gui = stimgen.calibration.CalibrationGui()
gui = stimgen.calibration.CalibrationGui(Adapter=adapter)
gui = stimgen.calibration.CalibrationGui(Engine=eng)
```

| Argument | Type | Description |
|----------|------|-------------|
| `Adapter` | `stimgen.calibration.HwAdapter` (optional) | Attach a hardware adapter for live calibration. If omitted, hardware-dependent buttons are disabled. |
| `Engine` | `stimgen.calibration.Engine` (optional) | Provide a pre-configured Engine (e.g. with custom parameters already set, or loaded from a file). If both `Adapter` and `Engine` are supplied, `Engine` takes precedence and the adapter is ignored. |

The constructor builds the figure, syncs all controls to the Engine's current values, draws any existing calibration data, and returns immediately. The GUI window opens in the foreground.

---

### show

```matlab
gui.show()
```

Brings the GUI window to the foreground. Safe to call at any time; no-op if the figure has been closed.

---

### set_adapter

```matlab
gui.set_adapter(adapter)
```

Attaches (or replaces) the hardware adapter after the GUI has been created. Useful when hardware connects asynchronously after the GUI is opened. Enables the hardware-dependent buttons and shows a status message.

```matlab
gui = stimgen.calibration.CalibrationGui();   % open offline
% ... hardware connects later ...
adapter = stimgen.calibration.InterfaceAdapter(RUNTIME.HW);
gui.set_adapter(adapter);
```

---

## Workflow walkthrough

A typical first-time calibration session:

1. **Open the GUI** with an adapter attached.
2. **Set Reference Level** to match your calibration source (typically 94 dB SPL).
3. **Set Reference Frequency** to match your source's tone (typically 1000 Hz).
4. Place the microphone at the calibration source. Click **Measure Reference**.
   - The Mic Sensitivity field updates automatically.
   - The Temporal and Spectral plots show the captured reference signal.
5. Move the microphone to the speaker under test. Click **Calibrate Tones**.
   - Leave the Tone Frequencies area at its placeholder text for the 50-point default sweep.
   - The Transfer Curves plot shows measured SPL vs frequency as the sweep runs (if Show Engine Live Plots is checked; otherwise the plot appears when the sweep finishes).
6. Click **Calibrate Clicks** to sweep click durations.
7. Optionally click **Design Filter** to generate an equalization FIR from the tone data.
8. Click **Save .esgc** to persist the calibration.

To re-run only tones after adjusting the speaker: click **Calibrate Tones** again. Existing click data is preserved.

---

## Button enable/disable rules

The GUI enforces a dependency order automatically:

| Button | Enabled when |
|--------|-------------|
| Measure Reference | An adapter is attached (`Engine.Adapter` is non-empty). |
| Calibrate Tones | An adapter is attached. |
| Calibrate Clicks | An adapter is attached. |
| Design Filter | `Engine.IsCalibrated` is `true` **and** `CalibrationData.tone` exists. |
| Save .esgc | `Engine.IsCalibrated` is `true`. |
| Load .esgc | Always enabled. |

---

## Status bar

The single-line status label at the bottom of the Controls panel shows:

| Situation | Message example | Color |
|-----------|-----------------|-------|
| Idle | `Ready.` | Black |
| Action in progress | `Running tone calibration...` | Black |
| Success | `Tone calibration complete.` | Black |
| Error | `Hardware timeout: BufferIndex stalled at 0` | Red |

The cursor changes to a watch pointer while an action is running and returns to an arrow on completion.

---

## Error handling

All action callbacks are wrapped in a `try/catch`. On failure:

- The status bar turns red and shows the error message.
- A `uialert` modal dialog displays the full message.
- The GUI returns to an interactive state — no data is lost and the user can retry.

Engine errors follow the structured ID convention `stimgen:calibration:<Class>:<type>`, so targeted `catch` blocks work for programmatic use.

---

## See also

- [stimgen_calibration.md](stimgen_calibration.md) — full reference for `Engine`, `InterfaceAdapter`, and `HwAdapter`
- [stimgen_StimCalibration.md](stimgen_StimCalibration.md) — thin GUI controller (owns an Engine; integrates with `StimType`)
- `obj/+stimgen/+calibration/Engine.m` — calibration engine driven by this GUI
