# Stimulus Generation Package

## Overview

The `stimgen` package is the stimulus authoring, calibration, and playback layer for EPsych. It covers three related jobs:

- defining waveforms as MATLAB objects such as `stimgen.Tone`, `stimgen.AMnoise`, and `stimgen.ClickTrain`
- calibrating output level so requested `SoundLevel` values map to hardware voltage
- scheduling and triggering stimuli through the stimgen GUIs and the RPvds playback circuit

This package is built around a small set of classes:

- `stimgen.StimType`: abstract base class for individual stimulus definitions
- `stimgen.StimPlay`: repetition and ordering wrapper around one or more stimulus objects
- `stimgen.StimCalibration`: calibration GUI and lookup-table manager
- `stimgen.StimGenInterface`: full playback GUI for multiple stimulus groups
- `stimgen.StimGenInterface_Simple`: lighter playback GUI for a single stimulus group

Use this guide in two ways:

- If you operate experiments, start with the end-user workflow sections.
- If you extend the package, start with the developer architecture and new stimulus type sections.

## Built-In Stimulus Types

The package currently auto-discovers these concrete stimulus classes from `obj/+stimgen`:

- `stimgen.Tone`: pure tone
- `stimgen.Noise`: band-limited Gaussian noise
- `stimgen.AMnoise`: sinusoidally amplitude-modulated noise
- `stimgen.AttackModNoise`: attack-shaped modulated noise
- `stimgen.ClickTrain`: periodic click train
- `stimgen.FMtone`: frequency-modulated tone
- `stimgen.multiTone`: a grid of tones built from frequency and level expressions

`stimgen.multiTone` is the main special case. Instead of storing one waveform definition, it expands `Frequency_MO` and `SoundLevel_MO` string expressions into an array of `stimgen.Tone` objects. Expressions such as `"500*2.^(0:6)"` and `"10:10:70"` are valid.

## End-User Workflow

### 1. Calibrate the output chain

Use `stimgen.StimCalibration` when you need level-correct playback.

```matlab
cal = stimgen.StimCalibration(RUNTIME);
```

With a valid runtime object, the constructor opens the calibration GUI and binds to the active hardware parameter set.

Important controls in the calibration GUI:

- `ReferenceLevel`: sound level of the calibrator or reference tone in dB SPL
- `ReferenceFrequency`: reference tone frequency used when measuring microphone sensitivity
- `MicSensitivity`: microphone sensitivity in V/Pa; can be entered manually or measured with `Measure Reference`
- `NormativeValue`: target reference level used when converting calibration measurements into lookup values
- `ExcitationSignalVoltage`: drive voltage used during calibration playback
- `Run Calibration`: performs the calibration routine and populates `CalibrationData`

Use the `File` menu in the calibration window to save or load calibration data.

### 2. Open a playback GUI

Use one of the two playback controllers depending on how much flexibility you need.

```matlab
sg = stimgen.StimGenInterface(RUNTIME);
```

`stimgen.StimGenInterface` is the full interface. It creates one tab per discovered stimulus type, lets you add multiple stimulus groups to a playback list, and supports serial or shuffled group ordering.

```matlab
sg = stimgen.StimGenInterface_Simple(RUNTIME);
```

`stimgen.StimGenInterface_Simple` is the reduced version for one `StimPlay` object. Use it when a protocol only needs one stimulus group and repeated playback.

### 3. Build stimuli in the GUI

The full interface has one tab per stimulus class. Each tab is generated from the class metadata exposed through `propMeta()`, so the labels and widgets follow the object properties closely.

Common controls across most stimulus types:

- `SoundLevel`
- `Duration`
- `WindowDuration`
- `ApplyWindow`

Type-specific controls add the actual waveform parameters, for example:

- `Tone`: `Frequency`, `OnsetPhase`, `WindowMethod`
- `AMnoise`: filter bounds plus `AMDepth`, `AMRate`, `EnvelopeOnly`
- `ClickTrain`: `Rate`, `Polarity`, `ClickDuration`, `OnsetDelay`
- `multiTone`: `Frequency_MO` and `SoundLevel_MO` expression strings

Use `Play Stim` to preview the currently selected stimulus object through MATLAB audio playback. This is a convenience preview, not the hardware-timed RPvds run path.

### 4. Add playback entries

In `StimGenInterface`, the right-side controls build `StimPlay` entries:

- `Stim Name`: label for the list entry
- `ISI`: inter-stimulus interval, stored as either a fixed value or a two-element range
- `Reps`: repetitions per underlying stimulus
- `Add`: wraps the currently selected stimulus into a `StimPlay` entry and adds it to the tree
- `Remove`: removes the selected tree entry
- play mode dropdown: chooses `Serial` or `Shuffle` selection across entries

For `multiTone`, one added entry can represent many tones because the object internally expands to `MultiObjects`. Repetitions and scheduling happen across the expanded tone set.

### 5. Attach calibration and run

Assign calibration before timed playback when you need calibrated output levels.

```matlab
cal = stimgen.StimCalibration(RUNTIME);
sg = stimgen.StimGenInterface(RUNTIME);
sg.Calibration = cal;
```

The full interface also exposes a `Calibration` menu item. Once a calibration object is attached, it propagates through `StimPlay` into the underlying `StimType` objects.
# Stimulus Generation Package

`stimgen` is EPsych's stimulus authoring, calibration, and playback layer.

At a high level, the package lets you:

- define waveforms as MATLAB objects
- scale those waveforms with acoustic calibration data
- present them through MATLAB preview audio or the stimgen RPvds circuit

This overview is the entry point for the subsystem. Use the linked guides for
the details behind each major class.

## Documentation map

- [stimgen_StimType.md](stimgen_StimType.md): base stimulus contract, built-in
    stimulus classes, discovery rules, and extension points
- [stimgen_StimPlay.md](stimgen_StimPlay.md): repetition and selection wrapper
    used by all playback tools
- [stimgen_StimCalibration.md](stimgen_StimCalibration.md): calibration
    workflow, `.sgc` files, and voltage lookup behavior
- [stimgen_StimGenInterface.md](stimgen_StimGenInterface.md): classic full and
    simple playback GUIs, `.sgi` configs, and timer-driven hardware playback
- [stimgen_StimPlayer.md](stimgen_StimPlayer.md): standalone stimulus-bank tool
    with `.spl` save/load support

## Core workflow

Most `stimgen` workflows follow the same model:

1. Create or edit a `stimgen.StimType` object such as `Tone` or `Noise`.
2. Wrap it in `stimgen.StimPlay` if you need repetitions, ISI handling, or
     multi-object sweep presentation.
3. Attach a `stimgen.StimCalibration` object when output level must be tied to
     measured SPL.
4. Present the result through `StimGenInterface`,
     `StimGenInterface_Simple`, or `StimPlayer`.

Minimal example:

```matlab
tone = stimgen.Tone('Frequency', 4000, 'SoundLevel', 60);
sp   = stimgen.StimPlay(tone);
sp.Reps = 20;

cal = stimgen.StimCalibration(RUNTIME);
tone.Calibration = cal;

gui = stimgen.StimGenInterface(RUNTIME);
gui.Calibration = cal;
```

## Built-in stimulus classes

The repository currently includes these main stimulus-definition classes:

- `stimgen.Tone`
- `stimgen.Noise`
- `stimgen.AMnoise`
- `stimgen.AttackModNoise`
- `stimgen.ClickTrain`
- `stimgen.FMtone`
- `stimgen.ParamSweep`

The older `stimgen.multiTone` class is still present, but it is deprecated and
hidden from the modern auto-discovery path. For new sweep-style work, prefer
`stimgen.ParamSweep`.

## Choosing the right tool

### Use `StimCalibration` when

- you need measured SPL-to-voltage mapping
- you want to save or load reusable `.sgc` calibration files
- your stimulus classes will run with `ApplyCalibration = true`

### Use `StimGenInterface` when

- you want the classic full playback GUI
- you need multiple named `StimPlay` entries in one session
- you want one editing tab per discoverable stimulus type

### Use `StimGenInterface_Simple` when

- you only need one `StimPlay` entry
- you want the same hardware playback path with less session management UI

### Use `StimPlayer` when

- you want a standalone bank editor outside a full experiment workflow
- you want easy local preview even when hardware is absent
- you want to save and reload stimulus banks as `.spl` files

## Runtime and hardware expectations

The active playback and calibration tools assume an `epsych.Runtime` whose
hardware layer exposes the parameter names expected by the stimgen RPvds
circuit.

The most important playback parameters are:

- `BufferData_0`
- `BufferData_1`
- `BufferSize_0`
- `BufferSize_1`
- `x_Trigger_0`
- `x_Trigger_1`

The sample rate is taken from `RUNTIME.HW.HW.FS`.

If the runtime object is missing or the expected parameters are unavailable,
the GUIs may still open, but hardware-triggered playback and calibration will
not work correctly.

## Saved file types

The subsystem uses several save formats depending on the tool.

- `.sgc`: calibration files from `StimCalibration`
- `.sgi`: saved configurations for `StimGenInterface` and
    `StimGenInterface_Simple`
- `.spl`: stimulus-bank files from `StimPlayer`
- `.mat`: presentation-order logs saved after a playback run

The repository also includes older `StimGen.prot` and `StimGen.ecfg` assets.
Those are part of the broader stimgen tooling history, but the current GUI
save/load paths described here revolve around `.sgc`, `.sgi`, and `.spl`.

## Developer notes

Several package behaviors are driven by file and metadata conventions.

- `StimType.list()` scans `obj/+stimgen` to decide which classes appear in GUI
    lists.
- `StimType.propMeta()` and `create_gui()` control how stimulus editors are
    built.
- `StimGenInterface` discovers cross-item selection strategies from
    `stimselect_*.m` files.
- `StimType.apply_calibration()` and `StimCalibration` are coupled through the
    stimulus class `CalibrationType` constant.

Two practical implications follow from that design.

- Adding a new stimulus class is usually straightforward if its constructor,
    metadata, and `update_signal()` implementation are clean.
- Adding a new calibration mode or a new cross-item selection strategy often
    requires coordinated edits across multiple files.

## Related files

- `obj/+stimgen/StimType.m`
- `obj/+stimgen/StimPlay.m`
- `obj/+stimgen/ParamSweep.m`
- `obj/+stimgen/@StimCalibration/StimCalibration.m`
- `obj/+stimgen/@StimGenInterface/StimGenInterface.m`
- `obj/+stimgen/@StimGenInterface_Simple/StimGenInterface_Simple.m`
- `obj/+stimgen/@StimPlayer/StimPlayer.m`