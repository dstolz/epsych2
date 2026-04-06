# ep_ExperimentDesign

This document explains what `ep_ExperimentDesign` does, how to use it, and how it interacts with the rest of the EPsych protocol toolchain.

`ep_ExperimentDesign` is the main GUI for building EPsych protocol files (`*.prot`). A protocol describes:

- which hardware modules are used
- which parameter tags are written to or read from each module
- how parameter values are combined into trials
- presentation options such as repetitions, randomization, and inter-stimulus interval

The GUI is implemented as a GUIDE-based MATLAB figure and is backed by a nested-function controller in [design/ep_ExperimentDesign.m](design/ep_ExperimentDesign.m).

## Table of contents

- [1) Quick start](#1-quick-start)
- [2) What the GUI produces](#2-what-the-gui-produces)
- [3) Main workflow](#3-main-workflow)
- [4) Main GUI areas](#4-main-gui-areas)
- [5) Module setup](#5-module-setup)
- [6) Parameter table](#6-parameter-table)
- [7) Protocol options](#7-protocol-options)
- [8) Saving, loading, and previewing](#8-saving-loading-and-previewing)
- [9) Runtime update behavior](#9-runtime-update-behavior)
- [10) Internal data model](#10-internal-data-model)
- [11) Related files](#11-related-files)
- [12) Common gotchas](#12-common-gotchas)

## 1) Quick start

Open the designer from MATLAB:

```matlab
ep_ExperimentDesign
```

Open an existing protocol immediately:

```matlab
ep_ExperimentDesign('C:\path\to\protocol.prot')
```

Open a protocol while tracking the currently running box index:

```matlab
ep_ExperimentDesign('C:\path\to\protocol.prot', 3)
```

Typical workflow:

1. Create a new protocol or load an existing `*.prot` file.
2. Add one or more hardware modules.
3. Define module parameters in the parameter table.
4. Set repetitions, ISI, trial selection, and compile options.
5. Preview the compiled trials.
6. Save the protocol for use in the runtime GUI.

## 2) What the GUI produces

When you save, the GUI builds a `protocol` struct and writes it to a MAT-file with a `*.prot` extension.

Important saved fields include:

- `protocol.MODULES`: one entry per hardware module
- `protocol.OPTIONS`: protocol-level settings such as randomization and repetitions
- `protocol.INFO`: free-form text from the protocol info area
- `protocol.meta`: EPsych metadata from `EPsychInfo`
- `protocol.COMPILED`: compiled trial information, unless runtime compilation is enabled

Before saving, the GUI:

- removes empty parameter rows
- copies GUI option states into `protocol.OPTIONS`
- compiles the protocol with `ep_CompileProtocol`
- converts stored WAV buffer structs into file-ID placeholders for the saved table view

If `compile_at_runtime` is enabled, the saved `protocol.COMPILED` struct keeps setup metadata but drops the full `trials` table so trials can be rebuilt later.

## 3) Main workflow

### 3.1 Opening the GUI

At startup the GUI either:

- loads a protocol passed in through `varargin`, or
- creates a new empty protocol with one default table row

If the global `PRGMSTATE` is `RUNNING` and a box index was supplied, the GUI enables the menu item for updating a running experiment.

### 3.2 Creating a protocol

Creating a new protocol resets the current module list, clears protocol info, restores default option widgets, and shows the splash overlay until a module is configured.

If a protocol is already loaded, the GUI prompts to save it before clearing state.

### 3.3 Working module-by-module

The designer edits one module at a time. The selected module drives:

- which parameter table data is displayed
- which RPvds file path is shown in the status label
- which module receives edits, buffer assignments, and calibration attachments

## 4) Main GUI areas

### 4.1 Module selector

The module selector shows all configured modules. In OpenEx mode it shows aliases only. In non-OpenEx mode it shows aliases plus the TDT module type and index, for example `Stim (RX8_1)`.

Selecting a module refreshes the parameter table and the RPvds status label.

### 4.2 Parameter table

This is where trial-defining parameters are entered. Each row represents one parameter tag for the current module.

The table always keeps an extra empty row available so users can add another parameter without manually inserting rows.

### 4.3 Options area

The GUI exposes protocol-wide options such as:

- randomized or serialized trial order
- number of repetitions
- ISI
- compile at runtime
- optional custom trial selection function
- whether to include WAV buffers in the saved protocol
- connection type (`GB` or `USB`)

### 4.4 Status and preview

The duration field is used as a quick validity indicator:

- green: protocol compiled successfully and duration could be estimated
- yellow: trial definitions are incomplete
- red: value combinations are invalid, usually because buddy-variable balancing failed

The compiled-trial preview opens a separate table using `ep_CompiledProtocolTrials`.

## 5) Module setup

### 5.1 OpenEx vs non-OpenEx mode

The first time a module is added, the GUI asks whether the experiment will use OpenEx.

OpenEx mode:

- module aliases are the primary identifiers
- module type changes are expected to happen in OpenEx Workbench
- importing tags from an RPvds file is optional

Non-OpenEx mode:

- the user selects a TDT module type such as `RX8`, `RZ2`, or `PA5`
- the user selects a module index
- non-PA5 modules can be associated with an `*.rcx` RPvds file

### 5.2 PA5 modules

PA5 attenuator modules are handled specially because they do not use RPvds files. For these modules the GUI seeds the parameter table with a `SetAtten` row and makes the parameter-name column non-editable.

### 5.3 Reading parameter tags from RPvds files

For RPvds-backed modules, `rpvds_tags` can inspect an `*.rcx` file via the TDT ActiveX control `RPco.x` and populate the parameter table automatically.

The importer filters out:

- OpenEx/system tags beginning with `z`, `Z`, `~`, `%`, `#`, or `!`
- tags containing path-like separators such as `/`, `\`, or `|`
- known helper tags such as `InitScript`, `TrigState`, `ResetTrigState`, and `rPvDsHElpEr`

This gives you a cleaner starting table containing only relevant parameter tags.

## 6) Parameter table

The default row layout is:

```matlab
{'' 'Write/Read' '< NONE >' '' false false '< NONE >'}
```

In practice the columns represent:

1. Parameter tag name
2. Direction or access mode
3. Buddy variable name
4. Values
5. Randomize within range
6. Use WAV buffers
7. Calibration file

### 6.1 Parameter tag name

The first column must not be empty. If the name begins with `$`, the GUI automatically enables compile-at-runtime because these tags depend on values that are expected to be resolved later.

### 6.2 Direction / access mode

Typical values are `Write`, `Read`, or `Read/Write`. These are passed to the compiler so it can populate the write-parameter and read-parameter lists.

### 6.3 Buddy variables

Buddy variables make multiple parameters co-vary instead of expanding independently. If you select `< ADD >`, the GUI prompts for a new buddy name and adds it to the table's dropdown choices.

Buddy variables matter during compilation because `ep_CompileProtocol` expects balanced groups. If a buddy group has mismatched lengths, trial compilation fails and the duration field turns red.

### 6.4 Values

The values column is interpreted differently depending on the row:

- standard parameters: numeric text that can be parsed by `str2num`
- random-range parameters: exactly two values, for example `2 6`
- WAV buffers: an automatically generated `FILE IDs: [...]` placeholder after scheduling files

### 6.5 Randomize within range

This option is only valid when the values field contains exactly two numeric values. If that requirement is not met, the GUI clears the random flag and shows a help dialog.

### 6.6 WAV buffers

When the WAV flag is enabled, the GUI launches [design/ep_SchedWAVgui.m](design/ep_SchedWAVgui.m) to schedule files. The selected buffer structs are stored under the current module in `protocol.MODULES.(moduleName).buffers`.

The GUI also forces consistent table values for WAV-backed rows:

- direction becomes `Write`
- values become a generated file-ID label
- random-range is disabled

### 6.7 Calibration files

Calibration selections are stored separately from the visible filename. The loaded calibration MAT-file is attached to the current module under `protocol.MODULES.(moduleName).calibrations{row}` and augmented with its source filename.

During compilation, calibrated parameters can create extra hidden rows such as amplitude and normalization helpers.

## 7) Protocol options

### 7.1 Repetitions and randomization

The GUI saves repetition count, randomization state, and ISI into `protocol.OPTIONS`. Compilation later expands unique trials into the full presentation list.

`ep_CompileProtocol` applies these rules:

- randomized mode: each repetition shuffles the compiled unique trials
- serialized mode: repetitions are concatenated in the same order
- infinite repetitions are supported and skip fixed-duration estimation

### 7.2 Trial selection function

The optional trial-selection function is validated when entered:

- the function must exist on the MATLAB path
- it must accept exactly one input
- it must return exactly one output

If validation fails, the GUI resets the field to `< default >`.

### 7.3 Connection type

The menu stores either `GB` or `USB` in `protocol.OPTIONS.ConnectionType`. This choice is used later by runtime code that talks to TDT hardware.

### 7.4 Include WAV buffers

The Include WAV Buffers menu controls whether full buffer data should remain embedded in the saved protocol. If disabled, the compiler strips each buffer's raw `buffer` field so the experiment will rely on original WAV file locations instead of carrying the waveform data inside the protocol file.

## 8) Saving, loading, and previewing

### 8.1 Saving

`SaveProtocolFile` writes a `protocol` struct to disk using MAT-file format `-v7.3`. The save dialog defaults to the `PSYCH/ProtDir` MATLAB preference.

The save process also stores EPsych metadata:

```matlab
E = EPsychInfo;
protocol.meta = E.meta;
```

### 8.2 Loading

`LoadProtocolFile` restores a saved protocol and updates the GUI for backward compatibility. If older protocols are missing newer option fields, the loader adds sensible defaults such as:

- `UseOpenEx = true`
- `IncludeWAVBuffers = 'on'`
- `ConnectionType = 'GB'`

### 8.3 Previewing compiled trials

The preview command calls [design/ep_CompiledProtocolTrials.m](design/ep_CompiledProtocolTrials.m), which first recompiles the protocol and then optionally opens a table containing the compiled write parameters and trials.

If the preview is truncated, only the first part of the trial list is shown, but compilation still runs against the full protocol.

## 9) Runtime update behavior

The file still contains an `UpdateRunningProtocol` entry point intended to modify an experiment while it is running. In the current code this behavior is intentionally disabled and returns immediately after printing a message.

That means the designer should currently be treated as an offline protocol editor rather than a live-update tool.

## 10) Internal data model

The GUI stores working state in the GUIDE `handles` struct (`h`) via `guidata`. The most important fields are:

- `h.protocol`: current protocol struct being edited
- `h.UseOpenEx`: whether the protocol targets OpenEx workflow
- `h.PA5flag`: whether the current module is a PA5 attenuator
- `h.CURRENTCELL`: currently selected parameter-table cell
- `h.CURRENT_BOX_IDX`: optional runtime box index used by the disabled live-update menu

Within `h.protocol`, module data is stored roughly like this:

```matlab
protocol.MODULES.(moduleName).data
protocol.MODULES.(moduleName).buffers
protocol.MODULES.(moduleName).calibrations
protocol.MODULES.(moduleName).RPfile
protocol.MODULES.(moduleName).ModType
protocol.MODULES.(moduleName).ModIDX
```

This representation is then consumed by [design/ep_CompileProtocol.m](design/ep_CompileProtocol.m).

## 11) Related files

- [design/ep_CompileProtocol.m](design/ep_CompileProtocol.m): expands module parameters into compiled write/read parameter lists and trial tables
- [design/ep_CompiledProtocolTrials.m](design/ep_CompiledProtocolTrials.m): previews compiled trials in a separate figure or returns compiled data programmatically
- [design/ep_AddTrial.m](design/ep_AddTrial.m): lower-level helper used by the compiler to combine parameters, buddy groups, and randomized ranges into trial definitions
- [design/ep_SchedWAVgui.m](design/ep_SchedWAVgui.m): GUI for attaching and ordering WAV buffers
- [helpers/findincell.m](helpers/findincell.m): used throughout for locating populated cells
- [documentation/overviews/RunExpt_GUI_Overview.md](documentation/overviews/RunExpt_GUI_Overview.md): describes how saved protocols are consumed by the runtime session GUI

## 12) Common gotchas

### 12.1 Buddy variables must balance

If two parameters share a buddy name, their value lists must be compatible. Otherwise compilation fails and the protocol duration display reports invalid value combinations.

### 12.2 Random-range rows need exactly two values

The random-range checkbox is not a general randomization switch for arbitrary lists. It is only for two-value ranges such as minimum and maximum.

### 12.3 Old protocols may load with defaults added silently

This is intentional backward compatibility behavior. If an old file behaves differently than expected, inspect `protocol.OPTIONS` after loading.

### 12.4 WAV data can make protocol files large

If you embed WAV buffers, the saved `*.prot` file may grow substantially. Disabling buffer inclusion keeps files smaller, but runtime systems must still be able to locate the original source WAV files.

### 12.5 RPvds tag import depends on TDT components

Reading tags from an `*.rcx` file requires the TDT ActiveX interface (`RPco.x`) to be available in MATLAB on Windows.

