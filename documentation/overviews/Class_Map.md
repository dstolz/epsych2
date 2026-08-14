# EPsych Class Map

This document complements the architecture overview with two class-oriented views of the toolbox:

- a strict inheritance map for the major classes
- a runtime dependency map showing how the major classes interact during a running session

The emphasis is on the classes developers are most likely to touch when changing experiment startup, runtime behavior, hardware integration, online analysis, or live GUIs.

## Inheritance map

This view shows inheritance only. To keep the tree readable, detailed MATLAB base types are moved into the summary tables below.

### Core runtime and hardware

```text
EPsych major classes
├─ epsych
│  ├─ Protocol
│  ├─ ProtocolDesigner
│  ├─ RunExpt
│  ├─ Runtime
│  ├─ Helper
│  ├─ TrialSelector
│  │  └─ DefaultTrialSelector
│  ├─ Subject
│  │  └─ DefaultSubject
│  ├─ BitMask
│  ├─ TrialJournal
│  ├─ eventModeChange
│  └─ TrialsData
├─ hw
│  ├─ Interface
│  │  ├─ TDT_Synapse
│  │  ├─ TDT_RPcox
│  │  ├─ Intan_RHX
│  │  ├─ VlcRecorder
│  │  └─ Software
│  ├─ Module
│  ├─ Parameter
│  ├─ DeviceState
│  ├─ InterfaceSpec
│  └─ InterfaceSpecOption
└─ top-level
   └─ PRGMSTATE
```

### Analysis, stimuli, and GUI

```text
Analysis and GUI classes
├─ psychophysics
│  ├─ Psych
│  │  ├─ Staircase
│  │  ├─ BestPEST
│  │  └─ MLP
│  ├─ Detect
│  └─ Detection
├─ stimgen                      (submodule; concrete stimuli vary by pinned commit)
│  ├─ StimType
│  │  └─ ...                    see obj/stimgen/documentation/stimgen_StimTypes.md
│  ├─ HardwareHost              ← implemented by stimbridge.RuntimeHost
│  ├─ StimCalibration
│  ├─ StimPlay
│  ├─ StimPlayer
│  ├─ StimInspector
│  └─ calibration
│     ├─ HwAdapter              ← implemented by stimbridge.InterfaceAdapter
│     │  └─ WindowsSoundCardAdapter
│     ├─ Engine
│     └─ CalibrationGui
├─ stimbridge
│  ├─ RuntimeHost
│  └─ InterfaceAdapter
└─ gui
   ├─ BasicGUI
   ├─ Helper
   │  └─ Triggers
   ├─ Parameter_Control
   ├─ Parameter_Monitor
   ├─ Parameter_Update
   ├─ ParameterDebugger
   ├─ ElapsedTrialTimer
   ├─ GenericTimer
   ├─ MicrophonePlot
   ├─ FilenameValidator
   ├─ ModeIndicator
   ├─ History
   ├─ OnlinePlot
   ├─ Performance
   ├─ PhaseSelector
   ├─ PsychPlot
   ├─ SlidingWindowPerformancePlot
   ├─ StaircaseTraining
   └─ StatusBar
```

### Support and legacy branches

```text
Support and task-specific classes
├─ peripherals
│  ├─ PumpCom
│  ├─ NanoMotorControl
│  └─ NanoMotorControlGUI
├─ util
│  └─ VideoConverter → gui.VideoConverterSetup
├─ eplog
│  ├─ Logger
│  ├─ Level (int32 enumeration)
│  └─ sink.Sink
│     ├─ sink.Console
│     └─ sink.FileSink
│        ├─ sink.TextFile
│        └─ sink.JsonLines
├─ helpers
│  ├─ EPsychInfo
├─ cl
│  ├─ cl_AppetitiveDetection_GUI_B
│  └─ cl_AppetitiveStimDetect
└─ runtime/guis
   └─ ep_GenericGUI
```

### Key base classes

| Area | Root class | Base type | Role |
| --- | --- | --- | --- |
| epsych | `RunExpt` | `handle` | Main session controller GUI |
| epsych | `Runtime` | `handle & dynamicprops` | Shared runtime state container |
| epsych | `TrialSelector` | `handle` | Abstract pluggable trial-selection API |
| hw | `Interface` | `matlab.mixin.Heterogeneous & matlab.mixin.SetGet` | Abstract hardware API |
| hw | `Module` | `handle` | Container for grouped parameters |
| hw | `Parameter` | `matlab.mixin.SetGet` | Runtime parameter wrapper |
| psychophysics | `Psych` | `handle & matlab.mixin.SetGet` | Abstract analysis base |
| stimgen | `StimType` | `handle & matlab.mixin.Heterogeneous & matlab.mixin.Copyable & matlab.mixin.SetGet` | Abstract stimulus base |
| stimgen | `HardwareHost` | `handle` | Abstract contract a host implements to give stimgen GUIs hardware access |
| stimgen | `calibration.HwAdapter` | `handle` | Abstract play/record contract for the calibration engine |
| gui | `Helper` | `handle` | Shared GUI helper base |
| eplog | `sink.Sink` | `handle` | Abstract log destination behind `vprintf` |

The `stimgen` package is a git submodule (see [../stimgen.md](../stimgen.md)) and
has no dependency on EPsych. EPsych implements its two abstract classes in
`obj/+stimbridge/`: `stimbridge.RuntimeHost` (a `stimgen.HardwareHost`) and
`stimbridge.InterfaceAdapter` (a `stimgen.calibration.HwAdapter`).

## Runtime dependency map

This view is not inheritance. It shows the main runtime relationships during a typical session. The Mermaid diagram gives the fast overview, and the short tree below keeps the same information in plain text.

```mermaid
flowchart TD
   A[Protocol design<br/>epsych.ProtocolDesigner<br/>epsych.Protocol] --> B[epsych.RunExpt<br/>session controller]
    B --> C[epsych.Runtime<br/>shared session state]
    C --> D[epsych.Helper<br/>event hub]
    C --> E[hw.Interface]
    E --> E1[hw.TDT_Synapse]
    E --> E2[hw.TDT_RPcox]
    E --> E3[hw.Intan_RHX]
   E --> E4[hw.Software]
    E1 --> F1[SynapseAPI]
    E2 --> F2[TDTRP]
    E --> G[hw.Module]
    G --> H[hw.Parameter]
    C --> R[epsych.TrialSelector]
    R --> R1[epsych.DefaultTrialSelector<br/>cl_AppetitiveStimDetect]
    D --> I[psychophysics.Psych]
    I --> I1[psychophysics.Staircase]
    I --> I4[psychophysics.BestPEST]
    I --> I5[psychophysics.MLP]
    I --> I6[psychophysics.SessionMetrics]
    C --> I3[psychophysics.Detection]
    H --> J[gui.Parameter_Control<br/>gui.Parameter_Update<br/>gui.Parameter_Monitor<br/>gui.ParameterDebugger]
    D --> K[gui.OnlinePlot<br/>gui.PsychPlot<br/>gui.ModeIndicator]
    D --> L[gui.History<br/>gui.SessionPerformance<br/>gui.Performance<br/>gui.SlidingWindowPerformancePlot]
    C --> M[cl_AppetitiveDetection_GUI_B]
    C --> N[peripherals.PumpCom]
    C --> O[peripherals.NanoMotorControl<br/>peripherals.NanoMotorControlGUI]
    C --> P[stimgen.StimType family<br/>StimCalibration<br/>StimPlay<br/>StimPlayer]
    C --> Q[EPsychInfo]
    P --> W[stimgen.calibration.Engine<br/>stimgen.calibration.HwAdapter family]
    C --> X[stimbridge.RuntimeHost<br/>stimbridge.InterfaceAdapter]
    X --> P
```

### Layered runtime view

```text
Protocol authoring
├─ epsych.ProtocolDesigner
└─ epsych.Protocol
   ↓
Session control
└─ epsych.RunExpt
   ↓
Runtime state and events
├─ epsych.Runtime
└─ epsych.Helper
   ↓
Hardware layer
├─ hw.Interface
│  ├─ hw.TDT_Synapse → SynapseAPI
│  ├─ hw.TDT_RPcox → TDTRP
│  ├─ hw.Intan_RHX
│  ├─ hw.VlcRecorder
│  └─ hw.Software
└─ hw.Module → hw.Parameter
   ↓
Trial selection
├─ epsych.TrialSelector
└─ epsych.DefaultTrialSelector / cl_AppetitiveStimDetect
   ↓
Analysis and visualization
├─ psychophysics.Psych → psychophysics.Staircase / psychophysics.BestPEST / psychophysics.MLP / psychophysics.SessionMetrics
├─ psychophysics.Detection
├─ gui.Parameter_Control / gui.Parameter_Update / gui.Parameter_Monitor / gui.ParameterDebugger
├─ gui.OnlinePlot / gui.PsychPlot / gui.ModeIndicator
└─ gui.History / gui.SessionPerformance / gui.Performance / gui.SlidingWindowPerformancePlot
   ↓
Task and support branches
├─ cl_AppetitiveDetection_GUI_B
├─ peripherals.PumpCom
├─ peripherals.NanoMotorControl / peripherals.NanoMotorControlGUI
├─ stimbridge.RuntimeHost / stimbridge.InterfaceAdapter  (seam into the submodule)
├─ stimgen.StimType family / StimCalibration / StimPlay / StimPlayer
└─ stimgen.calibration.Engine / HwAdapter family
```

### Main dependency patterns

| Pattern | Typical direction |
| --- | --- |
| Session lifecycle | `epsych.RunExpt -> epsych.Runtime` |
| Hardware control | `epsych.Runtime -> hw.Interface -> hw.Module -> hw.Parameter` |
| Backend bridge | `hw.TDT_Synapse -> SynapseAPI`, `hw.TDT_RPcox -> TDTRP` |
| Trial selection | `ep_TimerFcn_Start -> epsych.TrialSelector.create(...) -> selector subclass` |
| Online analysis | `epsych.Helper events -> psychophysics.Psych subclasses` |
| Parameter GUIs | `gui.Parameter_* <-> hw.Parameter` |
| Task GUIs | `cl.* -> epsych.Runtime -> psychophysics.* + gui.*` |

## Practical reading order

If you are tracing a live experiment session, the fastest route through the code is usually:

1. `epsych.RunExpt`
2. `epsych.Runtime`
3. `hw.Interface` and the active backend subclass
4. `hw.Module` and `hw.Parameter`
5. task GUI classes and psychophysics analysis classes attached to the runtime

If you are tracing online plots or task summaries, start with the task GUI class and then follow its references into `psychophysics.*`, `gui.*`, and the `Runtime.Helper` event path.

## Related documentation

- Architecture overview: [Architecture_Overview.md](Architecture_Overview.md)
- Runtime details: [../epsych/epsych_Runtime.md](../epsych/epsych_Runtime.md)
- Hardware interfaces: [../hw/hw_Interface.md](../hw/hw_Interface.md)
- Hardware modules: [../hw/hw_Module.md](../hw/hw_Module.md)
- Hardware parameters: [../hw/hw_Parameter.md](../hw/hw_Parameter.md)
- Psychophysics base class: [../psychophysics/psychophysics_Psych.md](../psychophysics/psychophysics_Psych.md)
- RunExpt walkthrough: [RunExpt_GUI_Overview.md](RunExpt_GUI_Overview.md)

