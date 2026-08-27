# `granary` — EPsych's logging dependency

`granary` is the package behind [`vprintf`](../helpers/helpers_vprintf.md). Every
message EPsych prints or logs goes through it: `vprintf` parses the call, and
`granary.Logger` turns it into one record and hands that record to each
configured _sink_ — the command window, the daily text log, and optionally a
structured JSON Lines log.

Nothing in the package throws. EPsych logs from inside `catch` blocks, and an
exception raised while reporting an exception destroys the report that the
operator actually needed.

Most code never touches this package directly. Call `vprintf`. Reach for
`granary` when you need to know _where_ the log is, make it durable, or add a
destination.

## It is a separate repository

`granary` is **not in this repository**. It lives at
[dstolz/granary](https://github.com/dstolz/granary) and is a hard dependency:
`vprintf` is a thin forward to `granary.printf`, so nothing here can log
without it. Clone it beside your epsych2 checkout, or point at an existing copy
with `setpref('EPsych','GranaryPath','<folder holding +granary>')`.

`epsych_startup`'s `setup_granary` locates it — already on the path, then that
preference, then `obj/granary` (where a submodule would sit), then a sibling of
the checkout, then a sibling one level up, which is where a **git worktree**
finds it. When it cannot, startup stops with clone instructions rather than
letting `Undefined variable granary` surface later from whichever call site
happened to log first.

Startup also applies the three settings that a library cannot discover about
its host:

| `granary.config` setting | EPsych sets it to | Why |
|---|---|---|
| `LogRoot` | the checkout root | keeps `.error_logs` where EPsych has always written |
| `FacadeFiles` | `{'vprintf.m','LogBridge.m'}` | see [Attribution](#attribution) — without it every record names the wrapper |
| `PrefGroup` | `'eplog'` | **deliberately not the package default**: the log-directory override predates the extraction, and renaming the group would silently orphan every rig's configured Error Log Path |

Ask `granary.config().PrefGroup` rather than spelling `'eplog'` at a new call
site, so this file and `granary.setLogDir` cannot drift apart.

### Attribution

`granary.callerFrame` decides which function a record is stamped with by
skipping the package's own stack frames plus every filename in `FacadeFiles`.
Both of EPsych's front doors sit between a call site and the logger — `vprintf`
for EPsych's own calls, `stimbridge.LogBridge` for stimgen's, which adds two
frames of its own. **Any new wrapper must be added to that list in
`epsych_startup`**, or it silently claims every message routed through it, at
one fixed line number, and the caller column the log exists for is lost.

## The path a message takes

```text
vprintf(level,[red],msg,values...)                      EPsych call sites
stimgen.util.vprintf(...) → stimbridge.LogBridge.emit   stimgen call sites
  └─ granary.isEnabled(level,'any')  gate — a message no destination wants stops here
       └─ granary.Logger.instance()
            ├─ granary.format / granary.formatException   text, once
            ├─ granary.callerFrame                      who logged it
            ├─ granary.record                           one struct
            └─ sink.write(rec) for each sink, each gating on its own level
                 ├─ granary.sink.Console     command window          (GVerbosity)
                 ├─ granary.sink.TextFile    .error_logs/error_log_ddmmmyyyy.txt        (GLogVerbosity)
                 └─ granary.sink.JsonLines   .error_logs/error_log_ddmmmyyyy.jsonl (opt-in, GLogVerbosity)
```

The gate comes first and is the only cost a message pays when **no** destination
wants it. With the default `GLogVerbosity` the log wants everything, so that
short circuit no longer fires — see the performance note below.

## Verbosity

The command window and the error log are filtered separately, and
`granary.isEnabled` is the only place either global is interpreted.

| Global | Destination | Default | Repaired to the default when |
| --- | --- | --- | --- |
| `GVerbosity` | command window | `1` | `NaN`, `Inf`, `[]`, non-scalar |
| `GLogVerbosity` | error log | `Inf` — everything | `NaN`, `[]`, non-scalar (`Inf` is legal here) |

The split exists because the two answer different questions. `GVerbosity` keeps
the command window readable during a session and is turned down freely;
`GLogVerbosity` decides what is on the record afterwards. Quieting the console
therefore hides output, it no longer discards it — the level-3 detail that
explains a failure is in `.error_logs` whether or not the operator was watching
for it.

```matlab
global GVerbosity GLogVerbosity
GVerbosity    = 0;     % near-silent command window
GLogVerbosity = Inf;   % (the default) the log still keeps every message
```

Ask about one destination with `granary.isEnabled(level,'console')` or
`granary.isEnabled(level,'log')`; with no second argument, or `'any'`, it answers
"would this reach either", which is the gate `vprintf` and `visenabled` use.

**Performance.** At the default the gate never suppresses anything, so a level-4
trace in the trial loop now costs a full record and file write (~200 µs) rather
than ~4 µs. On a rig where that matters, set `GLogVerbosity` to a finite level
— `3` keeps everything but per-trial traces — and the cheap suppressed path
comes back. `granary.sink.Sink.MaxLevel` caps one sink without touching either
global.

| Level | `granary.Level` | Meaning |
| --- | --- | --- |
| `-1` | `LogOnly` | written to the log, never echoed to the console |
| `0` | `Critical` | failures and things the operator must see |
| `1` | `Info` | general session information |
| `2` | `Debug` | useful while debugging |
| `3` | `Verbose` | detailed process tracing |
| `4` | `Trace` | per-trial detail |

`granary.Level` members are `int32`, so they can be passed anywhere a numeric
level is accepted: `vprintf(granary.Level.Debug,'connected to %s',name)`. Levels
outside the set remain legal — pass a plain number.

Use [`visenabled`](../helpers/helpers_vprintf.md#guarding-expensive-arguments)
to guard log arguments that are expensive to build.

## Message formatting

`granary.format` applies one rule, and it is the rule to remember:

- **With values**, the message is a `printf` format string, exactly as
  documented: `vprintf(1,'box %d of %d',i,n)`.
- **With no values**, the message is **literal**. Nothing is interpreted, so
  `'C:\new\data.mat'` and `'ffmpeg reported 90% at frame 12'` survive intact.

The literal no-values path is deliberate. About ten call sites pass a message
built at run time — `ME.message`, tool output, a data path — and those are
exactly the strings that contain stray `%` and Windows backslashes.

A trailing newline is never needed; the sinks add their own line ending, and
`granary.format` strips any the caller appended. A malformed format string yields
the literal message plus a note rather than an error.

## Exceptions

`vprintf` accepts an `MException`, or any struct carrying `.message` — a
`lasterror`-style struct such as `RUNTIME.ERROR`, or a timer `ErrorFcn` event
(which names its identifier `messageID`). All of them become **one** record:

```text
18:51:35.958,onCloseRequest,42: epsych:hw:disconnectFailed: COM4 did not respond
    at hw.Teensy.disconnect (line 118) C:\src\epsych2\obj\+hw\@Teensy\Teensy.m
    at epsych.RunExpt.onCloseRequest (line 39) C:\src\epsych2\obj\+epsych\@RunExpt\onCloseRequest.m
  caused by:
    MATLAB:serialport:timeout: operation timed out
```

The record is attributed to the `catch` site, not to the logger, and nested
`MException` causes are preserved.

## Where the log lives

The default is unchanged from every previous version of EPsych:

```text
<epsych root>/.error_logs/error_log_ddmmmyyyy.txt
```

`granary.builtinLogDir` resolves the root through `epsych_path`, falling back to
`tempdir` when the repository is not on the MATLAB path — a relative path there
would scatter log directories through whatever folder happened to be current.
The directory ships with the clone as a `.gitignore` stub that excludes every
log written into it, so the default costs the working tree nothing.
`granary.defaultLogDir` layers the override on top of it; the Customize dialog
shows the built-in as placeholder text so an empty field still names where the
log will land.

### Pointing the log somewhere else

Rigs whose repository sits on a read-only or cloud-synced share need the logs
on local storage. Set the destination in RunExpt's **Customize ▸ Paths ▸ Error
Log Path** (or `RunExpt.DefineLogPath` for the folder picker alone), or
programmatically:

```matlab
granary.setLogDir('D:\rig_logs')   % persists as getpref('eplog','LogDir')
granary.setLogDir('')              % clear the override, back to the default
```

`setLogDir` does two things a bare `setpref` cannot: it creates the directory
and reports failure, and it re-points the sinks of the **running** logger. A
file sink captures its directory at construction, so without that step the
change would not take effect until the next `granary.Logger.instance('-reset')`.
`reset()` on each sink also clears a latched open failure, so moving the logs
off an unwritable share restores logging immediately.

The path must be absolute (`granary.isAbsolutePath`); a relative one would follow
the working directory, and "Open Current Error Log" would point at whichever
copy happened to be current. Unlike the rest of the package, `setLogDir`
throws on a bad path — it is configuration, not logging, and a rejected setting
must reach the operator who typed it.

Ask the logger rather than rebuilding the path:

```matlab
L = granary.Logger.instance();
L.flush();          % the file sink buffers; MATLAB has no fflush
disp(L.LogFile)     % where the NEXT record will land, even before one has
```

`LogFile` names today's file whether or not anything has been written to it,
which is what "open the current log" needs. `RunExpt`'s Help ▸ Diagnostics ▸ _Open Current
Error Log_, the self-test window's _Open Log_ button, and self-test check A4
all resolve it this way.

### Durability

MATLAB exposes no `fflush`, so `granary.sink.FileSink.flush` closes and reopens
the file in append mode. Records at or below `FlushLevel` (default `0`, i.e.
critical messages) flush automatically; EPsych additionally flushes at the end
of a run, when a run ends in error, and when the session GUI closes.

### Rotation and recovery

- The file rolls over at midnight, so a rig left running overnight keeps
  logging and each day's records land in their own file.
- A handle closed underneath the sink — `fclose('all')` and `clear all` are
  routine while debugging — is detected and reopened.
- If the file cannot be opened at all, the failure is reported **once** on
  stderr and then latches. Clear it with
  `L.sinkOfType('granary.sink.FileSink').reset()`.
- Set `PerProcess = true` on a file sink when several MATLAB instances share one
  repository, so they stop interleaving into a single file.

## Adding a destination

```matlab
L = granary.Logger.instance();
L.addSink(granary.sink.JsonLines());   % structured log beside the human one
```

The JSON Lines sink writes one object per line carrying level, level name, red
flag, caller, line, file, identifier, message and — for exceptions — the stack,
so a session can be filtered or grouped without parsing the human-readable log:

```matlab
lines = strsplit(strtrim(fileread(L.sinkOfType('granary.sink.JsonLines').Path)),newline);
recs  = cellfun(@jsondecode,lines);
errs  = recs([recs.level] == 0);
```

A custom sink subclasses `granary.sink.Sink` and implements `write(rec)`; see
`granary.record` for the fields. Start `write` with `if ~obj.accepts(rec), return;
end` — the logger's gate answers for the session as a whole, so each sink
applies its own level in `accepts`. Override `accepts` to add a destination gate
of your own; `MaxLevel` alone caps a sink without any code. A sink that throws
is contained by the logger: the other sinks still receive the record, and the
caller never sees the error.

## Reference

| File | Role |
| --- | --- |
| [`granary.Logger`](https://github.com/dstolz/granary/blob/main/+granary/@Logger/Logger.m) | session-wide dispatcher; `instance()`, `emit`, `flush`, `addSink`, `LogFile` |
| [`granary.isEnabled`](https://github.com/dstolz/granary/blob/main/+granary/isEnabled.m) | the verbosity gate, per destination; the only reader of `GVerbosity` and `GLogVerbosity` |
| [`granary.Level`](https://github.com/dstolz/granary/blob/main/+granary/Level.m) | named levels and `label()` |
| [`granary.format`](https://github.com/dstolz/granary/blob/main/+granary/format.m) | message text policy |
| [`granary.formatException`](https://github.com/dstolz/granary/blob/main/+granary/formatException.m) | exceptions, error structs, causes |
| [`granary.callerFrame`](https://github.com/dstolz/granary/blob/main/+granary/callerFrame.m) | attributes a record to the code that logged it |
| [`granary.record`](https://github.com/dstolz/granary/blob/main/+granary/record.m) | the record struct |
| [`granary.stamp`](https://github.com/dstolz/granary/blob/main/+granary/stamp.m) / [`dateTag`](https://github.com/dstolz/granary/blob/main/+granary/dateTag.m) | fast timestamp and daily-filename rendering |
| [`granary.defaultLogDir`](https://github.com/dstolz/granary/blob/main/+granary/defaultLogDir.m) | the log directory in force: `getpref('eplog','LogDir')`, else the built-in |
| [`granary.builtinLogDir`](https://github.com/dstolz/granary/blob/main/+granary/builtinLogDir.m) | the built-in default alone, `<epsych root>/.error_logs`, ignoring any override |
| [`granary.setLogDir`](https://github.com/dstolz/granary/blob/main/+granary/setLogDir.m) | change it and re-point the live sinks |
| [`granary.isAbsolutePath`](https://github.com/dstolz/granary/blob/main/+granary/isAbsolutePath.m) | guards both against a working-directory-relative log location |
| [`granary.sink.Sink`](https://github.com/dstolz/granary/blob/main/+granary/+sink/Sink.m) | abstract destination; `accepts(rec)` and `MaxLevel` |
| [`granary.sink.Console`](https://github.com/dstolz/granary/blob/main/+granary/+sink/Console.m) | command window; where `GVerbosity` is applied |
| [`granary.sink.FileSink`](https://github.com/dstolz/granary/blob/main/+granary/+sink/FileSink.m) | daily-file lifecycle: rotation, flush, latch, recovery; where `GLogVerbosity` is applied |
| [`granary.sink.TextFile`](https://github.com/dstolz/granary/blob/main/+granary/+sink/TextFile.m) | human-readable daily log |
| [`granary.sink.JsonLines`](https://github.com/dstolz/granary/blob/main/+granary/+sink/JsonLines.m) | structured daily log (opt-in) |

Tests: [`the granary repo tests/smoke_test_logging.m`](../../the granary repo tests/smoke_test_logging.m) covers the
package in isolation;
[`tmp/smoke_test_granary_integration.m`](../../tmp/smoke_test_granary_integration.m)
covers the `vprintf` seam and the consumers that name the log file;
[`tmp/smoke_test_stimgen_logging.m`](../../tmp/smoke_test_stimgen_logging.m)
covers the `stimgen` bridge, including caller attribution through it.

## Related

- [`vprintf`](../helpers/helpers_vprintf.md) — the front door, and the only API most code needs
- [RunExpt self-test](../overviews/RunExpt_SelfTest.md) — check A4 verifies logging reaches disk
- `stimgen` has its own front door (`stimgen.util.vprintf`) but delivers through
  this package: `epsych_startup` installs `stimbridge.LogBridge`, which
  implements `stimgen.LogSink` and forwards to `granary.Logger.emit`. stimgen
  messages therefore appear in the session log, attributed to the stimgen call
  site. Without EPsych — or under a stimgen pinned before the seam — stimgen
  falls back to `fullfile(tempdir,'stimgen_error_logs')`. See
  [stimgen.md](../stimgen.md).
