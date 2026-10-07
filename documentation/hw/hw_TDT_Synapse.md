# hw.TDT_Synapse

**Status: under development.** The backend has been validated against an
in-process simulation of the Synapse API (see *Standing proof* below), and
its discovery path against a live Synapse holding an RZ6 in legacy mode
(read-only queries, 2026-10-07). It has not yet run a session. The section
*Confirmed on the rig, and still to confirm* says which is which.

The conventions are `hw.TDT_RPcox`'s throughout: the same `.rcx` discovered
through either backend yields the same parameters, the same hidden ones,
and the same triggers.

`hw.TDT_Synapse` connects EPsych to TDT Synapse through the SynapseAPI HTTP
client in `TDTfun/SynapseAPI/`. It implements the `hw.Interface` contract:
modules and parameters, mode control, parameter reads and writes, stimulus
writes, and triggers.

Source: [obj/+hw/@TDT_Synapse/](../../obj/+hw/@TDT_Synapse/)

## What a module is

A module is **one Synapse object that answers `getParameterNames`**. That is
usually a gizmo (`PulseGen1`, `Sort1`) with API access enabled on some of its
parameters. The Synapse name, spelled exactly as Synapse shows it, is what
every read, write and trigger is addressed to
(`setParameterValue(name, tag, value)`). A protocol-authored module carries
it in its `Label`, as an RPcox module carries its device type there, or in
its `Name`, which `hw.Module` documents as the hardware-specific field;
whichever of the two Synapse recognizes is used, `Label` first, and is
recorded on the module as `Info.SynapseName` at connect and at Read HW
Params. The other field is free for a display name such as `Behavior`.
`Index` is the module's position.

### Legacy mode

Synapse can run a processor in **legacy mode**: in the Rig Editor the
processor is switched to Legacy and given an RPvdsEx circuit file, which
Synapse loads onto the device whole. The RP2.1, RA16 and RX7 run only this
way; an RZ can be switched to it. This is how a circuit written for OpenEx
or for `hw.TDT_RPcox` runs under Synapse without being rebuilt as gizmos.

Through the API a legacy processor looks like this, and the backend is
built around it:

| Fact | Consequence |
|------|-------------|
| The processor is listed by `getGizmoNames` under its own name, `RZ6(1)`, with `getGizmoInfo` category `Legacy`. | The module's `Label` or `Name` is the processor name with its instance number, `RZ6(1)`. A module with neither (`RZ6`) is refused at connect with the names Synapse does have. |
| Its parameters are the circuit's parameter tags, verbatim. | EPsych's tag conventions apply as on `hw.TDT_RPcox`: `!` is a trigger, `_`/`~` hide a parameter. |
| `getGizmoParent` answers nothing for it: it has no parent, it **is** the processor. | Its sample rate is read from `getSamplingRates` under its own cleaned name (`RZ6_1`), where an ordinary gizmo's is read under its parent's. |
| `getParameterInfo` reports `Type` as `Float`, `Int` or `Logic`, and `Array` as a word at design time but as the element count once Synapse is running. | `hw.TDT_Synapse.parameterSpecFromInfo` translates; see the table below. |
| While Synapse is **Idle**, every tag of a legacy circuit is reported as `Float`, access `Read / Write`, bounds ±1e20, `Array` `No`, the FIR coefficient buffer included (observed on the rig). | A design-time read (ProtocolDesigner's Read HW Params) cannot tell a buffer from a scalar, or a logical from a float. The author sets those types, as for an RPcox protocol; connect reports any buffer still typed as a scalar. |
| Some tags are listed but not described (`getParameterInfo` answers nothing, or the client cannot parse the reply). The lab's earlier integration met this on triggers inside circuit macros. | The parameter is still created, as `Undefined` with no bounds, the way RPcox creates a tag of a type it does not know, rather than dropped. A trigger that is not there cannot fire. |
| The circuit's tags are named for the runtime: `x_NewTrial_1`, `x_ResetTrig_1`, `x_TrialComplete_1`, `_RespCode_1`. | They are ordinary parameters to discovery, as they are to RPcox. `x_NewTrial_<box>` and `x_ResetTrig_<box>` are marked as triggers in ProtocolDesigner, exactly as for an RPcox protocol over the same circuit; a `!`-prefixed tag is a trigger from discovery on either backend. |
| Moving Synapse to Idle unloads the circuit; the next runtime mode reloads it. | No `resetSession` is needed. `ep_TimerFcn_Stop` writes Idle, so DSP counters start from zero on every Run, which is what `hw.TDT_RPcox` has to reload its circuits to get. |

`Info.Legacy` on the module records the category, and `isLegacyModule`
reads it.

## Connecting

`connect` opens the client, brings Synapse to **Standby**, and binds the
modules. Standby is the lowest mode in which Synapse answers parameter
reads and writes, and the one in which a legacy circuit is loaded, so it is
where a connected interface waits between runs. A server found above
Standby is taken through Idle first, so every circuit reloads and the
session starts from a known device state. If Synapse will not enter Standby
the connect fails with `hw:TDT_Synapse:ModeRejected` and names the fix:
Standby Mode must be enabled under Synapse's Menu > Preferences.

Modules are **bound, never rebuilt**:

- An interface that already holds modules (a protocol loaded from an
  `.eprot`, or authored in ProtocolDesigner) keeps them. Each is placed by
  its `Label` or `Name` against `getGizmoNames`
  (`hw:TDT_Synapse:UnknownGizmo` when neither matches);
  category, parent processor and sample rate are refreshed from the server;
  and parameters are populated **only on a module that has none**. A
  populated module's parameters, with their `Values` and trial options,
  are left exactly as the protocol had them. Two things are reported once,
  in one log line each, rather than as a failed write per trial: tags the
  loaded circuit lacks, and tags that are arrays on the device but scalars
  in the protocol. The second is the legacy-mode trap: Synapse at Idle
  calls every legacy tag a scalar Float, so a protocol built from Read HW
  Params has its stimulus and coefficient buffers typed as scalars until
  the author sets them, and connect, in Standby, is the first moment
  anything can see the sizes.
- Only an interface with no modules at all discovers them: one module per
  object with API parameters, in listing order. A processor in its normal
  mode usually has none (its gizmos hold them) and is passed over.

A failed connect releases the client and returns Synapse to Idle, so
nothing is left half-connected. `disconnect` returns Synapse to Idle too.

## Parameter translation

`hw.TDT_Synapse.parameterSpecFromInfo(name, info)` is the one place the
Synapse vocabulary becomes `hw.Parameter` metadata. It is a pure static
function, so the whole mapping is testable with a struct.

| Synapse (`getParameterInfo`) | `hw.Parameter` |
|------|------|
| `Type` `Float` | `Type` `Float` |
| `Type` `Int` | `Type` `Integer` |
| `Type` `Logic` | `Type` `Boolean` |
| `Array` `Yes` (design time) or a count > 1 (runtime) | `Type` `Buffer`, `isArray` true |
| `Array` `No` or 1 | scalar |
| `Access` `Read / Write` (what the rig reports; any wording naming both) | `Access` `Any` |
| `Access` `Read`, or `Write` | `Read` or `Write` |
| `Access` blank or unrecognized | `Any`, with a debug log line |
| `Min`/`Max` NaN or blank (a read-only parameter) | `-Inf`/`Inf` |
| `Min`/`Max` of magnitude 1e20 or more (every legacy tag) | `-Inf`/`Inf`: the circuit declares no bounds, and ±1e20 as a control's limits is noise |
| Any other `Type` | `Undefined`, with a debug log line |
| No description at all | `Undefined`, `Access` `Any`, no bounds |

Name conventions are RPcox's: a leading `!` is a trigger, a leading `_`,
`~` or `#` hides the parameter. Nothing else about a name is interpreted.

The raw record is kept on the parameter as `UserData.SynapseInfo`, so what
Synapse actually said is in the protocol file when a mapping looks wrong.

The manual does not list the `Access` values, which is why they are matched
on their words rather than exactly; `Read / Write` and `Read` are what the
rig reports.

### Tags that are not exposed

`hw.TDT_Synapse.filterParameterNames` drops, with a reason logged at
verbosity 3:

- `%`-prefixed tags, which are RPvds-internal (dropped on `hw.TDT_RPcox`
  too);
- names containing `/`, `\` or `|`, or `rPvDsHElpEr`, which belong to RPvds
  helper objects and error strings leaking through the legacy HAL (the
  filter `ReadRPvdsTags` has applied since 2014);
- names containing `#`, `%`, `?` or whitespace, which cannot travel in the
  URL path the client builds (`/params/RZ6(1).#Tag` ends at the `#`). A
  `#`-prefixed tag is a hidden-parameter convention on `hw.TDT_RPcox`; over
  Synapse it is out of reach, and a circuit meant for both backends should
  spell hidden tags with `~`.

## Reads, writes, stimuli and triggers

- **Scalar** parameters go through `setParameterValue`/`getParameterValue`;
  a logical is written as 0/1.
- **Array** parameters (`isArray`, or `Type` `Buffer`/`Coefficient Buffer`)
  go through `setParameterValues`/`getParameterValues`. An array arrives
  from `hw.Parameter.set.Value` wrapped in a scalar cell; a bare array
  handed to a single parameter means the same thing.
- A **stimulus** (`Type` `StimType`) is written into the circuit's buffer
  tag as a waveform: `hw.Interface.stimulusPayload` regenerates it at the
  module's `Fs` (which connect read from the server), and
  `setParameterValues` carries the samples. The write is bounded by the
  tag: `getParameterSize` is asked once per connection, and a stimulus
  longer than the buffer is refused and reported rather than truncated.
  This is the counterpart of `hw.TDT_RPcox.writeStimulus_`, so the same
  `.rcx` plays the same sound under either backend.
- An **empty** value writes nothing and reports success (a `StimType`
  legitimately sits empty until a stimulus is chosen); a **text** value is
  logged and kept host-side, since Synapse parameters are numbers.
- An array read always **states its count** (`getParameterValues(gizmo,
  tag, n)`, `n` from `getParameterSize` once per connection). The client's
  own size cache is a struct keyed `Gizmo_Param`, and `RZ6(2)_Stim` is not
  a field name, so a count the client has to look up itself throws
  `Invalid field name` for every legacy processor. A scalar tag a protocol
  marks `isArray` is read as the scalar the device says it is.
- A read Synapse refuses (it answers `''` outside a runtime mode) is
  returned as NaN, and so is a read that throws, logged; one tag Synapse
  will not answer for must not end the session, since every readable
  parameter is read at every trial completion.
- A **trigger** is a 1 then 0 on the tag, 1 ms apart. If the rising edge is
  refused the trial loop hears `hw:TDT_Synapse:TriggerFailed`; a falling
  edge that fails is logged, since the edge did fire. `trigger` returns a
  datenum, which is what `hw.Parameter.lastUpdated` stores.

Every parameter call is one HTTP round trip. Reading a 100 000-sample
buffer at trial completion, as `ep_TimerFcn_RunTime` does for every readable
parameter, costs a JSON transfer of that size per trial; mark a large
read-only buffer invisible if a session does not need it in the data file.

## Modes

`mode` writes map `hw.DeviceState` onto Synapse's four modes: Idle,
Standby, Preview and Record pass through; `Stop` and `Error` land in Idle;
`Pause` lands in Standby (the circuit stays loaded, out of the record).
A mode change loads or unloads every device in the rig and takes seconds
(5.5 s from Idle to Preview with the lab's RZ6 and camera), and the HTTP
request can time out server-side (503 `Could not process request in time`)
while the change carries on, so the request's return is not the answer:
the backend **polls** for the target mode, every 0.25 s up to
`ModeTimeout` (20 s by default, settable), and only then reports
`hw:TDT_Synapse:ModeRejected`, naming the mode Synapse is in. Reading
`mode` asks the server. `ExperimentInfo.block` is read on entering Preview
or Record, since a block exists only from then on.

The session's own mode writes work out as: connect leaves Synapse in
Standby; Run writes Preview or Record; Stop writes Idle, unloading the
circuit; the next Run reloads it. Parameter writes before the Run's mode
write (the first dispatch happens from the timer's `StartFcn`, after it)
are not an issue; a write made while Synapse is Idle fails and is logged.

## In ProtocolDesigner

1. Add a `TDT Synapse` interface with the server name.
2. Add a module whose **Label** (or **Name**) is the Synapse name: `RZ6(1)`
   for a processor in legacy mode, the gizmo name otherwise. The other
   field can be a display name.
3. **Read HW Params** fills the module from the server without connecting
   and without touching Synapse's mode. It also records whether the module
   is a legacy processor and its sample rate. A module Synapse recognizes
   by neither field is declined with the names it does.
   Do not also give the protocol a `TDT_RPcox` interface for the same
   processor: RPcox loads the circuit over RPco.x at connect, while in
   legacy mode Synapse owns the processor and loads the circuit itself.
4. Finish the parameters as for an RPcox protocol over the same circuit:
   mark `x_NewTrial_<box>` and `x_ResetTrig_<box>` as triggers, set a
   buffer tag that will carry a stimulus to `Type` `StimType` and choose
   the stimulus as its value, set coefficient buffers to `Coefficient
   Buffer`, and set logicals to `Boolean`. Synapse at Idle reports none of
   this.

**Phase files saved under RPcox load unchanged.** A phase records each
parameter's owning interface type, and the loader
(`epsych.Runtime.readParameters`) treats `TDT_RPcox` and `TDT_Synapse` as
interchangeable when the session holds no interface of the recorded type
(`epsych.Runtime.INTERCHANGEABLE_PARENT_TYPES`): the same circuit's tags are
the same parameters. One log line per load says how many entries crossed. A
phase saved from a Synapse session records `TDT_Synapse` and loads into an
RPcox session the same way.

**Converting an RPcox protocol.** The designer's copy/move tool can carry
a configured RPcox module's parameters onto the Synapse module, but while
the RPcox module still exists every copy is renamed `Name_1` (names must
be unique across the protocol to compile). The copy still writes the right
tag, but the compiled trial table, the paradigm's trial selector and the
runtime's `x_NewTrial_<box>` lookup all go by Name, so the session fails
at start with an unresolved `TrialType`. Either delete the RPcox interface
first and then move, or run `tmp/fix_synapse_parameter_names.m` on the
saved protocol afterwards; it strips the suffixes, rewrites expressions,
recompiles and saves with the previous version archived.

`readHardwareParameters` opens a temporary client when the interface is
offline and releases it afterwards.

## Confirmed on the rig, and still to confirm

Read-only queries against the lab's Synapse (Idle, an RZ6 in legacy mode
beside a camera and a fiber-photometry gizmo, 2026-10-07) confirmed:

- the legacy processor is listed as `RZ6(2)`, type `LegacyHal`, category
  `Legacy`, with no parent, and `getGizmoNames(true)` includes it;
- `getSamplingRates` files it as `RZ6_2` (and carries `x_return_code`
  fields, which the lookup ignores);
- `getParameterNames` and `getParameterInfo` answer while Idle, so Read HW
  Params works without entering Standby;
- `Access` is `Read / Write` or `Read`; modern gizmos report `Logic`, `Int`,
  units and real bounds;
- at Idle every legacy tag is `Float`, `Read / Write`, ±1e20, `Array` `No`,
  so a design-time read types nothing; the circuit's helper tags (`sRCod/`,
  `%rPvDsHElpEr77638`, ...) leak through and are filtered.

The first Run (Preview, same rig) confirmed:

- the client's `getParameterValues` throws `Invalid field name:
  'RZ6(2)_TrialType'` whenever it has to look the count up itself, so every
  read now carries its count;
- `getGizmoParent` on the legacy processor and `getCurrentBlock` in Standby
  are 404s, which the client reports as warnings with a stack; neither is
  asked any more;
- Synapse answered the Stop's Idle request with 503 while still leaving
  Preview, so modes are polled for.

Still only a live session can settle, each isolated so a correction is one
line:

1. **What Synapse reports for a legacy tag once it is running.** The manual
   says the element count for arrays; whether it also reports `Int`/`Logic`
   then is unknown. The connect-time drift report is where the answer will
   show.
2. **Whether a `#` tag can be reached by percent-encoding it.** The client
   sends names verbatim; if Synapse decodes `%23`, `filterParameterNames`
   can stop dropping `#` names and the client encode them.
3. **The cost of `setParameterValues` for a stimulus-sized buffer.** The
   write is JSON over HTTP; the trial loop will show whether a 100 000
   sample stimulus per trial is acceptable, or whether the stimulus must be
   written once (`SetOnce`) and selected by a scalar.

## Standing proof

`tmp/smoke_test_synapse_legacy.m` drives the real backend through
`tmp/TDT_Synapse_Mock`, which swaps `tmp/SynapseAPI_Mock` in at the one
seam where a client is constructed (`createApi_`/`releaseApi_`). The mock
answers with the shapes the manual documents and the earlier integration
observed. Ten groups: the translation, the name filter, discovery of a
legacy processor beside ordinary gizmos, a protocol-authored module
surviving connect, scalar and array I/O, a stimulus landing in the buffer
tag at the device rate, triggers, mode mapping and a refused Standby, Read
HW Params at design time, and the disconnect/reconnect/round-trip.

```matlab
matlab -batch "run('tmp/smoke_test_synapse_legacy.m')"
```

## See also

- [hw_Interface.md](hw_Interface.md), the contract
- [hw_Interface_Tutorial.md](hw_Interface_Tutorial.md), the discovery pattern
- [hw_Parameter.md](hw_Parameter.md), the types and access values
- `TDTfun/SynapseAPI/SynapseAPI.m`, the client, and TDT's
  [SynapseAPI manual](https://www.tdt.com/docs/sdk/synapse-api/overview/)
