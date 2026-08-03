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

`stimgen` has no dependency on EPsych. It defines two abstract classes that a
host application implements, and EPsych's implementations live in
[`obj/+stimbridge/`](../obj/+stimbridge/):

| stimgen contract | EPsych implementation | Purpose |
|---|---|---|
| `stimgen.HardwareHost` | `stimbridge.RuntimeHost` | Protocol loading, connect/release, device mode, parameter lookup for `stimgen.StimPlayer` and `stimgen.calibration.CalibrationGui` |
| `stimgen.calibration.HwAdapter` | `stimbridge.InterfaceAdapter` | Play/record over an `hw.Interface` for `stimgen.calibration.Engine` |

Everything else in EPsych consumes `stimgen` as a plain library — `hw.Parameter`,
`hw.Module`, `epsych.Protocol`, and `epsych.ProtocolDesigner` treat
`stimgen.StimType` as a first-class parameter value type, unchanged by the split.

## Example assets

The demo protocol, config, and TDT circuit files that used to sit inside the
package are in [`examples/stimgen/`](../examples/stimgen/). They stayed in this
repository because the `.prot`/`.ecfg` files deserialize into `epsych.Protocol`
objects and the `.rcx` files are TDT-specific — neither is usable from a
standalone `stimgen`. See [`examples/stimgen/README.md`](../examples/stimgen/README.md)
for the circuit parameter contracts.

## Logging and provenance

`stimgen` vendors its own logger. It shares the `GVerbosity` global with EPsych,
so verbosity levels stay in sync, but it writes to
`fullfile(tempdir,'stimgen_error_logs')` — **not** to this repository's
`.error_logs/`. When diagnosing a StimPlayer or calibration failure, check both
locations; `epsych.SelfTest` check A4 reports the stimgen path.

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
