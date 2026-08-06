classdef Program < handle
    % obj = teensy.Program(Name=Value)
    % A trial contingency expressed as an explicit state machine.
    %
    % A Program is the document the Teensy Trial Designer edits and the
    % compiler turns into a state table the board executes. It owns the
    % logical I/O channels, the named quantities a protocol can vary per
    % trial, the states, and the transitions between them.
    %
    % Program is a handle class because the GUI mutates it in place and
    % several panels observe the same instance. Everything it contains is a
    % value class, which is what makes toStruct/fromStruct an exact
    % round-trip and therefore what makes undo correct by construction.
    %
    % Any numeric field in a State, Action or Condition may hold a literal or
    % an "@Name" reference to one of this program's Variables. A reference is
    % what lets epsych.ProtocolDesigner vary a duration or a threshold from
    % trial to trial without recompiling and re-uploading the state table.
    %
    % Properties
    %   Name, Description, Author - Identification.
    %   Created, Modified - Timestamps, kept as datetime.
    %   BoxID - Subject box this program serves; drives the trigger names.
    %   Board - teensy.BoardProfile the pin assignments are checked against.
    %   Channels, Variables, States - The program contents.
    %   GlobalTimers, Counters - Named auxiliary resources.
    %   StartState - Name of the state a trial begins in.
    %   Dirty - True when the program has changed since it was last saved.
    %
    % Methods
    %   addState, removeState, renameState - State management. Renames cascade.
    %   addChannel, removeChannel, renameChannel - Channel management.
    %   addVariable, removeVariable, renameVariable - Variable management.
    %   addTimer, removeTimer, addCounter, removeCounter - Auxiliary resources.
    %   state, channel, variable - Look one up by name.
    %   resolve - Turn a literal-or-reference into a number.
    %   graph - digraph of the state machine, with reachability.
    %   autoLayout - Assign diagram positions by BFS depth.
    %   validate - Full report of everything wrong with the program.
    %   parameterSpecs, applyToModule - Produce the EPsych hw.Parameter set.
    %   toStruct, fromStruct, save, load - Serialization.
    %   summary - Multi-line human-readable description.
    %
    % Events
    %   ProgramChanged - Fired by every mutator so the GUI can refresh.
    %
    % Example
    %   p = teensy.Program(Name="Detect");
    %   p.Channels = teensy.Channel.defaultSet();
    %   p.addState(teensy.State("ITI", DurationMs = 3000));
    %   p.addState(teensy.State("Hit", IsTerminal = true));
    %   p.States(1).Transitions(end+1) = teensy.Transition.to("Hit", ...
    %       teensy.Condition.timerElapsed());
    %   p.StartState = "ITI";
    %   disp(p.summary())
    %
    % See also: teensy.TrialDesigner, teensy.Compiler, teensy.Simulator,
    %           documentation/teensy/teensy_Program_Model.md

    properties
        Name (1,1) string = "Untitled"
        Description (1,1) string = ""
        Author (1,1) string = ""
        BoxID (1,1) double {mustBeInteger, mustBeNonnegative} = 1

        Board (1,1) teensy.BoardProfile = teensy.BoardProfile()

        Channels (1,:) teensy.Channel = teensy.Channel.empty(1, 0)
        Variables (1,:) teensy.Variable = teensy.Variable.empty(1, 0)
        States (1,:) teensy.State = teensy.State.empty(1, 0)

        % Name/DurationMs struct array. DurationMs may be an "@Var" reference.
        GlobalTimers (1,:) struct = struct('Name', {}, 'DurationMs', {})

        % Name/Channel/Edge struct array. Counters increment in the sampling
        % ISR on the firmware, so a fast lick train is counted exactly.
        Counters (1,:) struct = struct('Name', {}, 'Channel', {}, 'Edge', {})

        StartState (1,1) string = ""
    end

    properties (SetAccess = protected)
        Created (1,1) datetime = datetime('now')
        Modified (1,1) datetime = datetime('now')
        Dirty (1,1) logical = false
    end

    properties (Constant)
        % Bumped when the serialized layout changes incompatibly.
        FORMAT_VERSION = 1

        % Conventional parameter names the shipped GUIs and analyses look up.
        % gui.OnlinePlot searches for the ~<BoxID> forms literally, which is a
        % different shape from the x_*_<BoxID> triggers -- do not unify them.
        CORE_TRIGGERS = ["NewTrial", "ResetTrig"]
    end

    events
        ProgramChanged
    end

    methods
        function obj = Program(options)
            % obj = teensy.Program(Name=Value)
            % Construct an empty program.
            %
            % Name=Value
            %   Name, Description, Author (string) - Identification.
            %   BoxID (double) - Subject box. Default 1.
            %   Board (teensy.BoardProfile) - Default Teensy 4.1.
            arguments
                options.Name (1,1) string = "Untitled"
                options.Description (1,1) string = ""
                options.Author (1,1) string = ""
                options.BoxID (1,1) double {mustBeInteger, mustBeNonnegative} = 1
                options.Board (1,1) teensy.BoardProfile = teensy.BoardProfile()
            end

            obj.Name = options.Name;
            obj.Description = options.Description;
            obj.Author = options.Author;
            obj.BoxID = options.BoxID;
            obj.Board = options.Board;
        end

        % --- Lookup ---------------------------------------------------------

        function idx = stateIndex(obj, name)
            % idx = stateIndex(obj, name)
            % Index of a state by name, or 0 when absent.
            idx = obj.indexOf_([obj.States.Name], name);
        end

        function idx = channelIndex(obj, name)
            % idx = channelIndex(obj, name)
            % Index of a channel by name, or 0 when absent.
            idx = obj.indexOf_([obj.Channels.Name], name);
        end

        function idx = variableIndex(obj, name)
            % idx = variableIndex(obj, name)
            % Index of a variable by name, or 0 when absent.
            idx = obj.indexOf_([obj.Variables.Name], name);
        end

        function idx = timerIndex(obj, name)
            % idx = timerIndex(obj, name)
            % Index of a global timer by name, or 0 when absent.
            idx = obj.indexOf_(obj.namesOf_(obj.GlobalTimers), name);
        end

        function idx = counterIndex(obj, name)
            % idx = counterIndex(obj, name)
            % Index of a counter by name, or 0 when absent.
            idx = obj.indexOf_(obj.namesOf_(obj.Counters), name);
        end

        function s = state(obj, name)
            % s = state(obj, name)
            % One state by name, or an empty teensy.State when absent.
            idx = obj.stateIndex(name);
            if idx == 0
                s = teensy.State.empty(1, 0);
            else
                s = obj.States(idx);
            end
        end

        function c = channel(obj, name)
            % c = channel(obj, name)
            % One channel by name, or an empty teensy.Channel when absent.
            idx = obj.channelIndex(name);
            if idx == 0
                c = teensy.Channel.empty(1, 0);
            else
                c = obj.Channels(idx);
            end
        end

        function v = variable(obj, name)
            % v = variable(obj, name)
            % One variable by name, or an empty teensy.Variable when absent.
            idx = obj.variableIndex(name);
            if idx == 0
                v = teensy.Variable.empty(1, 0);
            else
                v = obj.Variables(idx);
            end
        end

        function value = resolve(obj, valueOrRef)
            % value = resolve(obj, valueOrRef)
            % Turn a literal or an "@Name" reference into a double.
            %
            % Returns NaN for an unresolved reference rather than throwing, so
            % a half-built program still renders and simulates.
            [isRef, refName] = teensy.isVarRef(valueOrRef);
            if ~isRef
                value = double(valueOrRef);
                return
            end

            idx = obj.variableIndex(refName);
            if idx == 0
                vprintf(0, 1, 'teensy.Program: "%s" refers to a variable that does not exist', ...
                    char(valueOrRef));
                value = NaN;
                return
            end
            value = obj.Variables(idx).Value;
        end

        % --- Mutation -------------------------------------------------------

        function s = addState(obj, stateOrName)
            % s = addState(obj, stateOrName)
            % Append a state, uniquifying its name. Returns the state added.
            if isa(stateOrName, 'teensy.State')
                s = stateOrName;
            else
                s = teensy.State(string(stateOrName));
            end

            s.Name = obj.uniqueName_(s.Name, [obj.States.Name], "State");
            obj.States(end + 1) = s;

            if strlength(obj.StartState) == 0
                obj.StartState = s.Name;
            end
            obj.touch();
        end

        function removeState(obj, name)
            % removeState(obj, name)
            % Delete a state. Transitions that targeted it are left pointing at
            % the missing name, which validate() then reports -- silently
            % rewriting them would hide the paradigm change from the user.
            idx = obj.stateIndex(name);
            if idx == 0
                return
            end

            removed = obj.States(idx).Name;
            obj.States(idx) = [];

            if strcmp(obj.StartState, removed)
                if isempty(obj.States)
                    obj.StartState = "";
                else
                    obj.StartState = obj.States(1).Name;
                end
            end
            obj.touch();
        end

        function renameState(obj, oldName, newName)
            % renameState(obj, oldName, newName)
            % Rename a state and rewrite every transition that targets it.
            idx = obj.stateIndex(oldName);
            if idx == 0
                return
            end

            newName = obj.uniqueName_(string(newName), ...
                [obj.States([1:idx-1, idx+1:end]).Name], "State");
            oldName = obj.States(idx).Name;
            if strcmp(oldName, newName)
                return
            end

            obj.States(idx).Name = newName;
            obj.applyRename_("state", oldName, newName);
            obj.touch();
        end

        function moveState(obj, name, offset)
            % moveState(obj, name, offset)
            % Reorder a state in the list. Order is presentation only.
            idx = obj.stateIndex(name);
            if idx == 0
                return
            end

            target = min(max(idx + offset, 1), numel(obj.States));
            if target == idx
                return
            end

            order = 1:numel(obj.States);
            order(idx) = [];
            order = [order(1:target-1), idx, order(target:end)];
            obj.States = obj.States(order);
            obj.touch();
        end

        function c = addChannel(obj, channelOrName)
            % c = addChannel(obj, channelOrName)
            % Append a channel, uniquifying its name.
            if isa(channelOrName, 'teensy.Channel')
                c = channelOrName;
            else
                c = teensy.Channel(string(channelOrName));
            end

            c.Name = obj.uniqueName_(c.Name, [obj.Channels.Name], "Chan");
            obj.Channels(end + 1) = c;
            obj.touch();
        end

        function removeChannel(obj, name)
            % removeChannel(obj, name)
            % Delete a channel. References to it are reported by validate().
            idx = obj.channelIndex(name);
            if idx == 0
                return
            end
            obj.Channels(idx) = [];
            obj.touch();
        end

        function renameChannel(obj, oldName, newName)
            % renameChannel(obj, oldName, newName)
            % Rename a channel and rewrite every condition, action and counter
            % that refers to it.
            idx = obj.channelIndex(oldName);
            if idx == 0
                return
            end

            newName = obj.uniqueName_(string(newName), ...
                [obj.Channels([1:idx-1, idx+1:end]).Name], "Chan");
            oldName = obj.Channels(idx).Name;
            if strcmp(oldName, newName)
                return
            end

            obj.Channels(idx).Name = newName;
            obj.applyRename_("channel", oldName, newName);
            obj.touch();
        end

        function v = addVariable(obj, variableOrName)
            % v = addVariable(obj, variableOrName)
            % Append a variable, uniquifying its name.
            if isa(variableOrName, 'teensy.Variable')
                v = variableOrName;
            else
                v = teensy.Variable(string(variableOrName));
            end

            v.Name = obj.uniqueName_(v.Name, [obj.Variables.Name], "Var");
            obj.Variables(end + 1) = v;
            obj.touch();
        end

        function removeVariable(obj, name)
            % removeVariable(obj, name)
            % Delete a variable. Dangling "@Name" references are reported by
            % validate() rather than silently replaced with a literal, because
            % guessing a replacement value would change the paradigm.
            idx = obj.variableIndex(name);
            if idx == 0
                return
            end
            obj.Variables(idx) = [];
            obj.touch();
        end

        function renameVariable(obj, oldName, newName)
            % renameVariable(obj, oldName, newName)
            % Rename a variable and rewrite every "@Name" reference to it.
            idx = obj.variableIndex(oldName);
            if idx == 0
                return
            end

            newName = obj.uniqueName_(string(newName), ...
                [obj.Variables([1:idx-1, idx+1:end]).Name], "Var");
            oldName = obj.Variables(idx).Name;
            if strcmp(oldName, newName)
                return
            end

            obj.Variables(idx).Name = newName;
            obj.applyRename_("variable", oldName, newName);
            obj.touch();
        end

        function addTimer(obj, name, durationMs)
            % addTimer(obj, name, durationMs)
            % Add a global timer. durationMs may be an "@Var" reference.
            arguments
                obj
                name (1,1) string
                durationMs = 1000
            end

            name = obj.uniqueName_(name, obj.namesOf_(obj.GlobalTimers), "Timer");
            obj.GlobalTimers(end + 1) = struct('Name', name, 'DurationMs', durationMs);
            obj.touch();
        end

        function removeTimer(obj, name)
            % removeTimer(obj, name)
            % Delete a global timer.
            idx = obj.timerIndex(name);
            if idx == 0
                return
            end
            obj.GlobalTimers(idx) = [];
            obj.touch();
        end

        function addCounter(obj, name, channelName, edge)
            % addCounter(obj, name, channelName, edge)
            % Add an input counter.
            arguments
                obj
                name (1,1) string
                channelName (1,1) string = ""
                edge (1,1) string {mustBeMember(edge, ["Rising","Falling","Either"])} = "Rising"
            end

            name = obj.uniqueName_(name, obj.namesOf_(obj.Counters), "Count");
            obj.Counters(end + 1) = struct('Name', name, 'Channel', channelName, 'Edge', edge);
            obj.touch();
        end

        function removeCounter(obj, name)
            % removeCounter(obj, name)
            % Delete a counter.
            idx = obj.counterIndex(name);
            if idx == 0
                return
            end
            obj.Counters(idx) = [];
            obj.touch();
        end

        function touch(obj)
            % touch(obj)
            % Mark the program modified and notify observers.
            obj.Modified = datetime('now');
            obj.Dirty = true;
            obj.notify('ProgramChanged');
        end

        function clearDirty(obj)
            % clearDirty(obj)
            % Clear the modified flag, after a successful save.
            obj.Dirty = false;
        end

        % --- Analysis -------------------------------------------------------

        function G = graph(obj)
            % G = graph(obj)
            % Connectivity of the state machine, with reachability resolved.
            %
            % Returns a plain struct rather than a MATLAB digraph: digraph
            % reorders edges internally, which would decouple an edge from its
            % transition index, and the transition index is exactly what the
            % designer needs to jump from an arrow back to the row that drew it.
            %
            % Returns:
            %   G - Struct with fields
            %       Names      - 1xN state names
            %       IsTerminal - 1xN logical
            %       Reachable  - 1xN logical, from StartState
            %       Successors - 1xN cell of successor state indices
            %       Edges      - 1xM struct array (Source, Target, Order, Label)
            names = [obj.States.Name];
            n = numel(names);

            edges = struct('Source', {}, 'Target', {}, 'Order', {}, 'Label', {});
            successorsOf = repmat({zeros(1, 0)}, 1, n);

            for i = 1:n
                T = obj.States(i).Transitions;
                for k = 1:numel(T)
                    if strlength(T(k).Target) == 0
                        j = i;   % "stay here" is a self-edge
                    else
                        j = obj.stateIndex(T(k).Target);
                    end
                    if j == 0
                        continue    % dangling target; validate() reports it
                    end

                    edges(end + 1) = struct('Source', i, 'Target', j, 'Order', k, ...
                        'Label', T(k).Condition.describe(obj));
                    successorsOf{i}(end + 1) = j;
                end
            end

            reachable = false(1, n);
            startIdx = obj.stateIndex(obj.StartState);
            if startIdx > 0
                queue = startIdx;
                reachable(startIdx) = true;
                while ~isempty(queue)
                    i = queue(1);
                    queue(1) = [];
                    for j = successorsOf{i}
                        if ~reachable(j)
                            reachable(j) = true;
                            queue(end + 1) = j;
                        end
                    end
                end
            end

            G = struct('Names', names, 'IsTerminal', [obj.States.IsTerminal], ...
                'Reachable', reachable, 'Successors', {successorsOf}, 'Edges', edges);
        end

        function autoLayout(obj)
            % autoLayout(obj)
            % Assign State.Position by BFS depth from the start state.
            %
            % Deterministic: depth gives the column, order within a depth gives
            % the row, and terminal states are pinned to the last column so an
            % outcome never appears upstream of the state that produced it.
            n = numel(obj.States);
            if n == 0
                return
            end

            G = obj.graph();
            depth = inf(n, 1);
            startIdx = obj.stateIndex(obj.StartState);
            if startIdx == 0
                startIdx = 1;
            end
            depth(startIdx) = 0;

            % Plain BFS rather than distances(): unreachable states must keep
            % Inf so they can be parked in their own column.
            queue = startIdx;
            while ~isempty(queue)
                i = queue(1);
                queue(1) = [];
                for j = G.Successors{i}
                    if isinf(depth(j))
                        depth(j) = depth(i) + 1;
                        queue(end + 1) = j;
                    end
                end
            end

            finite = depth(~isinf(depth));
            maxDepth = 0;
            if ~isempty(finite)
                maxDepth = max(finite);
            end

            isTerm = [obj.States.IsTerminal]';
            depth(isTerm & ~isinf(depth)) = maxDepth + 1;
            depth(isinf(depth)) = maxDepth + 2;

            levels = unique(depth);
            nCols = numel(levels);
            for c = 1:nCols
                members = find(depth == levels(c));
                nRows = numel(members);
                for r = 1:nRows
                    x = (c - 0.5) / nCols;
                    y = 1 - (r - 0.5) / nRows;
                    obj.States(members(r)).Position = [x, y];
                end
            end
            obj.touch();
        end

        function txt = summary(obj)
            % txt = summary(obj)
            % Multi-line human-readable description of the program.
            terminal = obj.States([obj.States.IsTerminal]);
            outcomes = strings(1, 0);
            for i = 1:numel(terminal)
                bits = terminal(i).RespCodeBits;
                if isempty(bits)
                    outcomes(end + 1) = sprintf("%s (no response code)", terminal(i).Name);
                else
                    outcomes(end + 1) = sprintf("%s -> %s", terminal(i).Name, ...
                        strjoin(string(bits), "+"));
                end
            end

            lines = strings(0, 1);
            lines(end + 1) = sprintf("Program   : %s", obj.Name);
            if strlength(obj.Description) > 0
                lines(end + 1) = sprintf("            %s", obj.Description);
            end
            lines(end + 1) = sprintf("Board     : %s, box %d", obj.Board.Name, obj.BoxID);
            lines(end + 1) = sprintf("States    : %d (start: %s)", numel(obj.States), obj.StartState);
            lines(end + 1) = sprintf("Channels  : %d", numel(obj.Channels));
            lines(end + 1) = sprintf("Variables : %d", numel(obj.Variables));
            lines(end + 1) = sprintf("Timers    : %d,  Counters: %d", ...
                numel(obj.GlobalTimers), numel(obj.Counters));

            if ~isempty(outcomes)
                lines(end + 1) = "Outcomes  :";
                for i = 1:numel(outcomes)
                    lines(end + 1) = sprintf("            %s", outcomes(i));
                end
            end

            if ~isempty(obj.Channels)
                lines(end + 1) = "Channel map:";
                for i = 1:numel(obj.Channels)
                    lines(end + 1) = sprintf("            %s", obj.Channels(i).describe());
                end
            end

            txt = char(strjoin(lines, newline));
        end

        % --- Serialization --------------------------------------------------

        function save(obj, filename)
            % save(obj, filename)
            % Write the program to a .etsm file, or to .json when so named.
            arguments
                obj
                filename (1,:) char
            end

            [~, ~, ext] = fileparts(filename);
            S = obj.toStruct();

            if strcmpi(ext, '.json')
                fid = fopen(filename, 'w');
                if fid < 0
                    vprintf(0, 1, 'teensy.Program: cannot open "%s" for writing', filename);
                    return
                end
                closeFile = onCleanup(@() fclose(fid));
                fprintf(fid, '%s', jsonencode(S, PrettyPrint = true));
            else
                Program = S;
                Format = "EPsychTeensyProgram";
                FormatVersion = teensy.Program.FORMAT_VERSION;
                Saved = datetime('now');
                builtin('save', filename, 'Program', 'Format', 'FormatVersion', 'Saved', '-mat');
            end

            obj.clearDirty();
            vprintf(1, 'teensy.Program: saved "%s"', filename);
        end
    end

    methods
        % Implemented in separate files
        iss = validate(obj)                          % Full validation report
        specs = parameterSpecs(obj)                  % hw.Parameter definitions
        P = applyToModule(obj, module, options)      % Create parameters on a module
        S = toStruct(obj)                            % Serialize to a plain struct
    end

    methods (Static)
        obj = fromStruct(S)                          % Rebuild from toStruct output
        obj = load(filename)                         % Read a .etsm or .json file
    end

    methods (Access = private)

        function applyRename_(obj, kind, oldName, newName)
            % applyRename_(obj, kind, oldName, newName)
            % Rewrite every reference of one kind across the whole program.
            %
            % Single traversal, single place that knows where names can hide.
            % Splitting this across the mutators is how cascading renames
            % silently miss a nested condition operand.
            for i = 1:numel(obj.States)
                S = obj.States(i);

                if kind == "variable"
                    S.DurationMs = teensy.Program.renameRef_(S.DurationMs, oldName, newName);
                end

                S.EntryActions = teensy.Program.renameActions_(S.EntryActions, kind, oldName, newName);
                S.ExitActions = teensy.Program.renameActions_(S.ExitActions, kind, oldName, newName);

                for k = 1:numel(S.Transitions)
                    T = S.Transitions(k);
                    if kind == "state" && strcmp(T.Target, oldName)
                        T.Target = newName;
                    end
                    T.Condition = teensy.Program.renameCondition_(T.Condition, kind, oldName, newName);
                    T.Actions = teensy.Program.renameActions_(T.Actions, kind, oldName, newName);
                    S.Transitions(k) = T;
                end

                obj.States(i) = S;
            end

            if kind == "state" && strcmp(obj.StartState, oldName)
                obj.StartState = newName;
            end

            if kind == "channel"
                for i = 1:numel(obj.Counters)
                    if strcmp(obj.Counters(i).Channel, oldName)
                        obj.Counters(i).Channel = newName;
                    end
                end
            end

            if kind == "variable"
                for i = 1:numel(obj.GlobalTimers)
                    obj.GlobalTimers(i).DurationMs = teensy.Program.renameRef_( ...
                        obj.GlobalTimers(i).DurationMs, oldName, newName);
                end
            end
        end
    end

    methods (Static, Access = private)

        function idx = indexOf_(names, name)
            % idx = indexOf_(names, name)
            % First index of name in names, or 0.
            idx = 0;
            if isempty(names)
                return
            end
            hit = find(strcmp(names, string(name)), 1);
            if ~isempty(hit)
                idx = hit;
            end
        end

        function names = namesOf_(structArray)
            % names = namesOf_(structArray)
            % Name field of a struct array as a string array.
            if isempty(structArray)
                names = strings(1, 0);
                return
            end
            names = string({structArray.Name});
        end

        function name = uniqueName_(name, existing, prefix)
            % name = uniqueName_(name, existing, prefix)
            % Make name a valid, unique identifier among existing.
            name = string(name);
            if strlength(name) == 0 || ~isvarname(char(name))
                name = string(matlab.lang.makeValidName(prefix + name));
            end

            if isempty(existing) || ~any(strcmp(existing, name))
                return
            end

            n = 2;
            candidate = name + string(n);
            while any(strcmp(existing, candidate))
                n = n + 1;
                candidate = name + string(n);
            end
            name = candidate;
        end

        function value = renameRef_(value, oldName, newName)
            % value = renameRef_(value, oldName, newName)
            % Rewrite an "@Old" reference to "@New", leaving literals alone.
            [isRef, refName] = teensy.isVarRef(value);
            if isRef && strcmp(refName, oldName)
                value = teensy.varRef(newName);
            end
        end

        function A = renameActions_(A, kind, oldName, newName)
            % A = renameActions_(A, kind, oldName, newName)
            % Apply a rename across an action array.
            for i = 1:numel(A)
                switch kind
                    case "channel"
                        if strcmp(A(i).Channel, oldName)
                            A(i).Channel = newName;
                        end
                    case "variable"
                        if strcmp(A(i).Variable, oldName)
                            A(i).Variable = newName;
                        end
                        for f = ["Value", "WidthMs", "DelayMs", "PeriodMs", "Count"]
                            A(i).(f) = teensy.Program.renameRef_(A(i).(f), oldName, newName);
                        end
                    case "timer"
                        if strcmp(A(i).Timer, oldName)
                            A(i).Timer = newName;
                        end
                    case "counter"
                        if strcmp(A(i).Counter, oldName)
                            A(i).Counter = newName;
                        end
                end
            end
        end

        function C = renameCondition_(C, kind, oldName, newName)
            % C = renameCondition_(C, kind, oldName, newName)
            % Apply a rename through a condition tree, operands included.
            for i = 1:numel(C.Operands)
                C.Operands(i) = teensy.Program.renameCondition_(C.Operands(i), kind, oldName, newName);
            end

            switch kind
                case "channel"
                    if strcmp(C.Channel, oldName)
                        C.Channel = newName;
                    end
                case "timer"
                    if strcmp(C.Timer, oldName)
                        C.Timer = newName;
                    end
                case "counter"
                    if strcmp(C.Counter, oldName)
                        C.Counter = newName;
                    end
                case "variable"
                    for f = ["Threshold", "HoldMs", "Count", "Probability"]
                        C.(f) = teensy.Program.renameRef_(C.(f), oldName, newName);
                    end
            end
        end
    end
end
