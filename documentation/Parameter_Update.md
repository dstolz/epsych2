# `gui.Parameter_Update`

`gui.Parameter_Update` is a small controller class that owns an **â€œUpdate Parametersâ€** button and keeps it in sync with a set of parameter editor widgets.

It solves a common GUI workflow:

- Let the user edit several parameters without immediately pushing changes to hardware.
- Visually indicate when there are **pending (uncommitted) edits**.
- Commit those edits either:
  - **for upcoming trials** (default), or
  - **immediately** (when a modifier key chord is held).

---

## Where it fits

In EPsych, parameter editing is typically done with [`gui.Parameter_Control`](../obj/+gui/Parameter_Control.m), which binds a single [`hw.Parameter`](Parameter.md) to a UI control and exposes a boolean `ValueUpdated` flag when the UI differs from the underlying parameter value.

`gui.Parameter_Update` watches one or more `gui.Parameter_Control` objects and:

- Enables/disables the button based on whether any `ValueUpdated` flags are true.
- Updates button color/text to reflect the current state.
- Commits pending edits into:
  - `RUNTIME.TRIALS.trials` (so the new values apply to subsequent trials), and
  - optionally into `hw.Parameter.Value` (immediate mode, or software-only parameters).

---

## Basic usage

Typical pattern inside a GUI that already has a `RUNTIME` struct and a parent container (`uigridlayout`, `uipanel`, etc.):

```matlab
% Create parameter controls (one per hw.Parameter)
ctrl(1) = gui.Parameter_Control(parent, RUNTIME.HW.Stim.PulseWidth, Type="editfield");
ctrl(2) = gui.Parameter_Control(parent, RUNTIME.HW.Stim.Level,      Type="editfield");

% Create the update button controller
updater = gui.Parameter_Update(RUNTIME, parent);

% Tell it which controls to watch
updater.watchedHandles = ctrl;
```

User experience:

- If the user changes any control, the button becomes enabled and shows **â€œUpdate Parametersâ€**.
- If nothing is pending, the button disables and shows **â€œNothing to Updateâ€**.
- Holding **Ctrl + Shift + Alt** while clicking changes behavior to **Immediate** (see below).

---

## Immediate vs. next-trial updates

### Default: â€œUpdate Parameters for the Next Trialâ€

When clicked normally, `commit_changes` updates the **trial table** (`RUNTIME.TRIALS.trials`) for any parameters that are part of the protocolâ€™s write-parameters list.

This is done by looking up the parameterâ€™s protocol column via:

- `loc = RUNTIME.TRIALS.writeParamIdx`
- `P.validName` (from `hw.Parameter.validName`)

and assigning the updated value into the corresponding column.

Important nuance:

- For non-software interfaces, this mode typically **does not** write directly to `P.Value` (hardware) unless the parameter belongs to a software-only parent.

### â€œUpdate Parameters Immediatelyâ€ (Ctrl + Shift + Alt)

When the modifier chord is held, `commit_changes` will additionally write the current UI value into the underlying `hw.Parameter`:

- `P.Value = watchedControl.Value`

This is intended for situations where you need the new setting applied right away (e.g., during an ongoing run), rather than waiting for the next trial boundary.

---

## What `watchedHandles` must provide

`watchedHandles` is expected to be an array of handle objects with at least:

- A **set-observable** logical property `ValueUpdated`
- A property `Value` containing the current UI value
- A property `Parameter` referencing an `hw.Parameter`
- A method `reset_label()` that clears the pending-edit indication

`gui.Parameter_Control` satisfies this contract.

---

## Runtime/trials expectations

`commit_changes` expects `RUNTIME` to have (single-subject) trial state shaped like:

- `RUNTIME.TRIALS.trials`: a table-like cell array storing per-trial write-parameter values
- `RUNTIME.TRIALS.writeParamIdx`: struct mapping parameter valid-names to column indices

This mapping is created during runtime start-up (see [`ep_TimerFcn_Start`](../runtime/timerfcns/ep_TimerFcn_Start.m)).

**Current limitation:** the implementation notes â€œCURRENTLY ONLY WORKS FOR SINGLE SUBJECTâ€ and uses `RUNTIME.TRIALS` as a scalar struct. If your experiment runs multiple subjects simultaneously (where `RUNTIME.TRIALS(i)` is used), youâ€™ll need one updater per subject (or extend the class with a subject index).

---

## Keyboard handling note

The constructor installs callbacks on the owning figure:

- `Figure.WindowKeyPressFcn = @obj.key_press`
- `Figure.WindowKeyReleaseFcn = @obj.key_release`

If other code in your GUI also needs `WindowKeyPressFcn`/`WindowKeyReleaseFcn`, you may need to chain callbacks or centralize key handling so the most recent assignment does not overwrite other handlers.

---

## Related files

- [obj/+gui/Parameter_Update.m](../obj/+gui/Parameter_Update.m): Implementation
- [obj/+gui/Parameter_Control.m](../obj/+gui/Parameter_Control.m): Typical watched editor control
- [documentation/Parameter.md](Parameter.md): `hw.Parameter` overview
- [runtime/timerfcns/ep_TimerFcn_Start.m](../runtime/timerfcns/ep_TimerFcn_Start.m): Creates `TRIALS.writeParamIdx`
