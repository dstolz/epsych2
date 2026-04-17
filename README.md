# EPsych v2

EPsych is a MATLAB toolbox for designing and running behavioral experiments, especially in labs using Tucker-Davis Technologies (TDT) hardware and software. It can also communicate with other systems through `hw.Interface`.

The project is aimed at labs that want a practical experiment framework without giving up the flexibility of normal MATLAB scripting. It combines protocol design tools, runtime GUIs, hardware integration, trial selection utilities, calibration tools, stimulus generation, and experiment-specific helper code in one repository.

The repository includes both legacy procedural code and a gradual migration toward newer object-oriented APIs under `obj/+epsych/`. In practice, EPsych is broad and actively useful, but not yet fully unified behind a single modern API.

## Project wiki

The associated wiki is here: <https://github.com/dstolz/epsych2/wiki>

Use the wiki for evolving setup notes, usage guidance, and project context that may be updated independently from the repository files.

## Start here

If you are setting up EPsych for the first time, use these documents in this order:

- Project wiki: <https://github.com/dstolz/epsych2/wiki>
- Toolbox orientation: [documentation/overviews/Toolbox_Overview.md](documentation/overviews/Toolbox_Overview.md)
- Installation and first-run setup: [documentation/overviews/Installation_Guide.md](documentation/overviews/Installation_Guide.md)
- Session GUI walkthrough: [documentation/overviews/RunExpt_GUI_Overview.md](documentation/overviews/RunExpt_GUI_Overview.md)
- Developer architecture notes: [documentation/overviews/Architecture_Overview.md](documentation/overviews/Architecture_Overview.md)

## What EPsych is for

EPsych is intended for experiments where you need to:

- design and parameterize behavioral tasks in MATLAB
- run sessions through a GUI-driven workflow
- coordinate behavioral control with TDT hardware
- manage calibration, runtime callbacks, and data saving
- extend the toolbox with custom protocols, GUIs, and helper code

At a glance, the repository provides:

- protocol design tools
- runtime session control GUIs
- calibration utilities
- hardware abstraction layers and TDT integration
- trial selection and closed-loop components
- stimulus generation and general helper code

## Quick start

1. Add the repository root to the MATLAB path and run startup:

   ```matlab
   addpath('C:\path\to\epsych2')
   epsych_startup
   ```

2. Build or open a protocol using the tools in `design/`.
3. Launch the main session GUI:

   ```matlab
   epsych.RunExpt
   ```

4. Add subjects, select protocol files, choose save paths, and preview or run the session.

If you are working on an older Windows or MATLAB setup, review `Notes_on_Installation.txt` for legacy MEX-related notes.

## Installation summary

Most setup issues come from one of four things not being aligned:

- a compatible MATLAB release
- the EPsych repository being added to the MATLAB path
- the correct TDT software being installed for your workflow
- any optional hardware-specific or toolbox-specific dependencies

For broad compatibility with the main workflows currently in this repository, MATLAB R2021a or newer is the practical recommendation.

For step-by-step instructions, see [documentation/overviews/Installation_Guide.md](documentation/overviews/Installation_Guide.md).

### Minimum checklist

1. Install any TDT components required by your experiment type.
2. Clone the repository or download the latest release into a stable local folder.
3. Add only the repository root to the MATLAB path with `addpath()`.
4. Run `epsych_startup`.
5. Run `epsych.RunExpt` to verify the toolbox loads.

### TDT software by workflow

- Behavioral experiments without electrophysiology: `TDT ActiveX Controls`
- Electrophysiology experiments using OpenEx: `TDT OpenEx` and `TDT OpenDeveloper Controls`
- Synapse-backed workflows: TDT Synapse with MATLAB access through the bundled `SynapseAPI`
- Non-OpenEx RPvds workflows: ActiveX-based RPco.x access available to MATLAB

### First verification

Run:

```matlab
epsych_startup
epsych.RunExpt
```

If the session GUI opens, the basic MATLAB-side installation is working.

## Requirements

- Legacy baseline: MATLAB R2014b or newer
- Recommended for the current repository: MATLAB R2021a or newer
- Recent development and documentation updates have been maintained against current MATLAB releases, including MATLAB R2024b
- TDT software is available from [Tucker-Davis Technologies](http://www.tdt.com)

### MATLAB toolboxes and other dependencies

Code-confirmed toolbox usage in the current repository includes:

- Signal Processing Toolbox for filter design and analysis in calibration and stimulus-generation helpers

Other external dependencies referenced in code or documentation include:

- TDT ActiveX, OpenEx, and Synapse components
- Psychtoolbox helpers in selected utility code

Some experiment setups may also require local hardware-specific components that are not universal across all labs.

## Repository layout

- `obj/+epsych/`: newer object-oriented APIs and higher-level runtime entry points
- `obj/+hw/`: hardware abstraction classes for Synapse and RPco.x-backed workflows
- `design/`: protocol and experiment design GUIs
- `runtime/`: runtime callbacks, timers, save functions, and trial-selection support
- `helpers/`: general utilities and support classes
- `calibration/`: calibration GUIs and support code
- `cl/`: customized trial selection logic and specialized GUIs for the Caras Lab
- `TDTfun/`: TDT-specific integration utilities
- `documentation/`: focused usage notes and developer-facing references

For a higher-level map of how these pieces fit together, see [documentation/overviews/Architecture_Overview.md](documentation/overviews/Architecture_Overview.md).

## Typical workflow

1. Design or edit a protocol in `design/`.
2. Save the protocol as a `.prot` file.
3. Launch `epsych.RunExpt`.
4. Add one or more subjects and assign each subject a protocol.
5. Preview the session or run it in record mode.
6. Save acquired data and, if needed, save the session configuration.

More detail is available in [documentation/overviews/RunExpt_GUI_Overview.md](documentation/overviews/RunExpt_GUI_Overview.md).

## Documentation map

- Project wiki: <https://github.com/dstolz/epsych2/wiki>
- Toolbox overview: [documentation/overviews/Toolbox_Overview.md](documentation/overviews/Toolbox_Overview.md)
- Installation guide: [documentation/overviews/Installation_Guide.md](documentation/overviews/Installation_Guide.md)
- Session GUI walkthrough: [documentation/overviews/RunExpt_GUI_Overview.md](documentation/overviews/RunExpt_GUI_Overview.md)
- Architecture overview: [documentation/overviews/Architecture_Overview.md](documentation/overviews/Architecture_Overview.md)
- Hardware abstraction notes centered on `hw.Interface`: [documentation/hw/hw_Interface.md](documentation/hw/hw_Interface.md)
- Additional topic-specific notes: [documentation/](documentation/)
- Legacy onboarding material: [Intro_to_ElectroPsych_Toolbox.pptx](Intro_to_ElectroPsych_Toolbox.pptx)

AI has been used to help expand parts of the documentation, so some mistakes may still be present.

## Notes for developers

This is not a small, single-entry-point library. EPsych is a toolbox containing GUI code, runtime orchestration, hardware abstraction, calibration utilities, and legacy helpers.

If you are modifying internals, start with [documentation/overviews/Architecture_Overview.md](documentation/overviews/Architecture_Overview.md).

The short version:

- `design/` defines protocols and experiment metadata
- `obj/+epsych/` contains newer object-oriented runtime entry points
- `runtime/` contains timers, callbacks, and execution helpers used during a session
- `obj/+hw/` and `TDTfun/` contain hardware-facing integration code
- `helpers/` contains shared utilities used across the codebase

## Notes on v2.0

EPsych v2.0 is effectively the original EPsych codebase with a few practical changes:

1. The `UserData` directory is no longer included because it became too large. Experimental data and local assets should be managed separately.
2. The codebase is being migrated gradually toward a more object-oriented structure.
3. Hardware support has expanded beyond the original version. The current repository includes both a Synapse-backed path (`hw.TDT_Synapse`) and a direct RPvds/RPco.x path (`hw.TDT_RPcox`).

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

## Links

[![Hypercommit](https://img.shields.io/badge/Hypercommit-DB2475)](https://hypercommit.com/epsych2)
