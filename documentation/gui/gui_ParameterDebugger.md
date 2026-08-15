# `gui.ParameterDebugger`

A window that lists every parameter a protocol defines and lets you read or
write any of them. It answers the question a box GUI cannot — *is the
hardware actually holding what I think it is* — because it shows everything,
including the parameters no GUI exposes, and it works the same against any
protocol on any backend.

Opened from the session window's **Help > Parameter Debugger...** (`Ctrl+E`),
or directly against a protocol, a runtime, or a bare interface array.

```matlab
% From a session window: Help > Parameter Debugger... (Ctrl+E)
RX.OpenParameterDebugger

% Standalone, against anything that owns interfaces
gui.ParameterDebugger                  % binds to the open session, if any
gui.ParameterDebugger(myProtocol)      % an epsych.Protocol
gui.ParameterDebugger(RUNTIME)         % an epsych.Runtime
gui.ParameterDebugger(RUNTIME.Interfaces)
```

![The parameter debugger over a detection protocol](images/ParameterDebugger.png)

> Exercised headlessly by `tmp/smoke_test_parameter_debugger.m`, which drives
> it against `tmp/ParameterDebuggerMock` — a real `hw.Interface` with a value
> store of its own, so failing reads, quantised writes, and the
> connected/disconnected distinction are all covered without hardware. Run it
> after any change.

---

## Nothing is polled

Every read happens because you asked for it: a button, a double-click, or a
key. There is no timer and no auto-refresh.

That is the point. A debugger you leave open beside a running experiment must
not add hardware traffic of its own, or the thing it measures is partly the
measuring. `gui.Parameter_Monitor` is the polling display, and it is the right
tool when you want a value to update itself; this window is the one you can
trust not to.

The corollary is that a value in the table is a value *as of* the time in its
**Last Read** column — never live.

## Reading

| Action | Reads |
|---|---|
| Double-click a parameter's name | that one parameter, buffers included |
| **Read Selected** (`Ctrl+Enter`), or the right-click item | every selected row, buffers included |
| **Read All** (`F5`) | every listed row except buffers and write-only parameters |

Three things are deliberately left out of a Read All sweep:

- **Write-only parameters.** `hw.Parameter.get.Value` logs a critical record
  and returns `NaN` for `Access = 'Write'`, so sweeping them would fill the
  error log with failures that are not failures. They are marked grey,
  `write-only`.
- **`Buffer` and `Coefficient Buffer` parameters.** One of them can be a
  megabyte off the device. They are marked grey, `buffer - double-click to
  read`; naming one — by double-clicking it or selecting it — always reads it,
  and ticking **Include buffers** puts them into the sweep.
- **Parameters whose object has been deleted**, which is what reloading a
  config leaves behind. Rebuild the list with `Ctrl+R`.

A read that throws is reported in the row and counted in the status line,
which quotes the first failure; the exception itself goes to the log
(**Help > Open Current Error Log**). One dead parameter never stops a sweep.

## Colour is the read report

The **Value** cell carries the state of the last thing that happened to it:

| Colour | Meaning |
|---|---|
| pale green | the read came back |
| blue | this window wrote the value, and it read back as written |
| amber | it was written, but reads back as something else |
| pale red | the read or the write threw, or the text could not be parsed |
| grey | cannot be read: write-only, or a buffer the sweep skipped |
| uncoloured | never read |

The last one matters: a row that has never been read stays uncoloured, so *I
have not asked yet* never looks like *it came back empty*.

Amber is not an error. Clamping to `Min`/`Max`, an `Expression`, and a coarse
hardware quantiser all legitimately change a written value, and the note
column shows both numbers — `wrote 5.4, read 5` — so you can tell which.

Hidden parameters are greyed across the whole row, over whatever tint the
value cell has.

## Writing

Type into the **Value** cell. What is accepted depends on the parameter's
`Type`:

| `Type` | Accepts |
|---|---|
| `Float`, `Integer`, `Undefined` | a number (`1500`), an array literal (`[1 2 3]`), or an arithmetic expression (`0:0.1:1`, `2*750`) |
| `Boolean` | `true`/`false`, `1`/`0`, `on`/`off`, `yes`/`no` |
| `String`, `File` | the text, verbatim |
| `Buffer`, `Coefficient Buffer` | an array literal, up to 24 elements |
| `StimType` | nothing — edit a stimulus in the Protocol Designer or the Stimulus Player |

Numeric text is evaluated with `str2num`, which is `eval`, so it is first
checked against a numeric-literal pattern. Anything containing an identifier
is refused before it gets there: a cell that could run arbitrary code while
pointed at live hardware would be a trap, not a convenience.

Every write is followed immediately by a read-back, because on a live backend
the only proof a write landed is what the device returns afterwards. Rows the
window refuses to write — read-only parameters, triggers, values too large to
be a literal — say so in the status line rather than failing quietly.

Two flags explain most writes that appear not to stick:

- **`expr`** — the parameter has an `Expression`, which `set.Value`
  re-evaluates on every dispatch and which overrides whatever you assign.
- **`per-trial`** — it has more than one design-time level and
  `UpdateEveryTrial` is set, so the trial dispatcher rewrites it at the start
  of the next trial.

Triggers are never fired by typing. Select the row and use **Fire Trigger**
(the `Parameters` menu, or right-click).

## What is listed

The **Source** dropdown offers one entry per subject in `RunExpt.CONFIG`, plus
the live session's interfaces when a run is in progress. Before a run these are
the same objects a run will use — `ExptDispatch` hands `RUNTIME` subject 1's
protocol interfaces — which is why the window is worth opening with a config
merely loaded. The entry a run is actually using is marked `- live`.

> Only subject 1's interfaces are ever connected; subjects 2+ hold their own
> unconnected copies of the same protocol. Reads against those return the
> values the host holds, marked `(offline)`. See
> [plans/multi-subject-support.md](../../plans/multi-subject-support.md).

`(offline)` on a timestamp is the single most useful thing in the window when
every value looks like the design-time default: it means the backend was never
asked, because it is not connected. The count on the right — `13 parameter(s)
| 1 of 1 interface(s) live` — says the same thing for the whole source, and is
recomputed after every sweep as well as after every rebuild.

**Show hidden** lists parameters whose `Visible` flag is false. **Find**
filters on interface, module, and parameter name together.

The table is deliberately **not sortable**. Header-click sorting decouples the
display order from the underlying data order, and every callback here turns a
row index back into an `hw.Parameter` — a translation that has to be exactly
right, because getting it wrong means writing to the wrong parameter on live
hardware. Find covers what sorting would be for, and the natural order
(interface, then module, then declaration order) is the one the Protocol
Designer and the circuit already use.

## The Flags column

| Flag | Set when |
|---|---|
| `hidden` | `Visible` is false |
| `trigger` | `isTrigger` |
| `array` | `isArray` |
| `random` | `isRandom` |
| `expr` | `Expression` is non-empty |
| `set-once` | `SetOnce` — written on the first dispatch only |
| `per-trial` | more than one design-time level, and `UpdateEveryTrial` |

## Shortcuts and the right-click menu

| Key | Action |
|---|---|
| `F5` | Read All |
| `Ctrl+Enter` | Read Selected |
| `Ctrl+R` | rebuild the list |
| `Ctrl+F` | jump to the Find box |
| `Ctrl+C` | copy the table (selection, else all) as TSV |
| `Esc` | close |

Right-click adds **Assign to Command Window (P)**, which puts the selected
`hw.Parameter` in the base workspace as `P` — the handoff point where the
window stops and the command line takes over, in the spirit of the session
window's *Assign RUNTIME to Command Window*.

## What is remembered

Only the window position, under the `epsych2_gui_ParameterDebugger`
preference group, written when the window is closed. Nothing else persists:
which source, what is filtered, and everything read are all properties of one
debugging session and would be misleading restored into the next.

## Testing

```matlab
matlab -batch "run('tmp/smoke_test_parameter_debugger.m')"
```

68 assertions over a mock backend and a live `epsych.RunExpt`: that hidden
parameters are opt-in, that a sweep skips what it should and reports what
fails, that each colour follows its state, that a double-click on a name reads
and a double-click in the Value cell does not, that each value type parses,
that read-only parameters, triggers, and code in a value cell are all refused,
that a disconnected rig is marked offline, and that the window opens from the
session window's Help menu and closes cleanly.

It also covers what goes missing underneath it — a parameter deleted out of a
protocol, an interface deleted out of the source array, an edit event carrying
a row index the list no longer has — and that each kind of empty table says
which kind it is.

See also: [gui_Parameter_Monitor](Parameter_Monitor.md) — the polling display,
[Parameter_Control.md](Parameter_Control.md) — one parameter bound to one
widget, [gui_BoxGUI.md](gui_BoxGUI.md),
[../hw/hw_Parameter.md](../hw/hw_Parameter.md),
[../overviews/RunExpt_SelfTest.md](../overviews/RunExpt_SelfTest.md) — the
other window on the Help menu.
