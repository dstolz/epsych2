# `stimgen.StimPlay`

`stimgen.StimPlay` is the scheduling wrapper that sits between a stimulus
definition and the playback tools.

The class does not generate waveforms on its own. Instead, it wraps one
`stimgen.StimType` object, adds repetition and order state, and exposes the
currently selected presentable waveform through dependent properties such as
`CurrentStimObj` and `Signal`.

## Why this wrapper exists

The playback controllers in `stimgen` need more than a waveform.

They also need to know:

- how many times the wrapped stimulus should be presented
- how long to wait between presentations
- which member of a multi-object sweep should be presented next
- what order the individual presentations occurred in

`StimPlay` centralizes that state so playback GUIs do not each have to solve
the same bookkeeping problem.

## Single-object and multi-object behavior

`StimPlay` supports two shapes of wrapped stimulus.

### Single-object stimulus

For a normal stimulus such as `stimgen.Tone` or `stimgen.Noise`, `StimObj`
is the presentable object. `CurrentStimObj` simply returns that same object.

### Multi-object stimulus

For a wrapper such as `stimgen.ParamSweep`, `StimObj.IsMultiObj` is true and
the real presentable objects live in `StimObj.MultiObjects`.

In that case, `StimPlay` uses `StimIdx` to select one child object at a time
and exposes the selected child through `CurrentStimObj`.

That is how one sweep definition can behave like many presentable stimuli
during playback.

## Key properties

- `StimObj`: the wrapped `StimType` object
- `Reps`: target repetitions per presentable stimulus
- `ISI`: scalar or two-element range in seconds
- `SelectionType`: `"Serial"` or `"Shuffle"`
- `RepsPresented`: per-stimulus presentation counts
- `StimIdx`: current child index inside the wrapped stimulus
- `StimOrder`: logged order of internal child selections

Useful dependent properties:

- `CurrentStimObj`
- `Signal`
- `NStimObj`
- `StimPresented`
- `StimTotal`
- `LastStim`

## Scheduling behavior

### `reset()`

`reset()` regenerates the wrapped stimulus signal, resets `StimIdx` to `1`,
zeros `RepsPresented`, and allocates a fresh `StimOrder` array.

Playback controllers usually call this before a run starts.

### `increment()`

`increment()` advances the internal selection state.

It chooses the next child index with either:

- `select_Serial()` to pick the first stimulus with the minimum rep count
- `select_Shuffle()` to pick a random stimulus among those with the minimum
  rep count

After selecting an index, the method increments `RepsPresented(idx)` and logs
that index in `StimOrder`.

### `get_isi()`

If `ISI` is a range `[min max]`, `get_isi()` returns a random scalar within
that range. If both values are equal, it returns the fixed value.

## Calibration propagation

Assigning `StimPlay.Calibration` also assigns the same object to the wrapped
stimulus.

That forwarding step is important because playback controllers typically work
with `StimPlay` arrays, while waveform scaling happens inside the underlying
`StimType` objects.

## Common usage

Wrap a simple tone:

```matlab
tone = stimgen.Tone('Frequency', 4000, 'SoundLevel', 60);
sp = stimgen.StimPlay(tone);
sp.Reps = 10;
sp.ISI = [0.8 1.2];
sp.SelectionType = "Serial";
sp.reset();
```

Wrap a parameter sweep:

```matlab
ps = stimgen.ParamSweep('stimgen.Tone');
ps.SweepParams = struct('Frequency', [2000 4000 8000], ...
                        'SoundLevel', [40 60]);

sp = stimgen.StimPlay(ps);
sp.Reps = 5;
sp.SelectionType = "Shuffle";
sp.reset();
```

In the second example, one `StimPlay` object manages six presentable child
stimuli because the sweep expands into a `MultiObjects` array.

## Serialization

`toStruct()` serializes the scheduling state plus the wrapped stimulus.

For single-object stimuli, the wrapped object is serialized directly through
`StimType.toStruct()`.

For multi-object stimuli, `StimPlay.toStruct()` serializes the expanded child
objects rather than the original wrapper object.

### Persistence caveat

That flattening makes sense for presentation logs, but it also means save/load
paths that expect a single `StimObj.Class` are easiest to use with
single-object stimuli. If you rely on round-tripping `ParamSweep` or other
multi-object wrappers through a saved bank or config file, test that workflow
before depending on it.

## Related files

- `obj/+stimgen/StimPlay.m`
- `obj/+stimgen/StimType.m`
- `obj/+stimgen/ParamSweep.m`
- `obj/+stimgen/@StimGenInterface/StimGenInterface.m`
- `obj/+stimgen/@StimPlayer/StimPlayer.m`