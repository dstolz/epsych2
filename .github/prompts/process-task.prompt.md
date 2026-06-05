---
description: "Process the next priority task from TaskList.md — plan or execute based on task status"
agent: "agent"
argument-hint: "Optional: task number or name to process (defaults to highest priority incomplete task)"
---

Review [TaskList.md](../../TaskList.md) and process the requested task, or the highest-priority incomplete task if none is specified.

## Workflow

1. **Read the task list**: Read `TaskList.md` and identify tasks by priority and status. Skip the _Task Template_ section.
2. **Select the task**:
   - If an argument was provided, find the matching task by number or name.
   - Otherwise, select the highest-priority task whose status is **Plan** or **Execute**.
3. **Process based on status**:
   - **Plan**: Think through the implementation approach, then update the task's "Steps to Complete" section in `TaskList.md` with concrete, ordered steps. Change the status to **Execute**.
   - **Execute**: Implement the task fully. Follow all conventions below. When done, mark the task status as **Complete** in `TaskList.md`.
4. **Update `TaskList.md`**: Reflect the new status immediately after completing the work. Include any relevant details or code snippets in the task description if helpful for future reference.

## MATLAB Conventions

Follow the project conventions in [copilot-instructions.md](../copilot-instructions.md):

- Target **MATLAB R2024b** syntax.
- Use `arguments` blocks for input validation when there are more than 2 inputs or validation is needed.
- Use **`vprintf`** for all formatted messages (info, warnings, errors) — never bare `fprintf`. Do not append `\n` to `vprintf` messages.
- Naming: PascalCase for classes/components, camelCase for functions/variables, ALL_CAPS for constants, trailing `_` for private class members.
- Place function help comments (call syntax, description, Parameters, Returns) immediately below the `function` line.
- Use `try/catch` sparingly; catch blocks must use `vprintf(0,1,ME)`.
- Prefer built-in and toolbox functions over custom implementations.
- Do not add compiler directives (e.g. `%#ok<AGROW>`).
