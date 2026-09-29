# `gui.ParameterDefaultsEditor`

The window for one subject's parameter defaults in one project: values that replace
the protocol's for that subject every time Run or Preview is pressed. The arithmetic
behind it is [`epsych.ParameterDefaults`](../epsych/epsych_ParameterDefaults.md).

Open it from **Subjects & Projects**: right-click a subject, **Parameter Defaults for
This Row...**, or select one and use **Subject > Parameter Defaults...**. Both need a
project selected, because the defaults belong to the membership.

```matlab
E = gui.ParameterDefaultsEditor.open(epsych.SubjectRoster, 'M001', 'Tone Detection');
```

`open` raises the window already open for that membership rather than building a
second one that could overwrite its edits.

## Layout

A header names the subject, project and protocol (and says when the membership is held
on an older protocol version, which is then the version listed). Below it:

| Column | Holds |
|---|---|
| Parameter | `Module.Name` |
| Unit | |
| Protocol | the protocol's value, or its levels for a roved parameter, or `random a – b` |
| Protocol Range | the protocol's `Min – Max` |
| **Default** | this subject's value; blank = the protocol's |
| **Min**, **Max** | this subject's bounds; blank = the protocol's |
| Notes | why a cell is greyed, `roved ×N`, `paired: X`, `hidden`, where a value came from, or what is wrong with it |

A cell that cannot take anything (a randomized parameter's Default, a Boolean's Min and
Max) is greyed rather than hidden, so every row reads the same way. A saved default is
bold on blue; one typed or copied since the last save is bold on green. A default whose
parameter the protocol no longer has — or that no longer passes its checks — is listed
in orange and skipped at Run; such a row can only be cleared.

The filter box narrows by name as you type; **Only parameters with defaults** and
**Show hidden parameters** narrow further.

## Editing

Type into Default, Min or Max. A value is checked the moment it is entered — type,
whole numbers for an Integer, inside the range (after this row's own Min/Max), a paired
parameter's level count — and a refused edit is put back with the reason on the status
line. Several levels are typed comma-separated (`0, -10, -20`). Numbers are read with
`str2double`, never evaluated.

Nothing is written until **Save** (Ctrl+S). Closing with unsaved edits asks Save /
Discard / Cancel. A save while a session runs changes the next Run, not the one in
progress.

## Copying values

Both copies take only what **differs from the protocol**, so a copy never turns every
parameter into a default, and neither ever clears a default the operator set. A default
whose parameter matches the protocol in the source is left alone and named in the
status line, so it can be cleared by hand if that was the intent.

- **Copy from Session** reads the running (or just-stopped) session for this subject:
  values and bounds. Refused until the subject has run in the session, since before
  that the session holds nothing but the protocol. A staircase-managed parameter reads
  its current level — "start the next session where this one is" is the reason to copy.
- **Copy from Last Data File...** finds the subject's newest saved session (not a
  Preview, not a recovery copy) and names it — file, date, trials — before copying the
  last trial's values; **Choose Another File...** picks a different one. Values only:
  bounds are not in the data. Refused while a session runs, because finding the file
  reads the subject's folders on the thread the trial loop runs on.

Roved parameters are never copied from either source: one trial's level is not the
list.

## Methods

| Method | Does |
|---|---|
| `open(roster, subject, project, RunExpt=, Visible=)` | show (or raise) the editor |
| `setDefault(param, text)` | what typing into Default does; `[ok, msg]` |
| `setBound(param, 'Min'\|'Max', text)` | what typing into Min/Max does |
| `clearDefaults(params)` | blank rows; none = all |
| `copyFromSession()` | Copy from Session; returns a report |
| `copyFromDataFile(file)` | copy from a file; `''` = the latest |
| `collect()` | the rows as roster records |
| `save()` | write them; fires `DefaultsSaved` |
| `close()` | close, asking about unsaved edits when on screen |

`param` is a row index, key, `Module.Name`, or a `Name` that is unique in the list.

## What is remembered

The window position (`epsych2_gui_ParameterDefaultsEditor`). Nothing else: the
defaults themselves are the roster's.

## Testing

Not yet covered by a GUI test. The engine it drives is covered headlessly by
`tmp/smoke_test_parameter_defaults.m`.

See also: [`epsych.ParameterDefaults`](../epsych/epsych_ParameterDefaults.md),
[`gui.SubjectManager`](gui_SubjectManager.md).
