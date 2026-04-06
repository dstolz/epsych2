# `vprintf`

`vprintf` is EPsych's shared console and log printing helper.

It adds a timestamp to each message, filters output using the global verbosity level, and writes messages to a daily log file under `.error_logs` in the EPsych root folder.

**_All EPsych functions should consider using this in place of directly calling `fprintf`_**

## Function signature

```matlab
vprintf(verbose_level, msg)
vprintf(verbose_level, red, msg)
vprintf(verbose_level, msg, value1, value2, ...)
vprintf(verbose_level, red, msg, value1, value2, ...)
vprintf(verbose_level, red, exception)
```

- `verbose_level`: Numeric message level.
- `red`: Optional flag. Use `1` to print to MATLAB's error stream (`fprintf(2, ...)`).
- `msg`: A format string for `fprintf`, or an `MException` object.
- `value1, value2, ...`: Optional values consumed by the format string.

## What it does

For normal string messages, `vprintf`:

1. Checks the global `GVerbosity` level.
2. Builds a timestamp in `HH:MM:SS.FFF` format.
3. Writes the message to the daily log file.
4. Prints the message to the MATLAB command window unless `verbose_level == -1`.

Printed messages look like this:

```text
18:51:35.958: Recording session started at 18:51:35
```

Every printed or logged message ends with a newline automatically.

## Verbosity levels

The help text describes these common levels:

- `-1`: Log only, do not print to the command window.
- `0`: Critical or high-priority user-facing messages.
- `1`: General informational messages.
- `2`: More detailed debugging information.
- `3`: Very verbose debugging output.

In practice, the implementation accepts any numeric level because it only compares `verbose_level` against `GVerbosity`. Some files in this repository use level `4` for very detailed trace messages.

If `GVerbosity` is empty or invalid, `vprintf` initializes it to `1`.

## Log file behavior

`vprintf` writes to a daily text file located at:

```text
.error_logs/error_log_ddmmmyyyy.txt
```

The `.error_logs` directory is created under the folder returned by `epsych_path`, which is the EPsych repository root.

Each log entry includes:

- The timestamp.
- The name of the calling function.
- The caller line number.
- The formatted message text.

This caller information is gathered from `dbstack` inside the nested `logmessage` helper.

## Global variables used

`vprintf` relies on two globals:

- `GVerbosity`: Controls whether a message is processed.

Typical setup:

```matlab
global GVerbosity
GVerbosity = 2;
```

The log file handle is managed internally with persistent function state. If the current handle is missing, invalid, closed, or belongs to a previous day, `vprintf` opens a new daily log file automatically.

## Basic examples

### Print a standard message

```matlab
global GVerbosity
GVerbosity = 2;

vprintf(1, 'Starting acquisition for box %d', boxId)
```

### Print to the error stream

```matlab
vprintf(0, 1, 'Unable to connect to pump on COM%d', comPort)
```

### Log without showing anything in the command window

```matlab
vprintf(-1, 'Custom trial selection failed for subject %s', subjectName)
```

### Log an exception

```matlab
try
    doSomethingRisky();
catch ME
    vprintf(0, 1, ME)
end
```

When the input message is an `MException`, `vprintf` logs:

- `ME.identifier`
- `ME.message`
- One line per stack frame with file, function name, and line number

## Notes and limitations

- `vprintf` uses `fprintf` formatting rules directly, so the format string and supplied values must match.
- The function always appends a newline. It is not intended for partial-line output.
- Logging includes stack inspection and file I/O, so very high-frequency debug logging can affect timing-sensitive code.
- The helper assumes the format message is character data when formatting a normal message.

## Related files

- [helpers/vprintf.m](../helpers/vprintf.m)
- [epsych_path.m](../epsych_path.m)
