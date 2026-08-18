# epsych.Protocol

`epsych.Protocol` is the model object used by EPsych to define interfaces, parameters, compile trial tables, and serialize protocol (`.eprot`) files. This is a developer reference; experiment designers normally work with protocols through the [Protocol Designer](../design/ProtocolDesigner_UserGuide.md).

Source class:

- [obj/+epsych/@Protocol/Protocol.m](../../obj/+epsych/@Protocol/Protocol.m)

## What This Class Owns

- `Interfaces`: ordered `hw.Interface` objects included in the protocol.
- `Options`: protocol-level options (`trialFunc`, `compileAtRuntime`, `IncludeWAVBuffers`, `ConnectionType`).
- `Info`: user description text.
- `COMPILED`: compiled output (`parameters`, `trials`, `writeparams`, `OPTIONS`, `ntrials`, `compiledAt`).
- `meta`: serialization metadata, including `protocolVersion` (`vN.YYMMDD`), which is incremented on each save unless the protocol is unmodified (see `save`'s `IncrementVersion` option). `epsych.RunExpt` compares this version against the file on disk to flag out-of-date subjects, and [`epsych.SubjectRoster`](epsych_SubjectRoster.md#protocol-versions) records it per subject so it can notice a protocol edited between sessions. Both go through the statics `epsych.Protocol.versionOnDisk(file)` — a peek at the one metadata field, not a `load` of the whole object graph — and `epsych.Protocol.versionNumber(str)`, which returns the comparable integer `N` or `NaN`, so an unknown version is never reported as outdated.

A new protocol always starts with one `hw.Software` interface as the default design-time parameter store. Design-time trial levels live on each parameter's `Values` property; `compile()` expands unpaired parameter levels as a cross-product, while parameters sharing a `Pair` name advance together.

## Core Workflows

### 1) Build protocol structure

- Add interfaces with `addInterface`.
- Add/remove interface parameters with `addParameter` and `removeParameter`.
- Update run options with `setOption`.

### 2) Validate and compile

- `validate` returns report entries (warnings and errors).
- `compile` blocks when validation contains severity-2 errors.
- Successful compile writes to `COMPILED`.

### 3) Save/load

- `save` writes `.eprot` (and JSON pathways are supported by dedicated methods). Every `.eprot` write is atomic (same-directory temp + rename) and goes through `epsych.Protocol.writeProtocolFile`, the low-level chokepoint shared with `Runtime.writeParametersProtocol` phase saves.
- `load` and `fromStruct` restore class state.
- During `fromStruct`, non-serializable `hw.Parameter` handles are rebuilt from active interfaces using `resolveCompiledParameters_`.

### 4) Version history

Saving an `.eprot` no longer discards what it overwrites: whenever the incoming
content carries a different `protocolVersion` than the file, the file's current
protocol struct is archived **inside the same `.eprot`** before being replaced.
The file holds four MAT variables:

| Variable | Content |
|---|---|
| `protocol` | the current version, in the unchanged `toStruct` layout (`formatVersion` stays 1.0, so phase fast-parse and every legacy reader are unaffected) |
| `history` | full superseded protocol structs, newest first (`Version`, `SavedAt`, `Origin`, `Protocol`) |
| `historyIndex` | `Version`/`SavedAt`/`Origin` only, so listing versions never decompresses the payloads |
| `historyFormat` | container format version (`1`) |

Rules that fall out of the design:

- **Within one file, a version string identifies content.** A same-version
  write — `save(..., IncrementVersion=false)`, or a phase save — replaces
  content without an archive entry, exactly as before.
- **History belongs to the file, not the object.** The in-memory Protocol is
  history-agnostic; `Save As` to a new path starts a fresh archive, and the
  original file keeps its own.
- **Version minting reconciles with the disk**: `save` mints past
  `max(in-memory N, on-disk N)`, so a stale object saved over a file that has
  moved on cannot coin a version the file already holds.
- **Retention is keep-all.** A heavily saved file grows without bound (a
  warning is logged past ~200 MB); protocols embedding WAV buffers are the
  case to watch. JSON files keep no history.
- Reading is unaffected and stays cheap: `load`, `versionOnDisk`, and the
  phase fast parse selectively load only the `protocol` variable.

The static API over the archive:

- `listVersions(file)` — current version plus the archive, payloads untouched.
- `hasVersion(file, v)` — true when the file's content or archive holds `v`; never throws.
- `loadVersion(file, v)` — one version (current or archived) as a live Protocol.
- `restoreVersion(file, v, Mode='newversion'|'exact')` — rewrite the file back
  to an archived version. `'newversion'` (default) brings the archived content
  back as a freshly minted version, git-revert style, so the counter stays
  monotonic and out-of-date checks keep working; `'exact'` rewinds the file to
  `v` verbatim (what a roster revert needs — see
  [`epsych.SubjectRoster.revertProtocol`](epsych_SubjectRoster.md#protocol-versions)),
  at the cost of the counter going backward for anyone recorded on a newer
  version. Either way the replaced content is archived first, so a restore is
  itself undoable, and the phase cache entry for the path is dropped.

In the Protocol Designer, `File > Version History...` lists a file's versions,
opens one as an unsaved working copy, or restores one. Standing proof:
`tmp/smoke_test_protocol_versioning.m`.

## Recent Behavior To Know

### Compiled parameter-handle reconstruction

`fromStruct` now restores `COMPILED.parameters` when missing by resolving names in `COMPILED.writeparams` against writable interface parameters.

Implementation files:

- `obj/+epsych/@Protocol/fromStruct.m`
- `obj/+epsych/@Protocol/resolveCompiledParameters_.m`

### Interface management APIs

The protocol supports explicit interface lifecycle operations:

- `addInterface`
- `replaceInterface`
- `removeInterface`
- `findInterface`

These methods are the foundation used by `epsych.ProtocolDesigner`.

### Parameter normalization and type inference

Compile and serialization helpers normalize parameter values and infer serialized types so protocols can round-trip through file formats with fewer ambiguities.

## Public API Quick Reference

- Construction: `Protocol(Name=..., Info=...)`
- Interfaces: `addInterface`, `removeInterface`, `replaceInterface`, `findInterface`
- Parameters: `addParameter`, `removeParameter`
- Options: `setOption`
- Compile/validate: `compile`, `validate`, `needsCompile`, `estimateDuration`
- Expressions: `analyzeExpressions`, `dryRunExpressions`, `dependencyGraph`
- Serialization: `save`, `load`, `toStruct`, `fromStruct`, `toJSON`, `fromJSON`
- Versions (static): `versionOnDisk(file)`, `versionNumber('vN.YYMMDD')`
- Version history (static): `listVersions(file)`, `hasVersion(file, v)`, `loadVersion(file, v)`, `restoreVersion(file, v, Mode=...)`; low-level writer `writeProtocolFile` (Hidden)

## Usage Example

```matlab
P = epsych.Protocol(Name='MyProtocol', Info='Example protocol');

P.addParameter('Software', 'ToneFreq', [1000 2000 4000], ...
    Type='Float', Unit='Hz', Access='Any');

P.setOption('trialFunc', 'cl_AppetitiveStimDetect');  % epsych.TrialSelector subclass
P.compile();
P.save('MyProtocol.eprot');
```

## Integration Notes

- `epsych.ProtocolDesigner` directly mutates a bound `epsych.Protocol` instance.
- `epsych.Runtime` borrows `Interfaces` and consumes `COMPILED` output during experiment execution.
- `Options.trialFunc` names an `epsych.TrialSelector` subclass; empty means `epsych.DefaultTrialSelector` (see [epsych_TrialSelector.md](epsych_TrialSelector.md)).
- Interface classes must be `hw.Interface` subclasses and are serialized through protocol helper methods.

## Related Documentation

- [../design/ProtocolDesigner.md](../design/ProtocolDesigner.md) — the designer GUI (developer reference)
- [epsych_Runtime.md](epsych_Runtime.md) — how compiled protocols are executed
- [epsych_TrialSelector.md](epsych_TrialSelector.md) — pluggable trial selection
- [../overviews/Architecture_Overview.md](../overviews/Architecture_Overview.md)
