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

When you press `Run`, the interface:

- resets repetition counts
- selects the next stimulus group
- writes the next waveform into the non-triggered hardware buffer
- triggers playback on a timer using `x_Trigger_0` and `x_Trigger_1`
- alternates buffers using `BufferData_0/1` and `BufferSize_0/1`
- logs stimulus order and trigger time for later saving

## Runtime and Hardware Expectations

The stimgen GUIs are not generic standalone waveform tools. They expect an EPsych runtime object that exposes hardware parameters with names used by the RPvds stimgen circuit.

The playback controllers depend on parameters such as:

- `BufferData_0`, `BufferData_1`
- `BufferSize_0`, `BufferSize_1`
- `x_Trigger_0`, `x_Trigger_1`

The sample rate is taken from `RUNTIME.HW.HW.FS`. If the runtime or parameter names do not match the expected stimgen circuit, the GUIs will construct but playback and calibration will fail.

## Developer Architecture

### `StimType`: base abstraction

`stimgen.StimType` owns the shared signal-generation contract.

Responsibilities of the base class:

- stores common parameters such as `SoundLevel`, `Duration`, `Fs`, and windowing controls
- listens to public `SetObservable` properties and regenerates the waveform when they change
- auto-builds a parameter GUI from `propMeta()`
- provides `plot`, `play`, `toStruct`, gating, normalization, and calibration helpers

Every concrete stimulus type must define these constants:

- `IsMultiObj`
- `CalibrationType`
- `Normalization`

Every concrete stimulus type must also implement:

- `update_signal(obj)`

Typical `update_signal` pipeline:

```matlab
obj.Signal = ...;          % generate raw waveform
obj.apply_gate();          % optional onset/offset windowing
obj.apply_normalization(); % normalize using the class constant
obj.apply_calibration();   % convert to calibrated output voltage
```

### GUI metadata and callbacks

The current base class includes a generic `create_gui()` implementation driven by `propMeta()` metadata. In practice this means new stimulus classes do not need to hand-build UI controls unless they need custom behavior.

Relevant hooks:

- `propMeta()`: returns labels, limits, formats, and widget types for GUI-visible properties
- `on_gui_changed(propName, value)`: optional hook for side effects after a GUI edit
- `UserProperties`: ordered list used for serialization and display
- `DisplayName`: title used in the full stimgen tab set

### `StimPlay`: scheduling wrapper

`stimgen.StimPlay` wraps one `StimType` instance or one multi-object stimulus and adds playback state:

- repetition count (`Reps`)
- inter-stimulus interval (`ISI`)
- selection mode (`Serial` or `Shuffle`)
- current stimulus index within the wrapped set

This class is the bridge between a waveform definition and the playback GUIs. It is also where `multiTone` becomes manageable during repeated presentation, because `StimPlay` knows how to address either `StimObj(i)` or `StimObj.MultiObjects(i)`.

### `StimCalibration`: calibration lookup manager

`stimgen.StimCalibration` measures reference responses and stores the result in `CalibrationData`. `StimType.apply_calibration()` later reads that data and maps requested stimulus parameters to output voltage.

Current calibration behavior is organized by `CalibrationType`, with built-in handling for cases such as:

- `"tone"`
- `"click"`
- filter-based equalization for noise-like signals

If you add a new calibration mode, you will likely need coordinated changes in both the stimulus class and the calibration code path.

### `StimGenInterface`: timed playback controller

`stimgen.StimGenInterface` manages a list of `StimPlay` objects and drives timed hardware playback through a MATLAB timer.

Important implementation details:

- stimulus classes are discovered by `stimgen.StimType.list()` scanning `obj/+stimgen/*.m`
- the GUI creates one tab per discovered class and instantiates each class once for editing
- playback uses ping-pong buffering to prepare the next waveform while the current one is being presented
- the timer loop busy-waits until the target ISI expires, then triggers hardware and schedules the next stimulus

Because discovery is file-based, helper classes placed directly in `obj/+stimgen` can accidentally appear as stimulus tabs. Keep non-stimulus helpers elsewhere, or update the filtering logic in `StimType.list()`.

## Adding a New Stimulus Type

### Minimum implementation

Create a new class file in `obj/+stimgen` that subclasses `stimgen.StimType`.

```matlab
classdef MyStim < stimgen.StimType

    properties (SetObservable, AbortSet)
        Frequency (1,1) double {mustBePositive,mustBeFinite} = 2000
    end

    properties (Constant)
        IsMultiObj = false
        CalibrationType = "tone"
        Normalization = "absmax"
    end

    methods
        function obj = MyStim(varargin)
            obj = obj@stimgen.StimType(varargin{:});
            obj.DisplayName = 'My Stim';
            obj.UserProperties = ["Frequency","SoundLevel","Duration","WindowDuration","ApplyWindow"];
        end

        function update_signal(obj)
            obj.Signal = sin(2*pi*obj.Frequency*obj.Time);
            obj.apply_gate();
            obj.apply_normalization();
            obj.apply_calibration();
        end
    end

    methods (Access = protected)
        function m = propMeta(obj)
            m = struct();
            m.Frequency = struct('label', 'Frequency', 'format', '%.1f Hz', 'limits', [100 40000]);
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj));
        end
    end
end
```

### How discovery works

New classes appear automatically in `StimGenInterface` and `StimGenInterface_Simple` if all of these are true:

- the class lives directly in `obj/+stimgen`
- the filename matches the class name
- the constructor can be called with no required positional arguments
- the file is not filtered out by `StimType.list()`

### Calibration decisions

Before adding a new type, decide which calibration behavior it should use:

- reuse an existing `CalibrationType` if one already matches the signal
- add new lookup logic only if the existing tone, click, or filter paths are insufficient

If the new signal needs its own calibration behavior, update the calibration code deliberately. The current package couples calibration strategy to the stimulus class constant.

### Multi-object types

`multiTone` shows the current pattern for one stimulus definition that expands into many presentable objects. Use that approach only if the GUI should define a family of stimuli as one logical item. If you do, expect to touch both `StimPlay` and any code that assumes a one-to-one relationship between a `StimType` object and a presentable waveform.

## Practical Notes and Caveats

- `multiTone` evaluates its frequency and level expressions with `eval`. Treat those fields as MATLAB expressions, not plain text labels.
- `ClickTrain` disables the default windowing path and uses click-specific duration checks.
- Property listeners on `StimType` regenerate signals automatically. This is convenient, but expensive properties should still be validated carefully.
- `StimGenInterface` and `StimGenInterface_Simple` use a timer plus a short busy-wait around trigger time. That behavior is intentional for timing, but it can make the UI feel less responsive during active playback.

## Related Files

- `obj/+stimgen/StimType.m`
- `obj/+stimgen/StimPlay.m`
- `obj/+stimgen/@StimCalibration/StimCalibration.m`
- `obj/+stimgen/@StimGenInterface/StimGenInterface.m`
- `obj/+stimgen/@StimGenInterface_Simple/StimGenInterface_Simple.m`
- `obj/+stimgen/multiTone.m`