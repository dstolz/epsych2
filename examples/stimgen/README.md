# stimgen example assets

These files stayed in epsych2 when `stimgen` moved to its own repository: the
`.rcx` circuits are TDT-specific and the `.prot` files deserialize into
`epsych.Protocol` objects, so neither is usable from a standalone `stimgen`.
The `stimgen` documentation refers to them from
[`stimgen_TDT_RPvds.md`](../../obj/stimgen/documentation/stimgen_TDT_RPvds.md),
but they ship only from here.

| File | Purpose |
|---|---|
| `StimGenCircuit.rcx` | RPvds circuit for hardware-triggered stimulus playback via `stimgen.StimPlayer` |
| `StimGenCalibration.rcx` | RPvds circuit for play-and-record speaker calibration via `stimbridge.InterfaceAdapter` |
| `StimGen.prot` | Demo protocol for the playback circuit |
| `StimGenCal.prot` | Demo protocol for the calibration circuit |

## Parameter contracts

The two circuits expose different tag sets, because playback and calibration go
through different seams.

**`StimGenCircuit.rcx` — `stimgen.StimPlayer`.** Resolved through
`stimgen.HardwareHost.findParameter` at Run time. If any is missing, StimPlayer
disables hardware playback and falls back to speaker preview rather than
erroring:

- `BufferData_0`, `BufferData_1` — audio data buffers (double-buffered)
- `BufferSize_0`, `BufferSize_1` — buffer length in samples
- `x_Trigger_0`, `x_Trigger_1` — playback trigger pulses

**`StimGenCalibration.rcx` — `stimbridge.InterfaceAdapter`.** Resolved and cached
at construction; a missing tag raises
`stimbridge:InterfaceAdapter:missingParameter` immediately:

- `BufferSize` — Integer, Write — samples to play/record
- `BufferOut` — Buffer, Write — output waveform
- `!Trigger` or `x_Trigger` — Boolean, Write — start pulse (first match wins)
- `BufferIndex` — Integer, Read — acquisition progress counter
- `BufferIn` — Buffer, Read — recorded microphone signal

The sample rate is discovered from the first `hw.Module` reporting `Fs > 0`, or
supplied explicitly as `stimbridge.InterfaceAdapter(iface, Fs=97656.25)`.

## Related

- [documentation/stimgen.md](../../documentation/stimgen.md) — submodule contract and the `stimbridge` seam
- [tmp/run_tdt_calibration.m](../../tmp/run_tdt_calibration.m) — drives `StimGenCalibration.rcx` end to end
