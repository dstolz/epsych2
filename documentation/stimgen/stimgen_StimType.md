# stimgen.StimType

`stimgen.StimType` is the abstract base class for editable stimulus objects in the `stimgen` package. This is a developer reference for subclassing and integration; for tool usage start at [stimgen_overview.md](stimgen_overview.md).

Source class:

- [obj/+stimgen/@StimType/StimType.m](../../obj/+stimgen/@StimType/StimType.m)

Concrete subclasses: `Tone`, `Noise`, `AMnoise`, `AttackModNoise`, `FMtone`, `ClickTrain`, `SweptSine` (loose `.m` files in `obj/+stimgen/`). Subclasses define the constants `CalibrationType` and `Normalization`, and the `IsMultiObj` property that tells wrappers whether the object expands into multiple presentable stimuli.

## What The Base Class Provides

- shared stimulus properties (`SoundLevel`, `Duration`, `Fs`, windowing controls)
- waveform storage (`Signal`)
- calibration integration (`ApplyCalibration`, `Calibration`)
- plotting and preview playback helpers
- serialization helpers (`toStruct`, `fromStruct`)
- GUI-generation and property metadata hooks

Subclasses implement `update_signal` and set class constants for calibration and normalization behavior.

## Signal Update Lifecycle

The base class listens to observable property changes and recomputes waveform data.

Typical subclass update flow:

1. generate raw signal in `update_signal`
2. apply gating/windowing (`apply_gate`)
3. normalize (`apply_normalization`)
4. apply calibration (`apply_calibration`)

`refresh_plot_if_valid` keeps open plot handles synchronized.

## Variant Selection

Vectorized user properties (for example a `Tone` with `Frequency = [1000 2000 4000]`) define a set of stimulus *variants*. The class has explicit variant-control properties and cache management:

- `VariantSelectionMode`
- `VariantCombinationMode`
- `VariantSelectorClass`
- `VariantSelectorConfig`
- `VariantReselectOnUpdate`

Supporting methods include:

- `build_variant_combinations_`
- `refresh_variant_cache_if_needed_`
- `select_variant_index_`
- `begin_variant_cycle_` / `end_variant_cycle_`
- `apply_variant_index_and_update_`
- `set_variant_index` / `step_variant`
- `get_variant_info`

This enables deterministic, shuffled, and custom selector-driven traversal of vectorized property combinations.

## Expression Evaluation

Stimulus property expressions are evaluated through guarded helper methods:

- `evalPropertyExpression`
- `evaluate_property_expression_`
- `build_expression_context_`
- `rewrite_qualified_property_refs_`

These are used by editing workflows that support computed property values.

## GUI Integration

`create_gui` builds widget controls from metadata (`propMeta`) and property definitions.

Recent UI sync behavior includes `update_handle_value`, which keeps control state aligned after property updates and variant changes.

## Common Public Methods

- `plot`, `plot_spectrogram`, `play`
- `selected_value`
- `current_parameter_summary`
- `toStruct`, `fromStruct`
- `list` (discover available stimulus classes)

## Minimal Example

```matlab
t = stimgen.Tone;
t.Frequency = 4000;
t.Duration = 0.1;
t.SoundLevel = 60;
t.update_signal();
t.plot();
```

Variant stepping example:

```matlab
t.Frequency = [1000 2000 4000];   % three variants
info = t.set_variant_index(1);
info = t.step_variant(1);
```

## Related Documentation

- [stimgen_overview.md](stimgen_overview.md) — package orientation
- [stimgen_StimCalibration.md](stimgen_StimCalibration.md) — how stimuli consume calibration
- [stimgen_calibration.md](stimgen_calibration.md) — calibration workflow
