# `vprintf`

`vprintf` is EPsych's shared console and log printing helper.

It stamps each message with the time, filters it against the global verbosity
level, and writes it both to the command window and to a daily log file under
`.error_logs` in the EPsych root folder.

**_All EPsych functions should use this in place of calling `fprintf` directly._**

`vprintf` is a thin façade: it parses the calling convention and hands the
result to the [`eplog`](../eplog/eplog_Logging.md) package, which formats the
record and dispatches it to every configured destination. This page covers
using it; [eplog](../eplog/eplog_Logging.md) covers the machinery, the log file
lifecycle, and adding destinations.

## Function signature

```matlab
vprintf(verbose_level, msg)
vprintf(verbose_level, red, msg)
vprintf(verbose_level, msg, value1, value2, ...)
vprintf(verbose_level, red, msg, value1, value2, ...)
vprintf(verbose_level, [red], exception)
```

- `verbose_level`: Numeric message level, or an `eplog.Level` member.
- `red`: Optional flag. Use `1` to print to MATLAB's error stream (`fprintf(2,...)`).
- `msg`: Message text, a format string, an `MException`, or an error struct.
- `value1, value2, ...`: Optional values consumed by the format string.

A `string` scalar is always a message, never the red flag.

## Verbosity levels

| Level | Name | Use |
| --- | --- | --- |
| `-1` | `LogOnly` | log it, but do not print to the command window |
| `0` | `Critical` | failures and messages the operator must see |
| `1` | `Info` | general session information (the default level) |
| `2` | `Debug` | useful while debugging |
| `3` | `Verbose` | detailed process tracing |
| `4` | `Trace` | per-trial detail |

A message is emitted when `verbose_level <= GVerbosity`. Any numeric level is
accepted; the table is convention, not a constraint.

```matlab
global GVerbosity
GVerbosity = 2;
```

If `GVerbosity` is empty, non-numeric, non-scalar or `NaN`, it is repaired to
`1`. In the session GUI, set it from **Customize ▸ Verbosity**.

## Format policy

This is the one rule worth remembering:

- **With values**, `msg` is a `printf` format string.

  ```matlab
  vprintf(1, 'Starting acquisition for box %d', boxId)
  ```

- **With no values**, `msg` is **literal text**. Nothing is interpreted:

  ```matlab
  vprintf(1, dataFile)     % 'C:\new\data.mat' survives intact
  vprintf(2, ME.message)   % a stray '%' survives intact
  ```

  This is what protects messages built at run time, which are precisely the
  ones containing backslashes and percent signs. If you need formatting,
  supply values.

Never append `\n`. Each record occupies its own line, and a trailing newline is
stripped if present.

## What a message looks like

Command window:

```text
18:51:35.958: Recording session started
```

Log file — the same record, plus the function and line that logged it:

```text
18:51:35.958,ep_TimerFcn_Start,64: Recording session started
```

## Logging an exception

```matlab
try
    doSomethingRisky();
catch ME
    vprintf(0, 1, ME)
end
```

The identifier, message, stack and any nested causes are written as a **single**
record, attributed to the `catch` site. `vprintf` also accepts a
`lasterror`-style struct (such as `RUNTIME.ERROR`) or a timer `ErrorFcn` event
struct.

## Guarding expensive arguments

`vprintf` returns before doing any work when a level is suppressed, but it
cannot stop the _caller_ from computing what it was about to pass. Use
`visenabled` when building the arguments is itself expensive:

```matlab
if visenabled(4)
    vprintf(4, 'buffer: %s', mat2str(obj.readBuffer()));   % never read
end
```

For ordinary messages the guard costs more than it saves — call `vprintf`
directly.

## Log file behavior

```text
.error_logs/error_log_ddmmmyyyy.txt
```

By default the directory sits under the folder returned by `epsych_path`;
RunExpt's **Customize ▸ Paths ▸ Error Log Path** (or `eplog.setLogDir`) points
it elsewhere. The file rolls over at midnight and reopens if its handle is
closed underneath it. Do not rebuild this path in your own code — ask the
logger:

```matlab
L = eplog.Logger.instance();
L.flush();
disp(L.LogFile)
```

The file sink buffers, so `flush` first if you are about to read, copy or open
the log. Critical messages (level `0`) flush automatically, as does the end of
a run and the close of the session GUI.

See [eplog](../eplog/eplog_Logging.md) for rotation, failure handling,
per-process log files, and the opt-in structured JSON Lines log.

## Notes and limitations

- `vprintf` never throws. Malformed levels, mismatched format values and
  unprintable messages degrade to a logged note.
- The function always ends the line. It is not intended for partial-line output.
- Logging performs file I/O, so very high-frequency debug logging still costs
  something (~150 µs per written message); the _suppressed_ path costs ~1 µs.
- `stimgen` vendors its own `stimgen.util.vprintf` and logs elsewhere; its
  messages do not appear in the session log.

## Related files

- [helpers/vprintf.m](../../helpers/vprintf.m)
- [helpers/visenabled.m](../../helpers/visenabled.m)
- [eplog package overview](../eplog/eplog_Logging.md)
- [epsych_path.m](../../epsych_path.m)
