---
applyTo: "**"
---
# Project general coding instructions
Use syntax valid for Matlab R2024b, unless explicitly requested otherwise. Assume access to the following toobloxes:
Audio Toolbox
Curve Fitting Toolbox
DSP System Toolbox
Global Optimization Toolbox
Image Acquisition Toolbox
Image Processing Toolbox
Optimization Toolbox
Parallel Computing Toolbox
Signal Processing Toolbox
Statistics and Machine Learning Toolbox

Make use of built-in and toolbox functions before generating a custom function when needed.

When parsing input parameters in a Matlab functin, always make use of the `arguments` syntax. Specify parameter class and validations where appropriate.

## Naming Conventions
- Use PascalCase for component names, interfaces, and type aliases
- Use camelCase for variables, functions, and methods
- Suffix private class members with underscore (_)
- Use ALL_CAPS for constants

## Error Handling
- Use try/catch blocks sparingly, only when necessary to handle expected errors.
- Use `vprintf` for formatted error messages. 
    Ex 1 `vprintf(0,1, 'Error: %s\n', errorMessage);`
    Ex 2 
    ```
    try
        % Some code that may throw an error
    catch ME
        vprintf(0,1,ME);
    end
    ```