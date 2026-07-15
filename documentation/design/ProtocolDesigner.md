# Protocol Designer (developer reference)

`epsych.ProtocolDesigner` is the UI for editing `epsych.Protocol` objects. This document covers its internal structure for developers maintaining or extending the designer. The end-user guide is [ProtocolDesigner_UserGuide.md](ProtocolDesigner_UserGuide.md).

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
- Parameter editing panel (`buildParametersTab`) — table columns: Interface / Module, Name, Type, Expression, Value, Min, Max, Random, Pair, Access, Unit, Visible, Trigger, Update Every Trial, Description
- Options dialog (`buildOptionsTab` / open options callback)
- Compiled preview dialog (`buildPreviewTab` / open preview callback)
- Footer status messaging via `gui.StatusBar`

Interface creation is data-driven: the "Add Interface" panel enumerates `hw.Interface` subclasses and builds each creation dialog from the class's static `getCreationSpec()` (see [../hw/hw_Interface_Tutorial.md](../hw/hw_Interface_Tutorial.md)). Interfaces are held in an offline/serialized form while editing; live hardware communication is not started by the designer.

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
- Ctrl+S save
- Ctrl+Shift+S save as
- Ctrl+Shift+C compile
- Ctrl+Shift+V open compiled preview dialog
- Ctrl+Shift+O open options dialog
- Ctrl+Shift+A add interface
- Ctrl+Shift+M add module
- Ctrl+Shift+D show selected parameter details
- Ctrl+Shift+L toggle table view
- Ctrl+Shift+Y cycle color mode
- Ctrl+Shift+? show keyboard shortcuts help

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
