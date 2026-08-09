classdef Compiler < handle
    % obj = teensy.Compiler()
    % Turn a teensy.Program into the wire program the firmware executes.
    %
    % The output is the record stream documented in
    % documentation/hw/hw_Teensy_Program_Protocol.md: one ASCII line per
    % record, names declared once and referenced by index thereafter, and
    % transition conditions as postfix token lists a fixed-depth stack
    % evaluator can run inside the sampling interrupt.
    %
    % Compilation always produces a report, even when it refuses to emit. The
    % designer shows that report whether or not the program is valid, because
    % "what is wrong with it" is more useful than "it failed".
    %
    % Properties
    %   LIMITS - (constant) firmware capacities every program is checked against.
    %
    % Methods
    %   compile - Validate, index, and emit; returns lines, report and stats.
    %   emitWireProgram - Just the lines, for an already-indexed program.
    %   upload - Send a compiled program to a connected hw.Teensy.
    %
    % Example
    %   c = teensy.Compiler();
    %   r = c.compile(program);
    %   if r.Ok, disp(r.Text); end
    %
    % See also: teensy.Program, hw.Teensy.sendProgramBlock,
    %           documentation/hw/hw_Teensy_Program_Protocol.md

    properties (Constant)
        % Firmware capacities. These mirror the compile-time array sizes in
        % firmware/EPsychTeensy/Config.h; changing one means changing both.
        % MAX_LINE_CHARS matches hw.Teensy.MAX_LINE_LENGTH.
        LIMITS = struct( ...
            'MAX_STATES', 64, ...
            'MAX_CHANNELS', 32, ...
            'MAX_VARIABLES', 48, ...
            'MAX_TIMERS', 8, ...
            'MAX_COUNTERS', 8, ...
            'MAX_ACTIONS_PER_STATE', 8, ...
            'MAX_TRANSITIONS_PER_STATE', 8, ...
            'MAX_COND_TOKENS', 24, ...
            'MAX_STACK_DEPTH', 8, ...
            'MAX_NAME_CHARS', 23, ...
            'MAX_LINE_CHARS', 240)

        % Wire format this compiler emits.
        FORMAT_VERSION = 1
    end

    methods

        function result = compile(obj, program)
            % result = compile(obj, program)
            % Validate a program and emit its wire records.
            %
            % Parameters
            %   program - teensy.Program to compile.
            %
            % Returns:
            %   result - Struct with fields
            %       Ok     - logical; true only when nothing is error-severity
            %       Lines  - cellstr of wire records, framed PROG BEGIN/END
            %       Text   - the same, joined by newlines, for display
            %       Report - issue struct array (see teensy.issue)
            %       Stats  - struct of Used/Limit pairs per resource
            arguments
                obj (1,1) teensy.Compiler
                program (1,1) teensy.Program
            end

            report = program.validate();
            report = [report, obj.checkCapacity_(program)];
            report = [report, obj.checkNames_(program)];
            report = [report, obj.checkConditions_(program)];

            stats = obj.stats(program);
            ok = ~teensy.Compiler.hasError(report);

            lines = {};
            if ok
                [lines, emitIssues] = obj.emitWireProgram(program);
                report = [report, emitIssues];
                ok = ~teensy.Compiler.hasError(report);
                if ~ok
                    lines = {};
                end
            end

            result = struct( ...
                'Ok', ok, ...
                'Lines', {lines}, ...
                'Text', strjoin(lines, newline), ...
                'Report', report, ...
                'Stats', stats);

            if ok
                vprintf(1, 'teensy.Compiler: compiled "%s" to %d records', ...
                    program.Name, numel(lines));
            else
                vprintf(0, 1, 'teensy.Compiler: "%s" did not compile; %d issue(s)', ...
                    program.Name, numel(report));
            end
        end

        function s = stats(obj, program)
            % s = stats(obj, program)
            % Resource use against the firmware limits.
            %
            % Returns:
            %   s - Struct array with fields Resource, Used, Limit.
            L = obj.LIMITS;

            maxActions = 0;
            maxTransitions = 0;
            maxTokens = 0;
            maxDepth = 0;
            for i = 1:numel(program.States)
                S = program.States(i);
                maxActions = max(maxActions, numel(S.EntryActions) + numel(S.ExitActions));
                maxTransitions = max(maxTransitions, numel(S.Transitions));
                for k = 1:numel(S.Transitions)
                    [tok, depth] = S.Transitions(k).Condition.toPostfix(program);
                    maxTokens = max(maxTokens, numel(tok));
                    maxDepth = max(maxDepth, depth);
                end
            end

            s = struct('Resource', {}, 'Used', {}, 'Limit', {});
            s(end+1) = struct('Resource', "States", 'Used', numel(program.States), 'Limit', L.MAX_STATES);
            s(end+1) = struct('Resource', "Channels", 'Used', numel(program.Channels), 'Limit', L.MAX_CHANNELS);
            s(end+1) = struct('Resource', "Variables", 'Used', numel(program.Variables), 'Limit', L.MAX_VARIABLES);
            s(end+1) = struct('Resource', "Timers", 'Used', numel(program.GlobalTimers), 'Limit', L.MAX_TIMERS);
            s(end+1) = struct('Resource', "Counters", 'Used', numel(program.Counters), 'Limit', L.MAX_COUNTERS);
            s(end+1) = struct('Resource', "Actions per state", 'Used', maxActions, 'Limit', L.MAX_ACTIONS_PER_STATE);
            s(end+1) = struct('Resource', "Transitions per state", 'Used', maxTransitions, 'Limit', L.MAX_TRANSITIONS_PER_STATE);
            s(end+1) = struct('Resource', "Condition tokens", 'Used', maxTokens, 'Limit', L.MAX_COND_TOKENS);
            s(end+1) = struct('Resource', "Evaluator stack", 'Used', maxDepth, 'Limit', L.MAX_STACK_DEPTH);
        end

        function [ok, msg] = upload(~, result, iface)
            % [ok, msg] = upload(obj, result, iface)
            % Send a compiled program to a connected board.
            %
            % Parameters
            %   result - Struct from compile().
            %   iface  - Connected hw.Teensy.
            %
            % Returns:
            %   ok  - True when the board accepted the program.
            %   msg - Human-readable result.
            arguments
                ~
                result (1,1) struct
                iface
            end

            if ~result.Ok || isempty(result.Lines)
                ok = false;
                msg = 'The program has not compiled successfully.';
                return
            end

            if isempty(iface) || ~isa(iface, 'hw.Teensy')
                ok = false;
                msg = 'No Teensy interface is bound to this program.';
                return
            end

            [ok, msg] = iface.sendProgramBlock(result.Lines);
        end
    end

    methods
        % Implemented in a separate file
        [lines, iss] = emitWireProgram(obj, program)  % Emit the record stream
    end

    methods (Access = private)

        function iss = checkCapacity_(obj, program)
            % iss = checkCapacity_(obj, program)
            % Report every resource that exceeds its firmware limit.
            iss = teensy.issue();
            s = obj.stats(program);

            for i = 1:numel(s)
                if s(i).Used <= s(i).Limit
                    continue
                end
                iss(end+1) = teensy.issue("error", "Capacity", ...
                    sprintf("%s: %d used, the firmware allows %d.", ...
                        s(i).Resource, s(i).Used, s(i).Limit), ...
                    Where = "Program", ...
                    Remedy = "Simplify the program, or raise the limit in the firmware and here.");
            end
        end

        function iss = checkNames_(obj, program)
            % iss = checkNames_(obj, program)
            % Names travel on the wire, so they must be short identifiers.
            iss = teensy.issue();
            limit = obj.LIMITS.MAX_NAME_CHARS;

            groups = { ...
                "State", [program.States.Name]; ...
                "Channel", [program.Channels.Name]; ...
                "Variable", [program.Variables.Name]; ...
                "Timer", localNames_(program.GlobalTimers); ...
                "Counter", localNames_(program.Counters)};

            for g = 1:size(groups, 1)
                label = groups{g, 1};
                names = groups{g, 2};
                for i = 1:numel(names)
                    name = names(i);
                    if strlength(name) > limit
                        iss(end+1) = teensy.issue("error", "Name", ...
                            sprintf("'%s' is %d characters; the wire format allows %d.", ...
                                name, strlength(name), limit), ...
                            Where = sprintf("%s '%s'", label, name), ...
                            Remedy = sprintf("Shorten it to %d characters or fewer.", limit));
                    elseif strlength(name) > 0 && ~isvarname(char(name))
                        iss(end+1) = teensy.issue("error", "Name", ...
                            sprintf("'%s' is not a valid identifier.", name), ...
                            Where = sprintf("%s '%s'", label, name), ...
                            Remedy = "Use letters, digits and underscores, starting with a letter.");
                    end
                end
            end
        end

        function iss = checkConditions_(obj, program)
            % iss = checkConditions_(obj, program)
            % Report conditions the firmware evaluator could not run.
            iss = teensy.issue();

            for i = 1:numel(program.States)
                S = program.States(i);
                for k = 1:numel(S.Transitions)
                    where = sprintf("State '%s' transition %d", S.Name, k);
                    [tokens, depth] = S.Transitions(k).Condition.toPostfix(program);

                    if depth > obj.LIMITS.MAX_STACK_DEPTH
                        iss(end+1) = teensy.issue("error", "Condition", ...
                            sprintf("The condition nests %d deep; the evaluator stack is %d.", ...
                                depth, obj.LIMITS.MAX_STACK_DEPTH), Where = where, ...
                            Remedy = "Flatten the condition, or split it across two states.");
                    end

                    if numel(tokens) > obj.LIMITS.MAX_COND_TOKENS
                        iss(end+1) = teensy.issue("error", "Condition", ...
                            sprintf("The condition needs %d tokens; the limit is %d.", ...
                                numel(tokens), obj.LIMITS.MAX_COND_TOKENS), Where = where, ...
                            Remedy = "Simplify the condition, or split it across two states.");
                    end

                    if ~isempty(tokens) && any(arrayfun(@(t) any(t.ArgRefs < 0), tokens))
                        iss(end+1) = teensy.issue("error", "Condition", ...
                            "The condition refers to a variable that does not exist.", ...
                            Where = where, ...
                            Remedy = "Add the variable on the Variables tab, or use a literal.");
                    end
                end
            end
        end
    end

    methods (Static)

        function tf = hasError(report)
            % tf = teensy.Compiler.hasError(report)
            % True when an issue report contains anything error-severity.
            %
            % Exists because [report.Severity] on an empty issue array is a
            % double [], and comparing that to a string throws. Every caller
            % that tests a report should come through here.
            %
            % Parameters
            %   report - Issue struct array; see teensy.issue.
            %
            % Returns:
            %   tf - Logical scalar.
            tf = ~isempty(report) && any([report.Severity] == "error");
        end

        function n = countBySeverity(report, severity)
            % n = teensy.Compiler.countBySeverity(report, severity)
            % Number of issues at one severity.
            %
            % Parameters
            %   report   - Issue struct array.
            %   severity - "error", "warning" or "info".
            %
            % Returns:
            %   n - Count.
            if isempty(report)
                n = 0;
                return
            end
            n = sum([report.Severity] == string(severity));
        end

        function s = wireValue(value, program)
            % s = teensy.Compiler.wireValue(value, program)
            % Render a literal-or-reference as a wire field.
            %
            % A literal becomes its number; an "@Name" reference becomes
            % "#<index>" so the firmware can look the value up in its constant
            % table and the host can change it per trial with an ordinary SET.
            %
            % Parameters
            %   value   - Literal double or "@Name" reference string.
            %   program - Owning teensy.Program, for resolving the index.
            %
            % Returns:
            %   s - String scalar for the wire.
            [isRef, refName] = teensy.isVarRef(value);
            if isRef
                s = "#" + string(program.variableIndex(refName));
                return
            end

            v = double(value);
            if isinf(v) || isnan(v)
                % No state timer. 0 is the firmware's "no timer" sentinel, so
                % Inf and NaN both collapse onto it rather than overflowing.
                s = "0";
            elseif v == fix(v) && abs(v) < 1e9
                s = string(sprintf('%d', v));
            else
                s = string(sprintf('%.6g', v));
            end
        end
    end
end


function names = localNames_(structArray)
% names = localNames_(structArray)
% Name field of a struct array as a string array.
if isempty(structArray)
    names = strings(1, 0);
    return
end
names = string({structArray.Name});
end
