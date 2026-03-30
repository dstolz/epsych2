# Runtime.m Documentation

## Overview

The `epsych.Runtime` class is a central container for managing the execution state of an EPsych experiment. It holds all experiment-wide state, including subject information, trial metadata, hardware and software interfaces, event dispatchers, and runtime services such as timers. This class is essential for coordinating the flow of an experiment, managing data, and interfacing with both hardware and software modules.

---

## Class Purpose

- **State Management:** Tracks the number of subjects, trial information, hardware/software interfaces, and experiment timing.
- **Parameter Serialization:** Provides methods to save and load experiment parameters to/from JSON files for reproducibility and configuration management.
- **Data Handling:** Manages paths and files for acquired data, as well as buffers for runtime data collection.
- **Integration:** Connects to helper/event dispatcher objects and MATLAB timer services for GUI and runtime operations.

---

## Properties

- **NSubjects:** Number of subjects in the experiment (default: 1)
- **HWinUse:** List of hardware in use (string array)
- **usingSynapse:** Logical flag indicating if Synapse hardware is used
- **TRIALS:** Protocol-specific trial information
- **dfltDataPath:** Default data path for output
- **HELPER:** Helper/event dispatcher object
- **TIMER:** MATLAB timer object for runtime services
- **DATA:** Container for acquired data, updated at the end of each trial
- **DataDir:** Directory for acquired data
- **DataFile:** Filepath(s) for acquired data
- **ON_HOLD:** Logical flag for hold state
- **HW:** Hardware interface object(s)
- **S:** Software interface object(s)
- **CORE:** Runtime core or struct-compatible
- **StartTime:** Experiment start time (datetime)
- **TrialComplete:** Manual trial completion flag
- **AcqBufferStr:** Buffer for acquired data (if used)

---

## Methods

- **Runtime:** Constructor. Initializes an empty runtime container and state.
- **writeParametersJSON:** Serializes runtime parameters to a JSON file. See also: [documentation/writeParametersJSON.md](writeParametersJSON.md)
- **readParametersJSON:** Loads runtime parameters from a JSON file. See also: [documentation/readParametersJSON.md](readParametersJSON.md)
- **getAllParameters:** Retrieves all parameters from hardware and software interfaces, with options for filtering by type, visibility, and access.
- **createTemplateJSON (Static):** Creates a template JSON file for parameter serialization, useful for configuration setup.

---

## Usage Example

```matlab
r = epsych.Runtime;
r.NSubjects = 2;
r.writeParametersJSON('params.json');
r.readParametersJSON('params.json');
```

---

## Integration and Related Files

- **Parameter Management:** See [documentation/Parameter_Control.md](Parameter_Control.md) for details on parameter handling and serialization.
- **Architecture Overview:** See [documentation/Architecture_Overview.md](Architecture_Overview.md) for the overall system design.
- **Experiment Info:** See [documentation/EPsychInfo.md](EPsychInfo.md) for general information about the EPsych framework.

---

## Version History
- Initial version: March 2026

---
This documentation was generated for `obj/+epsych/@Runtime/Runtime.m`. For more details, see the referenced documentation files above.
