# Protocol Designer

`epsych.ProtocolDesigner` is the interactive editor for `epsych.Protocol` objects. The implementation lives in the class folder `obj/+epsych/@ProtocolDesigner`, where the constructor, UI builders, callbacks, refresh methods, and private helper utilities are split into small files.

This documentation is for developers working on the designer itself, not just using it. It explains the runtime model, the main files in the class folder, and the extension points that matter when you add interface types or change protocol-editing behavior.

## Purpose

The designer gives a MATLAB UI for:

- creating and removing protocol interfaces
- adding and removing editable modules for supported interfaces
- editing `hw.Parameter` objects in a table-driven workflow
- changing protocol-level execution options
- compiling the current protocol and inspecting the resulting trial preview
- saving, loading, and opening the current protocol as JSON for inspection

Edits are applied directly to the bound `epsych.Protocol` object in memory. The UI is not a detached form buffer. In practice, that means most control changes mutate the model immediately, and invalid edits are rolled back by refreshing the affected control or table state.

## Entry Points

The main class file is `obj/+epsych/@ProtocolDesigner/ProtocolDesigner.m`.

Typical usage:

```matlab
ui = epsych.ProtocolDesigner();
```

Open an existing protocol object:

```matlab
protocol = epsych.Protocol.load('example.eprot');
ui = epsych.ProtocolDesigner(protocol);
```

Open directly from a saved protocol file:

```matlab
ui = epsych.ProtocolDesigner.openFromFile('example.eprot');
```

Construction flow:

1. The constructor stores the bound `epsych.Protocol` object.
2. `buildUI()` creates the top-level figure, menus, status label, and the main parameter-editing layout.
3. `refreshUI()` populates all visible state from the protocol.

The Help menu opens this file through `onOpenDocumentation()`, which resolves the path with `private/getDocumentationPath.m`.

## File Layout

The class folder is organized by responsibility.

### Core class surface

- `ProtocolDesigner.m`: class definition, shared properties, constructor, and `openFromFile()`.
- `buildUI.m`: top-level figure, menus, footer status label, and the primary layout entry point.
- `refreshUI.m`: top-level sync from model to visible controls.
- `setStatus.m`: footer messaging used across nearly every workflow.
- `suggestNextStep.m`: follow-up hint text for the status area.

### UI builders

- `buildParametersTab.m`: main designer surface for interfaces, modules, and parameters.
- `buildOptionsTab.m`: modal protocol-options panel.
- `buildPreviewTab.m`: modal compiled-preview panel.

Despite the names, the current implementation opens the options and preview views as separate dialog figures via `onOpenOptionsDialog.m` and `onOpenCompiledPreviewDialog.m`.

### Model mutation callbacks

- `onAddInterface.m`, `onRemoveInterface.m`
- `onAddModule.m`, `onRemoveModule.m`
- `onAddParam.m`, `onRemoveParam.m`
- `onParamEdited.m`, `onParamSelected.m`
- `onOptionControlChanged.m`
- `onCompile.m`
- `onSave.m`, `onLoad.m`, `onOpenAsJSON.m`

These files are the first place to read when behavior changes are needed.

### Refresh and synchronization helpers

- `refreshParameterTab.m`
- `refreshParameterTable.m`
- `refreshInterfaceControls.m`
- `refreshInterfaceSummary.m`
- `refreshModuleActionButtons.m`
- `refreshOptionsTab.m`
- `refreshCompiledPreview.m`

These methods rebuild table contents, dropdown items, tree state, and button enablement from the current protocol object.

### Private helper layer

The `private/` folder contains the reusable editing and formatting logic that keeps the callback files short. Common categories include:

- interface-spec discovery and option-dialog building
- parameter coercion and expression evaluation
- file and string value editors
- preview normalization and display formatting
- module editability checks and interface edit-state reconstruction

If a callback feels too specific or too long, similar logic probably already exists in `private/`.

## Runtime Model

The designer stores the active protocol in the `Protocol` property. Most other public properties are UI handles or selection state.

Important runtime state includes:

- `Protocol`: the bound `epsych.Protocol`
- `CurrentProtocolPath`: last save or load path
- `SelectedInterfaceRow`: currently focused interface index
- `SelectedModuleRow`: currently focused module index within the selected interface
- `SelectedParamRow` and `SelectedParamCol`: current parameter-table selection
- `ParameterHandles`: row-to-`hw.Parameter` mapping for the current table view

The general pattern is:

1. A callback mutates the model.
2. The designer refreshes only the affected slice when possible.
3. The footer status is updated with both a result message and a suggested next action.

`refreshUI()` is the full reset path and is used after initial construction and after loading a protocol from disk.

## Main Workflows

## Interface and module management

The left side of the main window is owned by `buildParametersTab.m`.

Available interface types are supplied by `private/getAvailableInterfaceSpecs.m`. The current implementation exposes normalized creation specs for:

- `hw.Software`
- serialized `hw.TDT_Synapse`
- serialized `hw.TDT_RPcox`

Two design details matter here:

- TDT-backed interfaces are created in a disconnected or serialized form for protocol editing, not as live hardware sessions.
- Duplicate interface types are prevented in `onAddInterface.m`.

When a new interface is added, `onAddInterface.m`:

1. resolves the selected interface spec
2. prompts for interface-scoped options
3. creates the interface through the spec's `createFcn`
4. adds it to the protocol
5. refreshes the interface tree, target dropdowns, and parameter table

If the interface supports editable modules, the designer immediately tries to continue into the Add Module flow.

Manual module editing is intentionally restricted. `onAddModule.m` first checks `canEditInterfaceModules()`. This supports software-backed or serialized interfaces where the designer owns the module list, while leaving live or self-managed hardware backends responsible for their own module structure.

Selecting a node in the interface tree affects both filtering and parameter-target defaults. Selecting a module node focuses the parameter view on that module within the selected interface.

## Parameter editing

The parameter table is the main editing surface. It shows one row per currently visible `hw.Parameter` and stores the backing objects in `ParameterHandles`.

Current columns are:

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

`onParamEdited.m` is the central mutation callback. It handles several special cases beyond simple property assignment.

### Type-aware editing

- Changing `Type` can coerce the current value into the new type.
- Switching to `File` opens the dedicated file editor rather than expecting direct cell editing.
- Switching to `String` can open a larger string-value editor that supports arrays.
- Non-string `Value` cells are treated as read-only in the main table.

### Expressions

Expressions are supported for numeric or logical scalar parameter types. The computed result is written back into the parameter value, and expression-backed rows are re-evaluated when the table refreshes.

Practical rules:

- expression-capable types are `Float`, `Integer`, and `Boolean`
- results must remain numeric or logical
- numeric results must be finite
- invalid expressions are highlighted and surfaced in the status label
- changing a parameter to a non-supported type clears any existing expression

The expression implementation is intentionally separate from the table callback. Read the helpers around `evaluateAndApplyParameterExpression.m`, `evaluateParameterExpression.m`, `buildExpressionContext.m`, and `applyExpressionErrorStyles.m` before changing this behavior.

### Pairing

The `Pair` column groups parameters that should advance together during compilation. Paired parameters must expose matching value counts. This is the modern version of the older buddy-style coupling behavior.

### File-backed values

File parameters are edited through a dedicated modal flow. The editor supports replacing, extending, clearing, and previewing selected paths. Parameter-specific picker behavior can be influenced through `hw.Parameter.UserData` fields such as:

- `FileFilter`
- `FileExtensions`
- `FileDialogTitle`
- `AllowMultipleFiles` or `FileMultiSelect`
- `InitialPath` or `FileInitialPath`

This behavior is implemented in the private editing helpers rather than directly in the table callback.

### New parameters

`onAddParam.m` creates a new parameter in the currently selected target module using default values, then refreshes the table so the row can be edited in place. If the requested name already exists, the designer generates a unique suffix.

## Protocol options

The Protocol Options dialog is opened from `onOpenOptionsDialog.m` and built by `buildOptionsTab.m`.

The current editable protocol-level settings are:

- trial function
- inter-stimulus interval in milliseconds
- compile-at-runtime flag
- include-WAV-buffers flag

These controls write directly to the bound protocol through `onOptionControlChanged.m`. They are not staged separately.

## Compiled preview

The Compiled Preview dialog is opened from `onOpenCompiledPreviewDialog.m`. That dialog is immediately compiled by calling `onCompile(dialog)` after the preview UI is built.

`onCompile.m` delegates to `obj.Protocol.compile()`, refreshes the preview table, and reports the resulting trial count. Compile failures are routed through the designer's error-reporting path instead of being left as raw command-window exceptions.

The preview path is useful when you need to verify:

- final trial count
- parameter expansion behavior
- cross-parameter pairing effects
- the display format of compiled values before runtime execution

The normalization helpers in files such as `normalizeCompiledPreviewData.m`, `normalizeCompiledPreviewValue.m`, and `normalizeCompiledPreviewValueAsText.m` are the right place to adjust preview formatting.

## Persistence and inspection

The File menu created in `buildUI.m` exposes four developer-relevant workflows:

- edit protocol info text
- load a saved protocol
- save the current protocol
- open the current protocol as JSON

`onOpenAsJSON.m` serializes the current protocol to a temporary JSON file and asks the host OS to open it with the default JSON editor. This is useful when you need to inspect the serialized shape without saving over a working `.eprot` file.

Recent protocol handling is managed through the recent-protocol menu helpers and `CurrentProtocolPath`.

## Interface-spec contract

The designer does not hardcode most interface prompts. Instead, it relies on interface creation specs and normalizes them through `hw.InterfaceSpec.normalize(...)`.

An interface spec provides the metadata required to build add-interface and option dialogs, including:

- label and description
- creation function
- available fields
- field types
- default values
- optional scopes such as interface-level versus module-level
- UI hints such as file and folder pickers

When you add support for a new interface type in ProtocolDesigner, the usual steps are:

1. expose or adapt a `getCreationSpec()` contract on the interface class
2. register the spec in `private/getAvailableInterfaceSpecs.m`
3. ensure the interface can be created in a protocol-editing-safe mode
4. implement or verify module-edit support if the interface should allow manual module management

If the interface requires special module construction, extend the type-specific logic in `onAddModule.m` or move that logic into a more reusable helper when it grows.

## Working on this code

For most changes, start in the file that owns the user gesture:

- button or menu behavior: the matching `on*.m` callback
- UI layout changes: `build*.m`
- stale or inconsistent visible state: `refresh*.m`
- parameter type coercion, expressions, or editor dialogs: `private/`
- documentation launch issues: `onOpenDocumentation.m` and `private/getDocumentationPath.m`

The lowest-friction way to debug behavior is to construct a designer with a small protocol object, perform one UI action, and then inspect the mutated `ui.Protocol` object in MATLAB.

## Notes and limitations

- The designer mutates the live in-memory protocol object immediately.
- Validation still depends heavily on the underlying `epsych.Protocol`, `hw.Interface`, `hw.Module`, and `hw.Parameter` implementations.
- Some interfaces intentionally do not allow manual module edits.
- The options and preview surfaces are currently dialogs, even though their builder files retain tab-oriented names.
- Invalid edits usually recover by refreshing the affected control state and updating the footer status instead of throwing the user out of the workflow.
