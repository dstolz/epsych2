classdef Condition
    % obj = teensy.Condition()
    % obj = teensy.Condition(kind, Name=Value)
    % One node of the boolean expression that guards a transition.
    %
    % A Condition is either a leaf that tests the world (a digital edge, an
    % analog threshold, a timer, a counter, a coin flip) or an operator node
    % (And, Or, Not) whose Operands are themselves Conditions. Because it is a
    % value class the whole tree copies, compares and undoes for free.
    %
    % Build trees with the static helpers rather than by hand:
    %
    %   c = teensy.Condition.all([ ...
    %           teensy.Condition.digitalEdge("Poke","Rising"), ...
    %           teensy.Condition.analogThreshold("Mic","Above",2.5,20)]);
    %   c.describe()      % "Poke rises AND Mic above 2.5 V for 20 ms"
    %
    % Threshold, HoldMs, Count and Probability each accept either a literal
    % double or an "@Name" reference to a teensy.Variable, so a staircase can
    % move a threshold between trials without recompiling the program.
    %
    % Properties
    %   Kind        - "Always" "Never" "StateTimer" "GlobalTimer" "DigitalEdge"
    %                 "DigitalLevel" "AnalogThreshold" "Counter" "Probability"
    %                 "And" "Or" "Not"
    %   Channel     - Channel name for the digital and analog kinds.
    %   Edge        - "Rising", "Falling" or "Either".
    %   Level       - 0 or 1, for DigitalLevel.
    %   Compare     - "Above", "Below", "CrossUp" or "CrossDown".
    %   Threshold   - Analog trip level; literal or "@Var".
    %   HoldMs      - How long the test must stay true; literal or "@Var". For
    %                 StateTimer it is the elapsed time to wait, and 0 means
    %                 "use the state's own DurationMs".
    %   Counter     - Counter name, for Counter.
    %   CompareOp   - "GE", "GT", "LE", "LT" or "EQ", for Counter.
    %   Count       - Counter target; literal or "@Var".
    %   Timer       - Global timer name, for GlobalTimer.
    %   Probability - Branch probability in 0..1; literal or "@Var".
    %   Operands    - Child Conditions, for And, Or and Not.
    %   LeafKinds, OperatorKinds - (constant) the two halves of the vocabulary.
    %
    % Methods
    %   describe      - Short English text used as a diagram arrow label.
    %   isLeaf        - True when the node tests the world rather than combining.
    %   channelsUsed  - Channel names referenced anywhere in the tree.
    %   varsUsed      - Variable names referenced anywhere in the tree.
    %   toPostfix     - Wire tokens plus the stack depth they need.
    %   validate      - Check the tree against a program.
    %   toStruct      - Serialize the whole tree to a struct.
    %   fromStruct    - (static) Rebuild a tree from a struct.
    %   always, never, timerElapsed, digitalEdge, digitalLevel, analogThreshold,
    %   counterReached, globalTimer, probability, all, any, negate - (static)
    %       constructors, one per kind.
    %
    % Example
    %   c = teensy.Condition.digitalLevel("Lick", 1, 50);
    %   disp(c.describe())            % Lick held high 50 ms
    %   [tok, depth] = c.toPostfix(); % 1 token, depth 1
    %
    % See also: teensy.Transition, teensy.Action, teensy.Variable

    properties (Constant)
        % Leaf kinds in wire-code order: the wire code is the 0-based index.
        LeafKinds = ["Always", "Never", "StateTimer", "GlobalTimer", ...
            "DigitalEdge", "DigitalLevel", "AnalogThreshold", "Counter", "Probability"]

        OperatorKinds = ["And", "Or", "Not"]
    end

    properties
        Kind (1,1) string {mustBeMember(Kind, ["Always","Never","StateTimer", ...
            "GlobalTimer","DigitalEdge","DigitalLevel","AnalogThreshold", ...
            "Counter","Probability","And","Or","Not"])} = "Always"

        Channel (1,1) string = ""

        Edge (1,1) string {mustBeMember(Edge, ["Rising","Falling","Either"])} = "Rising"

        Level (1,1) double {mustBeMember(Level, [0 1])} = 1

        Compare (1,1) string {mustBeMember(Compare, ["Above","Below","CrossUp","CrossDown"])} = "Above"

        % Untyped on purpose: a literal double or an "@Var" reference string.
        Threshold = 2.5

        HoldMs = 0

        Counter (1,1) string = ""

        CompareOp (1,1) string {mustBeMember(CompareOp, ["GE","GT","LE","LT","EQ"])} = "GE"

        Count = 1

        Timer (1,1) string = ""

        Probability = 0.5

        Operands (1,:) teensy.Condition = teensy.Condition.empty(1, 0)
    end

    methods
        function obj = Condition(kind, options)
            % obj = teensy.Condition(kind, Name=Value)
            % Construct one condition node. Every argument is optional so the
            % class works as an array element and as ClassName.empty.
            %
            % Parameters
            %   kind       - One of the values listed for the Kind property.
            %   Name=Value - Any property may be set by name.
            %
            % Returns
            %   obj - Configured teensy.Condition.
            arguments
                kind (1,1) string {mustBeMember(kind, ["Always","Never","StateTimer", ...
                    "GlobalTimer","DigitalEdge","DigitalLevel","AnalogThreshold", ...
                    "Counter","Probability","And","Or","Not"])} = "Always"
                options.Channel (1,1) string
                options.Edge (1,1) string {mustBeMember(options.Edge, ["Rising","Falling","Either"])}
                options.Level (1,1) double {mustBeMember(options.Level, [0 1])}
                options.Compare (1,1) string {mustBeMember(options.Compare, ["Above","Below","CrossUp","CrossDown"])}
                options.Threshold
                options.HoldMs
                options.Counter (1,1) string
                options.CompareOp (1,1) string {mustBeMember(options.CompareOp, ["GE","GT","LE","LT","EQ"])}
                options.Count
                options.Timer (1,1) string
                options.Probability
                options.Operands (1,:) teensy.Condition
            end

            obj.Kind = kind;

            fn = fieldnames(options);
            for i = 1:numel(fn)
                obj.(fn{i}) = options.(fn{i});
            end
        end

        function obj = set.Threshold(obj, value)
            obj.Threshold = normalizeValueOrRef_(value, 'Threshold');
        end

        function obj = set.HoldMs(obj, value)
            obj.HoldMs = normalizeValueOrRef_(value, 'HoldMs');
        end

        function obj = set.Count(obj, value)
            obj.Count = normalizeValueOrRef_(value, 'Count');
        end

        function obj = set.Probability(obj, value)
            obj.Probability = normalizeValueOrRef_(value, 'Probability');
        end

        function tf = isLeaf(obj)
            % tf = obj.isLeaf()
            % True for nodes that test the world rather than combine others.
            %
            % Returns
            %   tf - Logical of the same size as obj.
            arguments
                obj teensy.Condition
            end

            tf = false(size(obj));
            for k = 1:numel(obj)
                tf(k) = ismember(obj(k).Kind, teensy.Condition.LeafKinds);
            end
        end

        function s = describe(obj, program)
            % s = obj.describe()
            % s = obj.describe(program)
            % Return short English text for a diagram arrow or a table cell.
            %
            % Operators recurse and parenthesise, so a nested tree still reads
            % correctly: "Poke rises AND (Lick high OR 20% chance)".
            %
            % Parameters
            %   program - Owning teensy.Program, used only to look up the real
            %       units of an analog channel. Without it the unit is assumed
            %       to be "V", which is the Channel default.
            %
            % Returns
            %   s - Scalar string, normally under 40 characters per leaf.
            arguments
                obj (1,1) teensy.Condition
                program = []
            end

            switch obj.Kind
                case "Always"
                    s = "always";

                case "Never"
                    s = "never";

                case "StateTimer"
                    if isLiteralZero_(obj.HoldMs)
                        s = "state timer";
                    else
                        s = sprintf("state timer (%s)", msText_(obj.HoldMs));
                    end

                case "GlobalTimer"
                    s = sprintf("%s timer elapsed", nameOrPlaceholder_(obj.Timer, "timer"));

                case "DigitalEdge"
                    ch = nameOrPlaceholder_(obj.Channel, "input");
                    switch obj.Edge
                        case "Rising"
                            s = ch + " rises";
                        case "Falling"
                            s = ch + " falls";
                        otherwise
                            s = ch + " changes";
                    end

                case "DigitalLevel"
                    ch = nameOrPlaceholder_(obj.Channel, "input");
                    if obj.Level >= 1
                        word = "high";
                    else
                        word = "low";
                    end
                    if isLiteralZero_(obj.HoldMs)
                        s = ch + " " + word;
                    else
                        s = sprintf("%s held %s %s", ch, word, msText_(obj.HoldMs));
                    end

                case "AnalogThreshold"
                    ch = nameOrPlaceholder_(obj.Channel, "input");
                    unit = channelUnits_(program, obj.Channel);
                    s = sprintf("%s %s %s", ch, compareWord_(obj.Compare), numText_(obj.Threshold));
                    if strlength(unit) > 0
                        s = s + " " + unit;
                    end
                    if ~isLiteralZero_(obj.HoldMs)
                        s = s + " for " + msText_(obj.HoldMs);
                    end

                case "Counter"
                    s = sprintf("%s %s %s", nameOrPlaceholder_(obj.Counter, "counter"), ...
                        opSymbol_(obj.CompareOp), numText_(obj.Count));

                case "Probability"
                    if teensy.isVarRef(obj.Probability)
                        s = numText_(obj.Probability) + " chance";
                    else
                        s = sprintf("%g%% chance", 100 * obj.Probability);
                    end

                case {"And", "Or"}
                    if isempty(obj.Operands)
                        s = "(nothing)";
                        return
                    end
                    if obj.Kind == "And"
                        joiner = " AND ";
                    else
                        joiner = " OR ";
                    end
                    parts = strings(1, numel(obj.Operands));
                    for i = 1:numel(obj.Operands)
                        parts(i) = obj.operandText_(obj.Operands(i), program);
                    end
                    s = strjoin(parts, joiner);

                otherwise
                    if isempty(obj.Operands)
                        s = "NOT (nothing)";
                    else
                        s = "NOT (" + obj.Operands(1).describe(program) + ")";
                    end
            end
        end

        function names = channelsUsed(obj)
            % names = obj.channelsUsed()
            % Return every channel name referenced anywhere in the tree.
            %
            % Returns
            %   names - 1xN unique string array in first-use order.
            arguments
                obj (1,:) teensy.Condition
            end

            names = strings(1, 0);
            for k = 1:numel(obj)
                c = obj(k);
                if ismember(c.Kind, ["DigitalEdge","DigitalLevel","AnalogThreshold"]) ...
                        && strlength(c.Channel) > 0
                    names(end+1) = c.Channel;
                end
                if ~isempty(c.Operands)
                    names = [names, c.Operands.channelsUsed()];
                end
            end
            names = reshape(unique(names, 'stable'), 1, []);
        end

        function names = varsUsed(obj)
            % names = obj.varsUsed()
            % Return every "@Var" name referenced anywhere in the tree.
            %
            % Only the fields that the node's Kind actually uses are inspected,
            % so a stale reference left on an unused field is ignored.
            %
            % Returns
            %   names - 1xN unique string array in first-use order.
            arguments
                obj (1,:) teensy.Condition
            end

            names = strings(1, 0);
            for k = 1:numel(obj)
                c = obj(k);
                fields = refFieldsFor_(c.Kind);
                for i = 1:numel(fields)
                    [tf, name] = teensy.isVarRef(c.(fields(i)));
                    if tf
                        names(end+1) = name;
                    end
                end
                if ~isempty(c.Operands)
                    names = [names, c.Operands.varsUsed()];
                end
            end
            names = reshape(unique(names, 'stable'), 1, []);
        end

        function [tokens, maxDepth] = toPostfix(obj, program)
            % [tokens, maxDepth] = obj.toPostfix(program)
            % Flatten the tree into the postfix token list the firmware runs.
            %
            % Leaves are emitted depth first and each operator follows the
            % operands it consumes, so a fixed-depth stack evaluator can walk the
            % list from left to right. And/Or fold left in pairs, which keeps a
            % flat chain of N operands at depth 2 instead of depth N.
            %
            % Channel, counter, timer and variable indices are 1-based positions
            % in the matching program array; 0 means the name could not be
            % resolved, which validate() reports as an error.
            %
            % Parameters
            %   program - Owning teensy.Program. Without it every index resolves
            %       to 0, which is useful for previewing shape but not for
            %       uploading.
            %
            % Returns
            %   tokens - 1xN struct array with fields:
            %       Op      - "leaf", "and", "or" or "not"
            %       Kind    - the Kind that produced the token
            %       Args    - 1x4 double; NaN where the slot holds a reference
            %                 or is unused. Leaf layout by Kind:
            %                   StateTimer      [afterMs 0 0 0]
            %                   GlobalTimer     [timerIdx 0 0 0]
            %                   DigitalEdge     [chanIdx edgeCode 0 0]
            %                   DigitalLevel    [chanIdx level holdMs 0]
            %                   AnalogThreshold [chanIdx cmpCode threshold holdMs]
            %                   Counter         [counterIdx opCode count 0]
            %                   Probability     [p 0 0 0]
            %       ArgRefs - 1x4 double; 0 literal, >0 variable index,
            %                 -1 unresolved reference.
            %       Text    - wire token, "L<code>,<a1>,<a2>,<a3>,<a4>" for a
            %                 leaf and "&", "|" or "!" for an operator, where a
            %                 slot holding a variable is written "#<varIdx>".
            %   maxDepth - Deepest the evaluator stack gets. The firmware stack
            %       is 8 deep, so the compiler rejects anything above that.
            arguments
                obj (1,1) teensy.Condition
                program = []
            end

            tokens = emptyTokenArray_();
            [tokens, ~, maxDepth] = obj.emitPostfix_(program, tokens, 0, 0);
        end

        function iss = validate(obj, program, options)
            % iss = obj.validate()
            % iss = obj.validate(program, Where=where)
            % Check this condition, and everything below it, against a program.
            %
            % Parameters
            %   program - Owning teensy.Program. Without it only the checks that
            %       need no cross-references are run.
            %   Where   - Location text carried into every issue, e.g.
            %       "State 'Cue' transition 2".
            %
            % Returns
            %   iss - 1xN issue struct array; see teensy.issue.
            arguments
                obj (1,1) teensy.Condition
                program = []
                options.Where (1,1) string = ""
            end

            where = options.Where;
            if strlength(where) == 0
                where = "Condition";
            end

            iss = teensy.issue();

            if ismember(obj.Kind, teensy.Condition.OperatorKinds)
                iss = [iss, obj.validateOperator_(program, where)];
                return
            end

            if ~isempty(obj.Operands)
                iss(end+1) = teensy.issue("warning", "Condition", ...
                    sprintf("A %s condition ignores its %d operand(s).", obj.Kind, numel(obj.Operands)), ...
                    Where = where, Remedy = "Clear the operands, or change the kind to And/Or/Not.");
            end

            iss = [iss, obj.validateLeaf_(program, where)];
            iss = [iss, obj.validateRefs_(program, where)];
        end

        function S = toStruct(obj)
            % S = obj.toStruct()
            % Serialize conditions, including the whole operand tree.
            %
            % Returns
            %   S - Struct array shaped like obj; Operands is itself a struct
            %       array written by this method.
            arguments
                obj teensy.Condition
            end

            S = repmat(templateStruct_(), size(obj));
            for k = 1:numel(obj)
                S(k).Kind = obj(k).Kind;
                S(k).Channel = obj(k).Channel;
                S(k).Edge = obj(k).Edge;
                S(k).Level = obj(k).Level;
                S(k).Compare = obj(k).Compare;
                S(k).Threshold = obj(k).Threshold;
                S(k).HoldMs = obj(k).HoldMs;
                S(k).Counter = obj(k).Counter;
                S(k).CompareOp = obj(k).CompareOp;
                S(k).Count = obj(k).Count;
                S(k).Timer = obj(k).Timer;
                S(k).Probability = obj(k).Probability;
                S(k).Operands = obj(k).Operands.toStruct();
            end
        end
    end

    methods (Access = private)
        function [tokens, depth, maxDepth] = emitPostfix_(obj, program, tokens, depth, maxDepth)
            % [tokens, depth, maxDepth] = obj.emitPostfix_(program, tokens, depth, maxDepth)
            % Append this node's postfix tokens and track the evaluator stack.
            switch obj.Kind
                case {"And", "Or"}
                    if obj.Kind == "And"
                        opName = "and";
                        opText = "&";
                        filler = teensy.Condition("Always");
                    else
                        opName = "or";
                        opText = "|";
                        filler = teensy.Condition("Never");
                    end

                    ops = obj.Operands;
                    if isempty(ops)
                        % An empty And is vacuously true and an empty Or
                        % vacuously false; validate() flags the authoring error.
                        [tokens, depth, maxDepth] = filler.emitPostfix_(program, tokens, depth, maxDepth);
                        return
                    end

                    [tokens, depth, maxDepth] = ops(1).emitPostfix_(program, tokens, depth, maxDepth);
                    for i = 2:numel(ops)
                        [tokens, depth, maxDepth] = ops(i).emitPostfix_(program, tokens, depth, maxDepth);
                        tokens(end+1) = makeToken_(opName, obj.Kind, nan(1,4), zeros(1,4), opText);
                        depth = depth - 1;
                    end

                case "Not"
                    if isempty(obj.Operands)
                        filler = teensy.Condition("Never");
                        [tokens, depth, maxDepth] = filler.emitPostfix_(program, tokens, depth, maxDepth);
                        return
                    end
                    [tokens, depth, maxDepth] = obj.Operands(1).emitPostfix_(program, tokens, depth, maxDepth);
                    tokens(end+1) = makeToken_("not", "Not", nan(1,4), zeros(1,4), "!");

                otherwise
                    tokens(end+1) = obj.leafToken_(program);
                    depth = depth + 1;
                    maxDepth = max(maxDepth, depth);
            end
        end

        function tok = leafToken_(obj, program)
            % tok = obj.leafToken_(program)
            % Build the single wire token for a leaf node.
            args = zeros(1, 4);
            refs = zeros(1, 4);

            switch obj.Kind
                case "StateTimer"
                    [args(1), refs(1)] = resolveNum_(obj.HoldMs, program);

                case "GlobalTimer"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'GlobalTimers')), obj.Timer);

                case "DigitalEdge"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Channels')), obj.Channel);
                    args(2) = edgeCode_(obj.Edge);

                case "DigitalLevel"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Channels')), obj.Channel);
                    args(2) = obj.Level;
                    [args(3), refs(3)] = resolveNum_(obj.HoldMs, program);

                case "AnalogThreshold"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Channels')), obj.Channel);
                    args(2) = compareCode_(obj.Compare);
                    [args(3), refs(3)] = resolveNum_(obj.Threshold, program);
                    [args(4), refs(4)] = resolveNum_(obj.HoldMs, program);

                case "Counter"
                    args(1) = indexOfName_(namesOf_(programField_(program, 'Counters')), obj.Counter);
                    args(2) = compareOpCode_(obj.CompareOp);
                    [args(3), refs(3)] = resolveNum_(obj.Count, program);

                case "Probability"
                    [args(1), refs(1)] = resolveNum_(obj.Probability, program);
            end

            parts = strings(1, 4);
            for i = 1:4
                parts(i) = wireNum_(args(i), refs(i));
            end

            text = "L" + string(teensy.Condition.kindCode(obj.Kind)) + "," + strjoin(parts, ",");
            tok = makeToken_("leaf", obj.Kind, args, refs, text);
        end

        function s = operandText_(obj, child, program)
            % s = obj.operandText_(child, program)
            % Describe one operand, parenthesising it when precedence demands.
            s = child.describe(program);
            if ismember(child.Kind, ["And","Or"]) && child.Kind ~= obj.Kind
                s = "(" + s + ")";
            end
        end

        function iss = validateOperator_(obj, program, where)
            % iss = obj.validateOperator_(program, where)
            % Check an And, Or or Not node and recurse into its operands.
            iss = teensy.issue();
            n = numel(obj.Operands);

            if obj.Kind == "Not"
                if n == 0
                    iss(end+1) = teensy.issue("error", "Condition", ...
                        "NOT has nothing to negate.", Where = where, ...
                        Remedy = "Add one operand, or delete the NOT.");
                elseif n > 1
                    iss(end+1) = teensy.issue("error", "Condition", ...
                        sprintf("NOT takes one operand but has %d; the rest are ignored.", n), ...
                        Where = where, Remedy = "Wrap the extra operands in an AND or an OR first.");
                end
            else
                if n == 0
                    iss(end+1) = teensy.issue("error", "Condition", ...
                        sprintf("%s has no operands.", upper(obj.Kind)), Where = where, ...
                        Remedy = "Add at least two operands, or replace the node with a leaf.");
                elseif n == 1
                    iss(end+1) = teensy.issue("warning", "Condition", ...
                        sprintf("%s with a single operand does nothing.", upper(obj.Kind)), ...
                        Where = where, Remedy = "Add another operand, or use the operand on its own.");
                end
            end

            for i = 1:n
                iss = [iss, obj.Operands(i).validate(program, ...
                    Where = sprintf("%s operand %d", where, i))];
            end
        end

        function iss = validateLeaf_(obj, program, where)
            % iss = obj.validateLeaf_(program, where)
            % Check the channel, counter, timer and numeric fields of a leaf.
            iss = teensy.issue();

            switch obj.Kind
                case {"DigitalEdge", "DigitalLevel"}
                    iss = [iss, channelIssues_(program, obj.Channel, "Digital", where)];

                case "AnalogThreshold"
                    iss = [iss, channelIssues_(program, obj.Channel, "Analog", where)];

                case "Counter"
                    iss = [iss, listIssues_(program, 'Counters', obj.Counter, "counter", where)];
                    if ~teensy.isVarRef(obj.Count) && obj.Count < 0
                        iss(end+1) = teensy.issue("error", "Counter", ...
                            sprintf("A counter cannot reach %g.", obj.Count), Where = where, ...
                            Remedy = "Use a target of zero or more.");
                    end

                case "GlobalTimer"
                    iss = [iss, listIssues_(program, 'GlobalTimers', obj.Timer, "global timer", where)];

                case "Probability"
                    if ~teensy.isVarRef(obj.Probability) && (obj.Probability < 0 || obj.Probability > 1)
                        iss(end+1) = teensy.issue("error", "Probability", ...
                            sprintf("A probability of %g is outside 0..1.", obj.Probability), ...
                            Where = where, Remedy = "Enter a fraction, for example 0.2 for a 20% branch.");
                    end

                case "Never"
                    iss(end+1) = teensy.issue("info", "Condition", ...
                        "This transition can never fire.", Where = where, ...
                        Remedy = "Useful while testing; remove it before running subjects.");
            end

            if ismember(obj.Kind, ["StateTimer","DigitalLevel","AnalogThreshold"]) ...
                    && ~teensy.isVarRef(obj.HoldMs) && obj.HoldMs < 0
                iss(end+1) = teensy.issue("error", "Timing", ...
                    sprintf("A hold time of %g ms is negative.", obj.HoldMs), Where = where, ...
                    Remedy = "Use 0 for no hold requirement.");
            end
        end

        function iss = validateRefs_(obj, program, where)
            % iss = obj.validateRefs_(program, where)
            % Check that every "@Var" this leaf uses names a real variable.
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
        function obj = always()
            % obj = teensy.Condition.always()
            % Return a condition that is always true.
            %
            % Returns
            %   obj - teensy.Condition of Kind "Always".
            obj = teensy.Condition("Always");
        end

        function obj = never()
            % obj = teensy.Condition.never()
            % Return a condition that is never true.
            %
            % Returns
            %   obj - teensy.Condition of Kind "Never".
            obj = teensy.Condition("Never");
        end

        function obj = timerElapsed(afterMs)
            % obj = teensy.Condition.timerElapsed()
            % obj = teensy.Condition.timerElapsed(afterMs)
            % Return a condition on the time spent in the current state.
            %
            % Parameters
            %   afterMs - Elapsed time to wait for, literal or "@Var". The
            %       default 0 means "wait for the state's own DurationMs", which
            %       is the usual way to time a state out.
            %
            % Returns
            %   obj - teensy.Condition of Kind "StateTimer".
            arguments
                afterMs = 0
            end

            obj = teensy.Condition("StateTimer", HoldMs = afterMs);
        end

        function obj = globalTimer(name)
            % obj = teensy.Condition.globalTimer(name)
            % Return a condition that fires when a global timer expires.
            %
            % Parameters
            %   name - Global timer name declared on the program.
            %
            % Returns
            %   obj - teensy.Condition of Kind "GlobalTimer".
            arguments
                name (1,1) string = ""
            end

            obj = teensy.Condition("GlobalTimer", Timer = name);
        end

        function obj = digitalEdge(channel, edge)
            % obj = teensy.Condition.digitalEdge(channel, edge)
            % Return a condition on a digital input transition.
            %
            % Parameters
            %   channel - Digital input channel name.
            %   edge    - "Rising", "Falling" or "Either".
            %
            % Returns
            %   obj - teensy.Condition of Kind "DigitalEdge".
            arguments
                channel (1,1) string = ""
                edge (1,1) string {mustBeMember(edge, ["Rising","Falling","Either"])} = "Rising"
            end

            obj = teensy.Condition("DigitalEdge", Channel = channel, Edge = edge);
        end

        function obj = digitalLevel(channel, level, holdMs)
            % obj = teensy.Condition.digitalLevel(channel, level, holdMs)
            % Return a condition on a digital input level, optionally held.
            %
            % Parameters
            %   channel - Digital input channel name.
            %   level   - 0 or 1, after the channel's ActiveHigh polarity.
            %   holdMs  - How long the level must persist; literal or "@Var".
            %
            % Returns
            %   obj - teensy.Condition of Kind "DigitalLevel".
            arguments
                channel (1,1) string = ""
                level (1,1) double {mustBeMember(level, [0 1])} = 1
                holdMs = 0
            end

            obj = teensy.Condition("DigitalLevel", Channel = channel, Level = level, HoldMs = holdMs);
        end

        function obj = analogThreshold(channel, compare, threshold, holdMs)
            % obj = teensy.Condition.analogThreshold(channel, compare, threshold, holdMs)
            % Return a condition on a thresholded analog input.
            %
            % "Above" and "Below" test the current level; "CrossUp" and
            % "CrossDown" test the hysteretic crossing built from the channel's
            % ThresholdHigh and ThresholdLow.
            %
            % Parameters
            %   channel   - Analog input channel name.
            %   compare   - "Above", "Below", "CrossUp" or "CrossDown".
            %   threshold - Trip level in the channel's Units; literal or "@Var".
            %   holdMs    - How long the test must persist; literal or "@Var".
            %
            % Returns
            %   obj - teensy.Condition of Kind "AnalogThreshold".
            arguments
                channel (1,1) string = ""
                compare (1,1) string {mustBeMember(compare, ["Above","Below","CrossUp","CrossDown"])} = "Above"
                threshold = 2.5
                holdMs = 0
            end

            obj = teensy.Condition("AnalogThreshold", Channel = channel, ...
                Compare = compare, Threshold = threshold, HoldMs = holdMs);
        end

        function obj = counterReached(name, compareOp, count)
            % obj = teensy.Condition.counterReached(name, compareOp, count)
            % Return a condition on a counter's value.
            %
            % Parameters
            %   name      - Counter name declared on the program.
            %   compareOp - "GE", "GT", "LE", "LT" or "EQ".
            %   count     - Target value; literal or "@Var".
            %
            % Returns
            %   obj - teensy.Condition of Kind "Counter".
            arguments
                name (1,1) string = ""
                compareOp (1,1) string {mustBeMember(compareOp, ["GE","GT","LE","LT","EQ"])} = "GE"
                count = 1
            end

            obj = teensy.Condition("Counter", Counter = name, CompareOp = compareOp, Count = count);
        end

        function obj = probability(p)
            % obj = teensy.Condition.probability(p)
            % Return a condition that is true on a fraction p of evaluations.
            %
            % The firmware draws once per state entry, so a probability branch
            % chooses a path rather than flickering while the state runs.
            %
            % Parameters
            %   p - Probability in 0..1; literal or "@Var".
            %
            % Returns
            %   obj - teensy.Condition of Kind "Probability".
            arguments
                p = 0.5
            end

            obj = teensy.Condition("Probability", Probability = p);
        end

        function obj = all(conditions)
            % obj = teensy.Condition.all(conditions)
            % Return the AND of several conditions.
            %
            % A single condition is returned unchanged so callers can fold a
            % list without special-casing the one-element case.
            %
            % Parameters
            %   conditions - teensy.Condition array.
            %
            % Returns
            %   obj - teensy.Condition of Kind "And".
            arguments
                conditions (1,:) teensy.Condition = teensy.Condition.empty(1, 0)
            end

            if isscalar(conditions)
                obj = conditions;
                return
            end
            obj = teensy.Condition("And", Operands = conditions);
        end

        function obj = any(conditions)
            % obj = teensy.Condition.any(conditions)
            % Return the OR of several conditions.
            %
            % A single condition is returned unchanged so callers can fold a
            % list without special-casing the one-element case.
            %
            % Parameters
            %   conditions - teensy.Condition array.
            %
            % Returns
            %   obj - teensy.Condition of Kind "Or".
            arguments
                conditions (1,:) teensy.Condition = teensy.Condition.empty(1, 0)
            end

            if isscalar(conditions)
                obj = conditions;
                return
            end
            obj = teensy.Condition("Or", Operands = conditions);
        end

        function obj = negate(condition)
            % obj = teensy.Condition.negate(condition)
            % Return the logical negation of a condition.
            %
            % Negating a NOT unwraps it rather than nesting a second one.
            %
            % Parameters
            %   condition - teensy.Condition to invert.
            %
            % Returns
            %   obj - teensy.Condition of Kind "Not", or the unwrapped operand.
            arguments
                condition (1,1) teensy.Condition = teensy.Condition()
            end

            if condition.Kind == "Not" && ~isempty(condition.Operands)
                obj = condition.Operands(1);
                return
            end
            obj = teensy.Condition("Not", Operands = condition);
        end

        function code = kindCode(kind)
            % code = teensy.Condition.kindCode(kind)
            % Return the 0-based wire code for a leaf kind.
            %
            % Parameters
            %   kind - Condition kind.
            %
            % Returns
            %   code - 0-based index into LeafKinds, or -1 for an operator.
            arguments
                kind (1,1) string
            end

            idx = find(teensy.Condition.LeafKinds == kind, 1);
            if isempty(idx)
                code = -1;
            else
                code = idx - 1;
            end
        end

        function kind = kindName(code)
            % kind = teensy.Condition.kindName(code)
            % Return the leaf kind for a wire code.
            %
            % Parameters
            %   code - 0-based wire code.
            %
            % Returns
            %   kind - Matching kind, or "" when the code is out of range.
            arguments
                code (1,1) double
            end

            kinds = teensy.Condition.LeafKinds;
            if code < 0 || code >= numel(kinds) || code ~= floor(code)
                kind = "";
            else
                kind = kinds(code + 1);
            end
        end

        function obj = fromStruct(S)
            % obj = teensy.Condition.fromStruct(S)
            % Rebuild conditions, and their operand trees, from structs.
            %
            % Fields missing from an older save fall back to the current
            % defaults, and an unrecognised enumeration value is replaced by the
            % default rather than raising an error.
            %
            % Parameters
            %   S - Struct array from toStruct, or a teensy.Condition array.
            %
            % Returns
            %   obj - 1xN teensy.Condition.
            if isa(S, 'teensy.Condition')
                obj = reshape(S, 1, []);
                return
            end

            if ~isstruct(S) || isempty(S)
                obj = teensy.Condition.empty(1, 0);
                return
            end

            d = teensy.Condition();
            obj = teensy.Condition.empty(1, 0);

            for k = 1:numel(S)
                kind = pickMember_(teensy.getFieldOr(S(k), 'Kind', d.Kind), ...
                    [teensy.Condition.LeafKinds, teensy.Condition.OperatorKinds], d.Kind);
                c = teensy.Condition(kind);
                c.Channel = string(teensy.getFieldOr(S(k), 'Channel', d.Channel));
                c.Edge = pickMember_(teensy.getFieldOr(S(k), 'Edge', d.Edge), ...
                    ["Rising","Falling","Either"], d.Edge);
                c.Level = pickLevel_(teensy.getFieldOr(S(k), 'Level', d.Level), d.Level);
                c.Compare = pickMember_(teensy.getFieldOr(S(k), 'Compare', d.Compare), ...
                    ["Above","Below","CrossUp","CrossDown"], d.Compare);
                c.Threshold = refField_(S(k), 'Threshold', d.Threshold);
                c.HoldMs = refField_(S(k), 'HoldMs', d.HoldMs);
                c.Counter = string(teensy.getFieldOr(S(k), 'Counter', d.Counter));
                c.CompareOp = pickMember_(teensy.getFieldOr(S(k), 'CompareOp', d.CompareOp), ...
                    ["GE","GT","LE","LT","EQ"], d.CompareOp);
                c.Count = refField_(S(k), 'Count', d.Count);
                c.Timer = string(teensy.getFieldOr(S(k), 'Timer', d.Timer));
                c.Probability = refField_(S(k), 'Probability', d.Probability);
                c.Operands = teensy.Condition.fromStruct( ...
                    teensy.getFieldOr(S(k), 'Operands', struct([])));
                obj(end+1) = c;
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
    'Edge', "", ...
    'Level', 0, ...
    'Compare', "", ...
    'Threshold', 0, ...
    'HoldMs', 0, ...
    'Counter', "", ...
    'CompareOp', "", ...
    'Count', 0, ...
    'Timer', "", ...
    'Probability', 0, ...
    'Operands', {struct([])});
end


function tok = emptyTokenArray_()
% tok = emptyTokenArray_()
% Return the 1x0 token struct array that toPostfix grows.
tok = repmat(makeToken_("leaf", "Always", nan(1,4), zeros(1,4), ""), 1, 0);
end


function tok = makeToken_(op, kind, args, refs, text)
% tok = makeToken_(op, kind, args, refs, text)
% Build one postfix token with the canonical field order.
tok = struct('Op', string(op), 'Kind', string(kind), ...
    'Args', reshape(double(args), 1, 4), 'ArgRefs', reshape(double(refs), 1, 4), ...
    'Text', string(text));
end


function v = normalizeValueOrRef_(value, fieldName)
% v = normalizeValueOrRef_(value, fieldName)
% Accept a literal number or an "@Var" reference for a dual-typed field.
%
% A bare identifier is promoted to a reference, and text that parses as a
% number becomes a literal, so values typed into a GUI table behave sensibly.
if isnumeric(value) || islogical(value)
    if ~isscalar(value)
        error('teensy:Condition:BadValue', '%s must be a scalar.', fieldName);
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

error('teensy:Condition:BadValue', ...
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
% Return the dual-typed field names a given condition kind actually reads.
switch kind
    case "StateTimer"
        fields = "HoldMs";
    case "DigitalLevel"
        fields = "HoldMs";
    case "AnalogThreshold"
        fields = ["Threshold", "HoldMs"];
    case "Counter"
        fields = "Count";
    case "Probability"
        fields = "Probability";
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


function s = wireNum_(num, refIdx)
% s = wireNum_(num, refIdx)
% Format one wire argument as a literal or a "#<varIdx>" reference.
if refIdx > 0
    s = "#" + string(refIdx);
elseif refIdx < 0
    s = "#0";
else
    s = string(sprintf('%g', num));
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
% Check that a condition's channel exists and is an input of the right kind.
iss = teensy.issue();

if strlength(channelName) == 0
    iss(end+1) = teensy.issue("error", "Channel", ...
        "No channel selected.", Where = where, ...
        Remedy = sprintf("Pick a %s input channel.", lower(requiredKind)));
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

if ch.Direction ~= "Input"
    iss(end+1) = teensy.issue("error", "Channel", ...
        sprintf("'%s' is an output and cannot be tested.", channelName), Where = where, ...
        Remedy = "Conditions can only read input channels.");
end

if ch.Kind ~= requiredKind
    iss(end+1) = teensy.issue("error", "Channel", ...
        sprintf("'%s' is a %s channel but this condition needs a %s one.", ...
            channelName, lower(ch.Kind), lower(requiredKind)), Where = where, ...
        Remedy = "Pick a matching channel, or change the condition kind.");
end
end


function iss = listIssues_(program, listName, name, label, where)
% iss = listIssues_(program, listName, name, label, where)
% Check that a named counter or global timer is declared on the program.
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


function u = channelUnits_(program, channelName)
% u = channelUnits_(program, channelName)
% Return the engineering unit label for an analog channel.
%
% Without a program the Channel default "V" is assumed, which is what describe()
% needs to read naturally on its own.
u = "V";

if isempty(program) || strlength(channelName) == 0
    return
end

chans = programField_(program, 'Channels');
idx = indexOfName_(namesOf_(chans), channelName);
if idx > 0
    u = chans(idx).Units;
end
end


function tf = isLiteralZero_(value)
% tf = isLiteralZero_(value)
% True when a dual-typed field holds the literal 0 rather than a reference.
tf = ~teensy.isVarRef(value) && isnumeric(value) && isscalar(value) && value == 0;
end


function s = numText_(value)
% s = numText_(value)
% Format a dual-typed field for display: "2.5" or "@Level".
if teensy.isVarRef(value)
    s = string(value);
else
    s = string(sprintf('%g', value));
end
end


function s = msText_(value)
% s = msText_(value)
% Format a dual-typed duration for display: "50 ms" or "@HoldTime".
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


function w = compareWord_(compare)
% w = compareWord_(compare)
% Return the human phrase for an analog comparison.
switch compare
    case "Above"
        w = "above";
    case "Below"
        w = "below";
    case "CrossUp"
        w = "rises above";
    otherwise
        w = "falls below";
end
end


function s = opSymbol_(compareOp)
% s = opSymbol_(compareOp)
% Return the arithmetic symbol for a counter comparison.
switch compareOp
    case "GE"
        s = ">=";
    case "GT"
        s = ">";
    case "LE"
        s = "<=";
    case "LT"
        s = "<";
    otherwise
        s = "==";
end
end


function code = edgeCode_(edge)
% code = edgeCode_(edge)
% Return the wire code for a digital edge direction.
switch edge
    case "Rising"
        code = 0;
    case "Falling"
        code = 1;
    otherwise
        code = 2;
end
end


function code = compareCode_(compare)
% code = compareCode_(compare)
% Return the wire code for an analog comparison.
switch compare
    case "Above"
        code = 0;
    case "Below"
        code = 1;
    case "CrossUp"
        code = 2;
    otherwise
        code = 3;
end
end


function code = compareOpCode_(compareOp)
% code = compareOpCode_(compareOp)
% Return the wire code for a counter comparison.
switch compareOp
    case "GE"
        code = 0;
    case "GT"
        code = 1;
    case "LE"
        code = 2;
    case "LT"
        code = 3;
    otherwise
        code = 4;
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


function v = pickLevel_(value, default)
% v = pickLevel_(value, default)
% Coerce a stored 0/1 level, falling back when it is neither.
v = default;
if isnumeric(value) || islogical(value)
    d = double(value);
    if isscalar(d) && ismember(d, [0 1])
        v = d;
    end
end
end
