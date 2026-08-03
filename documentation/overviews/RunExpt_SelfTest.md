# RunExpt self-test

The self-test is a pre-flight check for a session. It runs real checks against whatever is currently loaded in `epsych.RunExpt` — compiling protocols, exercising the trial selector, writing and reading back data files, probing hardware — and tells you, per check, whether a run would work and what to do if it would not.

The problem it solves: almost every way a session can fail is only discovered once the session has started. A protocol missing a trigger parameter aborts inside the timer's start callback. An unwritable data directory trips an assertion after the hardware has already gone into run mode. A custom trial selector with a bug throws in the middle of the trial loop. The self-test moves those discoveries to before you press **Run**.

Open it from **Help → Run Self-Test...** (`Ctrl+D`).

## Table of contents

- [1) Using the window](#1-using-the-window)
- [2) Statuses](#2-statuses)
- [3) Opt-in checks](#3-opt-in-checks)
- [4) What is checked](#4-what-is-checked)
- [5) Logging](#5-logging)
- [6) Running it from the command line](#6-running-it-from-the-command-line)
- [7) The `hw.Interface.selfTest` hook](#7-the-hwinterfaceselftest-hook)
- [Related documentation](#related-documentation)

## 1) Using the window

- The tree on the left lists the nine check groups; all are ticked by default. **Run All** runs everything, **Run Selected** runs only the ticked groups.
- Each check produces one row in the results table, tinted by status. After a run, the first row that needs attention is selected and scrolled into view — a passing run leaves nothing selected.
- Selecting a row fills the pane below with that check's details and, for anything that failed or warned, a **What to do** line.
- **Copy Report** puts the full plain-text report on the clipboard; **Save Report...** writes it to the `.error_logs` directory beside the daily log. Both are useful for sending to whoever maintains the rig.
- The footer shows the tally and how long the run took.

The self-test is available while a session is running. The read-only checks are exactly what you want when something is behaving oddly mid-experiment; the checks that would disturb a run refuse to execute and report themselves as skipped.

## 2) Statuses

| Status | Meaning |
|--------|---------|
| `PASS` | The check verified what it set out to verify. |
| `FAIL` | This would break a run, or already has. Every failure carries a remedy. |
| `WARN` | Degraded or risky, but a run will start. Worth reading. |
| `SKIP` | A precondition was not met (no config loaded) or an opt-in check was not enabled. The reason is in the summary. |
| `INFO` | Inventory, not a verdict. Never counts against the run. |

## 3) Opt-in checks

Three groups of checks can only be real if they cause side effects, so they are off by default and marked `[!]` in the tree.

- **Connect hardware interfaces** — connects every interface in the protocol, asserts it reports connected (the same assertion the runtime makes), runs each backend's invasive self-test, then restores the connection state it found. This is the only way to verify parameters on hardware that discovers them at connect, such as TDT RPvds.
- **Launch the Box GUI** — launches the configured box GUI against a synthetic runtime and closes it again. Note that `ep_GenericGUI` allows only one instance, so an already-open box GUI will be replaced.
- **Cycle the live GUI state** — drives the session window through each program state, asserts which controls are enabled in each, and restores the original state. The window flickers briefly.

All three are refused while a session is RUNNING.

## 4) What is checked

**Environment & installation** — repository metadata, that every required function and class resolves on the path, that the stimgen submodule is checked out *and that `obj/+stimbridge/` still implements its abstract contract* (the check reports the pinned stimgen commit and fails if the submodule has drifted ahead of the bridge), that `vprintf` output actually reaches the log file, and that no stale RunExpt windows or orphaned timers are left over from a previous session. Note that stimgen logs separately to `fullfile(tempdir,'stimgen_error_logs')`; the log check reports that path too.

**Callback functions** — that every name in `FUNCS` resolves and has the signature the runtime will call it with, that the timer period is in range, and whether the session's callbacks have drifted from the stored preferences.

**Timer** — runs a throwaway timer configured exactly like the PsychTimer and reports the period the machine actually delivers, its jitter, and any dropped ticks. The verdict uses the median interval, so one stall does not condemn a machine that is otherwise fine; a long stall is reported separately.

**Config & subjects** — that every subject record is complete, that box IDs are unique positive integers, that subject names are safe to build filenames from, and that each subject's protocol file is still on disk.

**Protocol** — runs `validate()` and surfaces every finding; compares the in-memory protocol version against the file on disk; compiles the protocol and reports trial count, write-parameter count, and estimated duration; checks that the `x_NewTrial_<BoxID>`, `x_ResetTrig_<BoxID>`, and `x_TrialComplete_<BoxID>` trigger parameters the runtime demands exist for every subject's box; and checks that the write-parameter names can be used as struct fields.

Compilation always happens on an isolated copy of the protocol, so the self-test never mutates the protocol you are about to run.

**Trial selection** — resolves the configured selector, then drives it for up to 500 selections against the compiled trial table. Verifies every returned ID is an in-range integer and reports coverage, balance, and selection time — flagging anything slower than the 0.25 s the trial loop warns at. Then calls `onComplete`, `setRuntime`, and `onRecompile` to confirm none of them throw.

**Hardware & connections** — inventories the interfaces, then asks each one to check itself (see [section 7](#7-the-hwinterfaceselftest-hook)). Also checks the Intan path preferences for the spaces that RHX commands cannot express.

**Data saving** — proves the data directory and the crash-recovery directory are writable by actually writing, reading, and deleting a probe file; replicates the exact per-trial append pattern the trial loop uses and reads the trials back, reporting the per-trial write time; reserves the session filenames and checks they are unique; and, when video recording is enabled, checks that the recording path resolves and pairs with the data filename.

The default saving function is interactive, so the self-test deliberately does not invoke it. The per-trial round trip covers the disk path it eventually writes to.

**GUI wiring & state** — that every handle the window's code depends on exists, that the control tag conventions the state machine relies on are intact, that the configuration survives a save/load round trip unchanged, and that the event broadcaster reaches its listeners.

## 5) Logging

Every check writes its full detail to the daily log under `.error_logs/`, at a level that always logs regardless of the verbosity you choose. That means a self-test run is fully reconstructable after the fact even if the console was set to show nothing.

The **Verbosity** dropdown sets the level forced for the duration of the run, so nested code — protocol compilation, the trial selector, hardware connection — also emits its detailed messages. The previous level is restored when the run finishes. Level 3 is the default and is the right choice when you are diagnosing something.

## 6) Running it from the command line

The engine is independent of the window:

```matlab
st  = epsych.SelfTest;          % binds to the open session, if any
res = st.run();                 % all groups
disp(st.formatReport(res))
```

Run a subset, or enable an opt-in group:

```matlab
res = st.run(["Protocol" "TrialSelection"]);

st.IncludeHardwareConnect = true;
res = st.run("Hardware");
```

`res` is a struct array with one element per check: `id`, `group`, `name`, `status`, `summary`, `detail`, `remedy`, `seconds`, `mutating`. `epsych.SelfTest.rollup(res)` counts them by status, and `st.saveReport(res)` writes the text report.

## 7) The `hw.Interface.selfTest` hook

Only a backend can tell "not plugged in" from "wrong circuit loaded", so hardware checks are delegated to the interface itself. `hw.Interface` defines an optional `selfTest` hook, modeled on the existing `prepareRecording` lifecycle hook: a no-op on the base class that concrete backends override.

```matlab
results = interface.selfTest();                 % non-invasive
results = interface.selfTest(Invasive = true);  % may connect and query
```

The non-invasive form must not change hardware state — no connect, no mode writes, no recording configuration. The invasive form may connect and query the live device, and must restore the connection state it found. Neither form may throw: a failed probe is a `fail` result.

Build results with the static helper rather than hand-rolling structs:

```matlab
r = hw.Interface.selfTestResult('Command server reachable', 'fail', ...
    sprintf('Cannot reach the RHX command server at %s.', target), ...
    Detail = string(ME.message), ...
    Remedy = "Start the Intan RHX software and enable its TCP command server.");
```

Calling `hw.Interface.selfTestResult()` with no arguments returns the empty prototype, which is what the base class returns and what a backend should seed an accumulator with.

What the shipped backends check:

| Backend | Non-invasive | Invasive |
|---------|--------------|----------|
| `hw.Software` | Parameter inventory | — |
| `hw.Intan_RHX` | TCP reachability of the command server (no RHX command issued); recording paths free of spaces; settings file exists | Connects, reports run mode, sample rate, controller type |
| `hw.VlcRecorder` | `vlc.exe` located; a camera is configured | Enumerates cameras and confirms the configured one is present |
| `hw.TDT_RPcox` | TDT driver on the path; every module's `.rcx` circuit file exists | Loads the circuits, reports sample rate and parameter count per module |
| `hw.TDT_Synapse` | SynapseAPI on the path; Synapse server reachable | Connects, reports experiment info and mode |

A backend that does not override the hook returns nothing, and the self-test reports that plainly rather than assuming everything is fine.

## Related documentation

- [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md) — using the session GUI
- [../hw/hw_Interface.md](../hw/hw_Interface.md) — the hardware abstraction the `selfTest` hook belongs to
- [Architecture_Overview.md](Architecture_Overview.md) — internals
