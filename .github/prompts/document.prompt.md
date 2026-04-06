---
name: document
description: Generate clear documentation for code
---

<!-- Tip: Use /create-prompt in chat to generate content with agent assistance -->

Generate developer documentation for the target code file.

Write the documentation so it is clear, concise, and approachable for developers with varying levels of experience. Explain what the code does, how to use it, and any context needed to work with it effectively. Use plain language where possible, but include enough technical detail to remain useful.

The documentation should:
- Focus primarily on the file being documented.
- Pull in relevant context from other files only when it helps explain behavior, dependencies, or usage.
- Be well structured with clear headings and subheadings.
- Include usage examples when they help clarify the API or workflow.
- Avoid unnecessary jargon and overly dense explanations.

Place the generated documentation under the `documentation` directory, organized by subsystem.

Use these placement rules:
- Put subsystem-specific documentation in the matching `documentation/<subsystem>` directory.
- If the file is a general onboarding or repository-map document, place it under `documentation/overviews`.
- Preserve existing naming conventions where they already imply a subsystem prefix.

Examples:
- `obj/+hw/@Interface/Interface.m` -> `documentation/hw/hw_Interface.md`
- `obj/+gui/Parameter_Update.m` -> `documentation/gui/Parameter_Update.md`
- `obj/+psychophysics/Psych.m` -> `documentation/psychophysics/psychophysics_Psych.md`
- `helpers/vprintf.m` -> `documentation/helpers/helpers_vprintf.md`

If documentation for the target file already exists, update it instead of creating a duplicate. Preserve useful existing content and refresh it to match the current code. Add a short version history or changelog only when it meaningfully helps track important updates.

If the source file's help comments do not already reference the documentation file, add a reference to the generated documentation path in the help comments so developers can find the fuller documentation from the source.