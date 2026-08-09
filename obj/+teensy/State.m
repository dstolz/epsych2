classdef State
    % obj = teensy.State()
    % obj = teensy.State(name, DurationMs=..., Transitions=..., Role=...)
    % One node of a trial contingency: what happens, and what leads away from it.
    %
    % On entry the board runs EntryActions and ORs RespCodeBits into the trial's
    % response code. It then evaluates Transitions in array order every tick and
    % takes the first whose condition is true, running ExitActions and then that
    % transition's own actions. A state with a finite DurationMs also has an
    % implicit state timer that teensy.Condition.timerElapsed tests.
    %
    % A terminal state ends the trial. Every program needs at least one that is
    % reachable, or a trial can never complete.
    %
    % Properties
    %   Name         - MATLAB identifier of at most 23 chars, unique in a program.
    %   Notes        - Free text shown in the inspector.
    %   DurationMs   - State timeout; literal or "@Var". Inf or 0 means no timer.
    %   EntryActions - teensy.Action array run on entry, in order.
    %   ExitActions  - teensy.Action array run on leaving, in order.
    %   Transitions  - teensy.Transition array; first match wins.
    %   IsTerminal   - When true, entering this state ends the trial.
    %   RespCodeBits - epsych.BitMask array OR'd into the response code on entry.
    %   Color        - 1x3 RGB fill for the state diagram node.
    %   Position     - 1x2 diagram position in axis units.
    %
    % Methods
    %   describe     - Short English text used as a list entry or a tooltip.
    %   targets      - Names of the states this one can reach.
    %   respMask     - RespCodeBits folded into one uint32 mask.
    %   channelsUsed - Channel names read or driven anywhere in the state.
    %   varsUsed     - Variable names referenced anywhere in the state.
    %   validate     - Check the state against a program.
    %   toStruct     - Serialize to a plain struct.
    %   defaultColor - (static) Colour-blind-safe fill for a state role.
    %   fromStruct   - (static) Rebuild from a struct written by toStruct.
    %
    % Example
    %   s = teensy.State("Cue", DurationMs=2000, Role="normal");
    %   s.EntryActions = teensy.Action.pulse("Sync", 5);
    %   s.Transitions = teensy.Transition.to("Reward", ...
    %       teensy.Condition.digitalEdge("Poke","Rising"));
    %
    % See also: teensy.Transition, teensy.Action, teensy.Condition

    properties
        Name (1,1) string = ""

        Notes (1,1) string = ""

        % Untyped on purpose: a literal double or an "@Var" reference string.
        % Inf (the default) and 0 both mean "no state timer".
        DurationMs = Inf

        EntryActions (1,:) teensy.Action = teensy.Action.empty(1, 0)

        ExitActions (1,:) teensy.Action = teensy.Action.empty(1, 0)

        Transitions (1,:) teensy.Transition = teensy.Transition.empty(1, 0)

        IsTerminal (1,1) logical = false

        RespCodeBits (1,:) epsych.BitMask = epsych.BitMask.empty(1, 0)

        % Equal to teensy.State.defaultColor("normal"); see that method for the
        % palette and why the colours are tinted.
        Color (1,3) double {mustBeInRange(Color, 0, 1)} = 0.45 * ([191 191 191] / 255) + 0.55

        Position (1,2) double = [0 0]
    end

    methods
        function obj = State(name, options)
            % obj = teensy.State(name, Name=Value)
            % Construct one state. Every argument is optional so the class works
            % as an array element and as ClassName.empty.
            %
            % Parameters
            %   name       - State name.
            %   Role       - "start", "normal", "terminal", "reward", "punish" or
            %       "iti". Sets Color from the palette; an explicit Color wins.
            %   Name=Value - Any property may be set by name.
            %
            % Returns
            %   obj - Configured teensy.State.
            arguments
                name (1,1) string = ""
                options.Notes (1,1) string
                options.DurationMs
                options.EntryActions (1,:) teensy.Action
                options.ExitActions (1,:) teensy.Action
                options.Transitions (1,:) teensy.Transition
                options.IsTerminal (1,1) logical
                options.RespCodeBits (1,:) epsych.BitMask
                options.Color (1,3) double {mustBeInRange(options.Color, 0, 1)}
                options.Position (1,2) double
                options.Role (1,1) string {mustBeMember(options.Role, ...
                    ["start","normal","terminal","reward","punish","iti"])}
            end

            obj.Name = name;

            % Role is a constructor convenience rather than a property, so apply
            % it first and let an explicit Color override it.
            if isfield(options, 'Role')
                obj.Color = teensy.State.defaultColor(options.Role);
                options = rmfield(options, 'Role');
            end

            fn = fieldnames(options);
            for i = 1:numel(fn)
                obj.(fn{i}) = options.(fn{i});
            end
        end

        function obj = set.DurationMs(obj, value)
            obj.DurationMs = normalizeValueOrRef_(value, 'DurationMs');
        end

        function s = describe(obj)
            % s = obj.describe()
            % Return short English text for the state list or a tooltip.
            %
            % Returns
            %   s - Scalar string, e.g. "Cue (2000 ms, 2 ways out)".
            arguments
                obj (1,1) teensy.State
            end

            s = nameOrPlaceholder_(obj.Name, "state");

            parts = strings(1, 0);
            if hasStateTimer_(obj.DurationMs)
                parts(end+1) = msText_(obj.DurationMs);
            end
            if obj.IsTerminal
                parts(end+1) = "terminal";
            end
            n = numel(obj.Transitions);
            if n == 1
                parts(end+1) = "1 way out";
            elseif n > 1
                parts(end+1) = sprintf("%d ways out", n);
            end

            if ~isempty(parts)
                s = s + " (" + strjoin(parts, ", ") + ")";
            end
        end

        function names = targets(obj)
            % names = obj.targets()
            % Return the names of the states these states can reach.
            %
            % A transition that stays in place contributes nothing.
            %
            % Returns
            %   names - 1xN unique string array in first-use order.
            arguments
                obj (1,:) teensy.State
            end

            names = strings(1, 0);
            for k = 1:numel(obj)
                for i = 1:numel(obj(k).Transitions)
                    target = obj(k).Transitions(i).Target;
                    if strlength(target) > 0
                        names(end+1) = target;
                    end
                end
            end
            names = reshape(unique(names, 'stable'), 1, []);
        end

        function mask = respMask(obj)
            % mask = obj.respMask()
            % Fold RespCodeBits into one uint32 response mask.
            %
            % Bit index n sets 2^(n-1), matching epsych.BitMask.Bits2Mask.
            %
            % Returns
            %   mask - Scalar uint32.
            arguments
                obj (1,:) teensy.State
            end

            mask = uint32(0);
            for k = 1:numel(obj)
                b = double(obj(k).RespCodeBits);
                b = b(b >= 1 & b <= 32);
                for i = 1:numel(b)
                    mask = bitor(mask, bitshift(uint32(1), b(i) - 1));
                end
            end
        end

        function names = channelsUsed(obj)
            % names = obj.channelsUsed()
            % Return every channel name read or driven anywhere in these states.
            %
            % Returns
            %   names - 1xN unique string array in first-use order.
            arguments
                obj (1,:) teensy.State
            end

            names = strings(1, 0);
            for k = 1:numel(obj)
                names = [names, obj(k).EntryActions.channelsUsed()];
                names = [names, obj(k).ExitActions.channelsUsed()];
                names = [names, obj(k).Transitions.channelsUsed()];
            end
            names = reshape(unique(names, 'stable'), 1, []);
        end

        function names = varsUsed(obj)
            % names = obj.varsUsed()
            % Return every variable name referenced anywhere in these states.
            %
            % Returns
            %   names - 1xN unique string array in first-use order.
            arguments
                obj (1,:) teensy.State
            end

            names = strings(1, 0);
            for k = 1:numel(obj)
                [tf, name] = teensy.isVarRef(obj(k).DurationMs);
                if tf
                    names(end+1) = name;
                end
                names = [names, obj(k).EntryActions.varsUsed()];
                names = [names, obj(k).ExitActions.varsUsed()];
                names = [names, obj(k).Transitions.varsUsed()];
            end
            names = reshape(unique(names, 'stable'), 1, []);
        end

        function iss = validate(obj, program, options)
            % iss = obj.validate()
            % iss = obj.validate(program, Where=where)
            % Check this state, its actions and all of its transitions.
            %
            % Reachability and duplicate-name checks span the whole program and
            % belong to teensy.Program.validate; what is checked here is the
            % state on its own.
            %
            % Parameters
            %   program - Owning teensy.Program. Without it the checks that need
            %       cross-references are skipped.
            %   Where   - Location text carried into every issue. Defaults to
            %       "State '<Name>'".
            %
            % Returns
            %   iss - 1xN issue struct array; see teensy.issue.
            arguments
                obj (1,1) teensy.State
                program = []
                options.Where (1,1) string = ""
            end

            where = options.Where;
            if strlength(where) == 0
                where = sprintf("State '%s'", obj.Name);
            end

            iss = teensy.issue();
            iss = [iss, obj.validateName_(where)];
            iss = [iss, obj.validateFlow_(program, where)];
            iss = [iss, obj.validateProbabilities_(where)];

            for i = 1:numel(obj.EntryActions)
                iss = [iss, obj.EntryActions(i).validate(program, ...
                    Where = sprintf("%s entry action %d", where, i))];
            end

            for i = 1:numel(obj.ExitActions)
                iss = [iss, obj.ExitActions(i).validate(program, ...
                    Where = sprintf("%s exit action %d", where, i))];
            end

            for i = 1:numel(obj.Transitions)
                iss = [iss, obj.Transitions(i).validate(program, ...
                    Where = sprintf("%s transition %d", where, i))];
            end
        end

        function S = toStruct(obj)
            % S = obj.toStruct()
            % Serialize states, including actions, transitions and condition trees.
            %
            % RespCodeBits are stored as numeric indices so the struct survives a
            % MAT or JSON round-trip without the enumeration class.
            %
            % Returns
            %   S - Struct array shaped like obj with one field per property.
            arguments
                obj teensy.State
            end

            S = repmat(templateStruct_(), size(obj));
            for k = 1:numel(obj)
                S(k).Name = obj(k).Name;
                S(k).Notes = obj(k).Notes;
                S(k).DurationMs = obj(k).DurationMs;
                S(k).EntryActions = obj(k).EntryActions.toStruct();
                S(k).ExitActions = obj(k).ExitActions.toStruct();
                S(k).Transitions = obj(k).Transitions.toStruct();
                S(k).IsTerminal = obj(k).IsTerminal;
                S(k).RespCodeBits = reshape(double(obj(k).RespCodeBits), 1, []);
                S(k).Color = obj(k).Color;
                S(k).Position = obj(k).Position;
            end
        end
    end

    methods (Access = private)
        function iss = validateName_(obj, where)
            % iss = obj.validateName_(where)
            % Check that the state name is usable on the wire.
            iss = teensy.issue();

            if strlength(obj.Name) == 0
                iss(end+1) = teensy.issue("error", "Name", ...
                    "State has no name.", Where = where, ...
                    Remedy = "Give the state a short name such as Cue or Reward.");
            elseif ~isvarname(char(obj.Name))
                iss(end+1) = teensy.issue("error", "Name", ...
                    sprintf("'%s' is not a valid state name.", obj.Name), Where = where, ...
                    Remedy = "Use a letter followed by letters, digits or underscores.");
            elseif strlength(obj.Name) > 23
                iss(end+1) = teensy.issue("error", "Name", ...
                    sprintf("'%s' is longer than the 23 character wire limit.", obj.Name), ...
                    Where = where, Remedy = "Shorten the name.");
            end
        end

        function iss = validateFlow_(obj, program, where)
            % iss = obj.validateFlow_(program, where)
            % Check the duration, the terminal flag and the ways out of the state.
            iss = teensy.issue();

            [isRef, refName] = teensy.isVarRef(obj.DurationMs);
            if ~isRef && obj.DurationMs < 0
                iss(end+1) = teensy.issue("error", "Duration", ...
                    sprintf("A duration of %g ms is negative.", obj.DurationMs), Where = where, ...
                    Remedy = "Use Inf for a state with no timer.");
            elseif isRef && ~isempty(program) && ...
                    indexOfName_(namesOf_(programField_(program, 'Variables')), refName) == 0
                iss(end+1) = teensy.issue("error", "Variable", ...
                    sprintf("DurationMs refers to undefined variable '%s'.", refName), ...
                    Where = where, ...
                    Remedy = "Add the variable on the Variables tab, or enter a literal duration.");
            end

            leaves = 0;
            for i = 1:numel(obj.Transitions)
                if strlength(obj.Transitions(i).Target) > 0
                    leaves = leaves + 1;
                end
            end

            if obj.IsTerminal
                if isempty(obj.RespCodeBits)
                    iss(end+1) = teensy.issue("warning", "RespCode", ...
                        "A terminal state with no response bits reports Undefined.", ...
                        Where = where, ...
                        Remedy = "Pick the outcome bits, such as Hit or Miss, for this ending.");
                end
                if leaves > 0
                    iss(end+1) = teensy.issue("warning", "Flow", ...
                        "A terminal state ends the trial, so its transitions never fire.", ...
                        Where = where, Remedy = "Clear IsTerminal, or delete the transitions.");
                end
                return
            end

            if leaves == 0 && ~hasStateTimer_(obj.DurationMs)
                iss(end+1) = teensy.issue("error", "Flow", ...
                    "This state has no way out: no transition to another state and no duration.", ...
                    Where = where, ...
                    Remedy = "Add a transition, set a duration, or mark the state terminal.");
            end

            % Everything after an unconditional transition is dead code.
            for i = 1:numel(obj.Transitions) - 1
                if obj.Transitions(i).Condition.Kind == "Always"
                    iss(end+1) = teensy.issue("warning", "Flow", ...
                        sprintf("Transition %d always fires, so the %d after it can never run.", ...
                            i, numel(obj.Transitions) - i), Where = where, ...
                        Remedy = "Move the unconditional transition to the end of the list.");
                    break
                end
            end
        end

        function iss = validateProbabilities_(obj, where)
            % iss = obj.validateProbabilities_(where)
            % Report probability branches whose literal weights do not add up.
            iss = teensy.issue();

            total = 0;
            n = 0;
            for i = 1:numel(obj.Transitions)
                c = obj.Transitions(i).Condition;
                if c.Kind == "Probability" && ~teensy.isVarRef(c.Probability)
                    total = total + c.Probability;
                    n = n + 1;
                end
            end

            if n >= 2 && total > 1
                iss(end+1) = teensy.issue("info", "Probability", ...
                    sprintf("The %d probability branches add up to %g.", n, total), ...
                    Where = where, ...
                    Remedy = "Branches are tried in order, so later ones fire less often than their weight.");
            end
        end
    end

    methods (Static)
        function rgb = defaultColor(role)
            % rgb = teensy.State.defaultColor(role)
            % Return the diagram fill colour for a state role.
            %
            % The hues come from the Okabe and Ito colour-blind-safe palette and
            % are tinted 55% toward white so black label text stays legible on a
            % filled node. No pair in the set relies on a red/green distinction.
            %
            % Parameters
            %   role - "start", "normal", "terminal", "reward", "punish" or "iti".
            %
            % Returns
            %   rgb - 1x3 RGB in 0..1.
            arguments
                role (1,1) string {mustBeMember(role, ...
                    ["start","normal","terminal","reward","punish","iti"])} = "normal"
            end

            switch role
                case "start"
                    base = [86 180 233];    % sky blue
                case "terminal"
                    base = [0 114 178];     % blue
                case "reward"
                    base = [0 158 115];     % bluish green
                case "punish"
                    base = [213 94 0];      % vermillion
                case "iti"
                    base = [230 159 0];     % orange
                otherwise
                    base = [191 191 191];   % neutral grey
            end

            rgb = 0.45 * (base / 255) + 0.55;
        end

        function obj = fromStruct(S)
            % obj = teensy.State.fromStruct(S)
            % Rebuild states, with their actions and transitions, from structs.
            %
            % Fields missing from an older save fall back to the current
            % defaults, and an out-of-range colour or bit index is dropped rather
            % than raising an error.
            %
            % Parameters
            %   S - Struct array from toStruct, or a teensy.State array.
            %
            % Returns
            %   obj - 1xN teensy.State.
            if isa(S, 'teensy.State')
                obj = reshape(S, 1, []);
                return
            end

            if ~isstruct(S) || isempty(S)
                obj = teensy.State.empty(1, 0);
                return
            end

            d = teensy.State();
            obj = teensy.State.empty(1, 0);

            for k = 1:numel(S)
                s = teensy.State(string(teensy.getFieldOr(S(k), 'Name', d.Name)));
                s.Notes = string(teensy.getFieldOr(S(k), 'Notes', d.Notes));
                s.DurationMs = refField_(S(k), 'DurationMs', d.DurationMs);
                s.EntryActions = teensy.Action.fromStruct( ...
                    teensy.getFieldOr(S(k), 'EntryActions', struct([])));
                s.ExitActions = teensy.Action.fromStruct( ...
                    teensy.getFieldOr(S(k), 'ExitActions', struct([])));
                s.Transitions = teensy.Transition.fromStruct( ...
                    teensy.getFieldOr(S(k), 'Transitions', struct([])));
                s.IsTerminal = logical(teensy.getFieldOr(S(k), 'IsTerminal', d.IsTerminal));
                s.RespCodeBits = bitsFromStored_(teensy.getFieldOr(S(k), 'RespCodeBits', []));
                s.Color = pickColor_(teensy.getFieldOr(S(k), 'Color', d.Color), d.Color);
                s.Position = pickPosition_(teensy.getFieldOr(S(k), 'Position', d.Position), d.Position);
                obj(end+1) = s;
            end
        end
    end
end


function S = templateStruct_()
% S = templateStruct_()
% Return the 1x1 serialization struct with the canonical field order.
S = struct( ...
    'Name', "", ...
    'Notes', "", ...
    'DurationMs', Inf, ...
    'EntryActions', {struct([])}, ...
    'ExitActions', {struct([])}, ...
    'Transitions', {struct([])}, ...
    'IsTerminal', false, ...
    'RespCodeBits', [], ...
    'Color', [0 0 0], ...
    'Position', [0 0]);
end


function tf = hasStateTimer_(durationMs)
% tf = hasStateTimer_(durationMs)
% True when a duration actually arms a state timer.
%
% Inf and 0 both mean "no timer"; a variable reference always arms one, because
% its value is not known until the trial runs.
if teensy.isVarRef(durationMs)
    tf = true;
    return
end
tf = isfinite(durationMs) && durationMs > 0;
end


function v = normalizeValueOrRef_(value, fieldName)
% v = normalizeValueOrRef_(value, fieldName)
% Accept a literal number or an "@Var" reference for a dual-typed field.
%
% A bare identifier is promoted to a reference, and text that parses as a
% number becomes a literal, so values typed into a GUI table behave sensibly.
if isnumeric(value) || islogical(value)
    if ~isscalar(value)
        error('teensy:State:BadValue', '%s must be a scalar.', fieldName);
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

error('teensy:State:BadValue', ...
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


function rgb = pickColor_(value, default)
% rgb = pickColor_(value, default)
% Coerce a stored colour to a valid 1x3 RGB, falling back when it is not.
rgb = default;
if ~isnumeric(value) || numel(value) ~= 3
    return
end
candidate = reshape(double(value), 1, 3);
if all(isfinite(candidate)) && all(candidate >= 0 & candidate <= 1)
    rgb = candidate;
end
end


function pos = pickPosition_(value, default)
% pos = pickPosition_(value, default)
% Coerce a stored diagram position to a valid 1x2 vector.
pos = default;
if ~isnumeric(value) || numel(value) ~= 2
    return
end
candidate = reshape(double(value), 1, 2);
if all(isfinite(candidate))
    pos = candidate;
end
end


function s = msText_(value)
% s = msText_(value)
% Format a dual-typed duration for display: "2000 ms" or "@Dur".
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
