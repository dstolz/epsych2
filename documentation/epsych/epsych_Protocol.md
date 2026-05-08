# epsych.Protocol

`epsych.Protocol` is the model object used by EPsych to define interfaces, parameters, compile trial tables, and serialize protocol files.

Source class:

- `obj/+epsych/@Protocol/Protocol.m`

## What This Class Owns

- `Interfaces`: ordered `hw.Interface` objects included in the protocol.
- `Options`: protocol-level options (`trialFunc`, `compileAtRuntime`, `IncludeWAVBuffers`, `ConnectionType`).
- `Info`: user description text.
- `COMPILED`: compiled output (`parameters`, `trials`, `writeparams`, `OPTIONS`, `ntrials`, `compiledAt`).
- `meta`: serialization metadata and protocol versioning fields.

A new protocol always starts with one `hw.Software` interface as the default design-time parameter store.

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

- `save` writes `.eprot` (and JSON pathways are supported by dedicated methods).
- `load` and `fromStruct` restore class state.
- During `fromStruct`, non-serializable `hw.Parameter` handles are rebuilt from active interfaces using `resolveCompiledParameters_`.

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
- Serialization: `save`, `load`, `toStruct`, `fromStruct`, `toJSON`, `fromJSON`

## Usage Example

```matlab
P = epsych.Protocol(Name='MyProtocol', Info='Example protocol');

P.addParameter('Software', 'ToneFreq', [1000 2000 4000], ...
    Type='Float', Unit='Hz', Access='Any');

P.setOption('trialFunc', 'cl_TrialSelection_Appetitive_StimDetect');
P.compile();
P.save('MyProtocol.eprot');
```

## Integration Notes

- `epsych.ProtocolDesigner` directly mutates a bound `epsych.Protocol` instance.
- `epsych.Runtime` consumes compiled protocol output during experiment execution.
- Interface classes must be `hw.Interface` subclasses and are serialized through protocol helper methods.

## Related Documentation

- `documentation/design/ProtocolDesigner.md`
- `documentation/epsych/epsych_Runtime.md`
- `documentation/overviews/Architecture_Overview.md`
