# `stimgen.StimType` and built-in stimulus classes

`stimgen.StimType` is the abstract base class behind every editable stimulus
definition in the `stimgen` package.

Concrete subclasses such as `stimgen.Tone`, `stimgen.Noise`, and
`stimgen.ParamSweep` inherit a shared set of timing, level, plotting,
preview, GUI, and calibration helpers. If you are adding a new stimulus
class, this is the class to understand first.

## What the base class provides

Every `StimType` object owns the common pieces of a stimulus definition:

- level and timing properties such as `SoundLevel`, `Duration`, and `Fs`
- optional onset and offset windowing through `ApplyWindow`,
  `WindowDuration`, and `WindowFcn`
- optional output calibration through `ApplyCalibration` and `Calibration`
- a cached waveform in `Signal`
- convenience helpers for plotting, preview playback, serialization, and
  GUI construction

Subclasses provide the waveform-specific parameters and implement
`update_signal(obj)`.

## The signal lifecycle

The class is built around automatic regeneration.

When a public `SetObservable` property changes, `StimType` listeners call
`update_signal()` and then refresh any live plot handle.

The expected subclass pipeline is:

```matlab
obj.Signal = ...;          % generate raw waveform
obj.apply_gate();          % apply onset/offset window if enabled
obj.apply_normalization(); % normalize according to class constant
obj.apply_calibration();   % convert target level to hardware voltage
```

That shared sequence keeps different stimulus classes consistent.

### Calibration behavior

`apply_calibration()` reads the attached `stimgen.StimCalibration` object and
uses the subclass `CalibrationType` constant to decide how to map requested
level to output voltage.

Current built-in calibration paths are organized around:

- `"tone"`
- `"click"`
- `"filter"` for equalized noise-like signals

If no valid calibration data are attached, the method warns and leaves the
signal unchanged.

## GUI generation

`StimType` includes a generic `create_gui()` implementation.

That GUI builder reads metadata from `propMeta()` and automatically creates
numeric fields, checkboxes, dropdowns, or text fields based on either:

- an explicit `widget` setting in the metadata, or
- the underlying property class

Subclasses normally customize the editor by overriding `propMeta()` and, when
needed, `on_gui_changed()`.

This same metadata also drives the parameter editor inside
`stimgen.StimPlayer`, so keeping `propMeta()` accurate improves multiple
tools at once.

## Discovery rules

Playback GUIs discover available stimulus classes through `StimType.list()`.

That method scans `obj/+stimgen/*.m` and filters out support files such as:

- `StimType.m`
- `StimPlay.m`
- `donotsavedatafcn.m`
- `multiTone.m`
- files whose names contain `Calib`

Two practical consequences follow from that:

- `stimgen.ParamSweep` appears in the modern GUI lists.
- `stimgen.multiTone` is still in the repository but is deliberately hidden
  from current auto-discovery.

## Built-in stimulus classes

### `stimgen.Tone`

Pure sinusoid with configurable frequency, onset phase, and window method.

### `stimgen.Noise`

Band-limited Gaussian noise with filter parameters and filter-based
calibration support.

### `stimgen.AMnoise`

`Noise` plus sinusoidal amplitude modulation controls such as depth and rate.

### `stimgen.AttackModNoise`

`Noise` variant with an asymmetric attack and decay envelope.

### `stimgen.ClickTrain`

Impulse-train stimulus with click-specific timing rules. This class does not
use the normal onset windowing path in the same way as continuous stimuli.

### `stimgen.FMtone`

Carrier tone with frequency modulation parameters.

### `stimgen.ParamSweep`

Preferred multi-object sweep container.

`ParamSweep` wraps a prototype stimulus, expands `SweepParams` into a
full-factorial grid, and builds a `MultiObjects` array of generated child
stimuli. Use this instead of `multiTone` for new work.

### `stimgen.multiTone`

Legacy tone-grid wrapper. The class is still present, but it warns that it is
deprecated and recommends `stimgen.ParamSweep` instead.

## Common usage

Create and preview a simple tone:

```matlab
tone = stimgen.Tone('Frequency', 4000, 'Duration', 0.1, 'SoundLevel', 60);
tone.update_signal();
tone.plot();
tone.play();
```

Create a sweep from a prototype stimulus:

```matlab
ps = stimgen.ParamSweep('stimgen.Tone');
ps.Duration = 0.2;
ps.SweepParams = struct('Frequency', [2000 4000 8000], ...
                        'SoundLevel', 20:20:80);
ps.update_signal();
```

## Adding a new stimulus class

For a new class under `obj/+stimgen`, keep the implementation focused on the
parts that are truly stimulus-specific.

At minimum, a new class should:

1. Subclass `stimgen.StimType`.
2. Define public editable properties with useful validation.
3. Set `DisplayName` and `UserProperties` in the constructor.
4. Define `IsMultiObj`, `CalibrationType`, and `Normalization` constants.
5. Implement `update_signal()`.
6. Override `propMeta()` so the GUIs show clear labels and limits.

If the signal needs a new calibration strategy, you will also need matching
changes in `stimgen.StimCalibration` and `StimType.apply_calibration()`.

## Related files

- `obj/+stimgen/StimType.m`
- `obj/+stimgen/Tone.m`
- `obj/+stimgen/Noise.m`
- `obj/+stimgen/AMnoise.m`
- `obj/+stimgen/AttackModNoise.m`
- `obj/+stimgen/ClickTrain.m`
- `obj/+stimgen/FMtone.m`
- `obj/+stimgen/ParamSweep.m`
- `obj/+stimgen/multiTone.m`