classdef Transition
    % obj = teensy.Transition()
    % obj = teensy.Transition(target, Condition=..., Actions=..., Notes=...)
    % One guarded edge out of a state.
    %
    % A state's Transitions are evaluated in array order every firmware tick and
    % the FIRST one whose Condition is true wins; the rest are not even
    % evaluated. Order is therefore priority, which is why the GUI shows the
    % index and lets it be reordered.
    %
    % An empty Target means "stay in this state", which is how a transition can
    % fire Actions - count a lick, log an event, bump a counter - without leaving.
    %
    % Properties
    %   Condition - teensy.Condition guarding the edge.
    %   Target    - Destination state name, or "" to stay in the current state.
    %   Actions   - teensy.Action array fired as the edge is taken.
    %   Notes     - Free text shown in the transition table.
    %
    % Methods
    %   describe     - Short English text used as a diagram arrow label.
    %   channelsUsed - Channel names read or driven by this edge.
    %   varsUsed     - Variable names referenced by this edge.
    %   validate     - Check the edge against a program.
    %   toStruct     - Serialize to a plain struct.
    %   to           - (static) Build an edge to a target state.
    %   fromStruct   - (static) Rebuild from a struct written by toStruct.
    %
    % Example
    %   t = teensy.Transition.to("Reward", teensy.Condition.digitalEdge("Poke","Rising"), ...
    %       teensy.Action.pulse("Reward", 40));
    %   disp(t.describe())    % Poke rises -> Reward [pulse Reward 40 ms]
    %
    % See also: teensy.State, teensy.Condition, teensy.Action

    properties
        Condition (1,1) teensy.Condition = teensy.Condition()

        Target (1,1) string = ""

        Actions (1,:) teensy.Action = teensy.Action.empty(1, 0)

        Notes (1,1) string = ""
    end

    methods
        function obj = Transition(target, options)
            % obj = teensy.Transition(target, Name=Value)
            % Construct one transition. Every argument is optional so the class
            % works as an array element and as ClassName.empty.
            %
            % Parameters
            %   target     - Destination state name, or "" to stay.
            %   Name=Value - Condition, Actions or Notes may be set by name.
            %
            % Returns
            %   obj - Configured teensy.Transition.
            arguments
                target (1,1) string = ""
                options.Condition (1,1) teensy.Condition
                options.Actions (1,:) teensy.Action
                options.Notes (1,1) string
            end

            obj.Target = target;

            fn = fieldnames(options);
            for i = 1:numel(fn)
                obj.(fn{i}) = options.(fn{i});
            end
        end

        function s = describe(obj, program)
            % s = obj.describe()
            % s = obj.describe(program)
            % Return short English text for a diagram arrow or a table cell.
            %
            % Parameters
            %   program - Owning teensy.Program, passed through to the condition
            %       so analog units are shown correctly.
            %
            % Returns
            %   s - Scalar string, e.g. "Poke rises -> Reward [pulse Reward 40 ms]".
            arguments
                obj (1,1) teensy.Transition
                program = []
            end

            if strlength(obj.Target) == 0
                targetText = "stay";
            else
                targetText = obj.Target;
            end

            s = obj.Condition.describe(program) + " -> " + targetText;

            if ~isempty(obj.Actions)
                parts = strings(1, numel(obj.Actions));
                for i = 1:numel(obj.Actions)
                    parts(i) = obj.Actions(i).describe();
                end
                s = s + " [" + strjoin(parts, "; ") + "]";
            end
        end

        function names = channelsUsed(obj)
            % names = obj.channelsUsed()
            % Return every channel name read or driven by these transitions.
            %
            % Returns
            %   names - 1xN unique string array in first-use order.
            arguments
                obj (1,:) teensy.Transition
            end

            names = strings(1, 0);
            for k = 1:numel(obj)
                names = [names, obj(k).Condition.channelsUsed()];
                names = [names, obj(k).Actions.channelsUsed()];
            end
            names = reshape(unique(names, 'stable'), 1, []);
        end

        function names = varsUsed(obj)
            % names = obj.varsUsed()
            % Return every variable name referenced by these transitions.
            %
            % Returns
            %   names - 1xN unique string array in first-use order.
            arguments
                obj (1,:) teensy.Transition
            end

            names = strings(1, 0);
            for k = 1:numel(obj)
                names = [names, obj(k).Condition.varsUsed()];
                names = [names, obj(k).Actions.varsUsed()];
            end
            names = reshape(unique(names, 'stable'), 1, []);
        end

        function iss = validate(obj, program, options)
            % iss = obj.validate()
            % iss = obj.validate(program, Where=where)
            % Check the target, the condition and the actions of this edge.
            %
            % Parameters
            %   program - Owning teensy.Program. Without it the target cannot be
            %       resolved, so that check is skipped.
            %   Where   - Location text carried into every issue, e.g.
            %       "State 'Cue' transition 2".
            %
            % Returns
            %   iss - 1xN issue struct array; see teensy.issue.
            arguments
                obj (1,1) teensy.Transition
                program = []
                options.Where (1,1) string = ""
            end

            where = options.Where;
            if strlength(where) == 0
                where = "Transition";
            end

            iss = teensy.issue();

            if strlength(obj.Target) > 0
                if ~isvarname(char(obj.Target))
                    iss(end+1) = teensy.issue("error", "Target", ...
                        sprintf("'%s' is not a valid state name.", obj.Target), Where = where, ...
                        Remedy = "State names must be MATLAB identifiers.");
                elseif ~isempty(program) && ...
                        indexOfName_(namesOf_(programField_(program, 'States')), obj.Target) == 0
                    iss(end+1) = teensy.issue("error", "Target", ...
                        sprintf("There is no state named '%s'.", obj.Target), Where = where, ...
                        Remedy = "Point the transition at an existing state, or add that state.");
                end
            elseif isempty(obj.Actions)
                iss(end+1) = teensy.issue("warning", "Target", ...
                    "This transition stays in the state and does nothing.", Where = where, ...
                    Remedy = "Give it a target state, or add an action such as a counter increment.");
            end

            iss = [iss, obj.Condition.validate(program, Where = where)];

            for i = 1:numel(obj.Actions)
                iss = [iss, obj.Actions(i).validate(program, ...
                    Where = sprintf("%s action %d", where, i))];
            end
        end

        function S = toStruct(obj)
            % S = obj.toStruct()
            % Serialize transitions, including their condition trees and actions.
            %
            % Returns
            %   S - Struct array shaped like obj with one field per property.
            arguments
                obj teensy.Transition
            end

            S = repmat(templateStruct_(), size(obj));
            for k = 1:numel(obj)
                S(k).Condition = obj(k).Condition.toStruct();
                S(k).Target = obj(k).Target;
                S(k).Actions = obj(k).Actions.toStruct();
                S(k).Notes = obj(k).Notes;
            end
        end
    end

    methods (Static)
        function obj = to(target, condition, actions)
            % obj = teensy.Transition.to(target, condition, actions)
            % Build one edge to a target state.
            %
            % Parameters
            %   target    - Destination state name, or "" to stay.
            %   condition - teensy.Condition guarding the edge. Defaults to
            %       Always, which makes an unconditional edge.
            %   actions   - teensy.Action array fired as the edge is taken.
            %
            % Returns
            %   obj - Configured teensy.Transition.
            arguments
                target (1,1) string = ""
                condition (1,1) teensy.Condition = teensy.Condition.always()
                actions (1,:) teensy.Action = teensy.Action.empty(1, 0)
            end

            obj = teensy.Transition(target, Condition = condition, Actions = actions);
        end

        function obj = fromStruct(S)
            % obj = teensy.Transition.fromStruct(S)
            % Rebuild transitions from structs written by toStruct.
            %
            % Fields missing from an older save fall back to the current
            % defaults, so a program written before Notes existed still loads.
            %
            % Parameters
            %   S - Struct array from toStruct, or a teensy.Transition array.
            %
            % Returns
            %   obj - 1xN teensy.Transition.
            if isa(S, 'teensy.Transition')
                obj = reshape(S, 1, []);
                return
            end

            if ~isstruct(S) || isempty(S)
                obj = teensy.Transition.empty(1, 0);
                return
            end

            d = teensy.Transition();
            obj = teensy.Transition.empty(1, 0);

            for k = 1:numel(S)
                t = teensy.Transition(string(teensy.getFieldOr(S(k), 'Target', d.Target)));

                cond = teensy.Condition.fromStruct( ...
                    teensy.getFieldOr(S(k), 'Condition', struct([])));
                if isempty(cond)
                    t.Condition = teensy.Condition.always();
                else
                    t.Condition = cond(1);
                end

                t.Actions = teensy.Action.fromStruct( ...
                    teensy.getFieldOr(S(k), 'Actions', struct([])));
                t.Notes = string(teensy.getFieldOr(S(k), 'Notes', d.Notes));
                obj(end+1) = t;
            end
        end
    end
end


function S = templateStruct_()
% S = templateStruct_()
% Return the 1x1 serialization struct with the canonical field order.
S = struct( ...
    'Condition', {struct([])}, ...
    'Target', "", ...
    'Actions', {struct([])}, ...
    'Notes', "");
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
