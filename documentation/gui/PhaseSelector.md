# gui.PhaseSelector

![gui.PhaseSelector component: a phase dropdown with Load and Save buttons, plus a description label](images/PhaseSelector.png)

`gui.PhaseSelector` is a GUI component for switching between named **experiment phases** — saved parameter sets stored as protocol files. It lets an operator move a subject between training stages (for example, shaping → detection → psychometric testing) without editing the protocol or restarting the session.

The first half of this page explains the workflow for operators; the integration section at the end is for developers embedding the component in a task GUI.

Source class: [obj/+gui/@PhaseSelector/PhaseSelector.m](../../obj/+gui/@PhaseSelector/PhaseSelector.m)

## What a phase file is

Phases and protocols share one format: a phase file **is** a protocol file (`.eprot`; see [../epsych/epsych_Protocol.md](../epsych/epsych_Protocol.md)). Saving a phase serializes the session's protocol with the current parameter values (`epsych.Runtime.writeParametersProtocol`); loading a phase reads a protocol file and applies its parameters to the live session (`epsych.Runtime.readParameters`). Files live together in a phase directory (for example `cl/@cl_AppetitiveDetection_GUI_B/Phases/`), and each file's name (without extension) becomes the phase name shown in the dropdown.

Because a phase is a full protocol, it can be opened, inspected, and edited in `epsych.ProtocolDesigner`, and it carries everything the protocol format does — parameter values, design-time `Values` lists, parameter Expressions, and trial options — not just a flat value snapshot.

Legacy JSON snapshots (written by `epsych.Runtime.writeParametersJSON` in earlier versions) are still discovered and loaded; new saves always produce `.eprot` files.

## Using the phase selector (operators)

The component appears in task GUIs (such as the appetitive detection GUI) as a dropdown with two buttons, shown in the screenshot above:

- **Dropdown** — pick a phase by name. Selecting a phase does not change anything, but prints a table of parameters with their current values and the values the phase would apply to the command window, so you can sanity-check the change before loading it.
- **Load** — apply the selected phase: parameter values from the file are written to the live parameters and synchronized into the trial table, and a protocol recompile is scheduled for the next trial boundary so the phase's trial structure (value lists, expressions) takes effect, not just its current values.
- **Save** — snapshot the current session as a new phase protocol (`.eprot`; you are prompted for a name).

Typical workflow:

1. During setup, get each training stage's parameters right once, then **Save** a phase file per stage.
2. During later sessions, pick the subject's stage from the dropdown, check the printed parameter changes in the command window, then **Load**.

Loads are logged on the runtime (`RUNTIME.Phase`) with a timestamp and source path, so the session record shows which phase was active.

## Integration (developers)

```matlab
ps = gui.PhaseSelector(RUNTIME, phaseDir);  % phaseDir contains *.eprot phase files (legacy *.json also found)
h  = ps.createGUI(parentContainer);          % dropdown + Load/Save buttons
```

Individual controls can also be placed separately (`addPhaseSelectDropdown`, `addLoadPhaseButton`, `addSavePhaseButton`, `addDescriptionLabel`) when the host GUI needs a custom layout.

Key behavior:

- `PhasePath` is observable; assigning a new directory rescans for `*.eprot`, `*.prot`, and legacy `*.json` files and repopulates the dropdown.
- `onPhaseSelectionChanged` calls `showPhaseInfo` automatically whenever the dropdown selection changes to a real phase, printing the current-vs-phase comparison table (built by `computePhaseChanges`) to the command window.
- `loadPhaseParameters` delegates to `RUNTIME.readParameters`, which parses the file (`epsych.Runtime.phaseParameterData`), resolves each named parameter against the live interfaces, assigns its value, and schedules a safe-boundary protocol recompile (`TRIALS.RECOMPILE_REQUESTED`, applied by `ep_TimerFcn_RunTime`); `RUNTIME.updateTrialsFromParameters` then pushes writable values into the trial table for trials dispatched before that boundary.
- `writePhaseParameters` delegates to `RUNTIME.writeParametersProtocol`, which serializes the session's `epsych.Protocol` (`RUNTIME.Protocol`) — the runtime borrows that protocol's parameter handles, so the saved file is an exact snapshot of the live values.

Keep the handle returned by the constructor on your GUI object so the component is not garbage-collected, and follow the cleanup guidance in [../design/Customized_GUI_Instructions.md](../design/Customized_GUI_Instructions.md).

## Related documentation

- [../epsych/epsych_Runtime.md](../epsych/epsych_Runtime.md) — `writeParametersProtocol` / `readParameters` reference
- [../design/Customized_GUI_Instructions.md](../design/Customized_GUI_Instructions.md) — building task GUIs that host this component
- [Parameter_Update.md](Parameter_Update.md) — committing individual parameter edits (complementary to phase loads)
