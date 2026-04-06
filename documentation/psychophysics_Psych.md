# Psychophysics Base Analysis Class

## Overview

`psychophysics.Psych` is the abstract base class for behavioral analysis objects in EPsych. It handles the parts of the analysis workflow that are shared across paradigms:

- accepting either live runtime data or saved offline trial data
- storing the per-trial `DATA` array
- attaching to runtime `NewData` events in online mode
- normalizing excluded-trial settings
- extracting response-code and trial-type information
- publishing refreshed analysis state through a local `Helper` object

Subclasses provide the actual paradigm-specific computation by implementing `recomputeResults_`.

The main implementation is in `obj/+psychophysics/Psych.m`.

## When To Use This Class

Use `psychophysics.Psych` when you are building a new analysis object that should work in either of these modes:

- Online mode:
  Construct from a Runtime-like object and update automatically whenever `RUNTIME.HELPER` publishes `NewData`.
- Offline mode:
  Construct from a saved `DATA` struct array and compute results from stored trial data without attaching listeners.

The current staircase analysis class is the main example of this pattern in the repository: `obj/+psychophysics/@Staircase/Staircase.m`.

## Constructor

```matlab
obj = psychophysics.Psych(source, Parameter)
obj = psychophysics.Psych(source, Parameter, ExcludedTrials=value)
```

The constructor is defined in `obj/+psychophysics/Psych.m`.

### Inputs

- `source`
  - In online mode, this is a runtime object that exposes `RUNTIME.HELPER` and usually `RUNTIME.TRIALS`.
  - In offline mode, this is a `DATA` struct array.
- `Parameter`
  - In online mode, this must be a parameter object.
  - In offline mode, this can be either a parameter object or a `DATA` field name string.
- `ExcludedTrials`
  - Optional.
  - Accepts:
    - empty
    - a logical mask
    - a vector of 1-based trial indices

### Online vs offline behavior

The constructor first decides whether `source` is runtime-backed or DATA-backed in `configureSource_`.

If a runtime object is present, the class attaches a listener to `RUNTIME.HELPER.NewData`. In offline mode, no listener is attached.

Parameter validation is handled in `normalizeParameter_`:

- offline mode allows a string field name
- online mode rejects a string field name and requires a parameter object instead

## Core Responsibilities

### 1. Manage trial-data source

The class stores analysis data in `DATA` and runtime state in `RUNTIME`.

- `configureSource_` decides whether the object is live or offline
- `update_data` replaces `DATA` from incoming event payloads

In online mode, `update_data` expects `event.Data.DATA` to contain the current per-trial array.

### 2. Trigger recomputation

The base class never computes paradigm-specific results itself. Instead, it defines the recomputation lifecycle and delegates the actual work to `recomputeResults_`, which subclasses must implement.

Two public paths trigger recomputation:

- `refresh`
- `update_data`

Both call:

- `recomputeResults_`
- `afterRefresh_`
- `notifyDataUpdate_`

`afterRefresh_` is an optional protected hook for subclasses that need side effects after recomputation, such as updating plots or cached display state.

### 3. Re-broadcast analysis updates

The class owns its own `Helper` object and publishes `NewData` after a refresh through `notifyDataUpdate_`.

That helper is an instance of `epsych.Helper`, whose event definitions include `NewData`, `NewTrial`, and `ModeChange`.

The event payload is wrapped in `epsych.TrialsData`.

This makes the analysis object behave like a secondary event source: listeners can subscribe to `obj.Helper.NewData` instead of subscribing directly to the runtime.

## Public API

### `refresh`

```matlab
obj.refresh()
```

`refresh` recomputes the subclass results from the current `DATA`, runs any subclass post-refresh hook, and emits a `NewData` event through `obj.Helper` when runtime trial state is available.

This is the main method to call in offline workflows after changing DATA-dependent configuration.

### `update_data`

```matlab
obj.update_data(~, event)
```

This is the runtime callback used by the `NewData` listener. It:

- copies `event.Data.DATA` into `obj.DATA`
- recomputes subclass results
- forwards the updated event data to listeners on `obj.Helper`

In normal use, subclasses do not call this directly. It is invoked by the runtime event system.

### `delete`

```matlab
delete(obj)
```

The destructor removes any valid listener handles stored in `hl_NewData` so online analysis objects do not leave stale runtime subscriptions behind.

## Key Properties

### Configuration and state

- `Parameter`
  - Observable property holding either the tracked parameter object or, in offline mode, the `DATA` field name string.
- `RUNTIME`
  - Runtime object used in online mode.
- `DATA`
  - Cached per-trial data array.
- `Helper`
  - Local event broadcaster used to publish analysis updates.

### Dependent properties

- `responseCodes`
  - Reads `DATA.ResponseCode` when present and falls back to `DATA.RespCode`.
  - Returns a row vector of `uint32` values or an empty `uint32` array.
- `trialCount`
  - Returns `numel(obj.DATA)`.
- `ExcludedTrials`
  - Stores exclusions either as a logical mask or explicit trial indices.
  - Setting a new value automatically triggers `refresh`.
- `ParameterName`
  - Returns a display-friendly name for labels and titles.
  - Uses `Parameter.Name` when available, otherwise falls back to the parameter class name or string itself.

### Abstract property

- `Results`
  - Each subclass defines its own result structure or value container.

## Protected Helper Methods For Subclasses

These methods are the main extension points and shared utilities that subclasses use.

### `parameterFieldName_`

Returns the `DATA` field name corresponding to the tracked parameter:

- if `Parameter` is a string in offline mode, it returns that string
- otherwise it uses `Parameter.validName`

The current staircase subclass uses this helper when extracting tracked stimulus values.

### `dataFieldValues_`

Returns a row vector containing the values of a named `DATA` field. It also unwraps saved `Value` containers through `unwrapValueContainer_`.

This matters because saved trial data may store fields as structs or objects that expose a `Value` property rather than plain numeric values.

### `resolveDataFieldName_`

Searches candidate field names and returns the first one present in `DATA`. The `responseCodes` property uses this to support both `ResponseCode` and `RespCode`.

### `trialTypeValues_`

Returns the saved numeric `TrialType` values from `DATA` when available.

### `trialTypeMask_`

Builds a logical mask for a requested trial type. It uses one of two paths:

- if `DATA.TrialType` exists, compare those numeric values directly
- otherwise decode response codes through `epsych.BitMask.decode`

The resulting mask is then reshaped, trimmed or padded to match `trialCount`, and filtered through the current excluded-trial mask.

The staircase subclass uses this helper to select stimulus trials.

### `bitMaskToTrialTypeValue_`

Converts a `TrialType` bit selection from `epsych.BitMask` into the numeric `TrialType` value stored in saved `DATA`.

### `normalizeExcludedTrialsValue_`

Normalizes `ExcludedTrials` values and validates them. Accepted forms are:

- empty
- logical mask
- numeric vector of finite positive integers

Invalid values throw a class-scoped `MException`.

### `excludedTrialMask_`

Converts the stored exclusion setting into a logical mask aligned to `trialCount`. This is what `trialTypeMask_` uses when removing excluded trials from downstream analysis.

## Data Expectations

This class assumes each trial entry in `DATA` is a struct with fields that may include:

- `ResponseCode` or `RespCode`
- `TrialType`
- one or more parameter fields, often named from `Parameter.validName`

Depending on how the data was saved, those fields may contain plain values or `Value` wrappers. `unwrapValueContainer_` handles both formats.

In online mode, the runtime event payload is expected to look like the standard EPsych `NewData` event, where `event.Data.DATA` contains the per-trial array and the broader event payload can be wrapped in `epsych.TrialsData`.

## Minimal Subclass Pattern

A subclass built on `psychophysics.Psych` typically needs to do three things:

1. Declare a concrete `Results` property.
2. Call the base constructor.
3. Implement `recomputeResults_`.

Example outline:

```matlab
classdef MyAnalysis < psychophysics.Psych
    properties (SetAccess = protected)
        Results = struct()
    end

    methods
        function obj = MyAnalysis(source, Parameter, options)
            arguments
                source = []
                Parameter = []
                options.ExcludedTrials = []
            end
            obj = obj@psychophysics.Psych(source, Parameter, ExcludedTrials=options.ExcludedTrials);
            if isempty(obj.RUNTIME)
                obj.refresh();
            end
        end
    end

    methods (Access = protected)
        function recomputeResults_(obj)
            fieldName = obj.parameterFieldName_();
            values = obj.dataFieldValues_(fieldName);
            mask = obj.trialTypeMask_(epsych.BitMask.TrialType_0);

            obj.Results = struct( ...
                'Values', values, ...
                'SelectedMask', mask);
        end
    end
end
```

That is the same general inheritance pattern used by the staircase implementation in `obj/+psychophysics/@Staircase/Staircase.m`.

## Examples

### Offline analysis from saved DATA

```matlab
P = MyAnalysis(DATA, "Depth");
disp(P.Results)
```

In offline mode, you can pass a string field name for `Parameter` as long as `DATA` already contains that field.

### Online analysis from a runtime object

```matlab
P = MyAnalysis(RUNTIME, ParameterObject);
```

In online mode, the object subscribes to `RUNTIME.HELPER.NewData` automatically and updates whenever new trials arrive.

### Excluding trials

```matlab
P.ExcludedTrials = [1 4 7];
```

or

```matlab
P.ExcludedTrials = [false true false true];
```

Changing `ExcludedTrials` triggers a full refresh so subclass results stay consistent with the filtered trial set.

### Listening for analysis updates

```matlab
addlistener(P.Helper, 'NewData', @(src, evt) disp(P.Results));
```

This allows GUIs or downstream analyses to respond when the psychophysics object recomputes.

## Notes And Limitations

1. `psychophysics.Psych` is abstract and cannot be used directly because `Results` and `recomputeResults_` must be supplied by a subclass.
2. Online mode requires a runtime object with a compatible `HELPER` event source and, for some refresh paths, access to `TRIALS`.
3. If neither `TrialType` nor response-code fields exist in `DATA`, `trialTypeMask_` cannot infer trial membership and will return all false for decoded paths with no response codes.
4. `ExcludedTrials` values outside the current trial count are ignored when building the effective logical mask.
5. `responseCodes` are normalized to `uint32`, which matches `epsych.BitMask.decode` expectations.

## See Also

- `obj/+psychophysics/@Staircase/Staircase.m`
- `obj/+epsych/BitMask.m`
- `obj/+epsych/@Helper/Helper.m`
- `obj/+epsych/TrialsData.m`
- `documentation/Staircase.md`
- `documentation/Architecture_Overview.md`

## Changelog

- 2026-04-06: Added documentation for the `psychophysics.Psych` base class, including online/offline lifecycle behavior, extension hooks, excluded-trial handling, and subclass usage guidance.