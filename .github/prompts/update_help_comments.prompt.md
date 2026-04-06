---
name: update-help-comments
description: update help comments code to conform to `copilot-instructions.md`
---

Update MATLAB help comments so they conform to `.github/copilot-instructions.md`, with special focus on tightening what information is included and how it is formatted.

Treat this as an editing task, not a general rewrite. Preserve code behavior and public APIs. Only change comments that are missing, misleading, inconsistent, too verbose, or not aligned with the project comment style.

Follow these rules exactly:

1. Read `.github/copilot-instructions.md` first and apply its comment guidance strictly.
2. For function and method help comments, place the help block immediately below the `function` line.
3. Start the help block with the function call syntax on the first comment line. Do not label it as `Syntax:`.
4. Follow with a brief purpose statement of 1 to 2 lines.
5. Then include `Parameters:` and `Returns:` sections when they add value. Omit empty or trivial sections.
6. For classes, describe overall purpose, important properties, and key methods. Include a minimal usage example only when it materially helps.
7. For properties, keep inline comments short and practical.

Constrain the content of help comments:

- Include only information that helps a developer use or maintain the code.
- Prefer concrete descriptions over implementation detail.
- Document units, defaults, expected shapes, allowed values, and important assumptions when relevant.
- Call out side effects, required state, hardware dependencies, and notable limitations when relevant.
- Do not restate obvious code behavior line by line.
- Do not add tutorial-style explanations, marketing language, or speculative guidance.
- Do not invent behavior that is not supported by the code.
- Do not mention internal history, prior implementations, or TODO-style notes in help comments.
- Keep wording concise; prefer short sentences and predictable section structure.

Use this exact formatting guidance for parameter and return lists:

- Keep entry names aligned using tabs or equivalent uniform spacing.
- Use one entry per line.
- Format each entry as `Name<TAB>- Description`.
- Start descriptions with a noun phrase or imperative fragment, not a full paragraph.
- Include defaults in parentheses when helpful, for example `(default: false)`.
- Use consistent naming that matches the code exactly, including capitalization.

Example:

```matlab
% myFunction(inputSignal, sampleRate, mode)
% Compute the trial-aligned envelope used by the online detector.
%
% Parameters:
% 	inputSignal	- Input waveform vector in volts.
% 	sampleRate	- Sampling rate in Hz.
% 	mode		- Processing mode: "online" or "offline".
%
% Returns:
% 	envelope	- Smoothed magnitude envelope with one value per sample.
```

When deciding what to document, prefer this order of importance:

1. How to call it.
2. What it does.
3. Inputs, outputs, defaults, and constraints.
4. Side effects, assumptions, dependencies, and failure conditions.
5. A minimal example, only if it removes ambiguity.

When corresponding documentation exists under `documentation/`, mention it briefly in the help comments only if the reference is directly useful and can be stated concisely. Do not create new `documentation/*.md` files unless explicitly asked.

If existing comments are mostly correct, normalize formatting instead of rewriting them from scratch. If comments are absent, add the smallest complete help block that satisfies the rules above.