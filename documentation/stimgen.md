# Stimulus Generation (`stimgen`)

The `stimgen` package is no longer part of this repository. It now lives in its
own repository and is attached here as a git submodule:

- **Repository:** <https://github.com/dstolz/stimgen>
- **Submodule path:** `obj/stimgen/` (the package itself is `obj/stimgen/+stimgen/`)
- **Documentation:** [`obj/stimgen/documentation/`](../obj/stimgen/documentation/),
  also browsable at <https://github.com/dstolz/stimgen/tree/main/documentation>

## Getting the code

```bash
git clone --recurse-submodules https://github.com/dstolz/epsych2.git

# for an existing clone:
git submodule update --init --recursive
```

`epsych_startup` checks that the submodule is present and prints an actionable
message if it is not. This matters: without it, protocols containing
`stimgen.StimType` parameters load with silently degraded placeholder values
rather than failing outright.

## How EPsych integrates with it

`stimgen` has no dependency on EPsych. It defines three abstract classes that a
host application implements, and EPsych's implementations live in
[`obj/+stimbridge/`](../obj/+stimbridge/):

| stimgen contract | EPsych implementation | Purpose |
|---|---|---|
| `stimgen.HardwareHost` | `stimbridge.RuntimeHost` | Protocol loading, connect/release, device mode, parameter lookup for `stimgen.StimPlayer` and `stimgen.calibration.CalibrationGui` |
| `stimgen.calibration.HwAdapter` | `stimbridge.InterfaceAdapter` | Play/record over an `hw.Interface` for `stimgen.calibration.Engine` |
| `stimgen.LogSink` | `stimbridge.LogBridge` | Route `stimgen.util.vprintf` into the EPsych session log; installed by `epsych_startup` |

All three follow the same versioning rule: a new contract method must be
**concrete, with a safe default**. Adding one as `Abstract` makes the
corresponding `stimbridge` class unconstructable, which is what check A3 exists
to catch.

Everything else in EPsych consumes `stimgen` as a plain library — `hw.Parameter`,
`hw.Module`, `epsych.Protocol`, and `epsych.ProtocolDesigner` treat
`stimgen.StimType` as a first-class parameter value type, unchanged by the split.

## Launching the calibration GUI

`epsych.calibrate` is the entry point; RunExpt's **Utilities > Calibration GUI...**
does the same thing. It builds the `stimbridge.RuntimeHost` seam and the
calibration engine so callers never assemble them by hand:

```matlab
epsych.calibrate                        % opens with the host attached, no hardware
epsych.calibrate('MyExperiment.eprot')  % loads, connects, and sets Preview first
```

Without a protocol, connect from the GUI's **File > Initialize Runtime From
Protocol...**, or use **Hardware > Attach Adapter** to borrow a live session's
base-workspace `RUNTIME`. A protocol that fails to load or connect is logged and
the window still opens offline, so the menu can be used to retry.

The underlying `stimgen.calibration.CalibrationGui` also accepts a bare host —
`stimgen.calibration.CalibrationGui(host)` — since it creates its own engine when
none is supplied.

## Example assets

The demo protocol, config, and TDT circuit files that used to sit inside the
package are in [`examples/stimgen/`](../examples/stimgen/). They stayed in this
repository because the `.prot`/`.ecfg` files deserialize into `epsych.Protocol`
objects and the `.rcx` files are TDT-specific — neither is usable from a
standalone `stimgen`. See [`examples/stimgen/README.md`](../examples/stimgen/README.md)
for the circuit parameter contracts.

## Logging and provenance

`stimgen` ships its own logger so it can run standalone, but it does not have to
use it. `stimgen.LogSink` is a third abstract seam alongside `HardwareHost` and
`HwAdapter`: a host implements it, installs it with `stimgen.util.logSink`, and
from then on `stimgen` forwards every message instead of writing its own file.

`obj/+stimbridge/LogBridge.m` is EPsych's implementation, and `epsych_startup`
installs it. So a StimPlayer or calibration failure lands in `.error_logs/` with
everything else — same format policy, same sinks, same daily file, attributed to
the `stimgen` call site rather than to the bridge. **There is one log to read,
not two.** `epsych.SelfTest` check A6 proves it end to end by round-tripping a
marker through `stimgen.util.vprintf`.

Pinning a `stimgen` from before the seam is still supported: `epsych_startup`
probes for `stimgen.LogSink` and silently skips the install, `stimgen` keeps
writing to `fullfile(tempdir,'stimgen_error_logs')`, and A6 degrades to a
warning naming that path. The `GVerbosity` global still steers both either way,
and with the bridge installed `eplog.isEnabled` is its single reader — including
the split between console and log verbosity, so a `stimgen` message above
`GVerbosity` is still written to `.error_logs/` rather than dropped by
`stimgen`'s own single-destination gate.

Because `stimgen` releases independently, `EPsychInfo.stimgenChksum` records the
pinned submodule commit and `EPsychInfo.meta.StimgenChecksum` carries it into
saved session metadata alongside the EPsych checksum. `epsych.SelfTest` check A3
reports the same commit and fails if the pinned `stimgen` has added an abstract
method that `obj/+stimbridge/` does not yet implement.

## Updating the submodule

```bash
git submodule update --remote obj/stimgen   # pull latest stimgen main
git add obj/stimgen && git commit           # record the new commit in epsych2
```

The submodule pins an exact commit, so `stimgen` changes only reach this
repository when that pointer is deliberately updated and committed.
