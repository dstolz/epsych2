# Protocol Designer

`epsych.ProtocolDesigner` provides a lightweight editor for `epsych.Protocol` objects. It is intended to replace the older GUIDE-based protocol editing workflow with a package-based UI that operates directly on the object model.

## Launching

Open the designer from MATLAB with:

```matlab
ui = epsych.ProtocolDesigner();
```

To edit an existing protocol object:

```matlab
protocol = epsych.Protocol.load('example.eprot');
ui = epsych.ProtocolDesigner(protocol);
```

## Header Controls

The header area exposes the protocol info field together with buttons for:

- Opening this documentation
- Saving the current protocol to an `.eprot` file
- Loading an existing `.eprot` or `.prot` file

The status label at the top right reports the last successful action or validation error.

## Parameters Tab

The Parameters tab is the main editing surface.

### Interface Controls

Use **Add Interface** to create a new interface. Available interface types and their required setup options come from each hardware class through `getCreationSpec()`. This keeps the GUI aligned with the interface implementation instead of duplicating option definitions in the designer.

Use **Remove Interface** to remove the currently selected interface.

### Filtering and Target Selection

- **Filter Interface** controls which interfaces appear in the parameter table.
- **Target Interface** selects where new parameters will be added.
- **Target Module** selects the module within that interface.

### Parameter Table

The parameter table exposes the key editable fields for each `hw.Parameter`.

Important behaviors:

- `Type` is constrained to the supported parameter types.
- `Access` is constrained to the supported access modes.
- `Is Random` can only remain enabled when the parameter has finite `Min` and `Max` values.
- `File` parameters open a file-picker workflow for the `Value` field instead of requiring manual path entry.
- `Expression` is available for numeric scalar parameter types and computes the underlying `Value` from other parameters.
- Interface-specific parameter names displayed in the GUI may be uniquified for readability, while the original hardware-facing name is preserved internally for backend communication.

For file parameters, use **Browse File Value** after selecting a row in the parameter table. Editing the `Value` cell or changing `Type` to `File` also launches the file picker.

For derived numeric parameters, enter a formula in the `Expression` column. The table keeps the computed result in `Value` and recalculates expression-backed parameters when dependent parameter values change or when the parameter table refreshes.

Expression notes:

- Expressions are only allowed for `Float`, `Integer`, and `Boolean` parameter types.
- Expressions must evaluate to a finite numeric scalar.
- You can reference other numeric scalar parameters by their parameter name when it is unique, or by a qualified alias based on interface, module, and parameter names.

Parameter-level file-picker behavior can be customized through `hw.Parameter.UserData` fields such as:

- `FileFilter`
- `FileExtensions`
- `FileDialogTitle`
- `AllowMultipleFiles` or `FileMultiSelect`
- `InitialPath` or `FileInitialPath`

### Add Parameter

**Add Parameter** creates a new parameter immediately in the selected module using default values. After creation, edit the new row directly in the table.

Default values currently include:

- `Value = 1`
- `Type = 'Float'`
- `Access = 'Any'`
- visible, non-random, non-array, non-trigger
- `Min = -inf`, `Max = inf`

If the requested name already exists in the selected module, a unique suffix is appended automatically.

## Options Tab

The Options tab edits protocol-level settings stored on the `epsych.Protocol` object.

This includes:

- trial function name
- number of repetitions
- inter-stimulus interval
- randomization
- runtime compilation
- WAV buffer inclusion
- OpenEx usage
- connection type

Changes in this tab are applied directly to the protocol object.

## Compiled Preview Tab

Use **Compile Protocol** to compile the current protocol and inspect the resulting trial table.

The compiled preview is useful for checking:

- trial counts
- cross-product expansion behavior
- randomized and repeated trial generation
- final parameter values before runtime execution

## Interface Metadata Contract

Hardware interface classes are expected to define a static `getCreationSpec()` method. The returned struct describes:

- the interface label and description
- the creation function
- required and optional input fields
- input types such as text, numeric, choice, or list
- optional GUI hints such as `controlType`, `getFile`, `getFolder`, `fileFilter`, and `fileDialogTitle`

This is how the designer knows which prompts to show when adding hardware like `hw.TDT_Synapse` or `hw.TDT_RPcox`.

When `getFile` is enabled, the designer adds a **Browse** button backed by `uigetfile`. When `getFolder` is enabled, it uses `uigetdir`. File pickers remember the last browsed directory for the current MATLAB session and otherwise fall back to the repository root.

## Notes

- The designer works directly against the object model, so edits affect the in-memory `epsych.Protocol` instance immediately.
- Compile-time and runtime validation still depend on the underlying protocol and parameter classes.
- If an edit fails, the status label reports the error and the table is refreshed back to the last valid state.
