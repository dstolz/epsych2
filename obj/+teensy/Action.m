classdef Action
    % obj = teensy.Action()
    % obj = teensy.Action(kind, Name=Value)
    % One thing the board does on entering, leaving or transitioning out of a state.
    %
    % Actions are the only way a trial program changes the outside world or its
    % own bookkeeping. They run in array order, so a state's EntryActions read
    % top to bottom exactly as they fire.
    %
    % Every numeric field accepts either a literal double or an "@Name"
    % reference to a teensy.Variable, so reward duration, pulse width or a
    % counter step can be set per trial from the EPsych runtime.
    %
    % Properties
    %   Kind      - "SetOutput" "Pulse" "PulseTrain" "AnalogOut" "StartTimer"
    %               "CancelTimer" "ResetCounter" "IncrementCounter"
    %               "AddRespCode" "MarkLatency" "LogEvent" "SetVariable"
    %               "Sync" "EndTrial"
    %   Channel   - Output channel name for the I/O kinds.
    %   Value     - Output level, timer override, counter step or variable value.
    %   WidthMs   - Pulse width.
    %   DelayMs   - Delay before a Pulse starts.
    %   PeriodMs  - Pulse-to-pulse interval in a PulseTrain.
    %   Count     - Number of pulses in a PulseTrain.
    %   Timer     - Global timer name.
    %   Counter   - Counter name.
    %   Bits      - epsych.BitMask array OR'd into the trial's response code.
    %   EventName - Label logged by LogEvent.
    %   Variable  - Variable name written by SetVariable.
    %   Notes     - Free text shown in the action table.
    %
    % Methods
    %   describe     - Short English text used as a table cell.
    %   channelsUsed - Channel names this action drives.
    %   varsUsed     - Variable names this action reads or writes.
    %   respMask     - Bits folded into one uint32 mask.
    %   toArgs       - Wire arguments for the compiler.
    %   validate     - Check the action against a program.
    %   toStruct     - Serialize to a plain struct.
    %   fromStruct   - (static) Rebuild from a struct written by toStruct.
    %   setOutput, pulse, pulseTrain, analogOut, startTimer, cancelTimer,
    %   resetCounter, incrementCounter, addRespCode, markLatency, logEvent,
    %   setVariable, sync, endTrial - (static) constructors, one per kind.
    %
    % Example
    %   a = teensy.Action.pulse("Reward", 40);
    %   disp(a.describe())    % pulse Reward 40 ms
    %
    % See also: teensy.State, teensy.Transition, epsych.BitMask

    properties (Constant)
        % Kinds in wire-code order: the wire code is the 0-based index.
        Kinds = ["SetOutput", "Pulse", "PulseTrain", "AnalogOut", "StartTimer", ...
            "CancelTimer", "ResetCounter", "IncrementCounter", "AddRespCode", ...
            "MarkLatency", "LogEvent", "SetVariable", "Sync", "EndTrial"]
    end

    properties
        Kind (1,1) string {mustBeMember(Kind, ["SetOutput","Pulse","PulseTrain", ...
            "AnalogOut","StartTimer","CancelTimer","ResetCounter", ...
            "IncrementCounter","AddRespCode","MarkLatency","LogEvent", ...
            "SetVariable","Sync","EndTrial"])} = "SetOutput"

        Channel (1,1) string = ""

        % Untyped on purpose: a literal double or an "@Var" reference string.
        Value = 1

        WidthMs = 50

        DelayMs = 0

        PeriodMs = 100

        Count = 1

        Timer (1,1) string = ""

        Counter (1,1) string = ""

        Bits (1,:) epsych.BitMask = epsych.BitMask.empty(1, 0)

        EventName (1,1) string = ""

        Variable (1,1) string = ""

        Notes (1,1) string = ""
    end

    methods
        function obj = Action(kind, options)
            % obj = teensy.Action(kind, Name=Value)
            % Construct one action. Every argument is optional so the class works
            % as an array element and as ClassName.empty.
            %
            % Parameters
            %   kind       - One of the values listed for the Kind property.
            %   Name=Value - Any property may be set by name.
            %
            % Returns
            %   obj - Configured teensy.Action.
            arguments
                kind (1,1) string {mustBeMember(kind, ["SetOutput","Pulse","PulseTrain", ...
                    "AnalogOut","StartTimer","CancelTimer","ResetCounter", ...
                    "IncrementCounter","AddRespCode","MarkLatency","LogEvent", ...
                    "SetVariable","Sync","EndTrial"])} = "SetOutput"
                options.Channel (1,1) string
                options.Value
                options.WidthMs
                options.DelayMs
                options.PeriodMs
                options.Count
                options.Timer (1,1) string
                options.Counter (1,1) string
                options.Bits (1,:) epsych.BitMask
                options.EventName (1,1) string
                options.Variable (1,1) string
                options.Notes (1,1) string
            end

            obj.Kind = kind;

            fn = fieldnames(options);
            for i = 1:numel(fn)
                obj.(fn{i}) = options.(fn{i});
            end
        end

        function obj = set.Value(obj, value)
            obj.Value = normalizeValueOrRef_(value, 'Value');
        end

        function obj = set.WidthMs(obj, value)
            obj.WidthMs = normalizeValueOrRef_(value, 'WidthMs');
        end

        function obj = set.DelayMs(obj, value)
            obj.DelayMs = normalizeValueOrRef_(value, 'DelayMs');
        end

        function obj = set.PeriodMs(obj, value)
            obj.PeriodMs = normalizeValueOrRef_(value, 'PeriodMs');
        end

        function obj = set.Count(obj, value)
            obj.Count = normalizeValueOrRef_(value, 'Count');
        end

        function s = describe(obj)
            % s = obj.describe()
            % Return short English text for an action table cell.
            %
            % Returns
            %   s - Scalar string, e.g. "pulse Reward 40 ms" or "add Hit, Reward".
            arguments
                obj (1,1) teensy.Action
            end

            switch obj.Kind
                case "SetOutput"
                    ch = nameOrPlaceholder_(obj.Channel, "output");
                    if teensy.isVarRef(obj.Value)
                        s = ch + " = " + numText_(obj.Value);
                    elseif obj.Value ~= 0
                        s = ch + " on";
                    else
                        s = ch + " off";
                    end

                case "Pulse"
                    s = sprintf("pulse %s %s", nameOrPlaceholder_(obj.Channel, "output"), ...
                        msText_(obj.WidthMs));
                    if ~isLiteralZero_(obj.DelayMs)
                        s = s + " after " + msText_(obj.DelayMs);
                    end

                case "PulseTrain"
                    s = sprintf("%s train: %s x %s / %s", ...
                        nameOrPlaceholder_(obj.Channel, "output"), numText_(obj.Count), ...
                        msText_(obj.WidthMs), msText_(obj.PeriodMs));

                case "AnalogOut"
                    s = sprintf("set %s to %s", nameOrPlaceholder_(obj.Channel, "output"), ...
                        numText_(obj.Value));

                case "StartTimer"
                    s = "start timer " + nameOrPlaceholder_(obj.Timer, "timer");
                    if ~isLiteralZero_(obj.Value)
                        s = s + " (" + msText_(obj.Value) + ")";
                    end

                case "CancelTimer"
                    s = "cancel timer " + nameOrPlaceholder_(obj.Timer, "timer");

                case "ResetCounter"
                    s = "reset " + nameOrPlaceholder_(obj.Counter, "counter");

                case "IncrementCounter"
                    s = sprintf("%s += %s", nameOrPlaceholder_(obj.Counter, "counter"), ...
                        numText_(obj.Value));

                case "AddRespCode"
                    names = bitNames_(obj.Bits);
                    if isempty(names)
                        s = "add (no bits)";
                    else
                        s = "add " + strjoin(names, ", ");
                    end

                case "MarkLatency"
                    s = "mark latency";

                case "LogEvent"
                    s = sprintf("log '%s'", nameOrPlaceholder_(obj.EventName, "event"));

                case "SetVariable"
                    s = sprintf("%s = %s", nameOrPlaceholder_(obj.Variable, "variable"), ...
                        numText_(obj.Value));

                case "Sync"
                    if strlength(obj.Channel) == 0
                        s = "sync pulse";
                    else
                        s = sprintf("sync pulse on %s", obj.Channel);
                    end

                otherwise
                    s = "end trial";
            end
        end

        function names = channelsUsed(obj)
            % names = obj.channelsUsed()
            % Return every channel name driven by these actions.
            %
            % Returns
            %   names - 1xN unique string array in first-use order.
            arguments
                obj (1,:) teensy.Action
            end

            names = strings(1, 0);
            for k = 1:numel(obj)
                if ismember(obj(k).Kind, ["SetOutput","Pulse","PulseTrain","AnalogOut","Sync"]) ...
                        && strlength(obj(k).Channel) > 0
                    names(end+1) = obj(k).Channel;
                end
            end
            names = reshape(unique(names, 'stable'), 1, []);
        end

        function names = varsUsed(obj)
            % names = obj.varsUsed()
            % Return every variable name these actions read or write.
            %
            % Only the fields the action's Kind actually uses are inspected, and
            % the target of a SetVariable counts as used.
            %
            % Returns
            %   names - 1xN unique string array in first-use order.
            arguments
                obj (1,:) teensy.Action
            end

            names = strings(1, 0);
            for k = 1:numel(obj)
                a = obj(k);
                fields = refFieldsFor_(a.Kind);
                for i = 1:numel(fields)
                    [tf, name] = teensy.isVarRef(a.(fields(i)));
                    if tf
                        names(end+1) = name;
                    end
                end
                if a.Kind == "SetVariable" && strlength(a.Variable) > 0
                    names(end+1) = a.Variable;
                end
            end
            names = reshape(unique(names, 'stable'), 1, []);
        end

        function mask = respMask(obj)
            % mask = obj.respMask()
            % Fold the Bits of every action into one uint32 response mask.
            %
            % Bit index n sets 2^(n-1), matching epsych.BitMask.Bits2Mask and
            % epsych.BitMask.Mask2Bits. The Undefined bit contributes nothing.
            %
            % Returns
            %   mask - Scalar uint32.
            arguments
                obj (1,:) teensy.Action
            end

            mask = uint32(0);
            for k = 1:numel(obj)
                b = double(obj(k).Bits);
                b = b(b >= 1 & b <= 32);
                for i = 1:numel(b)
                    mask = bitor(mask, bitshift(uint32(1), b(i) - 1));
                end
            end
        end

        function [args, refs] = toArgs(obj, program)
            % [args, refs] = obj.toArgs(program)
            % Return the four wire arguments for this action.
            %
            % The wire line is "A <stateIdx> <when> <kind> <a1>..<a5>" and a5
            % carries the transition order for transition actions, so an action
            % gets at most four arguments of its own. Layout by Kind:
            %
            %   SetOutput        [chanIdx level 0 0]
            %   Pulse            [chanIdx widthMs delayMs 0]
            %   PulseTrain       [chanIdx widthMs periodMs count]
            %   AnalogOut        [chanIdx value 0 0]
            %   StartTimer       [timerIdx durationOverrideMs 0 0]
            %   CancelTimer      [timerIdx 0 0 0]
            %   ResetCounter     [counterIdx 0 0 0]
            %   IncrementCounter [counterIdx step 0 0]
            %   AddRespCode      [mask 0 0 0]
            %   MarkLatency      [0 0 0 0]
            %   LogEvent         [eventCode 0 0 0]
            %   SetVariable      [varIdx value 0 0]
            %   Sync             [chanIdx widthMs 0 0]
            %   EndTrial         [0 0 0 0]
            %
            % Channel, timer, counter and variable indices are 1-based positions
            % in the matching program array; 0 means unresolved.
            %
            % Parameters
            %   program - Owning teensy.Program. Without it every index is 0.
            %
            % Returns
            %   args - 1x4 double; NaN where the slot holds a variable reference.
            %   refs - 1x4 double; 0 literal, >0 variable index, -1 unresolved.
            arguments
                obj (1,1) teensy.Action
                program = []
            end

            args = zeros(1, 4);
            refs = zeros(1, 4);

            switch obj.Kind
                case "SetOutput"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Channels')), obj.Channel);
                    [args(2), refs(2)] = resolveNum_(obj.Value, program);

                case "Pulse"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Channels')), obj.Channel);
                    [args(2), refs(2)] = resolveNum_(obj.WidthMs, program);
                    [args(3), refs(3)] = resolveNum_(obj.DelayMs, program);

                case "PulseTrain"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Channels')), obj.Channel);
                    [args(2), refs(2)] = resolveNum_(obj.WidthMs, program);
                    [args(3), refs(3)] = resolveNum_(obj.PeriodMs, program);
                    [args(4), refs(4)] = resolveNum_(obj.Count, program);

                case "AnalogOut"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Channels')), obj.Channel);
                    [args(2), refs(2)] = resolveNum_(obj.Value, program);

                case "StartTimer"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'GlobalTimers')), obj.Timer);
                    [args(2), refs(2)] = resolveNum_(obj.Value, program);

                case "CancelTimer"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'GlobalTimers')), obj.Timer);

                case "ResetCounter"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Counters')), obj.Counter);

                case "IncrementCounter"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Counters')), obj.Counter);
                    [args(2), refs(2)] = resolveNum_(obj.Value, program);

                case "AddRespCode"
                    args(1) = double(obj.respMask());

                case "LogEvent"
                    [args(1), refs(1)] = resolveNum_(obj.Value, program);

                case "SetVariable"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Variables')), obj.Variable);
                    [args(2), refs(2)] = resolveNum_(obj.Value, program);

                case "Sync"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Channels')), obj.Channel);
                    [args(2), refs(2)] = resolveNum_(obj.WidthMs, program);
            end
        end

        function iss = validate(obj, program, options)
            % iss = obj.validate()
            % iss = obj.validate(program, Where=where)
            % Check this action against a program.
            %
            % Parameters
            %   program - Owning teensy.Program. Without it only the checks that
            %       need no cross-references are run.
            %   Where   - Location text carried into every issue, e.g.
            %       "State 'Cue' entry action 1".
            %
            % Returns
            %   iss - 1xN issue struct array; see teensy.issue.
            arguments
                obj (1,1) teensy.Action
                program = []
                options.Where (1,1) string = ""
            end

            where = options.Where;
            if strlength(where) == 0
                where = sprintf("Action '%s'", obj.Kind);
            end

            iss = teensy.issue();
            iss = [iss, obj.validateTargets_(program, where)];
            iss = [iss, obj.validateTiming_(where)];
            iss = [iss, obj.validateRefs_(program, where)];
        end

        function S = toStruct(obj)
            % S = obj.toStruct()
            % Serialize actions to a plain struct array for saving or undo.
            %
            % Bits are stored as their numeric indices so the struct survives a
            % MAT or JSON round-trip without the enumeration class.
            %
            % Returns
            %   S - Struct array shaped like obj with one field per property.
            arguments
                obj teensy.Action
            end

            S = repmat(templateStruct_(), size(obj));
            for k = 1:numel(obj)
                S(k).Kind = obj(k).Kind;
                S(k).Channel = obj(k).Channel;
                S(k).Value = obj(k).Value;
                S(k).WidthMs = obj(k).WidthMs;
                S(k).DelayMs = obj(k).DelayMs;
                S(k).PeriodMs = obj(k).PeriodMs;
                S(k).Count = obj(k).Count;
                S(k).Timer = obj(k).Timer;
                S(k).Counter = obj(k).Counter;
                S(k).Bits = reshape(double(obj(k).Bits), 1, []);
                S(k).EventName = obj(k).EventName;
                S(k).Variable = obj(k).Variable;
                S(k).Notes = obj(k).Notes;
            end
        end
    end

    methods (Access = private)
        function iss = validateTargets_(obj, program, where)
            % iss = obj.validateTargets_(program, where)
            % Check the channel, timer, counter or variable the action targets.
            iss = teensy.issue();

            switch obj.Kind
                case {"SetOutput", "Pulse", "PulseTrain", "Sync"}
                    iss = [iss, channelIssues_(program, obj.Channel, "Digital", where)];

                case "AnalogOut"
                    iss = [iss, channelIssues_(program, obj.Channel, "Analog", where)];

                case {"StartTimer", "CancelTimer"}
                    iss = [iss, listIssues_(program, 'GlobalTimers', obj.Timer, "global timer", where)];

                case {"ResetCounter", "IncrementCounter"}
                    iss = [iss, listIssues_(program, 'Counters', obj.Counter, "counter", where)];

                case "AddRespCode"
                    if isempty(obj.Bits)
                        iss(end+1) = teensy.issue("error", "RespCode", ...
                            "No response bits selected.", Where = where, ...
                            Remedy = "Pick at least one bit, such as Hit or Reward.");
                    end

                case "LogEvent"
                    if strlength(obj.EventName) == 0
                        iss(end+1) = teensy.issue("error", "Event", ...
                            "No event name given.", Where = where, ...
                            Remedy = "Name the event, for example CueOn.");
                    elseif ~isvarname(char(obj.EventName))
                        iss(end+1) = teensy.issue("error", "Event", ...
                            sprintf("'%s' is not a valid event name.", obj.EventName), ...
                            Where = where, Remedy = "Use letters, digits and underscores, with no spaces.");
                    elseif strlength(obj.EventName) > 23
                        iss(end+1) = teensy.issue("error", "Event", ...
                            sprintf("'%s' is longer than the 23 character wire limit.", obj.EventName), ...
                            Where = where, Remedy = "Shorten the event name.");
                    end

                case "SetVariable"
                    iss = [iss, listIssues_(program, 'Variables', obj.Variable, "variable", where)];
                    if ~isempty(program) && strlength(obj.Variable) > 0
                        vars = programField_(program, 'Variables');
                        idx = indexOfName_(namesOf_(vars), obj.Variable);
                        if idx > 0 && vars(idx).Access == "Read"
                            iss(end+1) = teensy.issue("error", "Variable", ...
                                sprintf("'%s' is read-only and cannot be written.", obj.Variable), ...
                                Where = where, Remedy = "Change the variable's Access to Any.");
                        end
                    end
            end
        end

        function iss = validateTiming_(obj, where)
            % iss = obj.validateTiming_(where)
            % Check the pulse geometry and the numeric fields of the action.
            iss = teensy.issue();

            if ismember(obj.Kind, ["Pulse","PulseTrain","Sync"]) ...
                    && ~teensy.isVarRef(obj.WidthMs) && obj.WidthMs <= 0
                iss(end+1) = teensy.issue("error", "Timing", ...
                    sprintf("A pulse width of %g ms produces nothing.", obj.WidthMs), ...
                    Where = where, Remedy = "Use a positive width.");
            end

            if obj.Kind == "Pulse" && ~teensy.isVarRef(obj.DelayMs) && obj.DelayMs < 0
                iss(end+1) = teensy.issue("error", "Timing", ...
                    sprintf("A delay of %g ms is negative.", obj.DelayMs), Where = where, ...
                    Remedy = "Use 0 to fire immediately.");
            end

            if obj.Kind == "PulseTrain"
                if ~teensy.isVarRef(obj.Count) && obj.Count < 1
                    iss(end+1) = teensy.issue("error", "Timing", ...
                        sprintf("A train of %g pulses produces nothing.", obj.Count), ...
                        Where = where, Remedy = "Use a count of one or more.");
                end
                if ~teensy.isVarRef(obj.PeriodMs) && ~teensy.isVarRef(obj.WidthMs) ...
                        && obj.PeriodMs <= obj.WidthMs
                    iss(end+1) = teensy.issue("error", "Timing", ...
                        sprintf("A %g ms period cannot hold a %g ms pulse.", obj.PeriodMs, obj.WidthMs), ...
                        Where = where, Remedy = "Make the period longer than the width.");
                end
                if ~isLiteralZero_(obj.DelayMs)
                    iss(end+1) = teensy.issue("warning", "Timing", ...
                        "PulseTrain has no room for DelayMs in the wire program, so it is ignored.", ...
                        Where = where, ...
                        Remedy = "Use a delayed Pulse, or put the delay in a preceding state.");
                end
            end

            if obj.Kind == "IncrementCounter" && isLiteralZero_(obj.Value)
                iss(end+1) = teensy.issue("warning", "Counter", ...
                    "Incrementing by zero leaves the counter unchanged.", Where = where, ...
                    Remedy = "Use 1 to count events.");
            end
        end

        function iss = validateRefs_(obj, program, where)
            % iss = obj.validateRefs_(program, where)
            % Check that every "@Var" this action uses names a real variable.
            iss = teensy.issue();

            if isempty(program)
                return
            end

            known = namesOf_(programField_(program, 'Variables'));
            fields = refFieldsFor_(obj.Kind);

            for i = 1:numel(fields)
                [tf, name] = teensy.isVarRef(obj.(fields(i)));
                if tf && indexOfName_(known, name) == 0
                    iss(end+1) = teensy.issue("error", "Variable", ...
                        sprintf("%s refers to undefined variable '%s'.", fields(i), name), ...
                        Where = where, ...
                        Remedy = "Add the variable on the Variables tab, or enter a literal value.");
                end
            end
        end
    end

    methods (Static)
        function obj = setOutput(channel, value)
            % obj = teensy.Action.setOutput(channel, value)
            % Hold a digital output at a level until something else changes it.
            %
            % Parameters
            %   channel - Digital output channel name.
            %   value   - 1 for the active level, 0 for the inactive level;
            %       literal or "@Var".
            %
            % Returns
            %   obj - teensy.Action of Kind "SetOutput".
            arguments
                channel (1,1) string = ""
                value = 1
            end

            obj = teensy.Action("SetOutput", Channel = channel, Value = value);
        end

        function obj = pulse(channel, widthMs, delayMs)
            % obj = teensy.Action.pulse(channel, widthMs, delayMs)
            % Drive a digital output active for a fixed time.
            %
            % Parameters
            %   channel - Digital output channel name.
            %   widthMs - Pulse width; literal or "@Var".
            %   delayMs - Delay before the pulse starts; literal or "@Var".
            %
            % Returns
            %   obj - teensy.Action of Kind "Pulse".
            arguments
                channel (1,1) string = ""
                widthMs = 50
                delayMs = 0
            end

            obj = teensy.Action("Pulse", Channel = channel, WidthMs = widthMs, DelayMs = delayMs);
        end

        function obj = pulseTrain(channel, widthMs, periodMs, count)
            % obj = teensy.Action.pulseTrain(channel, widthMs, periodMs, count)
            % Drive a digital output with a burst of pulses.
            %
            % Parameters
            %   channel  - Digital output channel name.
            %   widthMs  - Width of each pulse; literal or "@Var".
            %   periodMs - Pulse onset to pulse onset; literal or "@Var".
            %   count    - Number of pulses; literal or "@Var".
            %
            % Returns
            %   obj - teensy.Action of Kind "PulseTrain".
            arguments
                channel (1,1) string = ""
                widthMs = 10
                periodMs = 100
                count = 5
            end

            obj = teensy.Action("PulseTrain", Channel = channel, WidthMs = widthMs, ...
                PeriodMs = periodMs, Count = count);
        end

        function obj = analogOut(channel, value)
            % obj = teensy.Action.analogOut(channel, value)
            % Set an analog output to a level.
            %
            % Parameters
            %   channel - Analog output channel name.
            %   value   - Output level in the channel's Units; literal or "@Var".
            %
            % Returns
            %   obj - teensy.Action of Kind "AnalogOut".
            arguments
                channel (1,1) string = ""
                value = 0
            end

            obj = teensy.Action("AnalogOut", Channel = channel, Value = value);
        end

        function obj = startTimer(name, durationMs)
            % obj = teensy.Action.startTimer(name, durationMs)
            % Start or restart a global timer.
            %
            % Parameters
            %   name       - Global timer name declared on the program.
            %   durationMs - Duration override; literal or "@Var". The default 0
            %       uses the duration declared with the timer.
            %
            % Returns
            %   obj - teensy.Action of Kind "StartTimer".
            arguments
                name (1,1) string = ""
                durationMs = 0
            end

            obj = teensy.Action("StartTimer", Timer = name, Value = durationMs);
        end

        function obj = cancelTimer(name)
            % obj = teensy.Action.cancelTimer(name)
            % Stop a running global timer without firing it.
            %
            % Parameters
            %   name - Global timer name.
            %
            % Returns
            %   obj - teensy.Action of Kind "CancelTimer".
            arguments
                name (1,1) string = ""
            end

            obj = teensy.Action("CancelTimer", Timer = name);
        end

        function obj = resetCounter(name)
            % obj = teensy.Action.resetCounter(name)
            % Set a counter back to zero.
            %
            % Parameters
            %   name - Counter name.
            %
            % Returns
            %   obj - teensy.Action of Kind "ResetCounter".
            arguments
                name (1,1) string = ""
            end

            obj = teensy.Action("ResetCounter", Counter = name);
        end

        function obj = incrementCounter(name, step)
            % obj = teensy.Action.incrementCounter(name, step)
            % Add to a counter.
            %
            % Parameters
            %   name - Counter name.
            %   step - Amount to add; literal or "@Var".
            %
            % Returns
            %   obj - teensy.Action of Kind "IncrementCounter".
            arguments
                name (1,1) string = ""
                step = 1
            end

            obj = teensy.Action("IncrementCounter", Counter = name, Value = step);
        end

        function obj = addRespCode(bits)
            % obj = teensy.Action.addRespCode(bits)
            % OR response bits into the trial's response code.
            %
            % Parameters
            %   bits - epsych.BitMask array, or numeric bit indices.
            %
            % Returns
            %   obj - teensy.Action of Kind "AddRespCode".
            arguments
                bits (1,:) epsych.BitMask = epsych.BitMask.empty(1, 0)
            end

            obj = teensy.Action("AddRespCode", Bits = bits);
        end

        function obj = markLatency()
            % obj = teensy.Action.markLatency()
            % Stamp the response latency at the moment this action runs.
            %
            % Returns
            %   obj - teensy.Action of Kind "MarkLatency".
            obj = teensy.Action("MarkLatency");
        end

        function obj = logEvent(name, value)
            % obj = teensy.Action.logEvent(name, value)
            % Push a timestamped event into the board's event queue.
            %
            % Parameters
            %   name  - Event label; a valid identifier of at most 23 chars.
            %   value - Numeric payload sent with the event; literal or "@Var".
            %
            % Returns
            %   obj - teensy.Action of Kind "LogEvent".
            arguments
                name (1,1) string = ""
                value = 0
            end

            obj = teensy.Action("LogEvent", EventName = name, Value = value);
        end

        function obj = setVariable(name, value)
            % obj = teensy.Action.setVariable(name, value)
            % Write a value into a program variable.
            %
            % Parameters
            %   name  - Variable name.
            %   value - New value; literal or "@Var" to copy another variable.
            %
            % Returns
            %   obj - teensy.Action of Kind "SetVariable".
            arguments
                name (1,1) string = ""
                value = 0
            end

            obj = teensy.Action("SetVariable", Variable = name, Value = value);
        end

        function obj = sync(channel, widthMs)
            % obj = teensy.Action.sync(channel, widthMs)
            % Emit a sync pulse for the acquisition system.
            %
            % Parameters
            %   channel - Digital output channel carrying the sync line.
            %   widthMs - Pulse width; literal or "@Var".
            %
            % Returns
            %   obj - teensy.Action of Kind "Sync".
            arguments
                channel (1,1) string = ""
                widthMs = 5
            end

            obj = teensy.Action("Sync", Channel = channel, WidthMs = widthMs);
        end

        function obj = endTrial()
            % obj = teensy.Action.endTrial()
            % End the trial as soon as the current state finishes its actions.
            %
            % Returns
            %   obj - teensy.Action of Kind "EndTrial".
            obj = teensy.Action("EndTrial");
        end

        function code = kindCode(kind)
            % code = teensy.Action.kindCode(kind)
            % Return the 0-based wire code for an action kind.
            %
            % Parameters
            %   kind - Action kind.
            %
            % Returns
            %   code - 0-based index into Kinds, or -1 when unrecognised.
            arguments
                kind (1,1) string
            end

            idx = find(teensy.Action.Kinds == kind, 1);
            if isempty(idx)
                code = -1;
            else
                code = idx - 1;
            end
        end

        function kind = kindName(code)
            % kind = teensy.Action.kindName(code)
            % Return the action kind for a wire code.
            %
            % Parameters
            %   code - 0-based wire code.
            %
            % Returns
            %   kind - Matching kind, or "" when the code is out of range.
            arguments
                code (1,1) double
            end

            kinds = teensy.Action.Kinds;
            if code < 0 || code >= numel(kinds) || code ~= floor(code)
                kind = "";
            else
                kind = kinds(code + 1);
            end
        end

        function obj = fromStruct(S)
            % obj = teensy.Action.fromStruct(S)
            % Rebuild actions from structs written by toStruct.
            %
            % Fields missing from an older save fall back to the current
            % defaults, and an unrecognised enumeration value or bit index is
            % dropped rather than raising an error.
            %
            % Parameters
            %   S - Struct array from toStruct, or a teensy.Action array.
            %
            % Returns
            %   obj - 1xN teensy.Action.
            if isa(S, 'teensy.Action')
                obj = reshape(S, 1, []);
                return
            end

            if ~isstruct(S) || isempty(S)
                obj = teensy.Action.empty(1, 0);
                return
            end

            d = teensy.Action();
            obj = teensy.Action.empty(1, 0);

            for k = 1:numel(S)
                kind = pickMember_(teensy.getFieldOr(S(k), 'Kind', d.Kind), teensy.Action.Kinds, d.Kind);
                a = teensy.Action(kind);
                a.Channel = string(teensy.getFieldOr(S(k), 'Channel', d.Channel));
                a.Value = refField_(S(k), 'Value', d.Value);
                a.WidthMs = refField_(S(k), 'WidthMs', d.WidthMs);
                a.DelayMs = refField_(S(k), 'DelayMs', d.DelayMs);
                a.PeriodMs = refField_(S(k), 'PeriodMs', d.PeriodMs);
                a.Count = refField_(S(k), 'Count', d.Count);
                a.Timer = string(teensy.getFieldOr(S(k), 'Timer', d.Timer));
                a.Counter = string(teensy.getFieldOr(S(k), 'Counter', d.Counter));
                a.Bits = bitsFromStored_(teensy.getFieldOr(S(k), 'Bits', []));
                a.EventName = string(teensy.getFieldOr(S(k), 'EventName', d.EventName));
                a.Variable = string(teensy.getFieldOr(S(k), 'Variable', d.Variable));
                a.Notes = string(teensy.getFieldOr(S(k), 'Notes', d.Notes));
                obj(end+1) = a;
            end
        end
    end
end


function S = templateStruct_()
% S = templateStruct_()
% Return the 1x1 serialization struct with the canonical field order.
S = struct( ...
    'Kind', "", ...
    'Channel', "", ...
    'Value', 0, ...
    'WidthMs', 0, ...
    'DelayMs', 0, ...
    'PeriodMs', 0, ...
    'Count', 0, ...
    'Timer', "", ...
    'Counter', "", ...
    'Bits', [], ...
    'EventName', "", ...
    'Variable', "", ...
    'Notes', "");
end


function bits = bitsFromStored_(value)
% bits = bitsFromStored_(value)
% Rebuild an epsych.BitMask array from stored numeric bit indices.
if isa(value, 'epsych.BitMask')
    bits = reshape(value, 1, []);
    return
end

bits = epsych.BitMask.empty(1, 0);
if ~(isnumeric(value) || islogical(value)) || isempty(value)
    return
end

raw = reshape(double(value), 1, []);
raw = raw(raw >= 0 & raw <= 31 & raw == floor(raw));
if ~isempty(raw)
    bits = epsych.BitMask(raw);
end
end


function names = bitNames_(bits)
% names = bitNames_(bits)
% Return the enumeration member name of every bit as a 1xN string.
names = strings(1, 0);
if isempty(bits)
    return
end

[members, memberNames] = enumeration('epsych.BitMask');
values = uint32(members);

for i = 1:numel(bits)
    hit = find(values == uint32(bits(i)), 1);
    if ~isempty(hit)
        names(end+1) = string(memberNames{hit});
    end
end
end


function v = normalizeValueOrRef_(value, fieldName)
% v = normalizeValueOrRef_(value, fieldName)
% Accept a literal number or an "@Var" reference for a dual-typed field.
%
% A bare identifier is promoted to a reference, and text that parses as a
% number becomes a literal, so values typed into a GUI table behave sensibly.
if isnumeric(value) || islogical(value)
    if ~isscalar(value)
        error('teensy:Action:BadValue', '%s must be a scalar.', fieldName);
    end
    v = double(value);
    return
end

if ischar(value) || isstring(value)
    s = string(value);
    if isscalar(s)
        if teensy.isVarRef(s)
            v = s;
            return
        end
        parsed = str2double(s);
        if ~isnan(parsed)
            v = parsed;
            return
        end
        if isvarname(char(s))
            v = teensy.varRef(s);
            return
        end
    end
end

error('teensy:Action:BadValue', ...
    '%s must be a number or an "@Variable" reference.', fieldName);
end


function v = refField_(S, name, default)
% v = refField_(S, name, default)
% Read a dual-typed field from a saved struct, rejecting unusable values.
v = teensy.getFieldOr(S, name, default);

usable = (isnumeric(v) || islogical(v)) && isscalar(v);
if ~usable && (ischar(v) || isstring(v))
    s = string(v);
    usable = isscalar(s) && strlength(s) > 0 && ...
        (teensy.isVarRef(s) || ~isnan(str2double(s)) || isvarname(char(s)));
end

if ~usable
    v = default;
end
end


function fields = refFieldsFor_(kind)
% fields = refFieldsFor_(kind)
% Return the dual-typed field names a given action kind actually reads.
switch kind
    case {"SetOutput", "AnalogOut", "StartTimer", "IncrementCounter", "SetVariable", "LogEvent"}
        fields = "Value";
    case "Pulse"
        fields = ["WidthMs", "DelayMs"];
    case "PulseTrain"
        fields = ["WidthMs", "PeriodMs", "Count"];
    case "Sync"
        fields = "WidthMs";
    otherwise
        fields = strings(1, 0);
end
end


function [num, refIdx] = resolveNum_(value, program)
% [num, refIdx] = resolveNum_(value, program)
% Split a dual-typed field into a literal and a 1-based variable index.
[tf, name] = teensy.isVarRef(value);

if ~tf
    num = double(value);
    refIdx = 0;
    return
end

num = NaN;
refIdx = indexOfName_(namesOf_(programField_(program, 'Variables')), name);
if refIdx == 0
    refIdx = -1;
end
end


function items = programField_(program, name)
% items = programField_(program, name)
% Read one list off a program, tolerating no program at all.
items = [];
if isempty(program)
    return
end
items = program.(name);
end


function names = namesOf_(items)
% names = namesOf_(items)
% Return the Name of every element of an object or struct array as a 1xN string.
if isempty(items)
    names = strings(1, 0);
    return
end
names = reshape(string({items.Name}), 1, []);
end


function idx = indexOfName_(names, name)
% idx = indexOfName_(names, name)
% Return the 1-based position of a name in a list, or 0 when absent.
idx = 0;
if isempty(names) || strlength(name) == 0
    return
end
hit = find(names == name, 1);
if ~isempty(hit)
    idx = hit;
end
end


function iss = channelIssues_(program, channelName, requiredKind, where)
% iss = channelIssues_(program, channelName, requiredKind, where)
% Check that an action's channel exists and is an output of the right kind.
iss = teensy.issue();

if strlength(channelName) == 0
    iss(end+1) = teensy.issue("error", "Channel", ...
        "No channel selected.", Where = where, ...
        Remedy = sprintf("Pick a %s output channel.", lower(requiredKind)));
    return
end

if isempty(program)
    return
end

chans = programField_(program, 'Channels');
idx = indexOfName_(namesOf_(chans), channelName);

if idx == 0
    iss(end+1) = teensy.issue("error", "Channel", ...
        sprintf("There is no channel named '%s'.", channelName), Where = where, ...
        Remedy = "Add the channel on the Channels tab, or pick an existing one.");
    return
end

ch = chans(idx);

if ch.Direction ~= "Output"
    iss(end+1) = teensy.issue("error", "Channel", ...
        sprintf("'%s' is an input and cannot be driven.", channelName), Where = where, ...
        Remedy = "Actions can only write output channels.");
end

if ch.Kind ~= requiredKind
    iss(end+1) = teensy.issue("error", "Channel", ...
        sprintf("'%s' is a %s channel but this action needs a %s one.", ...
            channelName, lower(ch.Kind), lower(requiredKind)), Where = where, ...
        Remedy = "Pick a matching channel, or change the action kind.");
end
end


function iss = listIssues_(program, listName, name, label, where)
% iss = listIssues_(program, listName, name, label, where)
% Check that a named timer, counter or variable is declared on the program.
iss = teensy.issue();

if strlength(name) == 0
    iss(end+1) = teensy.issue("error", "Name", ...
        sprintf("No %s selected.", label), Where = where, ...
        Remedy = sprintf("Pick a %s, or add one from the Insert menu.", label));
    return
end

if isempty(program)
    return
end

if indexOfName_(namesOf_(programField_(program, listName)), name) == 0
    iss(end+1) = teensy.issue("error", "Name", ...
        sprintf("There is no %s named '%s'.", label, name), Where = where, ...
        Remedy = sprintf("Add the %s from the Insert menu, or pick an existing one.", label));
end
end


function tf = isLiteralZero_(value)
% tf = isLiteralZero_(value)
% True when a dual-typed field holds the literal 0 rather than a reference.
tf = ~teensy.isVarRef(value) && isnumeric(value) && isscalar(value) && value == 0;
end


function s = numText_(value)
% s = numText_(value)
% Format a dual-typed field for display: "40" or "@Level".
if teensy.isVarRef(value)
    s = string(value);
else
    s = string(sprintf('%g', value));
end
end


function s = msText_(value)
% s = msText_(value)
% Format a dual-typed duration for display: "40 ms" or "@RewardDur".
if teensy.isVarRef(value)
    s = string(value);
else
    s = string(sprintf('%g ms', value));
end
end


function s = nameOrPlaceholder_(name, label)
% s = nameOrPlaceholder_(name, label)
% Return a name, or a bracketed placeholder when it has not been chosen yet.
if strlength(name) == 0
    s = "<" + label + ">";
else
    s = name;
end
end


function v = pickMember_(value, allowed, default)
% v = pickMember_(value, allowed, default)
% Coerce a stored enumeration value, falling back when it is unrecognised.
v = default;
if ~(ischar(value) || isstring(value))
    return
end
s = string(value);
if isscalar(s) && ismember(s, allowed)
    v = s;
end
end
