# EPsych v2

EPsych is a MATLAB toolbox for designing and running behavioral experiments, especially in labs using Tucker-Davis Technologies (TDT) hardware and software. It can also communicate with other systems through `hw.Interface`.

The project is aimed at labs that want a practical experiment framework without giving up the flexibility of normal MATLAB scripting. It combines protocol design tools, runtime GUIs, hardware integration, trial selection utilities, calibration tools, stimulus generation, and experiment-specific helper code in one repository.

The repository includes both legacy procedural code and a gradual migration toward newer object-oriented APIs under `obj/+epsych/`. In practice, EPsych is broad and actively useful, but not yet fully unified behind a single modern API.

## Features

- **Protocol design** — `epsych.ProtocolDesigner` builds `.eprot` protocol files: hardware interfaces, parameters, trial options, and a compiled-trial preview, with validation before anything runs.
- **Session control** — `epsych.RunExpt` runs the session: subjects, protocol loading, run/pause/stop transport, and pre-flight diagnostics via `epsych.SelfTest`.
- **Subjects & projects** — `gui.SubjectManager` over a shared, file-backed `epsych.SubjectRoster`: subjects organized by project, per-project session defaults, and tracking of which protocol version each subject last ran.
- **Hardware abstraction** — one `hw.Interface` contract covers TDT RPvds (`hw.TDT_RPcox`) and Synapse, a software-only backend for hardware-free development, and in-development Teensy, Bpod, Intan RHX, and NE-1000 syringe pump backends.
- **Stimulus generation & calibration** — the [stimgen](https://github.com/dstolz/stimgen) submodule supplies stimulus classes and `stimgen.StimPlayer`; `epsych.calibrate` measures speaker frequency response and maps dB SPL to voltage.
- **Behavior GUIs** — subclass `gui.BehaviorGUI`, or assemble one by drag-and-drop in `gui.BehaviorBuilder`; a library of reusable components covers performance summaries, psychometric plots, trial history, parameter controls, and syringe pump operation.
- **Online & offline analysis** — the `psychophysics` package: hit/false-alarm rates and d′, staircases, BestPEST and MLP threshold tracking, and windowed session metrics.
- **Trial selection** — pluggable `epsych.TrialSelector` classes for custom and closed-loop paradigms; `epsych.BlockSequence` for balanced block-randomized value sequences.
- **Teensy trial programs** — design operant state machines in `teensy.TrialDesigner`, then simulate and compile them so the contingency runs on the microcontroller (under development).
- **Data & logging** — crash-safe per-trial journaling (`epsych.TrialJournal`), configurable save functions, and session logging to `.error_logs/`.

## Installation

Stimulus generation lives in a separate repository ([dstolz/stimgen](https://github.com/dstolz/stimgen)) attached here as a git submodule, so clone recursively:

```bash
git clone --recurse-submodules https://github.com/dstolz/epsych2.git

# for an existing clone:
git submodule update --init --recursive
```

Then, in MATLAB:

```matlab
addpath('C:\path\to\epsych2')
epsych_startup
```

Skipping the submodule step does not fail loudly — protocols containing stimulus objects load with silently degraded placeholder values. `epsych_startup` warns when it detects this. Full instructions are in the [Installation Guide](documentation/overviews/Installation_Guide.md), and the submodule contract is described in [documentation/stimgen.md](documentation/stimgen.md).

## Documentation

Setup instructions, usage guides, and developer references are in this repository under [documentation/](documentation/README.md), organized for experimenters and for developers.

The project wiki is the guided companion to those references. It is organized as two paths: a workflow guide for experimenters (installation, protocol design, running sessions, calibration, training tools, custom behavior GUIs) and a developer guide (architecture, runtime and events, hardware backends, stimgen integration, analysis and GUI frameworks):

**<https://github.com/dstolz/epsych2/wiki>**

## Contact

Daniel Stolzberg, PhD  
[Daniel.Stolzberg@gmail.com](mailto:Daniel.Stolzberg@gmail.com)

All files in this toolbox are available for learning and research use under the license below. Questions about getting started with a new setup should be directed to the contact above.

## License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.