# Stimulus Generation Package

`stimgen` is EPsych's stimulus authoring, calibration, and playback layer.

At a high level, the package lets you:

- define waveforms as MATLAB objects (tones, noise, clicks, and more)
- scale those waveforms with acoustic calibration data so requested dB SPL levels are accurate
- present them through MATLAB preview audio or hardware playback

This overview is the entry point for the subsystem. The first half is for users operating the tools; the developer notes at the end are for people extending the package.

## Documentation map

- [stimgen_StimType.md](stimgen_StimType.md): base stimulus contract, built-in stimulus classes, and extension points (developer reference)
- [stimgen_StimPlay.md](stimgen_StimPlay.md): repetition and selection wrapper used by playback tools (developer reference)
- [stimgen_StimPlayer.md](stimgen_StimPlayer.md): standalone stimulus-bank tool with `.spl` save/load support
- [stimgen_calibration.md](stimgen_calibration.md): calibration concepts, GUI walkthrough, and programmatic workflow
- [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md): calibration GUI reference
- [stimgen_SweptSineCalibration.md](stimgen_SweptSineCalibration.md): swept-sine calibration method
- [stimgen_StimCalibration.md](stimgen_StimCalibration.md): the `StimCalibration` wrapper used by stimulus objects

## Core workflow

Most `stimgen` workflows follow the same model:

1. Create or edit a `stimgen.StimType` object such as `Tone` or `Noise`.
2. Wrap it in `stimgen.StimPlay` if you need repetitions, ISI handling, or ordered/shuffled presentation.
3. Attach calibration when output level must be tied to measured SPL.
4. Present the result through `stimgen.StimPlayer` or your experiment's hardware circuit.

Minimal example:

```matlab
tone = stimgen.Tone;
tone.Frequency = 4000;
tone.SoundLevel = 60;
tone.update_signal;
tone.play          % preview through the computer speakers

sp = stimgen.StimPlay(tone);
sp.Reps = 20;
sp.ISI = [0.8 1.2];
```

## Built-in stimulus classes

- `stimgen.Tone` — pure tone; `Frequency` and `OnsetPhase` may be vectorized to define variants
- `stimgen.Noise` — band-limited Gaussian noise
- `stimgen.AMnoise` — sinusoidally amplitude-modulated noise
- `stimgen.AttackModNoise` — attack-shaped modulated noise
- `stimgen.ClickTrain` — periodic click train
- `stimgen.FMtone` — frequency-modulated tone
- `stimgen.SweptSine` — logarithmic chirp (also used by calibration)

To present a family of related stimuli (e.g., a frequency × level grid), assign vector values to the relevant properties and use the variant-selection controls on `stimgen.StimType` (`VariantSelectionMode`, `VariantCombinationMode`, and related methods). This replaced the older `multiTone` class, which has been removed.

## Choosing the right tool

### Use the calibration GUI (`stimgen.calibration.CalibrationGui`) when

- you need measured SPL-to-voltage mapping for a speaker or earphone
- you want to save or load reusable `.esgc` calibration files
- your stimulus classes will run with `ApplyCalibration = true`

See [stimgen_calibration.md](stimgen_calibration.md) for the full walkthrough.

### Use `StimPlayer` when

- you want a stimulus bank editor and player, with or without hardware
- you want easy local speaker preview even when hardware is absent
- you want to save and reload stimulus banks as `.spl` files

`stimgen.StimPlayer` optionally accepts an `epsych.Protocol` (object or `.eprot` file path) that defines the hardware interfaces used for playback. The older `StimGenInterface` and `StimGenInterface_Simple` GUIs have been removed; `StimPlayer` is the current playback tool.

## Runtime and hardware expectations

Hardware playback assumes a protocol whose hardware layer exposes the parameter names expected by the stimgen RPvds circuit (`StimGenCircuit.rcx`):

- `BufferData_0`, `BufferData_1` — audio data buffers
- `BufferSize_0`, `BufferSize_1` — buffer length in samples
- `x_Trigger_0`, `x_Trigger_1` — playback trigger pulses

If the protocol is missing or the expected parameters are unavailable, the GUIs still open, but only speaker preview is available; hardware-triggered playback is disabled.

## Saved file types

- `.esgc`: calibration files from the `stimgen.calibration` package (legacy `.sgc` files can still be loaded)
- `.spl`: stimulus-bank files from `StimPlayer`
- `.eprot`: EPsych protocols, which `StimPlayer` can load to reach hardware

The repository also includes `StimGen.prot`/`StimGen.ecfg` assets from earlier tooling generations; current save/load paths revolve around `.esgc` and `.spl`.

## Developer notes

Several package behaviors are driven by file and metadata conventions:

- `stimgen.StimType.list()` scans `obj/+stimgen` to decide which classes appear in GUI lists.
- `propMeta()` and `create_gui()` control how stimulus editors are built; a new subclass with clean metadata usually appears in `StimPlayer` without any player changes.
- `StimType.apply_calibration()` and the calibration engine are coupled through the stimulus class's `CalibrationType` constant.

Practical implications:

- Adding a new stimulus class is usually straightforward: implement `update_signal()`, define user-facing properties with good `propMeta()` metadata, and keep the constructor callable with no required arguments. See [stimgen_StimType.md](stimgen_StimType.md).
- Adding a new calibration mode requires coordinated edits across the `stimgen.calibration` package and `StimType`.

## Related files

- [obj/+stimgen/@StimType/StimType.m](../../obj/+stimgen/@StimType/StimType.m)
- [obj/+stimgen/StimPlay.m](../../obj/+stimgen/StimPlay.m)
- [obj/+stimgen/@StimPlayer/StimPlayer.m](../../obj/+stimgen/@StimPlayer/StimPlayer.m)
- [obj/+stimgen/@StimCalibration/StimCalibration.m](../../obj/+stimgen/@StimCalibration/StimCalibration.m)
- [obj/+stimgen/+calibration/](../../obj/+stimgen/+calibration/)
