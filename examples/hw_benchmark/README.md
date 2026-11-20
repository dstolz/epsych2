# I/O benchmark example assets

Ready-made protocols for `hw.benchmarkIO`, which `Utilities > Hardware > I/O
Benchmark...` in `epsych.RunExpt` runs on a loaded protocol's hardware
interface. See [hw_benchmarkIO.md](../../documentation/hw/hw_benchmarkIO.md) for
what it measures and how to read the results.

| File | Purpose |
|---|---|
| `HwBenchmark_TDT_RPcox.rcx` | RPvds circuit exposing the benchmark's contract tags on a TDT processor |
| `HwBenchmark_TDT_RPcox.eprot` | `hw.TDT_RPcox` protocol that loads the circuit above |
| `HwBenchmark_Software.eprot` | `hw.Software` protocol with the same parameter names, for trying the utility with no hardware. Timings are EPsych's own overhead, not a device's |
| `create_hw_benchmark_protocol.m` | Regenerates `HwBenchmark_Software.eprot` (it is tracked, so re-running it rewrites the committed file) |

## Contract tags

| Tag | Circuit | Role |
|---|---|---|
| `WScalar` | writes a `ConstF` value | scalar write |
| `RScalar` | reads a `ConstF` output | scalar read |
| `!BenchTrig` | writes a `ConstL` value (the `!` makes it a trigger) | trigger |
| `Buf` | a `SerialBuf`'s `>Data` port | buffer write and read-back, at each size you ask for |

The `SerialBuf` `Size` is the largest length the benchmark can test. The
benchmark takes a buffer's capacity from the tag size the processor reports when
the circuit loads, and skips (and says so on the plot) any requested size above it.
Rebuild the circuit with a larger `Size` for larger tests, and reload it, since
a processor still holding the old circuit keeps reporting the old size.

## Moving the protocol

`HwBenchmark_TDT_RPcox.eprot` stores the circuit's absolute path
(`RPvdsFile`), as every `hw.TDT_RPcox` protocol does. On another checkout or
machine, re-point it in `epsych.ProtocolDesigner` (module `IOBenchmark`) before
the first Run.
