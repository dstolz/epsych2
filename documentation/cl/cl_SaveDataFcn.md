# cl_SaveDataFcn.m Documentation

## Overview

`cl_SaveDataFcn` is a customized function for saving behavioral data in the ePsych system. It is designed to be called at the end of an experiment to save all subject data contained in the `RUNTIME.TRIALS` structure. The function also prompts the user to update the appropriate log (WATER or FOOD) via a modal GUI, and then saves each subject's data to a `.mat` file in a default or user-specified directory.

This function is typically invoked automatically by the ePsych runtime, but a custom save function can be specified using the `ep_RunExpt` GUI if needed.

## Function Signature

```matlab
cl_SaveDataFcn(RUNTIME)
```

### Parameters
- `RUNTIME` (struct): Structure containing experiment runtime information, including the `TRIALS` array and `NSubjects` field. Each element of `RUNTIME.TRIALS` should contain a `Subject` sub-struct and a `DATA` field with the subject's behavioral data.

## Functionality

- Checks if there is data to save in `RUNTIME.TRIALS.DATA`. If not, it prints a message and exits.
- Displays a modal GUI prompting the user to update the WATER or FOOD log by opening a Google Sheets link in the browser.
- Iterates over all subjects in `RUNTIME.TRIALS`:
  - Determines the save path for each subject (default or user-specified).
  - If a `DataFilename` is already specified, it is used; otherwise, the user is prompted for a save location.
  - Attempts to save the subject's data to a `.mat` file. If saving fails, the user is prompted again.
  - Prints the location of the saved data file.

## Usage Example

```matlab
% Example usage within an experiment script:
cl_SaveDataFcn(RUNTIME);
```

## Customization

- To use a custom save function, specify it in the `ep_RunExpt` GUI.
- The default save directory is set to `D:\epsych_files\Data`, but this can be changed in the code if needed.

## Related Files
- `ep_RunExpt` GUI (for specifying custom save functions)
- `vprintf.m` (for formatted printing)
- `epsych.RunExpt.defaultFilename` (for generating default filenames)

## Version History
- **2025**: Updated help comments and documentation for clarity and consistency.
- **2016**: Original version by Daniel Stolzberg, PhD.

## Contact
For questions or issues, contact Daniel Stolzberg at Daniel.Stolzberg@gmail.com.
