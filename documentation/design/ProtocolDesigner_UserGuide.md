# Protocol Designer User Guide

`epsych.ProtocolDesigner` is the graphical editor for building and checking protocol files without editing MATLAB code directly. Use it to create interfaces, add modules and parameters, adjust protocol settings, and preview the compiled trial list before saving.

This guide is written for experiment designers and operators. If you need to change the software itself, use `documentation/design/ProtocolDesigner.md` instead.

## Opening the designer

Open the designer from MATLAB with:

```matlab
ui = epsych.ProtocolDesigner();
```

To open an existing protocol file:

```matlab
ui = epsych.ProtocolDesigner.openFromFile('example.eprot');
```

When the window opens, the message area at the bottom shows the latest action, error, or suggested next step.

## What the window is for

The main window has two working areas:

- **Interfaces** on the left, where you add hardware or software interfaces and manage their modules.
- **Protocol Parameters** on the right, where you edit the parameter table for the selected interface or module.

There are also separate dialogs for:

- **Protocol Options**
- **Compiled Preview**

Use the **Help** menu to open this guide or the developer documentation.

## Typical workflow

Most users will follow this order:

1. Add an interface.
2. Add one or more modules if that interface supports manual module editing.
3. Add parameters to the selected module.
4. Set parameter values, ranges, and any pairings or expressions.
5. Open **Protocol Options** and confirm trial function and timing settings.
6. Open **Compiled Preview** or click **Compile Protocol** to verify the generated trials.
7. Save the protocol to an `.eprot` file.

## Adding an interface

Use the **Add Interface** panel in the upper-left area.

1. Choose an interface type from **Interface Type**.
2. Click **Add Interface**.
3. Fill in any required options in the dialog.

If the interface type already exists in the current protocol, the designer prevents adding a duplicate.

Some interfaces are created in an offline or serialized form inside the designer. This is expected. The goal is to define the protocol structure and settings, not to start live hardware communication while editing.

## Managing modules

After an interface is added, it appears in the **Current Interfaces** tree.

- Select an interface to focus the parameter table on that interface.
- Select a module under that interface to focus editing on that module.
- Use **Add** and **Remove** to manage modules when the selected interface allows it.
- Use **Options** to reopen editable interface settings.

Not every interface allows manual module changes. For some hardware-backed interfaces, the module list is controlled by the interface implementation rather than by the designer.

## Adding and editing parameters

Use **Add To Interface** and **Module** above the parameter table to choose where a new parameter will be created, then click **Add Parameter**.

The parameter table includes these main fields:

- `Name`: parameter name
- `Type`: value type such as float, integer, boolean, string, or file
- `Expression`: optional formula for supported numeric or logical parameter types
- `Pair`: links parameters so they advance together during compilation
- `Value`: parameter value for editable types
- `Min` and `Max`: numeric limits
- `Random`: whether values are randomized
- `Access`: read or write behavior
- `Visible`: whether the parameter is intended to be visible
- `Trigger`: trigger flag for boolean parameters
- `Description`: free-text note

Important editing rules:

- The **Value** cell is edited directly only for string parameters.
- File parameters open a separate value editor.
- Changing a parameter type may also change or reset the stored value.
- If an edit is invalid, the row is refreshed back to the last valid state and the status line explains the problem.

## Working with file parameters

For parameters with `Type = File`, use **Edit Selected Value**.

The file editor lets you:

- choose one file
- choose multiple files when the parameter allows it
- remove selected files from the current list
- clear the current selection
- preview the full selected path

Use file parameters when a protocol step depends on an external stimulus or resource file.

## Working with expressions

Expressions let one parameter value be calculated from others.

Use the **Expression** column when:

- the parameter type is numeric or boolean
- the value should be derived instead of entered manually

Examples:

```matlab
amplitude * 2
```

```matlab
baseISI + 50
```

If an expression fails, the row is highlighted and the message area shows the error. Fix the expression and refresh or compile again.

## Pairing parameters

Use the **Pair** column when two or more parameters should advance together instead of creating every possible combination.

Example:

- parameter A values: 1, 2, 3
- parameter B values: 10, 20, 30

If both parameters share the same pair name, compilation uses `(1,10)`, `(2,20)`, and `(3,30)` instead of the full cross-product.

Paired parameters must have matching value counts.

## Protocol options

Click **Protocol Options** to open the protocol-level settings dialog.

The current options include:

- **Trial Function**
- **ISI (ms)**
- **Compile At Runtime**
- **Include WAV Buffers**

These settings apply to the full protocol rather than to one parameter.

## Compiling and checking the protocol

Use **Compiled Preview...** or **Compile Protocol** to build the current protocol and inspect the resulting trial list.

Use the compiled preview to check:

- how many trials will be produced
- whether parameter combinations look correct
- whether paired parameters stay aligned
- whether expressions resolve to the expected final values

If compilation fails, the designer shows the error in the status area and in an alert dialog.

## Saving and loading

Use the **File** menu to:

- edit the protocol info text
- load a protocol from disk
- save the current protocol
- open the current protocol as JSON for inspection

Saving writes an `.eprot` file that can be reopened later.

## Tips

- Watch the status bar after every major action. It usually tells you what to do next.
- Compile early when building a new protocol. It is faster to catch problems after a few edits than after a large batch of changes.
- If a module or parameter is not appearing where expected, reselect the interface and module in the tree and check the filter dropdown.
- Use JSON export when you want a quick structured view of the current protocol contents.

## Troubleshooting

### I cannot add a module

The selected interface may manage its own modules internally. Try reviewing the interface options instead.

### My parameter row turned red

The parameter likely has an expression or value error. Read the status message, fix the row, and compile again.

### The Value cell cannot be edited

That is expected for many parameter types. Use the type-specific editor, the expression field, or switch the type if appropriate.

### Compilation failed

Check recent edits first: file paths, paired parameter lengths, expressions, and protocol options are the most common causes.

## Related documentation

- Developer reference: `documentation/design/ProtocolDesigner.md`
