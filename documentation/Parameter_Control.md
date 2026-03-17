# `gui.Parameter_Control`

`gui.Parameter_Control` binds a single `hw.Parameter` to a small App Designer-style UI control (edit field, dropdown, checkbox, toggle, label, or button). It keeps the displayed value synchronized with the underlying parameter and can either:

- **Commit immediately** (`autoCommit=true`) when the user changes the control, or
- **Stage edits** (`autoCommit=false`, default) by marking the control as “changed” until another component (commonly `gui.Parameter_Update`) commits updates.

This class is intended for use inside `uifigure`/`uigridlayout`-based GUIs.

## Quick start

### Numeric edit field (default)

```matlab
fig = uifigure;
layout = uigridlayout(fig,[1 1]);

p = R.S.Module.add_parameter("MyParam", 0.5);
ctrl = gui.Parameter_Control(layout, p);  % Type='editfield'
```

### Toggle button with immediate commit

```matlab
p = R.S.Module.add_parameter("DeliverTrials", 0);
ctrl = gui.Parameter_Control(layout, p, Type="toggle", autoCommit=true);
ctrl.Text = "Deliver Trials";          % override label text
ctrl.colorNormal = fig.Color;          % customize appearance
colors = jet(5);
ctrl.colorOnUpdate = colors(3,:);      % single 1x3 RGB value
```

## Construction

```matlab
obj = gui.Parameter_Control(parent, parameter)
obj = gui.Parameter_Control(parent, parameter, Type=TYPE, autoCommit=TF)
```

### Inputs

- `parent`
  - Graphics container to hold the control (commonly a `uigridlayout`, `uipanel`, or `uifigure`).
- `parameter`
  - A `hw.Parameter` instance that supplies name/description/value and receives updates.

### Name-value options

- `Type` (char)
  - One of: `editfield`, `dropdown`, `checkbox`, `toggle`, `readonly`, `momentary`.
- `autoCommit` (logical)
  - If `true`, user changes are written to `parameter.Value` immediately.
  - If `false`, user changes only update the UI and set `obj.ValueUpdated=true` until committed elsewhere.

## UI types

`Type` selects which UI element is created inside `parent`:

- `editfield`
  - `uilabel` + numeric `uieditfield`
  - Uses `parameter.Min`/`parameter.Max` for editfield limits.
  - If `parameter.Type` is `'Integer'`, fractional input is rounded.
- `dropdown`
  - `uilabel` + `uidropdown`
  - Use `obj.Values` to define the allowed values (stored in `ItemsData`).
- `checkbox`
  - A single `uicheckbox`
- `toggle`
  - A single state `uibutton` (`'state'`)
- `momentary`
  - A single push `uibutton` (`'push'`)
  - On click, calls `parameter.Trigger` instead of writing `parameter.Value`.
- `readonly`
  - A single `uilabel` showing `parameter.ValueStr`.

## Key properties

### `Parameter`
The bound `hw.Parameter` instance.

### `Value`
- Reads from / writes to the UI element’s `Value`.
- Setting `obj.Value = ...` simulates a value change on the control (it routes through `value_changed`).

Important behavior:
- When `autoCommit=true`, **programmatic** `obj.Value = ...` does **not** auto-commit to `Parameter.Value` (the method returns early when there is no UI event source). User-triggered UI events still commit.

### `Values` (dropdown only)
For `Type='dropdown'`, `obj.Values` maps to `uidropdown.ItemsData`.

- If `Values` is numeric, `Items` are displayed as strings.
- Setting `obj.Value` for numeric dropdowns uses `isapprox(...,'loose')` matching to tolerate type differences.

### `Text`
Label text shown next to the control (or on the control itself for checkbox/toggle/button types).

### `ValueUpdated` (read-only)
A flag indicating whether the UI currently differs from the underlying parameter:

- `true` when `obj.Value` is not equal to `obj.Parameter.Value`
- `false` after committing the value or calling `reset_label()`

This is designed to be watched by `gui.Parameter_Update`.

### Color properties
The control uses several color properties to provide feedback:

- `colorNormal` (default background)
- `colorOnUpdate` (pending local edit)
- `colorOnUpdateAuto` (reserved for auto-commit feedback; currently not used)
- `colorOnUpdateExternal` (parameter changed externally)
- `colorOnError` (validation failed)

You can override these after construction to match your GUI’s styling.

## Editing and commit flow

### Default behavior (`autoCommit=false`)
1. User changes the UI control.
2. `obj.ValueUpdated` becomes `true` if the new UI value differs from `Parameter.Value`.
3. The control background changes to `colorOnUpdate`.
4. Another component (commonly `gui.Parameter_Update`) decides when to apply the staged values.

### Auto-commit (`autoCommit=true`)
- User changes are immediately written to `Parameter.Value`.
- If you also need the change reflected in trial tables or runtime configuration, pair this with the surrounding system’s update logic.

## Validation with `EvaluatorFcn`

You can attach custom validation/coercion by setting:

- `obj.EvaluatorFcn` (function handle)
- `obj.EvaluatorArgs` (cell array of extra args)

Signature:

```matlab
[value, success] = EvaluatorFcn(obj, event, parameter, extraArgs{:})
```

- `event` is the UI event converted to a struct; it always contains `Value` and may include `PreviousValue`.
- Return `success=false` to indicate invalid input; the control briefly flashes `colorOnError`.
- The returned `value` is written back into the UI, and (if `autoCommit=true`) may be committed to the underlying parameter.

## Enable/disable behavior (parameter parent “mode”)

`Parameter_Control` listens to `parameter.Parent.mode` (PostSet). When `mode > 1`, the UI is enabled; otherwise the UI is disabled. This is used to lock out edits depending on system state.

## Integration with `gui.Parameter_Update`

A common pattern is:

- Create multiple `gui.Parameter_Control` objects with `autoCommit=false`
- Register them with a single `gui.Parameter_Update` instance
- When the update button is pressed, it commits all staged edits

Example sketch:

```matlab
% Create several controls
h(1) = gui.Parameter_Control(layout, p1, Type="editfield");
h(2) = gui.Parameter_Control(layout, p2, Type="dropdown");
h(2).Values = [0 1 2];

% Create an update button that watches ValueUpdated
u = gui.Parameter_Update(RUNTIME, layoutButton);
u.watchedHandles = h;
```

## Related files

- Source: obj/+gui/Parameter_Control.m
- Update button: obj/+gui/Parameter_Update.m
- Polling display: obj/+gui/Parameter_Monitor.m
- GUI utility: obj/+gui/@Helper/Helper.m

## Notes and gotchas

- `readonly` controls display `Parameter.ValueStr` and highlight when the parameter changes externally.
- For `dropdown`, external parameter values that are not already in `ItemsData` are added automatically so the UI can display them.
- For `momentary`, button clicks call `Parameter.Trigger` (useful for actions rather than numeric/boolean settings).
