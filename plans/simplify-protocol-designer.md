# Simplify the `epsych.ProtocolDesigner` GUI

> **Status:** plan only, not implemented. Written 2026-10-01 against `f260409`.

## Current state

About 10.5k lines across 236 files (110 in the class folder, 126 in `private/`).

1. **Each command is reachable from three or four places.** There is a menu, a 12-button
   toolbar, a shortcut, and often a button inside a panel as well. Compile alone is in the
   menu, the toolbar, the Preview dialog and Ctrl+Shift+C. The shortcut list is written out
   four times: `onFigureKeyPress` (a 25-case switch), `showKeyboardShortcuts`, the menu labels,
   and `documentation/design/ProtocolDesigner.md`.
2. **There are two filter mechanisms.** The parameter panel has a Filter dropdown, and the
   Interfaces dialog tree also filters through `SelectedModuleRow`. A third pair of dropdowns
   (Add To Interface / Module) picks where a new parameter goes.
3. **Six separate windows share control handles.** The Interfaces, Options, Preview, Check Calcs
   and Find/Replace dialogs plus the dependency graph all write to the same control properties.
   Several refresh functions have to cope with controls that only exist while their dialog is
   open (`refreshInterfaceSummary`, `refreshInterfaceBuilder`, `getSelectedInterfaceSpec`).
4. **The table's column definitions are copied around, and columns are referred to by number.**
   Names, formats, widths and the Simple/Detailed visibility are defined in both
   `buildParametersTab` and `refreshParameterTable`. `onParamEdited` switches on column numbers
   3 to 16, so reordering columns would break it.
5. **Everything is placed in hard-coded pixels.** The window and its panels do not resize.
6. **Visual noise and small redundancies:**
   - Info-only nodes in the interface tree (Type, Modules count, Params count). The selection
     code depends on their count (`Children(selectedModuleRow + 3)`).
   - A Refresh button that does nothing new, because every edit already refreshes.
   - The Options dialog has three controls in two nested panels, and its hint text points to a
     "Preview tab" that no longer exists.
   - Edit Info and Options are two separate dialogs for protocol-level metadata.

## Phase 0: baseline

- Run the designer smoke tests (listed under Testing below) and record which pass. Requires
  MATLAB.
- Capture before screenshots with `tmp/generate_protocol_designer_screenshots.m`.

## Phase 1: internal refactor, no visible change

- **One column table** (`private/parameterColumns.m`): name, id, format, editable, width, and
  whether it shows in the Simple view. Build, refresh and `onParamEdited` all read from it, and
  `onParamEdited` switches on column id instead of number.
- **One command table** (`private/commandTable.m`): id, label, shortcut, callback and where it
  appears (menu, toolbar). Menus, toolbar, shortcut handling and the help dialog are all
  generated from it. Shortcuts go through `gui.KeyBindings` (`getOrCreate(fig)`) instead of the
  custom switch, so a shortcut can no longer be added without showing up in Help.
- **Grid layouts:** replace pixel `Position`s with `uigridlayout` so the window resizes.

## Phase 2: visible consolidation

- **Toolbar down from 12 buttons to 6:** New, Open, Save | Interfaces, Settings | Preview.
  - Compile is folded into Preview, which already compiles. Ctrl+Shift+C stays as a
    compile-only shortcut.
  - Check Calcs, Dependencies, Find/Replace and Shortcuts move to a **Tools** menu, keeping
    their shortcuts.
- **Protocol Settings:** merge Edit Info and Options into one dialog (info, trial function,
  Compile At Runtime, Include WAV Buffers).
- **Parameter panel:**
  - Top row: Find on the left, Add Parameter on the right.
  - Add Parameter goes to the module of the selected row or the active filter, and asks only
    when that is ambiguous. This removes the Add To Interface / Module dropdowns.
  - Color By and Simple/Detailed move to the View menu; their shortcuts stay.
  - Bottom row: Remove, Edit Value, Read HW Params. The Refresh button is dropped.
- **Interfaces and filtering (decision needed):**
  - **Option A (recommended):** a narrow, collapsible interface/module tree on the left of the
    main window. Selecting a node filters the table and sets where new parameters go. This
    replaces the Filter dropdown, the target dropdowns and most of the Interfaces dialog; adding
    an interface becomes a small modal dialog. It reverses the earlier move of the tree out of
    the main window, but a collapsible pane keeps most of the table width that move was for.
  - **Option B:** keep the Interfaces dialog and only replace the three filter/target dropdowns
    with a single Module filter dropdown.
- **Interface tree:** remove the info-only nodes and show their counts in the tooltip and node
  label instead.

## Phase 3: cleanup

- Delete private functions left unused (target-module helpers, `refreshTargetModuleControls`,
  the code that tolerates missing dialog controls under Option A, `suggestNextStep` branches
  that no longer apply). Each deletion gets a grep confirming nothing calls it.
- Shorten the next-step hint chains in `onParamSelected`. The status text stays factual; only
  the redundant hints go.

## Not in scope

- `epsych.Protocol`, the `.eprot` format and expression semantics.
- The type-specific value editors: String, File, StimType and Coefficient Buffer.
- Constant-expression healing (`normalizeConstantExpressions`) and version history.
- The public entry points: the constructor, `openFromFile`, `normalizeConstantExpressions`,
  `planParameterNameReplacement`, `applyParameterNameReplacement`. Callers outside the designer
  (RunExpt, SubjectManager, `gui.compareProtocolVersions`, examples) still need to be checked to
  confirm they use only these.

## Testing and docs

- Update `tmp/smoke_test_protocoldesigner_toolbar.m` (checks toolbar buttons and dialog layout)
  and the two screenshot generators (`tmp/generate_protocol_designer_screenshots.m`,
  `tmp/generate_wiki_screenshots.m`); they read `InterfaceFigure`/`PreviewFigure` and the
  `TableViewMode` preference.
- Re-run the designer smoke tests: `smoke_test_parameter_find_replace`,
  `smoke_test_designer_constant_expression`, `smoke_test_index_expressions`,
  `smoke_test_preview_transpose`, `smoke_test_checkcalc_random`,
  `smoke_test_coefficient_buffer_param`, `smoke_test_dependency_graph`.
- Add one headless test that checks the command table matches the menus, the shortcuts and the
  help text.
- Update `documentation/design/ProtocolDesigner.md` and `ProtocolDesigner_UserGuide.md`, then
  refresh the wiki screenshots.

## Decisions needed

1. Option A or Option B for interfaces and filtering.
2. Keep every existing shortcut? Recommended: keep all of them; they cost nothing once they come
   from the command table.
3. Keep the Simple/Detailed view toggle, or replace it with right-click column visibility?

Each phase can be committed and reviewed on its own; Phase 1 should go in before any visible
change.
