---
name: update-help-comments
description: update help comments code to conform to `copilot-instructions.md`
---

<!-- Tip: Use /create-prompt in chat to generate content with agent assistance -->

update help comments code to conform to `copilot-instructions.md`.

If you are unsure about how to update the comments, please refer to the `copilot-instructions.md` file for guidance on formatting and style. The goal is to ensure that the comments are clear, concise, and provide helpful information to users who may be new to the codebase.

Example formatting for parameter comments:

```matlab
% Parameters:
%   RUNTIME              - Runtime object with HELPER and trial data for online mode.
%   DATA                 - Per-trial struct array for offline mode, typically the loaded `Data` struct.
%   Parameter            - hw.Parameter object, or in offline mode a field name from DATA.
%   StimulusTrialType    - BitMask for stimulus trials (default: TrialType_0).
%   CatchTrialType       - BitMask for catch trials (default: TrialType_1).
%   StaircaseDirection   - "Up" or "Down" (default: "Down").
%   ConvertToDecibels    - Convert stimulus values to dB (default: false).
%   Plot                 - Enable staircase plotting (default: false).
%   PlotAxes             - Axes to draw into; creates new figure when empty.
%   ShowSteps            - Show step-direction markers when plotting.
%   ShowReversals        - Show reversal markers when plotting.
```

Make comments on parameters/properties uniformly spaced using tabs, and ensure that the descriptions are informative and easy to understand. Avoid using overly technical jargon or abbreviations that may not be familiar to all users. Additionally, make sure to include any relevant examples or use cases in the comments to help users understand how to use the code effectively.

If a `*.md` file already exists in the `documentation` folder that corresponds to the code being commented, please make sure to link to it in the comments where appropriate. This will help users find more detailed information about the code and its functionality. If a corresponding `*.md` file does not exist, you may want to create one to provide additional context, explanations, and usage examples for the code. Make use of the `/document` prompt to generate the content for these documentation files, ensuring that they are well-structured and informative for developers of all levels.