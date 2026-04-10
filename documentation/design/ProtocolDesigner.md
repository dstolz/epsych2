# Protocol Designer

`epsych.ProtocolDesigner` provides a lightweight editor for `epsych.Protocol` objects. It is implemented as a package class folder under `obj/+epsych/@ProtocolDesigner` with separate method files for UI construction, callbacks, and private helpers, replacing the previous monolithic single-file class.

The designer edits the in-memory protocol directly. Most changes are applied immediately to the bound `epsych.Protocol` instance, and invalid edits are reverted by refreshing the affected table or control state.

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

The status label along the bottom of the window reports the last successful action or validation error.

## Parameters Tab

The Parameters tab is the main editing surface.

### Interface Controls

Use **Add Interface** to create a new interface. Available interface types and their required setup options come from each hardware class through `getCreationSpec()`. This keeps the GUI aligned with the interface implementation instead of duplicating option definitions in the designer.

Creation options can now be marked as either interface-level or module-level. Interface-level options apply once to the owning `hw.Interface`, while module-level options supply one value per `hw.Module` created under that interface. The add/edit dialog shows this distinction in a dedicated `Level` column.

Use **Remove Interface** to remove the currently selected interface.

For interfaces that expose editable module lists, use **Add Module** and **Remove Module** from the Current Interfaces panel. This is primarily intended for software-backed or serialized interfaces where the designer owns the module list directly. Hardware interfaces such as live TDT backends can still expose multiple modules through their creation options and discovery logic, but may not support manual module edits after construction.

### Filtering and Target Selection

- **Filter Interface** controls which interfaces appear in the parameter table.
- **Add To Interface** selects where new parameters will be added.
- **Module** selects the target module within that interface.
- Selecting a module node in the tree focuses the parameter table on that module within the selected interface.

For module-level creation options, enter one value per module. Some fields may allow a single scalar value to be broadcast to every module; the dialog guidance calls that out explicitly.

### Parameter Table

The parameter table exposes the key editable fields for each `hw.Parameter`.

The visible columns are:

- `Interface`
- `Module`
- `Name`
- `Type`
- `Expression`
- `Pair`
- `Value`
- `Min`
- `Max`
- `Random`
- `Access`
- `Unit`
- `Visible`
- `Trigger`
- `Description`

Important behaviors:

- `Type` is constrained to the supported parameter types.
- `Access` is constrained to the supported access modes.
- `Pair` makes parameters co-vary during compilation, even across different modules or interfaces.
- `File` parameters use a dedicated file editor instead of relying on direct path entry.
- `Expression` is available for numeric scalar parameter types and computes the underlying `Value` from other parameters.

The parameter table is also where cross-parameter validation shows up. If an expression can no longer be evaluated, for example because it references a parameter that was changed to `File`, the row is highlighted in red and the status line shows the error message.

Paired parameters must expose the same number of values. A paired group behaves like the legacy buddy mechanism: the first value of each paired parameter is compiled together, then the second value of each paired parameter, and so on.

For file parameters, use **Edit Selected File Value** after selecting a row in the parameter table. Editing the `Value` cell or changing `Type` to `File` launches the same modal file editor.

The file editor supports:

- replacing the current file or file list
- adding one or more files at once
- removing selected entries from the list
- clearing the current file value
- previewing the full path of the current selection

The list emphasizes file names and shows a shortened folder hint. The full selected path or paths appear in a separate preview area below the list.

For derived numeric parameters, enter a formula in the `Expression` column. The table keeps the computed result in `Value` and recalculates expression-backed parameters when dependent parameter values change or when the parameter table refreshes.

Expression notes:

- Expressions are only allowed for `Float`, `Integer`, and `Boolean` parameter types.
- Expressions can be general MATLAB expressions and may evaluate to a single value or an array.
- Results must remain numeric or logical, and numeric results must be finite.
- You can reference other numeric scalar parameters by their parameter name when it is unique, or by a qualified alias based on interface, module, and parameter names.
- Rows with expression-evaluation errors are highlighted in red until the expression is fixed.

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
- `Access = 'Read / Write'`
- visible, non-random, non-array, non-trigger
- `Min = -inf`, `Max = inf`

If the requested name already exists in the selected module, a unique suffix is appended automatically.

## Options Tab

The Options tab edits protocol-level settings stored on the `epsych.Protocol` object.

The current controls are:

- trial function name
- inter-stimulus interval
- runtime compilation
- WAV buffer inclusion

Changes in this tab are applied directly to the protocol object.

## Compiled Preview Tab

Use **Compile Protocol** to compile the current protocol and inspect the resulting trial table.

The compiled preview is useful for checking:

- trial counts
- cross-product expansion behavior
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
- The file editor can promote a single-file parameter to a file list when multiple files are added in one operation.
