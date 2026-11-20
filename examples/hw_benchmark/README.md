# I/O benchmark example assets

Ready-made protocols for `hw.benchmarkIO`, which `Utilities > Hardware > I/O
Benchmark...` in `epsych.RunExpt` runs on a loaded protocol's hardware
interface. See [hw_benchmarkIO.md](../../documentation/hw/hw_benchmarkIO.md) for
what it measures and how to read the results.

| File | Purpose |
|---|---|
| `HwBenchmark_TDT_RPcox.rcx` | RPvds circuit exposing the benchmark's contract tags on a TDT processor |
| `HwBenchmark_TDT_RPcox.eprot` | `hw.TDT_RPcox` protocol that loads the circuit above |
| `HwBenchmark_Software.eprot` | `hw.Software` protocol with the same parameter names, for trying the utility with no hardware. Timings are the in-memory call into a backend that writes and logs nothing, not a device's, and not all of EPsych's overhead either (see "The HAL floor" in the documentation). `hw.Software` keeps nothing it is written and reads `NaN`, so its round trip **fails by design**; the figure, `Problems` and the status line report that as a simulated interface's |
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

### Required `SerialBuf` configuration

`Buf` must be written and read by the host only. The circuit must not write
into it while the benchmark runs:

- the `SerialBuf` **not recording**: its write/record input off (`Write = 0`),
  or the component disabled so its index does not run;
- `Size` at least the largest length you will test (292969 or more to bracket a
  3 s stimulus at 97656.25 Hz). `hw.TDT_RPcox` reads the whole tag, so every
  read and round-trip check moves `Size` samples;
- the `Buf` tag on the buffer's data port, as now.

**The committed circuit may not meet this.** Read with `strings` (not confirmed
in RPvdsEx), its `SerialBuf` is stored with `Size=1e+06`, `AccEnab=1`,
`Write=1`, `Rst=0`, with `Buf` on `{>Data}` and an input port wired. If so, the
DSP overwrites `Buf` continuously while the host writes and reads it, and the
round trip fails with one contiguous run of mismatched samples.

Step for the user, in RPvdsEx (the `.rcx` cannot be edited from MATLAB):

1. Open `HwBenchmark_TDT_RPcox.rcx` and confirm the `SerialBuf` settings above.
2. If it records its input, turn that off (`Write = 0`, or disable the
   component / disconnect its input) so nothing the DSP produces reaches the
   buffer. Keep `Size` at 1000000, or reduce it to the largest size you test.
3. Compile, save, and reload the circuit (re-open the protocol or reconnect).
4. Run the benchmark with sizes that bracket `TargetSamples`, e.g.
   `1024 4096 65536 300000`. Every round-trip check should pass; a
   **ROUND TRIP FAILED** heading on the figure means the buffer is still being
   written by the circuit.

Reads are whole-tag, so on one tag the benchmark times a read once per path,
at the first size, and lists the other read sizes as not timed. To time reads
at several lengths, add one tag per length (`Buf_1024`, `Buf_65536`, ...).

## Moving the protocol

`HwBenchmark_TDT_RPcox.eprot` stores the circuit's absolute path
(`RPvdsFile`), as every `hw.TDT_RPcox` protocol does. On another checkout or
machine, re-point it in `epsych.ProtocolDesigner` (module `IOBenchmark`) before
the first Run.
