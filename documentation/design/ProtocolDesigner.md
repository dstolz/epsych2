# Protocol Designer (developer reference)

![Protocol Designer main window, showing the toolbar above the full-width Protocol Parameters table](images/ProtocolDesigner.png)

`epsych.ProtocolDesigner` is the UI for editing `epsych.Protocol` objects. This document covers its internal structure for developers maintaining or extending the designer. The end-user guide is [ProtocolDesigner_UserGuide.md](ProtocolDesigner_UserGuide.md).

The main window is a toolbar (`buildToolbar`) above the parameter editing table (`buildParametersTab`), which fills the remaining width. The interfaces/modules tree (`buildInterfaceTab`, `refreshInterfaceSummary`) moved out of the main window into a dialog opened from the toolbar, alongside the options, preview, and check-calculations dialogs.

Source class folder:

- [obj/+epsych/@ProtocolDesigner/](../../obj/+epsych/@ProtocolDesigner/)

## Purpose

The designer provides an interactive workflow for:

- adding/removing interfaces and modules
- editing parameter rows and types
- configuring protocol options
- compiling and previewing compiled trial tables
- exporting protocol objects and compiled previews

The UI edits the bound protocol object directly. Most edits are applied immediately and then normalized through refresh methods.

## Construction

```matlab
ui = epsych.ProtocolDesigner();
ui = epsych.ProtocolDesigner(protocolObj);
ui = epsych.ProtocolDesigner('path/to/file.eprot');
```

Static entry point:

```matlab
ui = epsych.ProtocolDesigner.openFromFile('path/to/file.eprot');
```

## UI Areas

- Main figure and menu system (`buildUI`)
- Toolbar (`buildToolbar`) — New, Open, Save | Interfaces, Options | Compile, Preview, Check Calcs, Dependencies | Find/Replace, Shortcuts. Buttons are placed from a running cursor, so retitling or reordering one entry does not shift the rest by hand.
- Parameter editing panel (`buildParametersTab`) — table columns: Interface / Module, Name, Type, Expression, Value, Min, Max, Random, Pair, Access, Unit, Visible, Trigger, Update Every Trial, Description
- Interfaces dialog (`buildInterfaceTab` / `onOpenInterfaceDialog`) — Add Interface builder plus the interface/module tree and its Remove / Options / Add Module / Remove Module actions
- Options dialog (`buildOptionsTab` / open options callback)
- Compiled preview dialog (`buildPreviewTab` / open preview callback)
- Check Calculations dialog (`buildCheckCalculationsTab` / `refreshCheckCalculations`)
- Parameter dependency graph figure (`onShowParameterDependencyGraph`, backed by `epsych.Protocol.dependencyGraph`) — node labels and per-parameter `= expression` annotations are drawn as tagged `text` objects (`nodeLabel` / `formulaLabel`) rather than GraphPlot labels, and formula boxes are nudged vertically to clear each other and the node labels
- Footer status messaging via `gui.StatusBar`

All four tool dialogs are tracked by a figure property (`InterfaceFigure`, `OptionsFigure`, `PreviewFigure`, `CheckCalcFigure`) and opened through `openToolDialog`, which raises an already-open window instead of building a second one. Without that, a duplicate would take ownership of the shared control properties and every earlier copy would go stale, refreshing nothing. Because the interface controls only exist while their dialog is open, `refreshInterfaceSummary`, `refreshInterfaceBuilder`, and `getSelectedInterfaceSpec` all tolerate their absence, and `getSelectedInterfaceRowIndex` falls back to `SelectedInterfaceRow` and then the Add To Interface dropdown. `onAddInterface` and `onAddModule` open the dialog first so the menu and keyboard entry points act on a visible selection.

Interface creation is data-driven: the "Add Interface" panel enumerates `hw.Interface` subclasses and builds each creation dialog from the class's static `getCreationSpec()` (see [../hw/hw_Interface_Tutorial.md](../hw/hw_Interface_Tutorial.md)). Interfaces are held in an offline/serialized form while editing; live hardware communication is not started by the designer.

The **Read HW Params** button (`onReadHardwareParams`) fills in a module's parameter list from the hardware definition via `hw.Interface.readHardwareParameters` — for `hw.TDT_RPcox` this reads the module's RPvds circuit file directly (no hardware needed); for `hw.TDT_Synapse` it queries the Synapse server read-only. If the module already has parameters, a Merge / Replace / Cancel dialog is shown. Backends that cannot enumerate their parameters report "not supported" in the status bar.

## Keyboard Shortcuts

Implemented in `onFigureKeyPress` and shown by `showKeyboardShortcuts`.

### Type shortcuts

- Ctrl+1 Float
- Ctrl+2 Integer
- Ctrl+3 Boolean
- Ctrl+4 Buffer
- Ctrl+5 Coefficient Buffer
- Ctrl+6 String
- Ctrl+7 File
- Ctrl+8 StimType
- Ctrl+9 Undefined

### Parameter and protocol actions

- Ctrl+Shift+B add boolean parameter
- Ctrl+Shift+T add trigger boolean parameter
- Ctrl+Shift+F add float parameter
- Ctrl+Shift+N add integer parameter
- Ctrl+Shift+R remove selected parameter
- Ctrl+F focus the parameter Find box
- Ctrl+H open Find and Replace for parameter names
- Ctrl+S save
- Ctrl+Shift+S save as
- Ctrl+Shift+C compile
- Ctrl+Shift+V open compiled preview dialog
- Ctrl+Shift+K open check calculations dialog
- Ctrl+Shift+G plot parameter dependency graph
- Ctrl+Shift+O open options dialog
- Ctrl+Shift+I open interfaces dialog
- Ctrl+Shift+A add interface
- Ctrl+Shift+M add module
- Ctrl+Shift+D show selected parameter details
- Ctrl+Shift+L toggle table view
- Ctrl+Shift+Y cycle color mode
- Ctrl+Shift+? show keyboard shortcuts help

## Finding and Renaming Parameters

The **Find** box beside the parameter table sets `ParamNameFilter`, which
`getParameterTableData` applies while building rows, so `ParameterHandles` always matches
what the user sees and every scope that reads it ("shown", remove, styles) stays consistent.
`matchesParameterNameFilter` implements the match: case-insensitive substring by default,
whole-name wildcard when the text contains `*` or `?`, and against the qualified
`Module.Parameter` form when it contains a dot. `onFindParameterChanged` is wired to both
`ValueChangedFcn` and `ValueChangingFcn` for live filtering.

Find and Replace is split so the rename logic is testable without the dialog:

- `planParameterNameReplacement(findText, replaceText, MatchCase=, WholeName=, Scope=)` returns
  a struct array of proposed renames with `Status` set to `rename`, `conflict`, or `invalid`.
  It never mutates the protocol. Uniqueness is tracked per module as the plan is built, so two
  renames that would collide with each other are reported rather than applied.
- `applyParameterNameReplacement(changes)` applies only the `rename` entries, then refreshes
  expression values and the table.
- `onFindReplaceParameterNames` / `refreshFindReplacePreview` are the dialog on top of those.

## Expressions and index-selecting types

`parameterSupportsExpression` gates the Expression column: `Float`, `Integer`, `Boolean`,
`String`, and `StimType`, minus triggers. The split in meaning lives in one predicate,
`hw.Parameter.expressionSelectsIndex`, which is true for `String` and `StimType`. Everything
that reasons about expressions consults it rather than re-listing type names:

- `normalizeExpressionResult` / `evaluateAndApplyParameterExpression` validate the result with
  `hw.Parameter.selectValueByIndex` and **leave `Values` untouched** — for these types `Values`
  is the item list the expression indexes, not a set of computed levels. Every other type still
  has `Values` overwritten by the result.
- `hw.Parameter.evaluateExpression_` skips the `numel(Values) > 1` dormancy guard for these
  types and returns `Values{index}`; `set.Value` defers its `stimgen.StimType` type check until
  after evaluation so a bare index can be assigned.
- `Protocol.compile_internal` emits a single placeholder level for an index-selecting parameter
  with an expression, so the item list does not multiply the trial cross product.
- `Protocol.analyzeExpressions` reports `selectsIndex` and `itemCount`, and forces
  `multiLevelDormant` false; `expressionIssues_`, `dependencyGraph`, `dryRunExpressions`, and
  `sweepExpressions` all key off those fields.

Adding a third index-selecting type means editing `expressionSelectsIndex` only.

Headless coverage: `tmp/smoke_test_index_expressions.m`.

## Constants are values, not expressions

A non-empty `hw.Parameter.Expression` is re-evaluated by `set.Value` on **every** per-trial
dispatch, overriding whatever the runtime assigned. That is the point of an expression — and
poison for a constant: a `Depth` carrying `Expression="0"` pins itself at 0 dB forever, so a
staircase writing new depths into the trial table appears frozen. Three rules keep constants
out of the Expression slot (value-computing types only; a constant index on `String`/`StimType`
deliberately pins which item is used):

- `evaluateAndApplyParameterExpression` drops the Expression after applying the result when the
  entered text is a literal constant (`isLiteralConstantExpression`: no identifiers beyond
  `pi`/`Inf`/`NaN`/`true`/`false`, so `-2`, `0:5:40`, and `2*pi` are values while `StimDelay+10`,
  `Depth.Min`, and `rand()*5` stay expressions). This also covers `refreshExpressionValues`,
  which routes every stored expression through the same apply path on each refresh.
- The Value column accepts direct numeric edits for `Float`/`Integer`/`Boolean`
  (`onParamEdited` case 5): the text is evaluated once, stored as fixed `Values`, and any prior
  Expression is removed — typing a value declares the value, not a rule, as the source of truth.
- `normalizeConstantExpressions` (public, called by `openProtocolFile` and the file-path
  constructor) converts constants in protocols saved by older designer versions, reports the
  converted names in the status bar, and marks the protocol modified so the healed state gets
  saved. Files the designer cannot open (`.ecfg` embedded protocols, phase snapshots) must be
  healed externally or re-saved from a healed session.

Headless coverage: `tmp/smoke_test_designer_constant_expression.m`.

## Renaming and expression references

Renaming rewrites dependent expressions through `rewriteExpressionReferences`, which must stay
in step with `hw.Parameter.resolveExpressionContext`: bare sibling names, `Module.Parameter`,
and either form suffixed with `.Min`/`.Max`/`.Value`/`.Values`. Qualified references are
rewritten before bare ones so the new name — now preceded by `.` — is not rewritten twice.
Nothing outside the protocol is updated; trial functions and custom GUIs that name parameters
in code are the user's responsibility.

Headless coverage: `tmp/smoke_test_parameter_find_replace.m`.

## Recent Export Features

### Export protocol object to workspace

`onExportProtocolToWorkspace` exports a detached protocol copy to base workspace variable `Protocol`.

### Export compiled preview table

`onExportCompiledPreview` supports:

- `workspace` (variable `compiledTable`)
- `mat` (with column names/types metadata)
- `csv`
- `xlsx`

If no compiled data exists, export is blocked with status + alert guidance.

## Important Callback Groups

### Structure editing

- `onAddInterface`, `onRemoveInterface`, `onModifyInterfaceOptions`
- `onAddModule`, `onRemoveModule`
- `onAddParam`, `onRemoveParam`, `onParamEdited`, `onParamSelected`
- `onReadHardwareParams` (Read HW Params button)

### Find and rename

- `onFindParameterChanged`, `setParameterNameFilter`, `focusParameterFind`
- `planParameterNameReplacement`, `applyParameterNameReplacement`
- `onFindReplaceParameterNames`, `refreshFindReplacePreview`
- Private helpers: `matchesParameterNameFilter`, `getReplacementCandidates`,
  `replaceInParameterName`, `renameParameterInPlace`, `rewriteExpressionReferences`,
  `ensureParameterNameVisible`

### Compile and preview

- `onCompile`
- `refreshCompiledPreview`
- `getCompiledPreviewTableData`
- `onExportCompiledPreview`

### Persistence and file operations

- `onNew`, `onLoad`, `onSave`, `onSaveAs`, `onCloseRequest`
- Recent file helpers in `private/` (`addRecentProtocolPath`, `refreshRecentProtocolMenu`, etc.)

## Extension Notes

- Add interface support through interface specs discovered by private helpers.
- Keep parameter type coercion aligned with protocol serialization and `hw.Parameter` behavior.
- For new UI actions, update both menu entries (`buildUI`) and shortcut dispatch (`onFigureKeyPress`) when appropriate.

## Related Files

- [obj/+epsych/@Protocol/Protocol.m](../../obj/+epsych/@Protocol/Protocol.m) — the data model the designer edits
- [../epsych/epsych_Protocol.md](../epsych/epsych_Protocol.md) — protocol class reference
- [ProtocolDesigner_UserGuide.md](ProtocolDesigner_UserGuide.md) — end-user guide
