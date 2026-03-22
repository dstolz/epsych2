# epsych v2.1.0

EPsych is a MATLAB toolbox for building and running behavioral experiments primarily built around Tucker-Davis Technologies (TDT) hardware and software, but can also talk to any hardware and software through the `hw.Interface`.

The project is designed for labs that want a practical experiment framework without giving up the flexibility of normal MATLAB scripting. It combines protocol design tools, runtime GUIs, hardware integration, trial selection utilities, calibration tools, stimulus generation, and experiment-specific helper code in one repository.

## At a glance

- MATLAB-first framework for behavioral and electrophysiology experiments
- Designed around TDT hardware workflows, with both OpenEx-style and RPvds-based paths present in the codebase
- Includes protocol design tools, runtime session control, calibration utilities, hardware wrappers, and support classes
- Supports both legacy procedural workflows and newer object-oriented APIs under `obj/+epsych/`

## For new users

Start here if you are setting up EPsych for the first time:

- Toolbox orientation guide: [documentation/Toolbox_Overview.md](documentation/Toolbox_Overview.md)
- Installation and first-run guide: [documentation/Installation_Guide.md](documentation/Installation_Guide.md)
- Session GUI walkthrough: [documentation/RunExpt_GUI_Overview.md](documentation/RunExpt_GUI_Overview.md)
- Developer-facing architecture notes: [documentation/Architecture_Overview.md](documentation/Architecture_Overview.md)

## What EPsych is for

EPsych is aimed at experiments where you need to:

- design and parameterize behavioral tasks in MATLAB
- run sessions through a GUI-driven workflow
- coordinate behavioral control with TDT hardware
- manage calibration, data saving, and runtime callbacks
- extend the toolbox with your own protocols, GUIs, and analysis helpers

The repository includes both legacy procedural code and a gradual migration toward a more object-oriented structure. In practice, this means the toolbox is broad, flexible, and actively useful, but not yet fully unified under a single modern API.

## Documentation status

- A concise onboarding map of the main tools is available in [documentation/Toolbox_Overview.md](documentation/Toolbox_Overview.md)
- A practical overview of the session GUI is available in [documentation/RunExpt_GUI_Overview.md](documentation/RunExpt_GUI_Overview.md)
- A detailed setup guide is available in [documentation/Installation_Guide.md](documentation/Installation_Guide.md)
- A developer-oriented codebase map is available in [documentation/Architecture_Overview.md](documentation/Architecture_Overview.md)
- Additional notes and feature-specific documentation live under [documentation/](documentation/)
- Legacy onboarding material may still be useful, including `Intro_to_ElectroPsych_Toolbox.ppt` if it is present in your local copy

## Quick start

1. Add the repository to the MATLAB path and run startup:

    ```matlab
    addpath('C:\path\to\epsych2')
    epsych_startup
    ```

2. Build or open a protocol using the design tools in `design/`.
3. Launch the main experiment session GUI:

    ```matlab
    epsych.RunExpt
    ```

4. Add subjects, select protocol files, define save paths, and preview or run the session.

If you are setting up an older MATLAB or Windows environment, review `Notes_on_Installation.txt` for legacy build notes related to MEX components.

## Installation

EPsych setup is mostly about getting four pieces aligned:

- a compatible MATLAB release
- the EPsych repository on the MATLAB path
- the correct TDT software for your workflow
- any optional toolboxes or hardware-specific dependencies you plan to use

For full step-by-step instructions, see [documentation/Installation_Guide.md](documentation/Installation_Guide.md).

### Minimum setup checklist

1. Choose a MATLAB release that matches the workflow you plan to use.
2. Clone or unpack this repository to a stable local folder.
3. Add that folder to the MATLAB path and run `epsych_startup`.
4. Install the required TDT components for your experiment type.
5. Open a protocol designer or run `epsych.RunExpt` to confirm the toolbox loads.

### MATLAB compatibility matrix

EPsych contains both older GUIDE-era code paths and newer object-oriented UIFigure-based components. The minimum compatible MATLAB release therefore depends on which parts of the repository you actually intend to use.

| Workflow or component | Earliest practical MATLAB release | Notes |
| --- | --- | --- |
| Legacy design and runtime subset | R2014b | Matches the long-standing documented baseline for older design GUIs, legacy runtime code, and older TDT workflows. |
| Main modern `epsych.RunExpt` workflow | R2021a | Safest minimum for the current UIFigure-based runtime entry points and newer name=value call syntax used across `obj/+epsych/`, `cl/`, and several helper classes. |
| Closed-loop behavior GUIs in `cl/` | R2021a | Uses UIFigure components and modern name=value syntax extensively. |
| Newer helper classes using `arguments` blocks | R2019b | `arguments` blocks were introduced in R2019b, but other syntax used nearby can still raise the practical floor to R2021a. |
| Serial hardware helpers using `serialport` | R2019b | Applies to newer serial helpers such as pump and nanomotor control classes. |
| VLC recorder helpers using `tcpclient` and `arguments` blocks | R2019b | The helper classes themselves fit R2019b+, but repository-wide modern GUI syntax still makes R2021a the safer overall recommendation. |

In practice, if you want broad compatibility with the main components currently checked into this repository, use MATLAB R2021a or newer.

### TDT software matrix

- Behavioral experiments without electrophysiology: `TDT ActiveX Controls`
- Electrophysiology experiments using OpenEx: `TDT OpenEx` and `TDT OpenDeveloper Controls`
- Non-OpenEx RPvds workflows: ActiveX-based RPco.x access must be available to MATLAB

### Optional MATLAB capabilities

- Image Acquisition Toolbox for camera recording via `videoinput`
- Audio input hardware if webcam recording should also capture audio
- Older Windows/MATLAB combinations may require legacy MEX setup for timer-related components

### First verification step

After adding EPsych to the path, run:

```matlab
epsych_startup
epsych.RunExpt
```

If the GUI opens successfully, the basic MATLAB-side installation is working.

## Repository layout

- `obj/+epsych/`: object-oriented APIs and higher-level entry points
- `design/`: protocol and experiment design GUIs
- `runtime/`: runtime callbacks, timers, save functions, and trial-selection support
- `helpers/`: general utilities and support classes
- `calibration/`: calibration GUIs and helpers
- `TDTfun/`: TDT-specific integration utilities
- `documentation/`: focused usage notes and developer-facing references

For a higher-level description of how these pieces fit together, see [documentation/Architecture_Overview.md](documentation/Architecture_Overview.md).

## Typical workflow

For a standard experiment session, the usual flow is:

1. Design or edit a protocol in `design/`.
2. Save the protocol as a `.prot` file.
3. Launch `epsych.RunExpt`.
4. Add one or more subjects and associate each subject with a protocol.
5. Preview the session or run it in record mode.
6. Save acquired data and optionally save the session configuration.

This workflow is described in more detail in [documentation/RunExpt_GUI_Overview.md](documentation/RunExpt_GUI_Overview.md).

## Requirements

- Legacy baseline: MATLAB R2014b or newer
- Recommended release for the current main repository workflows: MATLAB R2021a or newer
- Historical development has been done on MATLAB 2020a and newer releases
- TDT software available from [Tucker-Davis Technologies](http://www.tdt.com)

### Toolbox references in the current codebase

Code-confirmed toolbox usage:

- Signal Processing Toolbox: filter design and analysis paths in calibration and stimulus-generation helpers
- Optimization Toolbox: nonlinear fitting via `lsqcurvefit` in `helpers/chunkwiseDeline.m`

Documented optional toolbox usage:

- Image Acquisition Toolbox for camera recording via `videoinput`

Other external dependencies referenced in code or documentation:

- TDT ActiveX / OpenEx / Synapse components for hardware workflows
- Psychtoolbox helpers in selected utility code
- VLC for standalone DirectShow webcam recording helpers

Required TDT software depends on your use case:

- Behavioral experiments without electrophysiology: `TDT ActiveX Controls`
- Electrophysiology experiments: `TDT OpenEx` and `TDT OpenDeveloper Controls`

Optional components:

- Standalone webcam recording: Image Acquisition Toolbox for `videoinput`
- Audio capture during webcam recording: a working microphone input

## For developers

This repository is not a small single-entry-point library. It is a toolbox with a mix of GUI code, runtime orchestration, hardware abstraction, calibration support, and legacy helpers. If you are modifying internals, read [documentation/Architecture_Overview.md](documentation/Architecture_Overview.md) first.

The short version is:

- `design/` defines protocols and experiment metadata
- `obj/+epsych/` contains newer object-oriented runtime entry points
- `runtime/` contains timers, callbacks, and execution helpers used while a session is running
- `obj/+hw/` and `TDTfun/` handle hardware-facing integration
- `helpers/` contains general utilities and support classes used across the codebase

## Standalone webcam recording

EPsych also includes webcam-recording utilities that can be used outside the main experiment runtime.

- `epsych.WebcamRecorder` provides programmatic start/stop recording
- Outputs are written as separate video (`.avi`), audio (`.wav`), and metadata (`.mat`) files
- `obj/exampleWebcamRecorder.m` provides a minimal smoke test
- `helpers/@VlcRecorder/VlcRecorder.m` supports VLC-based DirectShow webcam capture for preview, HTTP streaming, and file recording via `launchWebcam(...)`
- `obj/exampleVlcWebcamRecorder.m` provides a minimal VLC-backed example

Current limitation:

- VLC webcam selection relies on the Windows DirectShow friendly device name, so two cameras with the exact same visible device name cannot be distinguished reliably in a single VLC-backed multi-camera launch

For additional background on recorder capabilities currently present in the codebase, see the examples in `obj/` and the recorder classes under `helpers/` and `obj/+epsych/`.

## Notes on v1.1

EPsych v1.1 is essentially the same codebase as the original EPsych repository, with a few important practical differences:

1. `UserData` is no longer included in this repository because it became too large. Manage your own experimental data and local assets in a separate repository or storage location.
2. The codebase is being migrated gradually toward an object-oriented structure, which should make future versions easier to maintain and extend.
3. TDT Synapse is not currently supported by this version.

## Contact

Daniel Stolzberg, PhD  
[Daniel.Stolzberg@gmail.com](mailto:Daniel.Stolzberg@gmail.com)

All files in this toolbox are available for learning and research use under the license below. If you are trying to get started with a new setup, direct questions to the contact above.

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
