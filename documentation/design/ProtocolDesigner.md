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

## Function Reference

Complete tree of all class functions with a brief description of each role. Public methods are defined in files directly under the class folder; private helpers live in `private/`.

```
ProtocolDesigner            Constructor; binds protocol and builds UI.
openFromFile                (Static) Load a .eprot file and open in designer.

UI construction
├─ buildUI                  Create the top-level figure and persistent controls.
├─ buildOptionsTab          Build the Options tab controls (reps, ISI, flags).
├─ buildParametersTab       Build the Parameters tab controls and table.
└─ buildPreviewTab          Build the compiled-preview tab controls.

UI refresh
├─ refreshUI                     Reload all visible controls from Protocol state.
├─ refreshInterfaceControls      Refresh interface type/description controls.
├─ refreshInterfaceSummary       Update the interface summary label below the tree.
├─ refreshModuleActionButtons    Enable/disable module add/remove buttons.
├─ refreshOptionsTab             Sync Options tab controls with Protocol properties.
├─ refreshParameterTab           Sync Parameters tab with the current interface.
├─ refreshParameterTable         Rebuild parameter table rows from the model.
├─ refreshTargetModuleControls   Refresh target interface/module dropdowns.
└─ refreshCompiledPreview        Rebuild the compiled-preview table.

User actions (callbacks)
├─ onLoad                        Prompt to load a protocol file from disk.
├─ onSave                        Save the protocol (prompt if no current path).
├─ onCompile                     Compile the protocol and refresh preview.
├─ onEditInfo                    Handle edits to the protocol name field.
├─ onInfoChanged                 Sync UI title after protocol info changes.
├─ onAddInterface                Add the selected interface spec to the protocol.
├─ onRemoveInterface             Remove the selected interface from the protocol.
├─ onModifyInterfaceOptions      Open interface options dialog for selection.
├─ onAddModule                   Add a new module to the selected interface.
├─ onRemoveModule                Remove the selected module from its interface.
├─ onAddParam                    Add a new parameter row to the parameter table.
├─ onRemoveParam                 Remove the selected parameter row.
├─ onParamEdited                 Apply an in-table parameter edit to the model.
├─ onParamSelected               Handle parameter row/cell selection changes.
├─ onBrowseSelectedFileParameter Open file browser for the selected File parameter.
├─ onInterfaceFilterChanged      Respond to filter dropdown change; refresh table.
├─ onInterfaceRegistrySelected   Respond to selection of an interface in the tree.
├─ onInterfaceSpecChanged        Respond to a change in the interface type dropdown.
├─ onTargetInterfaceChanged      Respond to changes in the target interface dropdown.
├─ onOptionControlChanged        Respond to a change in an option control value.
├─ onOpenOptionsDialog           Open the module options dialog.
├─ onOpenCompiledPreviewDialog   Open the full compiled preview in a modal dialog.
├─ onOpenDocumentation           Open documentation for the selected interface.
└─ onOpenAsJSON                  Serialize protocol to temp JSON and open in editor.

Queries (public getters)
├─ getAddableInterfaceSpecs           Return interface specs that can be added.
├─ getCompiledWriteParamType          Return write-param type for one compiled column.
├─ getCompiledWriteParamTypes         Return write-param types for all compiled columns.
├─ getFileNameDisplayText             Return display text for the current file path.
├─ getTrialFunctionPathWarning        Return warning if the trial function path is bad.
├─ normalizeCompiledPreviewData       Normalize compiled trial data for the preview table.
├─ normalizeCompiledPreviewValue      Normalize a single compiled preview cell value.
├─ normalizeCompiledPreviewValueAsText Convert a compiled preview value to display text.
├─ setStatus                          Update the footer status label.
└─ suggestNextStep                    Return a short next-step hint for the current state.

private/ — Persistence
├─ addRecentProtocolPath         Persist a path to the recent-protocols preference.
├─ removeRecentProtocolPath      Remove a path from the recent-protocols preference.
├─ getRecentProtocolPaths        Read the recent-protocols list from preferences.
├─ getLastProtocolFilePath       Read the last-used protocol file path from prefs.
├─ setLastProtocolFilePath       Persist the last-used protocol file path.
├─ getLastBrowseDirectory        Read the last-used browse directory from prefs.
├─ setLastBrowseDirectory        Persist the last-used browse directory.
├─ getRepositoryRoot             Locate the epsych2 repository root directory.
├─ refreshRecentProtocolMenu     Repopulate the Recent Protocols submenu.
└─ onOpenRecentProtocol          Load a protocol from a recent-protocols menu entry.

private/ — File / path helpers
├─ openProtocolFile              Execute the full open-and-bind flow for a file.
├─ getProtocolFileDialogStartPath Determine start path for protocol file dialogs.
├─ getBrowseStartPath            Determine start directory for file browse dialogs.
├─ getShortDisplayPath           Shorten a file path to a display-friendly string.
├─ getDocumentationPath          Resolve the documentation path for an interface.
├─ buildFileFilterFromExtensions Convert extension list to a uigetfile filter spec.
├─ normalizeDialogFileFilter     Normalize a file filter for uigetfile/uiputfile.
├─ validateDialogSelectionPaths  Validate that file-dialog selections are accessible.
└─ onBrowseInterfacePath         Open a file browser for an interface path field.

private/ — Interface helpers
├─ getAvailableInterfaceSpecs    Return all registered interface specs (filtered).
├─ getSelectedInterfaceSpec      Return the spec for the currently selected interface.
├─ getSelectedInterfaceRowIndex  Return the row index of the selected interface.
├─ getInterfaceIndexFromTreeNode Resolve an interface index from a tree node.
├─ getInterfaceEditState         Return enabled/disabled state for interface buttons.
├─ getInterfaceItems             Build display items for the interface tree.
├─ canEditInterfaceModules       Return true if the interface allows module editing.
├─ interfaceLabel                Format the display label for an interface node.
├─ isMissingInterfaceOption      Return true if a required interface option is unset.
├─ describeInterfaceField        Return a human-readable description of a field.
├─ formatInterfaceDefault        Format an interface field default value for display.
├─ refreshInterfaceBuilder       Rebuild interface-option controls for the selection.
├─ createInterfaceOptionControl  Build a uicontrol for one interface option field.
├─ readInterfaceControlValue     Read the current value from an option control.
├─ parseInterfaceOptionValue     Parse a raw value from an interface option control.
├─ editInterfaceOptionValue      Apply a new value to one option in an interface.
├─ formatInterfaceOptionDisplayValue Format an option value for the options dialog.
├─ applyUpdatedModuleOptions     Write edited option values back to the module.
├─ promptForInterfaceOptions     Show a dialog to collect required interface options.
├─ selectedFilterIndex           Return the current interface-filter dropdown index.
└─ selectedTargetInterfaceIndex  Return the selected target interface index.

private/ — Module helpers
├─ getModuleEditState            Return enabled/disabled state for module buttons.
├─ getModuleIndexFromTreeNode    Resolve a module index from a tree node.
├─ getSelectedModuleRow          Return the row index of the selected module.
├─ getSelectedTargetModule       Return the module struct for the target module.
├─ setSelectedModuleRow          Set the selected module row and update controls.
├─ getTargetModuleItems          Build dropdown items for the target-module selector.
├─ moduleDisplayLabel            Format the display label for a module node.
├─ getUniqueModuleText           Return a unique display label for a module.
├─ getUniqueModuleTextForEdit    Return a unique editable label for a module rename.
├─ cloneModulesToInterface       Copy modules from one interface to another.
├─ replaceInterfaceModules       Replace all modules in an interface with a new set.
├─ getSingleModuleOptionNumeric  Read one option value from a module as a number.
├─ getSingleModuleOptionText     Read one option value from a module as a string.
└─ createPathPickerControl       Build a path-picker row (edit + browse button).

private/ — Parameter helpers
├─ getAllParameters               Collect all parameters across interfaces as a flat array.
├─ getSelectedParameter          Return the parameter struct at the current selection.
├─ getUniqueParameterName        Return a unique parameter name (deduplicates existing).
├─ validateParameterName         Validate a name and return an error message if invalid.
├─ getParameterTableData         Build the full cell array of parameter table data.
├─ getParameterValueDisplay      Return a truncated display string for a value.
├─ getParameterValueFull         Return the complete, untruncated value string.
├─ getTypeOptions                Return type option strings for parameter type dropdowns.
├─ getAccessOptions              Return R/W access option strings for dropdowns.
├─ resolveParameterTargetModule  Map a parameter to its assigned target module index.
├─ sanitizeParameterTrigger      Validate and clear invalid trigger assignments.
├─ parameterAllowsTrigger        Return true if the parameter type allows a trigger.
├─ editParameterFileValue        Open the modal file-value editor for a File parameter.
├─ editParameterStringValue      Open the modal string-value editor for a String parameter.
├─ promptForParameterFileValue   Show the file-selector dialog for a File parameter.
├─ getParameterFileConfig        Return the file-selection config for a File parameter.
├─ getParameterFileList          Return the current file list for a File parameter.
├─ getParameterFileStartPath     Determine the start directory for a File parameter browser.
├─ isFileLikeValue               Return true if a value looks like a file path.
├─ normalizeFileValueToList      Normalize a file parameter value to a cell array.
├─ resolveFileSelectionMode      Determine single vs. multi-file selection mode.
├─ getFileDisplayItems           Build display items for the file-selection list.
├─ getFileSelectionCountText     Return a summary string for the file selection count.
├─ getFilePreviewLines           Read the first few lines of a file for preview.
├─ formatStringParameterValue    Format a string parameter value for table display.
├─ parseStringParameterValue     Parse a raw string from a table cell into a value.
├─ parseValue                    Parse a string representation into a typed value.
├─ parseList                     Split a delimited string into trimmed tokens.
└─ parseNumericList              Parse a string into a numeric vector.

private/ — Pair helpers
├─ getParameterPair              Return the pair struct for a paired parameter.
├─ setParameterPair              Update the pair group assignment for a parameter.
├─ getPairDisplayValue           Format a parameter pair value for table display.
├─ getPairDropdownOptions        Build dropdown items for a paired-parameter column.
├─ promptForNewPairName          Show an input dialog for a new pair name.
└─ validatePairedParameterLengths Collect errors for pairs with mismatched value counts.

private/ — Expression helpers
├─ buildExpressionContext        Build the variable context used during evaluation.
├─ getExpressionAliases          Return alias-to-parameter mappings for evaluation.
├─ getQualifiedExpressionAlias   Qualify a short alias to a fully-scoped reference.
├─ resolveQualifiedExpressionReference Resolve a qualified alias to a parameter value.
├─ evaluateParameterExpression   Evaluate one expression against current parameters.
├─ evaluateAndApplyParameterExpression Evaluate and store the result of an expression.
├─ refreshExpressionValues       Re-evaluate and display all active expressions.
├─ getParameterExpression        Read the stored expression for a parameter.
├─ setParameterExpression        Store an expression string on a parameter.
├─ clearParameterExpression      Remove the expression from a parameter.
├─ hasParameterExpression        Return true if the parameter has an active expression.
├─ normalizeExpressionResult     Normalize the raw expression result to a string.
├─ getExpressionErrorMessage     Build an error message string for an expression failure.
├─ applyExpressionErrorStyles    Apply cell styles to highlight expression errors.
├─ setExpressionErrors           Store and display expression error state.
├─ validateExpressionReferences  Check that all expression aliases resolve correctly.
├─ parameterCanParticipateInExpression Return true if a param can be an expression term.
└─ parameterSupportsExpression   Return true if the parameter type supports expressions.

private/ — Miscellaneous helpers
├─ coerceLogicalValue            Cast a value to logical with fallback.
├─ coerceNumericValue            Cast a value to double with fallback.
├─ coerceValueForType            Coerce a raw value to the expected parameter type.
├─ onOffForCondition             Return "on"/"off" string from a logical condition.
├─ getCurrentControlPath         Return the path of the currently selected tree node.
├─ makeUniqueDisplayItems        Deduplicate and suffix display item labels.
├─ parseIndexedLabel             Parse an indexed label string to name and index.
├─ stringToTextAreaValue         Convert a string to a textarea-compatible cell array.
└─ showCompileFailure            Report a compile failure with validation context.
```

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
