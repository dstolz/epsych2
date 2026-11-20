# `hw.benchmarkIO`

`hw.benchmarkIO` times what a running session pays to talk to its hardware:
scalar writes, scalar reads and triggers, and buffer writes and read-backs as a
function of buffer length. It works on any `hw.Interface`, because it calls only
the methods the runtime calls: `set_parameter`, `get_parameter`, `trigger`,
`find_parameter` and `all_parameters`.

Three `hw.Interface` hooks supply what the utility would otherwise have to get by
checking the backend's class (see [hooks](#hw-layer-hooks)):

- `parameterCapacity` gives the element count behind a buffer.
- `isSimulated` says whether a device sits behind the interface at all.
- `transferContext` describes the conditions a transfer time depends on
  (device model, link, the driver calls and sample format, cycle usage).

There is no `isa(iface, ...)` test anywhere in the function. The standing proof
checks for that.

The question it was written for was about an RZ6 under `hw.TDT_RPcox`. A ~3 s
stimulus at 97656.25 Hz is 292969 float32 samples. Should it be uploaded before
every trial, or loaded once per session with only scalars written per trial?
[Deciding](#deciding-per-trial-upload-versus-once-per-session) walks through how
to answer that from the output.

---

## What is measured, and why

Each measurement is one **block**: one role, one parameter, and one **path**.
`Warmup` calls are made and discarded, then `Repeats` calls are timed one at a
time, each between its own `tic` and `toc`. Every timed call is kept raw. Nothing
is written to the console per call, and one level-2 log line is written per
block.

| Role | Call timed | Value |
|---|---|---|
| `ScalarWrite` | `set_parameter(target, v)` | two values inside the parameter's bounds, alternated, so a backend that skips an unchanged write still works |
| `ScalarRead` | `get_parameter(target)` | — |
| `Trigger` | `trigger(target)` | — |
| `BufferWrite` | `set_parameter(target, {data})` | full-capacity random `single` vector, inside a scalar cell, which is the shape `hw.Parameter.set.Value` hands every backend for an array |
| `BufferRead` | `get_parameter(target)` | the length actually returned is recorded for every call |

**Paths.** Each call is timed two ways. **By handle** (`Path = "param"`) passes
the pre-resolved `hw.Parameter`. **By name** (`Path = "name"`, `IncludeLookup`,
on by default) passes the parameter's name, so the backend's `find_parameter` is
part of the cost. The difference between the two medians is the **lookup cost**,
drawn in the figure's bottom-right panel. The runtime's trial dispatch passes
`hw.Parameter` handles, so the by-handle times are the ones a session pays. The
figure labels every box, dot and legend entry with its path in words.

**The HAL floor.** With `CompareToSoftware` on (the default), the same contract is
run again on an in-memory twin: an `hw.Software` interface holding one parameter
per contract parameter, with the same name, type, access, trigger flag,
visibility and bounds, at the same sizes. `Floor.AboveFloor_s` is the device's
median minus the twin's. Nothing below the HAL is ever called.

The floor is **not** "EPsych's own overhead" in full. It is the cost of calling
into a backend method that does almost nothing:

| | `hw.Software` (the twin) | `hw.TDT_RPcox`, for comparison |
|---|---|---|
| `set_parameter` | resolves a name (by-name path only), returns 1. Writes nothing and logs nothing | `IsConnected` probe (a `GetStatus` COM call per module), name lookup (by-name path), `TDTRP.write` (tag-size check, the RPcoX call), a level-4 `vprintf` record, which the log file takes by default |
| `get_parameter` | returns `NaN`. Does not resolve a name, and moves no data | `IsConnected` probe, name lookup (by-name path), whole-tag `ReadTagVEX` |
| `trigger` | returns `now` | `IsConnected` probe, two writes and a 1 ms `pause` |

So `AboveFloor_s` is the transport **plus** the connection probe, the log
record and the value formatting the real backend does and the twin does not.
To separate the logging part, run once at the default `GLogVerbosity` and once
at 3 (see *Running it*). The floor is skipped when the interface is itself
simulated.

**Round trip.** With `VerifyRoundTrip` on (the default), each readable buffer is
written once more, at each size, with a fresh vector, then read back through its
`hw.Parameter`. The first `NWritten` samples read are compared at float32
precision, allowing one ulp per element; a backend that reads the whole tag back
returns more, and what lies past `NWritten` is not checked. `RoundTrip` reports
how many samples were compared (`NCompared`), how many differ (`NMismatched`),
in how many contiguous runs (`MismatchRuns`), and where (`FirstMismatch`,
`LastMismatch`). One contiguous run of mismatches is what a buffer the device is
itself writing into leaves behind (a running write index); a run that touches
both ends of what was compared is reported as one that may have wrapped.

A failed round trip is not an error, but it is never quiet:

- it is a `Problems` row (`Role = "RoundTrip"`) naming the size and the note;
- it is logged at level 0 (level 1 on a simulated interface, see below);
- it heads the figure in red (**ROUND TRIP FAILED**, one line per failed check);
- RunExpt puts it first on the status line.

`hw.Software` keeps nothing it is written and reads `NaN`, so a round trip on it
fails **by design**; on a simulated interface the `Problems` reason and the
status line say so.

**Refusals.** A disconnected interface is refused unless `isSimulated()` is
true. `hw.TDT_RPcox`, `hw.TDT_Synapse`, `hw.Teensy`, `hw.Bpod`, `hw.Intan_RHX`
and `hw.NE1000` all return success from `set_parameter` while disconnected, and
most serve the cached `Value` (Intan returns empty) from `get_parameter`. Timing
that would report I/O that never happened.

---

## Running it

```matlab
% iface: a connected backend, e.g. RUNTIME.Interfaces(1), or one taken from a
% loaded protocol and connected by hand. Run it between sessions.
R = hw.benchmarkIO(iface);                         % defaults
R = hw.benchmarkIO(iface, Repeats=200, Warmup=10, SaveTo="D:\bench\");
R = hw.benchmarkIO(iface, ScalarWrite="Freq", Trigger=[], Buffers=["StimA" "StimB"]);
```

| Option | Default | Meaning |
|---|---|---|
| `ScalarWrite`, `ScalarRead`, `Trigger` | discovered | name or `hw.Parameter`. Given: must exist and qualify, or it errors naming it. Given as `[]`: the role is skipped |
| `Buffers` | discovered | names or `hw.Parameter` array, same rules |
| `Sizes` | `[]` | element counts to time **every** buffer at, e.g. `[1024 4096]`: one tag, several lengths. A size above what the backend (`parameterCapacity`), `BufferSizes` or a `Buf_<N>` name says the buffer holds is skipped and listed in `R.Unsupported`; with none of those known (`hw.Software`) the sizes are trusted. `[]` times each buffer once, at its own size. The RunExpt menu item asks for these in a dialog, default `1024 4096` |
| `BufferSizes` | `[]` | declared size per buffer, aligned with `Buffers` (or with the discovered list in `R.Contract` order). `NaN` = unknown |
| `Repeats` | 50 | timed calls per block |
| `Warmup` | 5 | discarded calls per block |
| `VerifyRoundTrip` | true | see above |
| `IncludeLookup` | true | also time the by-name path, which is what the lookup-cost panel needs |
| `TargetSamples` | 292969 | length to predict one and two buffer uploads for (3 s at 97656.25 Hz) |
| `SaveTo` | `''` | an existing folder (or a path ending in a separator) gets a timestamped stem. Anything else is a file stem. Writes `<stem>.mat` (`results`), `<stem>.csv` (raw table) and `<stem>_summary.csv` |
| `Plot` | true | buffers (median, 5th–95th percentile, fit, ★ prediction) beside scalars and triggers |
| `CompareToSoftware` | true | run the Software floor |
| `Progress` | true | log each measurement as it starts and finishes (`[7/14] BufferWrite, by handle, N=4096 ...` then its median and elapsed time), the round-trip check, the floor run and the total time. `vprintf` level 1, so it reaches the command window at the default verbosity. A large buffer over a slow link can take minutes, and the call is otherwise silent until the end |

Helpers:

```matlab
twin = hw.benchmarkIO("softwareTwin", iface);     % the hw.Software the floor runs on
f    = hw.benchmarkIO("fit", N, seconds, TargetSamples=292969);
txt  = hw.benchmarkIO("contract");                % the default contract as text
```

These are subcommands rather than `hw.benchmarkIO.softwareTwin(...)` because a
package function cannot carry static methods.

**Before a run, set the logging level you want measured.** Every
`set_parameter` on `hw.TDT_RPcox` and `hw.TDT_Synapse` logs a level-4 record.
`GLogVerbosity` defaults to `Inf`, so every write also costs a log-file write
(about 200 µs, per [granary_Logging.md](../granary/granary_Logging.md)). The
levels in force are recorded in `R.Environment` (`GVerbosity`, `GLogVerbosity`,
`Level4ToLog`). To see the logging cost, run once at the default and once with
`GLogVerbosity = 3`.

---

## Roles and the default contract

A role left unspecified is discovered by name. A role it cannot fill is listed in
`R.Unsupported` with the reason, and is never an error or a time. A role named
explicitly that does not exist, or does not qualify, is an error naming it. When
nothing at all can be measured, the call errors and prints this contract.

| Role | Default parameter name | Requirements |
|---|---|---|
| ScalarWrite | `WScalar` | writable (Access not `Read`), not a trigger, numeric scalar |
| ScalarRead | `RScalar` | readable (Access not `Write`), numeric scalar, e.g. driven by a counter |
| Trigger | `BenchTrig` or `!BenchTrig` | `isTrigger` true. On RPvds (`hw.TDT_RPcox`, and `hw.TDT_Synapse` in legacy mode) a tag is a trigger only when its name starts with `!`, and the parameter's `Name` is the tag name verbatim, so the tag is `!BenchTrig` |
| Buffers | `Buf` (or `Buf_<N>`) | writable, preferably readable, `Type` `Buffer`/`Coefficient Buffer` or `isArray` or size > 1. Timed at each of `Sizes`, else once at its own size |

**Buffer size** (what a buffer holds, with no `Sizes` given), in order of precedence:

1. `iface.parameterCapacity(P)`: the device's own answer.
2. The caller's `BufferSizes` entry.
3. The `N` in a `Buf_<N>` name.
4. The length one untimed read returns.

When the device's capacity disagrees with a stated size, the capacity is used, and
`R.Contract.Note` says so. `R.Contract.SizeSource` records which source was used
(`Sizes` when the lengths were asked for), and `R.Contract` has one row per
buffer and size.

**Several sizes on one tag.** The fit `t = Overhead + PerSample*N` needs two
distinct lengths, which one `Buf` tag now supplies through `Sizes`. Each size is
its own `Summary` row (the requested size is part of the grouping) and its own
round-trip check. A write sends exactly `N` samples.

**Whole-tag reads.** A backend that reads the **whole tag** back
(`hw.TDT_RPcox`: `TDTRP.read` with no size) returns its full size whatever was
written, so on one tag every read is the same transfer. Once a read returns
more samples than its block asked for, the later read blocks of that buffer and
path are **not timed**: each is an `Unsupported` row (`BufferRead`, "not timed at
N=...: the read at N=... returned ... samples, the whole buffer"). So a read is
timed once per path, at the first size, and labelled by what it moved:

- the progress line reads `moved 1000000 samples (the whole buffer, not the 1024 requested)`;
- `Summary.NTransferred` is what moved (`NRequested` is the block it was timed in);
- the buffer and throughput plots place it at the samples moved;
- the lookup-cost panel labels it `BufferRead, 1000000 samples`.

The `BufferRead` fit then sees one distinct length and reports `NaN` terms; that
is the device's behaviour, not a missing measurement. To time reads at several
lengths under `hw.TDT_RPcox`, use one tag per length (`Buf_1024`, `Buf_4096`,
...), each discovered and timed at its own size. A read that returns **fewer**
samples than asked (the twin's `NaN`) does not trigger the skip.

Size the tag for the largest length you will ask for. With a whole-tag read, a
large tag also makes every read (and every round-trip check) pay for the whole
tag.

**By-name path.** The name is timed only when `find_parameter`, at its default
visibility, resolves it to the same parameter. Most backends call
`find_parameter` that way. An invisible parameter, or a name another parameter
shares, gets an `Unsupported` row for path `name`, and its `param` path is still
timed.

---

## Reading the results

| Field | Content |
|---|---|
| `Raw` | one row per timed call: `Role, Parameter, Backend, Path, NRequested, NTransferred, Iteration, Seconds, Accepted`. `Accepted` is false only where `set_parameter` returned false |
| `Summary` | per Role/Parameter/Path/NRequested: `Min_s`, `P5_s`, `Median_s`, `Mean_s`, `P95_s`, `Max_s` (`prctile`, `median`, `mean`) — the same six the progress log prints for each measurement as it finishes. For buffers also `MSamplesPerSec`, `MBPerSec` and `MbitPerSec` (= 8 × `MBPerSec`) at 4 bytes per sample. **TX is the `BufferWrite` rows and RX the `BufferRead` rows**; the rate uses the samples actually moved, so a whole-tag read counts the full tag. The figure's Throughput panel plots it against size, by handle, with the ceiling the fit implies (1 / `PerSample_s`) |
| `Fit` | per buffer role and path: `t = Overhead_s + PerSample_s*N` (least squares over the per-size medians). `Predicted_s` at `TargetSamples`, `PredictedTwoBuffers_s` = two such calls, `Extrapolated` when `TargetSamples` lies outside the sizes measured, and `ExtrapolationFactor` (`TargetSamples / NMax`, or `NMin / TargetSamples`; 1 inside the range). `Note` carries the "does not bracket" sentence below. Needs two distinct sizes. With one, both terms are `NaN` |
| `Lookup` | per measurement timed both ways: `NRequested`, `NMoved`, `ByHandle_s`, `ByName_s`, `Cost_s` (by name minus by handle), `PValue` (two-sided Wilcoxon rank-sum over the two sets of timed calls, `ranksum`) and `Status`: `resolved` (p < 0.05 and by name slower), `below resolution` (p ≥ 0.05), or `negative` (p < 0.05 but by name *faster*) |
| `RoundTrip` | per readable buffer and size: `NWritten`, `NRead`, `NCompared`, `NMismatched`, `MismatchRuns`, `FirstMismatch`, `LastMismatch`, `MaxAbsError`, `Tolerance` (largest ulp of the data), `Pass`, `Note` |
| `Floor` | per Summary row: `Backend_s`, `Floor_s` (the twin's median), `AboveFloor_s` |
| `Software` | the twin's own results struct (empty when not run) |
| `Contract` | what filled each role, from where (`explicit`/`discovered`), `Capacity`, `DeclaredSize`, `Holds` (what the buffer is known to hold: capacity, declared size or the `N` in its name; `NaN` when only a read said), `N`, `SizeSource`, `NamePath` |
| `Unsupported` | `Role, Parameter, Path, Reason`, including sizes a buffer cannot hold and whole-tag reads not repeated |
| `Problems` | blocks that threw, had writes rejected, or returned varying lengths, and every failed round trip (`Role = "RoundTrip"`) |
| `Environment` | date, MATLAB version and release, computer, backend class/type/label, `IsSimulated`, `IsConnected`, `Mode`, creation spec, modules (Label, Name, Index, Fs, Info), `Transfer` (below), `EPsychCommit`, `GVerbosity`, `GLogVerbosity`, `Level4ToConsole`, `Level4ToLog`, `TicTocOverhead_s`, `PayloadSeed` |

`Environment.Transfer` is what the interface's `transferContext` hook reports,
one record per device link, read before any timing: `Module`, `Device`, `Link`,
`DeviceNumber`, `SampleRate`, `CycleUsage` (percent) and `CycleUsageSource`
(`live`, `at circuit load`, `not connected` or `unavailable`), `WriteCall`,
`ReadCall`, `SampleFormat`, `Notes`. It is empty for a backend that does not
override the hook. Vendor transfer rates are quoted for stated conditions
(TDT's for RZ devices over Optibit at 50% cycle usage with 1,000,000-sample
transfers), so compare against them only with this record beside the timing.

### The figure

- **Buffers** (top left): median per size with 5th–95th percentile bars, the
  linear fit (solid over the sizes timed, **dashed** beyond them), and a
  pentagram at `TargetSamples`. The pentagram is **hollow** and its label reads
  `EXTRAPOLATED 4.5x beyond the largest size timed` when the prediction lies
  outside the sizes timed, filled and labelled `predicted` when it does not.
  When a buffer could hold `TargetSamples` but the sizes timed do not bracket
  it, a note in the top-right corner says so and which size to add (it is also
  logged at level 1 and appended to `Fit.Note`). No size is ever added for you.
  Sizes skipped because the buffer is too small are listed bottom right.
- **Scalars and triggers** (top right): every timed call, over a box per path.
- **Throughput** (bottom left): bit rate against samples moved, by handle.
- **Lookup cost** (bottom right): a bar only where `Lookup.Status` is
  `resolved`. A `below resolution` difference is written at zero with its
  p-value; a `negative` one is written as "by name ... faster: not a cost". The
  by-name and by-handle blocks run at different moments, so a resolved
  difference can still include drift between them; a negative one *is* drift,
  since a lookup cannot make a call faster. Labels name buffer rows by the
  samples the call moved.
- A failed round trip puts a red **ROUND TRIP FAILED** heading over all four.

For a write, `NTransferred` is what was handed to `set_parameter`. Nothing in the
interface reports what the device accepted beyond the return flag. For a read,
it is what came back, and the buffer-read fit, the plots and the lookup labels
use that length.

### Worked example

**The numbers below are illustrative, chosen to show the arithmetic. They are not
a measurement of any device.** Suppose a run with buffers of 1024, 16384, 131072,
300000 and 600000 samples gives this `Fit` row:

| Role | Path | Overhead_s | PerSample_s |
|---|---|---|---|
| BufferWrite | param | 0.80e-3 | 0.12e-6 |

For `TargetSamples` = 292969:

- one upload: 0.80 ms + 0.12 µs × 292969 = 0.80 ms + 35.16 ms = **35.96 ms** (`Predicted_s`)
- two buffers of it, two calls: 2 × 35.96 ms = **71.91 ms** (`PredictedTwoBuffers_s`)
- throughput: 4 B × 292969 / 35.96 ms = 32.6 MB/s

Here the fixed cost is under 3% of the upload, so splitting the stimulus into
more, smaller writes would cost little. Uploading less data is what would save
time. Compare `Floor.AboveFloor_s` for the same row: if the twin's median is a
few tens of microseconds, almost all of those 36 ms are transport.

Check `Extrapolated`: with 300000 and 600000 measured, 292969 lies inside the
range and the prediction is an interpolation. Had the largest size been 65536,
`ExtrapolationFactor` would be 4.47 and the pentagram hollow: a linear fit
carried 4.5x past the data assumes the per-sample cost stays constant over a
range nobody measured.

---

## Deciding per-trial upload versus once per session

A per-trial upload costs `Predicted_s` for the `BufferWrite` `param` row (two
buffers: `PredictedTwoBuffers_s`). It is paid between trials, on the MATLAB
thread the trial loop runs on, so compare it with the inter-trial interval and
with the trial-loop timer period.

One more cost decides the answer, and it is easy to miss. **At every trial end,
`ep_TimerFcn_RunTime` reads every visible, readable, non-trigger parameter**
(`RUNTIME.all_parameters(Access='Read')`, each through `hw.Parameter.get.Value`),
and stores the result in `DATA` and in the trial journal. On `hw.TDT_RPcox` that
read is a whole-tag `ReadTagVEX`. A stimulus held in a visible `Buffer` tag with
`Any` access (what `hw.TDT_RPcox` gives every tag it discovers) is therefore read
back in full every trial, whether or not it was rewritten. It is converted to
`double` and saved, so 292969 samples are about 2.3 MB per trial in memory and
in the file. The `BufferRead` fit predicts the time. Two things avoid it:

- an invisible tag (a `_` or `~` prefix in RPvds, or `Visible = false` in the
  designer), which the trial-end read leaves out;
- a `StimType` parameter, which `get.Value` always answers host-side.

Loaded once per session, the stimulus costs one `Predicted_s` at Run, plus
whatever scalars select or gate it per trial. Those scalars cost the
`ScalarWrite` median each.

---

## Recipes per backend

### TDT RPcox, and Synapse in legacy mode (one RPvds circuit)

A ready-made circuit and protocol are in
[`examples/hw_benchmark/`](../../examples/hw_benchmark/README.md)
(`HwBenchmark_TDT_RPcox.rcx` and `.eprot`). To build your own, or add these tags
to the experiment circuit:

| Tag | Suggested RPvds construction | Becomes |
|---|---|---|
| `WScalar` | a parameter tag on a writable constant (e.g. a `ConstF` value) | Float, Access `Any` |
| `RScalar` | a tag on a value that changes, e.g. a counter's output | read as a scalar |
| `!BenchTrig` | a tag on a logic input the circuit can pulse (`trigger` writes 1, waits 1 ms, writes 0, so the 1 ms `pause` is part of the trigger time) | `isTrigger = true` (the `!` prefix) |
| `Buf` | one data buffer (e.g. a serial buffer component) at least as long as the largest size you will test, tagged on its data, **that the circuit itself never writes into** (below) | `Type = 'Buffer'` (tag type 68) |

**The buffer must be host-only.** The benchmark writes `Buf` from MATLAB and
reads it back. If the circuit is also writing into it — a `SerialBuf` recording
its input, its index advancing every sample — then the DSP overwrites what the
host just wrote, the round trip fails with one contiguous run of mismatches (or
two touching both ends, where the index wrapped), and the write and read times
are of a buffer the DSP is using at the same moment. The required `SerialBuf`
configuration is:

- **not recording**: its write/record input off (`Write = 0`), or the component
  disabled so the index does not run; nothing the DSP produces may reach the
  buffer during the benchmark;
- **`Size`** at least the largest length you will test. Because
  `hw.TDT_RPcox` reads the whole tag, every read and every round-trip check
  then moves `Size` samples; size it no larger than you need;
- the `Buf` parameter tag on the buffer's data, as now.

The committed `examples/hw_benchmark/HwBenchmark_TDT_RPcox.rcx` was read with
`strings`, **not confirmed in RPvdsEx**: its `SerialBuf` is stored with
`Size=1e+06`, `AccEnab=1`, `Write=1`, `Rst=0`, with the `Buf` tag on `{>Data}`
and an input port wired. If that reading is right, the DSP writes into `Buf`
continuously. Open it in RPvdsEx, confirm, and if so change it as above (see
[examples/hw_benchmark/README.md](../../examples/hw_benchmark/README.md)); a
passing round trip at every size is the check that the change worked.

Notes:

- **Names map verbatim.** The `hw.Parameter` `Name` is the tag name, prefixes
  included. Do not start a contract tag with `_`, `~` or `#`: those make it
  invisible, and the by-name path is then not timed. `%` tags are never exposed
  at all, and `#` tags are unreachable over Synapse's HTTP path.
- **Capacity comes from the device.** Under `hw.TDT_RPcox`, `parameterCapacity`
  is `TDTRP`'s tag size, so the `N` in the name only needs to be honest for
  readability. Under `hw.TDT_Synapse` it is `getParameterSize`, asked once per
  connection.
- **Check buffer memory against the device before building.** One `Buf` of the
  largest length you will test (4096 for the default dialog sizes; 300000 to
  bracket a 3 s stimulus) is held on the processor in addition to whatever the
  experiment circuit already holds. Confirm it fits in the RPvdsEx compile report.
  `TargetSamples` is extrapolated (hollow pentagram, `ExtrapolationFactor`) when
  it lies outside the sizes tested. To interpolate a 3 s stimulus, include a
  size of at least 292969, e.g. `1024 4096 65536 300000`.
- **Do not hold the same processor in two interfaces.** A protocol must not have
  both an `hw.TDT_RPcox` and an `hw.TDT_Synapse` for one RZ6.
- **Synapse refuses parameter access at Idle.** Run it with Synapse in a runtime
  mode. A `RoundTrip` row that fails with NaN reads is the sign that it was not.

### Teensy (`hw.Teensy`)

The firmware publishes parameters by name, so the default contract needs
firmware-side variables named `WScalar` and `RScalar` (a counter, for example),
and a trigger `BenchTrig`. Two backend behaviours change what the scalar numbers
mean. They are reported here rather than worked around, because they are also
what a session pays:

- `CoalesceWrites` is true by default. `set_parameter` then only queues the
  write, and the serial transaction happens at the next `trigger` or read. The
  `ScalarWrite` time is the queueing cost, and the transport cost moves into
  `Trigger` and `ScalarRead`. Set `iface.CoalesceWrites = false` to time each
  write's own round trip.
- Reads are served from a `SNAP` snapshot refreshed at most every
  `SnapshotInterval` (5 ms). A `ScalarRead` loop faster than that times mostly
  cache hits.

There are **no buffers**. The `SETM` grammar carries space-delimited scalars and
the firmware has no waveform output, so `Buffers` is reported unsupported.

### Bpod (`hw.Bpod`)

Only fixed wire names reach the device:

- writes to `ValveN`, `PWMN`, `BNCOutN`, `WireOutN`, `SerialNByte` and soft codes;
- reads of `PortNIn`, `BNCInN` and `WireInN`, cached within `SnapshotInterval`.

A parameter called `WScalar` is kept host-side and logs "no device write" on
every call. So pass the roles explicitly. For example, use
`ScalarWrite="BNCOut1"` (not a valve, which would open a water line on every call) and
`ScalarRead="BNCIn1"`. Pass `Trigger=[]`: only `x_NewTrial_*` and `x_ResetTrig_*`
act, and they start and reset trials. Output writes are deferred while a state
matrix runs. There are no buffers.

### Which backends can take part in which roles

| Backend | ScalarWrite | ScalarRead | Trigger | Buffers |
|---|---|---|---|---|
| `hw.TDT_RPcox` | yes | yes | yes (`!` tag) | yes. Reads are whole-tag |
| `hw.TDT_Synapse` (legacy) | yes | yes | yes (`!` tag) | yes. Reads are sized by Synapse's count |
| `hw.Teensy` | yes (coalesced by default) | yes (snapshot cache) | yes | no |
| `hw.Bpod` | fixed output wires only | input wires only | no (do not benchmark trial start/reset) | no |
| `hw.Intan_RHX` | RHX parameters by their command names | yes | no: on a Stim/Record controller it delivers a manual stimulation pulse, and on a Recording controller it is ignored without a transaction | no |
| `hw.NE1000` | pump settings, never while dispensing | yes | no: `Start`/`Stop` move the syringe | no |
| `hw.VlcRecorder` | host-side strings only | host-side only | no: triggers launch and stop VLC | no |
| `hw.Software`, `hw.Replay` | the in-memory call only (simulated; see the floor) | `hw.Software` reads return `NaN` (values live in `hw.Parameter`). `hw.Replay` reads the record | the call only | `hw.Software` round trips fail by design, and are reported as a simulated interface's |

---

## Known limits

- **`tic`/`toc` resolution.** The cost of an empty `tic`/`toc` pair is recorded as
  `Environment.TicTocOverhead_s`. Treat medians within a few multiples of it as
  "below resolution". Timer jitter and the OS scheduler show in `P95_s` and
  `Max_s`, which is why the medians, not the means, are fitted.
- **Whole-tag reads.** `hw.TDT_RPcox` reads a buffer's whole tag
  (`TDTRP.read` with no size), so read time follows the tag's capacity, not what
  was written. `NTransferred` records the length actually returned, the read is
  timed once per path (see *Whole-tag reads* above), and the read fit uses that
  length. The round trip compares only the first `NWritten` samples of it.
- **What a buffer time does not tell you.** A per-sample cost far from a
  vendor's figure locates the cost below `hw.Interface` (in `TDTRP.write`, the
  RPcoX call, its argument marshalling, or the device), not which of those it
  is. The [raw-transport diagnostic](#raw-transport-diagnostic) times the RPcoX
  calls directly to narrow that down.
- **Lookup cost is a difference of two medians** taken at different moments.
  It is drawn only where a rank-sum test resolves it, and a negative one is
  reported as drift, never as a cost.
- **Logging.** RPcox and Synapse writes log at level 4, and the log takes
  everything by default. That cost is inside every write time. See *Running it*.
- **The runtime's wrappers are not included.** A session writes through
  `hw.Parameter.set.Value`, which adds randomization, `Expression`, clamping and
  the update callbacks. It reads through `get.Value`, which adds one
  `IsConnected` probe (a `GetStatus` COM call per module on `hw.TDT_RPcox`) and a
  `double` conversion. Those costs are EPsych's and are small next to a buffer
  transfer. They are not in these numbers.
- **4 bytes (32 bits) per sample** is assumed for `MBPerSec` and `MbitPerSec`,
  the TX/RX bit rates. They are payload rates, not line rates: protocol framing,
  a backend that sends text (Synapse's HTTP JSON), and the pause in a trigger all
  put more on the wire than that. `MSamplesPerSec` makes no assumption.
- **It writes to the device.** The last values written stay in the contract
  parameters, and the buffers hold random data. It shares the MATLAB thread with
  the trial loop. Never run it during a session.
- **Device mode is not changed.** Put the device in the mode it runs in. The
  utility records `Environment.Mode` and does not touch it.

---

## hw-layer hooks

All three hooks are concrete on `hw.Interface` with safe defaults, following the
`connectionRecoveryLabel`/`canRunOffline` pattern. No existing backend needed an
edit to keep working. See [hw_Interface.md](hw_Interface.md#parametercapacity--issimulated--transfercontext).

| Hook | Default | Overrides |
|---|---|---|
| `parameterCapacity(P)` | `NaN` | `hw.TDT_RPcox`: `TDTRP.PARTAG` tag size, with no COM call. `hw.TDT_Synapse`: its per-connection size cache |
| `isSimulated()` | `false` | `hw.Software`, `hw.Replay`: `true` |
| `transferContext()` | empty record array (`hw.Interface.transferContextRecord()`) | `hw.TDT_RPcox`: one record per module — device type, link (`GB`/`USB`), device number, sample rate, `GetCycUse` read live (falling back to the value read at circuit load), the `TDTRP.write`/`TDTRP.read` calls and `F32`. Offline it reports the module configuration and `NaN` cycle usage, with no COM call |

No registry site changes: the utility adds no backend, so
[hw_Interface_Tutorial.md](hw_Interface_Tutorial.md)'s four sites are untouched.

## Raw-transport diagnostic

`tmp/diag_rpcox_buffer_transfer.m` is the step below `hw.benchmarkIO`, kept
separate so the benchmark stays backend-agnostic. Given a **connected**
`hw.TDT_RPcox` and a buffer tag, it times the RPcoX calls directly at several
lengths up to the tag's capacity:

- `WriteTagVEX(tag, 0, 'F32', single)` — the current path (`TDTRP.write`);
- `WriteTagV` with `single` data, and with `double` data;
- `WriteTagVEX(tag, 0, 'I16', int16)`;
- `ReadTagVEX(..., 'F32', 'F32', 1)` and `ReadTagV`, each at every requested
  length and at the whole tag.

Every write is verified over its **full** length by an untimed read-back, and
every RPcoX return value is checked. It records `GetCycUse` (per measurement,
and at start and end), `GetSFreq`, `GetStatus`, the tag's type and size, the
device type, number and interface, then prints one table and saves it
(`.mat` and `.csv`).

```matlab
% at the rig, between sessions, on an interface that is already connected
T = diag_rpcox_buffer_transfer(iface, "Buf", Sizes=[1024 4096 65536 300000 1000000]);
```

It never connects, never loads a circuit, and leaves random data (including
int16 data the circuit will read as meaningless floats) in the tag; the next
Run reloads the circuit. The `I16` read-back convention is RPcoX's and is not
confirmed here, so a mismatch on that row alone may be the convention rather
than the write. Nothing in `TDTRP` changes on the strength of this script: if
its table shows a faster call that also verifies, that is a recommendation to
change `TDTRP.write`/`TDTRP.read`, to be made and reviewed separately. It is COM
work, so restart a persistent MATLAB session afterwards (CLAUDE.md).

## Standing proof

`tmp/smoke_test_hw_benchmark_io.m` runs headless, in memory, and opens no
window. It uses `hw.Software` and `tmp/BenchLoopbackInterface.m`, an
`hw.Software` that keeps what it is written and can be told to read back a
whole tag (`ReadWhole`), clobber a run of samples as a circuit writing into the
buffer would (`ClobberRun`), and delay calls by path (`NameDelay`,
`HandleDelay`, `AlternateDelay`) so each lookup-cost status is reproduced
deterministically. The offline hook checks also use an `hw.TDT_RPcox` and an
`hw.TDT_Synapse` constructed with `Connect=false`, and `hw.TDT_Synapse` over
`tmp/SynapseAPI_Mock`. `tmp/smoke_test_hw_benchmark_runexpt.m` covers the
RunExpt menu item, including the status line for a failed round trip.

What only a rig can confirm: the `SerialBuf` reading of the committed circuit,
`transferContext`'s live branch (`GetCycUse` on a connected device), and
everything `tmp/diag_rpcox_buffer_transfer.m` measures.

```matlab
matlab -batch "run('tmp/smoke_test_hw_benchmark_io.m')"
```
