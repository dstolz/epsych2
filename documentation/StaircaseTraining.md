# StaircaseTraining

`gui.StaircaseTraining` is a small MATLAB App Designer–style UI for configuring staircase (“progressive training”) step rules and bounds around a single `hw.Parameter`.

It is designed to be embedded inside another UI (panel/grid/etc.) or used standalone in its own figure.

## What problem it solves

In many training/behavior tasks, you want to adjust a parameter over time based on trial outcomes:

- If the subject is doing well, make the task *harder* (decrease a parameter).
- If the subject is struggling, make the task *easier* (increase a parameter).

This class provides:

- A table to edit `StepUp`, `StepDown`, `MinValue`, `MaxValue` and each field’s valid limits.
- A method (`updateParameter`) to apply an “up” or “down” step to `Parameter.Value`.
- A simple plot of the parameter value history.

## Key concepts

### Immediate commit (table edits)

Edits in the table apply immediately:

- Changing a **Value** cell directly updates the corresponding public property on the object (for example, editing “Step Up” updates `obj.StepUp`).
- Changing a **limit** cell directly updates the corresponding `*Limits` property (for example, editing the lower bound for “Step Up” updates `obj.StepUpLimits(1)`).

The GUI does **not** automatically change `Parameter.Value` when you edit these settings. `Parameter.Value` only changes when you call `updateParameter`.

### Reject-on-violation validation

When you edit the table, the edit is validated before it is accepted. If it would violate constraints, the GUI:

- Rejects the edit.
- Reverts the row back to the last committed value.
- Shows an error message in the status label at the bottom.

Validation rules:

- `MinValue` must be ≤ `MaxValue`.
- Every value must remain within its corresponding limits (`StepUp` within `StepUpLimits`, etc.).
- Step sizes (`StepUp`, `StepDown`) must be finite and > 0.
- Step limits must be ≥ 0, and the upper limit must be > 0.

### Step semantics

- `StepUp` and `StepDown` are positive magnitudes.
- `updateParameter("up")` increases `Parameter.Value` by `StepUp`.
- `updateParameter("down")` decreases `Parameter.Value` by `StepDown`.
- After stepping, the value is clamped to the range `[MinValue, MaxValue]`.

“Clamped” means the value is forced to stay inside the range:

- If it goes below `MinValue`, it becomes `MinValue`.
- If it goes above `MaxValue`, it becomes `MaxValue`.

## Requirements and dependencies

### Parameter object

The constructor requires a `hw.Parameter` instance (from `obj/+hw/Parameter.m`). `gui.StaircaseTraining` uses:

- `Parameter.Name` (shown at the top)
- `Parameter.Value` (read/updated by `updateParameter`)
- `Parameter.ValueStr` (used for display in the UI)

### MATLAB UI components

The GUI uses standard UI components:

- `uifigure` (only if you do not pass a `Parent`)
- `uigridlayout`
- `uitable`
- `uilabel`
- `uiaxes` (for the value history plot)

## Constructor

```matlab
G = gui.StaircaseTraining(Parameter)
G = gui.StaircaseTraining(Parameter, Name=Value, ...)
```

Name–value options:

- `Parent` (default `[]`): if provided, the GUI is embedded in this container.
- `MinValue`, `MaxValue`, `StepUp`, `StepDown`: initial committed values.
- `StepUpLimits`, `StepDownLimits`, `MinValueLimits`, `MaxValueLimits`: initial limits.
- `WindowStyle`: `"alwaysontop" | "modal" | "normal"` (only used when `Parent=[]`).

## The table layout

The table has 4 rows and 4 columns:

- Rows:
  1. Step Up
  2. Step Down
  3. Minimum
  4. Maximum

- Columns:
  1. **Param** (read-only label)
  2. **≥** (editable lower limit)
  3. **≤** (editable upper limit)
  4. **Value** (editable current value)

When you edit a cell, the entire row is refreshed from the committed properties.

## updateParameter

```matlab
v = G.updateParameter("up")
v = G.updateParameter("down")
```

- Input is case-insensitive.
- Any other input is a no-op (no change).
- Returns the new parameter value `v`.
- Appends the new value to `G.ValueHistory` and refreshes the history plot.

Important: `updateParameter` directly writes `Parameter.Value`. If another part of your application is also updating the same parameter, you must handle synchronization outside of this class.

## Usage examples

### Example 1: Standalone window

```matlab
% Assuming you already have (or create) a hw.Parameter named p
p.Name = 'Tone Level';
p.Value = 20;

G = gui.StaircaseTraining(p, ...
    MinValue=0, MaxValue=80, ...
    StepUp=5, StepDown=2);

% Later, after a trial completes:
G.updateParameter("down");   % make it harder
G.updateParameter("up");     % make it easier
```

### Example 2: Embedded in an existing app layout

```matlab
fig = uifigure('Name','Task');
g = uigridlayout(fig,[1 1]);

% p is a hw.Parameter
G = gui.StaircaseTraining(p, Parent=g);
```

## Lifecycle and cleanup

- If `Parent` is not provided (`Parent=[]`), the class creates and owns a new `uifigure`.
- When the object is deleted, it deletes the UI components it owns.
- If it owns its figure, it saves the window position using MATLAB preferences:
  - Preference group: `StaircaseTraining`
  - Preference key: `Position`

If you embed the GUI in another container, the class attaches a listener so it will delete itself when the parent is destroyed.

## Notes and limitations

- The value history starts with the initial `Parameter.Value` when the GUI is constructed.
- The history plot is intentionally simple (axes labels are hidden).
- This class validates the GUI’s own `MinValue/MaxValue` bounds; it does not enforce the `hw.Parameter.Min`/`Max` constraints.

## Related files

- `obj/+gui/@StaircaseTraining/StaircaseTraining.m` (this class)
- `obj/+hw/Parameter.m` (`hw.Parameter` definition)
