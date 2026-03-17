# Adaptive Staircase Analysis

## Overview

The `psychophysics.Staircase` class implements adaptive staircase analysis for psychophysical experiments. It automatically tracks stimulus reversals, computes threshold estimates, and maintains staircase history as trials are completed in real-time.

**Key Features:**

- Automatic reversal detection in adaptive staircases
- Real-time threshold estimation from the last N reversals
- Support for both arithmetic mean and geometric mean thresholds
- Optional decibel conversion for stimulus values
- Event-driven architecture with listener integration
- Configurable trial filtering by trial type

## Basic Usage

### Creating a Staircase

The most basic usage requires a Runtime object and a Parameter to track:

```matlab
% Create a basic staircase
S = psychophysics.Staircase(RUNTIME, Parameter);
```

### Offline Analysis

If you already have per-trial data (e.g., `event.Data.DATA` from the EPsych event system), you can compute staircase history without attaching listeners:

```matlab
% DATA is a struct array of trials
S = psychophysics.Staircase(DATA, Parameter);
```

### Advanced Configuration

You can customize the staircase behavior with name-value options:

```matlab
% Create a staircase tracking stimulus intensity "up"
S = psychophysics.Staircase(RUNTIME, Parameter, ...
    StaircaseDirection="Up", ...
    ConvertToDecibels=true);

% Customize trial type filtering
S = psychophysics.Staircase(RUNTIME, Parameter, ...
    StimulusTrialType=epsych.BitMask.TrialType_1, ...
    CatchTrialType=epsych.BitMask.TrialType_2);
```

## Properties

### Configuration Properties

These properties control how the staircase behaves. Most can be set at construction or modified later.

#### `StaircaseDirection` (string)

- **Values:** `"Up"` or `"Down"` (default: `"Down"`)
- **Purpose:** Defines the direction of staircase progression for reversal detection
- **Details:**
  - `"Down"` — reversals occur when stimulus increases after decreasing (downward staircase)
  - `"Up"` — reversals occur when stimulus decreases after increasing (upward staircase)

#### `Parameter` (hw.Parameter)

- **Purpose:** The stimulus parameter being tracked in the staircase
- **Details:** This parameter's `validName` property is used to extract values from trial data

#### `StimulusTrialType` and `CatchTrialType` (epsych.BitMask)

- **Default:** `TrialType_0` and `TrialType_1`
- **Purpose:** Define which trials are stimulus trials (analyzed) vs. catch trials (excluded)
- **Details:** Only stimulus trials are used for reversal detection and threshold computation

#### `ThresholdFromLastNReversals` (integer)

- **Default:** `12`
- **Purpose:** Number of most recent reversals to use when computing threshold
- **Details:** The threshold is computed from stimulus values at the last N reversal points

#### `ThresholdFormula` (string)

- **Values:** `"Mean"` (default) or `"GeometricMean"`
- **Purpose:** Method for computing the threshold value
- **Details:**
  - `"Mean"` — arithmetic mean of reversal stimulus values
  - `"GeometricMean"` — geometric mean (better for logarithmic scales)

#### `ConvertToDecibels` (logical)

- **Default:** `false`
- **Purpose:** Whether to convert stimulus values to decibel scale
- **Details:** When true, values are transformed as `dB = 20*log10(x)` with non-positive values replaced by NaN

### Computed Results

These properties are automatically calculated and updated with each trial. They are read-only (SetAccess = private).

#### `ReversalCount` (integer)

- Number of reversals detected in the current staircase sequences

#### `ReversalIdx` (integer array)

- Trial indices where reversals occurred
- **Example:** If `ReversalIdx = [15, 22, 31, ...]`, reversals occurred at trials 15, 22, 31, etc.

#### `Threshold` (double)

- Current threshold estimate computed from the last N reversals
- Empty if no reversals have occurred yet
- Computed using `ThresholdFormula`

#### `ThresholdStd` (double)

- Standard deviation of stimulus values at the last N reversal points
- Measures the stability of the staircase

#### `StepDirection` (double array)

- Direction of each step in the staircase sequence
- **Values:** `1` (up), `-1` (down), `NaN` (non-stimulus trials and the first stimulus step)

### Dependent Properties (Read-Only)

These properties are computed on-demand from trial data.

#### `responseCodes` (array)

- Response codes from all trials in `DATA`
- Extracted from `ResponseCode` field of each trial struct

#### `stimulusValues` (array)

- Stimulus parameter values from all trials
- Optionally converted to decibels if `ConvertToDecibels=true`

#### `trialCount` (integer)

- Total number of trials currently in `DATA`

## Methods

### Constructor

```matlab
S = psychophysics.Staircase(RUNTIME, Parameter)
S = psychophysics.Staircase(DATA, Parameter)
S = psychophysics.Staircase(RUNTIME, Parameter, Name=Value)
```

**Purpose:** Create a new Staircase object in online (listener-attached) or offline mode.

**Parameters:**

- `RUNTIME` — The Runtime object containing trial data and event infrastructure (online mode)
- `DATA` — Per-trial struct array (offline mode), typically `event.Data.DATA`
- `Parameter` — The hw.Parameter object to track in this staircase
- `StimulusTrialType` — BitMask for stimulus trials (default: `TrialType_0`)
- `CatchTrialType` — BitMask for catch trials (default: `TrialType_1`)
- `StaircaseDirection` — `"Up"` or `"Down"` (default: `"Down"`)
- `ConvertToDecibels` — Convert stimulus values to dB (default: `false`)

**Details:**

- In online mode, the constructor attaches a listener to `RUNTIME.HELPER`'s `NewData` event
- In offline mode, no listener is attached and history is computed immediately

### Plotting (Optional)

The Staircase class can plot its history on a MATLAB axes.

```matlab
S.enablePlot();           % create and own a new figure/axes
S.enablePlot(ax);         % plot into existing axes
S.refreshPlot();          % redraw from current state
S.disablePlot();          % turn off plotting and delete graphics
```

### `refresh_history()`

```matlab
S.refresh_history()
```

**Purpose:** Manually trigger a recompute of the staircase history and notify listeners.

**When to use:**

- After modifying configuration properties that affect reversal detection
- If trial data changed outside the normal event pathway
- To force an update without waiting for the next trial

## Advanced Topics

### How Reversals Are Detected

A reversal occurs when the direction of stimulus change reverses:

1. Stimulus values are extracted from all trials matching `StimulusTrialType`
2. The sign of the difference between consecutive values is computed
3. If `StaircaseDirection = "Down"`, signs are flipped (negative reversals become positives)
4. A reversal is detected whenever the sign changes between consecutive steps

**Example:**

```text
Stimulus sequence (Down staircase):  10 → 8 → 6 → 7 → 9 → 8
Step direction:                      ↓  ↓  ↑  ↑  ↓
Reversals at:                           trial 3 (sign changes from -1 to +1)
                                        trial 5 (sign changes from +1 to -1)
```

### Threshold Calculation

Once reversals are identified:

1. The last `ThresholdFromLastNReversals` reversals are found
2. Stimulus values at those reversal points are extracted
3. The threshold is computed as either:
   - **Mean:** Arithmetic mean of reversal stimulus values
   - **GeometricMean:** Geometric mean (recommended for dB-scaled data)
4. Standard deviation is computed from the same values

**Example:**

```matlab
% If last 4 reversals occurred at stimulus values [100, 90, 110, 95]
% Mean threshold = (100 + 90 + 110 + 95) / 4 = 98.75
% Geometric mean = (100 × 90 × 110 × 95)^(1/4) ≈ 98.25
```

### Event System Integration

The Staircase class uses the EPsych event system for integration:

- Listens to `RUNTIME.HELPER.NewData` events when trials complete
- Broadcasts `NewData` events after updating staircase history
- Can be used with other GUI components that listen for staircase updates

```matlab
% Example: Listen to staircase updates in another object
addlistener(StaircaseObj.Helper, 'NewData', @myCallback);
```

### Decibel Conversion

When `ConvertToDecibels=true`, stimulus values are converted as follows:

```matlab
% Original stimulus (linear scale)
stimulus = [100, 50, 25, 10];

% After decibel conversion
dB = 20*log10(stimulus)
% Result: dB = [40.00, 33.98, 27.96, 20.00]

% Special handling for non-positive values
stimulus = [100, 0, -5, 50];
% Non-positive values become NaN: [40.00, NaN, NaN, 33.98]
```

## Limitations and Considerations

1. **No automatic saving** — Staircase history is computed in-memory. Save threshold and reversal data explicitly if needed.

2. **Reversal detection assumes monotonic changes** — Step sizes must change direction for reversals to be detected. Very small oscillations might not register.

3. **Trial filtering is critical** — If `StimulusTrialType` doesn't match actual stimulus trials, reversals will be computed incorrectly. Verify your trial type masks.

4. **Threshold stability** — With fewer than 4-5 reversals, threshold estimates may be unreliable. The standard deviation (`ThresholdStd`) can help assess stability.

5. **Geometric mean and decibels** — Use geometric mean (not arithmetic) with dB-converted values for correct statistical properties.

## Common Patterns

### Offline Analysis From Saved Trials

```matlab
% DATA is a per-trial struct array (e.g. saved from event.Data.DATA)
% Parameter is the hw.Parameter you want to analyze
S = psychophysics.Staircase(DATA, Parameter);

fprintf('Reversals: %d\n', S.ReversalCount);
fprintf('Threshold: %.3f (std=%.3f)\n', S.Threshold, S.ThresholdStd);

% Optional: plot offline results
S.enablePlot();
```

### Monitoring Threshold in Real Time

```matlab
% Create a listener to track threshold changes
addlistener(S.Helper, 'NewData', @(src, evt) disp(['Threshold: ', num2str(S.Threshold)]));
```

### Extracting Final Results

```matlab
% After experiment completes
finalThreshold = S.Threshold;
finalStd = S.ThresholdStd;
reversalIndices = S.ReversalIdx;
reversalCount = S.ReversalCount;

% Save to results structure
results.threshold = finalThreshold;
results.reversalCount = reversalCount;
results.thresholdStd = finalStd;
```

### Comparing Multiple Staircases

```matlab
% Track multiple stimulus parameters
S1 = psychophysics.Staircase(RUNTIME, Param1);
S2 = psychophysics.Staircase(RUNTIME, Param2);

% Both update automatically as trials complete
% Access results independently
fprintf('Parameter 1 threshold: %.2f\n', S1.Threshold);
fprintf('Parameter 2 threshold: %.2f\n', S2.Threshold);
```

## See Also

- `psychophysics.Detect` — Alternative analysis for detection tasks
- `epsych.Helper` — Event system used for real-time updates
- `hw.Parameter` — Parameter definition and validation
- `epsych.BitMask` — Trial type definitions and utility methods
