# gui.PhaseSelector

![gui.PhaseSelector component: a phase dropdown with Load and Save buttons, plus a description label](images/PhaseSelector.png)

`gui.PhaseSelector` is a GUI component for switching between named **experiment phases** — saved parameter sets stored as JSON files. It lets an operator move a subject between training stages (for example, shaping → detection → psychometric testing) without editing the protocol or restarting the session.

The first half of this page explains the workflow for operators; the integration section at the end is for developers embedding the component in a task GUI.

Source class: [obj/+gui/@PhaseSelector/PhaseSelector.m](../../obj/+gui/@PhaseSelector/PhaseSelector.m)

## What a phase file is

A phase file is a JSON snapshot of parameter values (plus optional description text), produced by `epsych.Runtime.writeParametersJSON` or by the PhaseSelector's own save button. Files live together in a phase directory (for example `cl/@cl_AppetitiveDetection_GUI_B/Phases/`), and each file's name (without extension) becomes the phase name shown in the dropdown.

Because phases are plain JSON, they can be inspected and edited in any text editor. `epsych.Runtime.createTemplateJSON` writes a starter file showing the expected fields.

## Using the phase selector (operators)

The component appears in task GUIs (such as the appetitive detection GUI) as a dropdown with two buttons, shown in the screenshot above:

- **Dropdown** — pick a phase by name. Selecting a phase does not change anything, but prints a table of parameters with their current values and the values the phase would apply to the command window, so you can sanity-check the change before loading it.
- **Load** — apply the selected phase: parameter values from the file are written to the live parameters and synchronized into the trial table.
- **Save** — snapshot the current parameter values to a new phase JSON file (you are prompted for a name).

Typical workflow:

1. During setup, get each training stage's parameters right once, then **Save** a phase file per stage.
2. During later sessions, pick the subject's stage from the dropdown, check the printed parameter changes in the command window, then **Load**.

Loads are logged on the runtime (`RUNTIME.Phase`) with a timestamp and source path, so the session record shows which phase was active.

## Integration (developers)

```matlab
ps = gui.PhaseSelector(RUNTIME, phaseDir);  % phaseDir contains *.json phase files
h  = ps.createGUI(parentContainer);          % dropdown + Load/Save buttons
```

Individual controls can also be placed separately (`addPhaseSelectDropdown`, `addLoadPhaseButton`, `addSavePhaseButton`, `addDescriptionLabel`) when the host GUI needs a custom layout.

Key behavior:

- `PhasePath` is observable; assigning a new directory rescans for `*.json` files and repopulates the dropdown.
- `onPhaseSelectionChanged` calls `showPhaseInfo` automatically whenever the dropdown selection changes to a real phase, printing the current-vs-phase comparison table (built by `computePhaseChanges`) to the command window.
- `loadPhaseParameters` delegates to `RUNTIME.readParametersJSON`, which resolves each named parameter through `RUNTIME.find_parameter` and assigns its value; `RUNTIME.updateTrialsFromParameters` then pushes writable values into the trial table.
- `writePhaseParameters` delegates to `RUNTIME.writeParametersJSON`.

Keep the handle returned by the constructor on your GUI object so the component is not garbage-collected, and follow the cleanup guidance in [../design/Customized_GUI_Instructions.md](../design/Customized_GUI_Instructions.md).

## Related documentation

- [../epsych/epsych_Runtime.md](../epsych/epsych_Runtime.md) — `writeParametersJSON` / `readParametersJSON` reference
- [../design/Customized_GUI_Instructions.md](../design/Customized_GUI_Instructions.md) — building task GUIs that host this component
- [Parameter_Update.md](Parameter_Update.md) — committing individual parameter edits (complementary to phase loads)
