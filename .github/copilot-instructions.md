---
applyTo: "**/*.m"
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

When parsing input parameters in a Matlab functin, always make use of the `arguments` syntax. Specify parameter class and validations where appropriate. Only use `arguments` syntax for functions with more than 2 input parameters, or when input validation is needed. For simple functions with 1-2 parameters and no validation needs, use traditional parameter parsing when necessary.

- Do not use compiler directives (e.g. `%#ok<AGROW>`)

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
- Avoid using unhandled `try/catch` blocks that may suppress important error information. Only use `try/catch` when you have a specific error handling strategy in place, such as logging the error or providing a user-friendly message.

## Commenting
 - Use concise and clear comments to explain the purpose of code blocks, especially for complex logic or non-obvious implementations.
 - Avoid redundant comments that simply restate what the code does. Instead, focus on explaining why the code is doing something, or any important context that may not be immediately clear from the code itself.
 - Use comments to indicate any assumptions, limitations, or important considerations related to the code.
 - For functions and methods, include function call syntax, a brief description of the function's purpose, its input parameters, and its return values in the comments. For private functions, focus on explaining the logic and any important details that may not be immediately clear from the code itself. Place comments immediately below the function definition line, and use a consistent format for describing parameters and return values.
 - For classes, include comments that describe the overall purpose of the class, its properties, and its methods. For complex classes, consider adding comments to explain the relationships between different properties and methods, as well as any important design decisions or patterns used in the implementation. Also provide minimmal usage examples in the class comments when appropriate.
 - For properties, place concise comments inline with the property definition to explain the purpose of the property and suggested values if appropriate. For complex properties, consider adding more detailed comments that explain how the property is used in the context of the class and any important considerations for setting its value.