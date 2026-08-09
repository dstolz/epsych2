classdef Variable
    % obj = teensy.Variable()
    % obj = teensy.Variable(name, Type=..., Value=..., Min=..., Max=...)
    % Named, per-trial-settable quantity that becomes an hw.Parameter.
    %
    % Variables are the seam between a compiled trial program and the EPsych
    % runtime. Any numeric field of a condition, an action or a state duration
    % may hold "@Name" instead of a literal, and the firmware then reads the
    % current value out of its variable table. teensy.Program.toParameters turns
    % each Variable into an hw.Parameter so the existing trial dispatcher,
    % protocol designer and runtime GUIs pick it up with no extra wiring.
    %
    % Properties
    %   Name             - MATLAB identifier of at most 23 chars.
    %   Type             - "Float", "Integer" or "Boolean".
    %   Value            - Default value used when a trial does not set one.
    %   Min, Max         - Inclusive bounds passed through to hw.Parameter.
    %   Units            - Unit label, e.g. "ms" or "dB".
    %   Description      - One line shown in the variables table and GUIs.
    %   UpdateEveryTrial - When true the runtime pushes it on every trial.
    %   Access           - "Any" (settable) or "Read" (reported by the board).
    %
    % Methods
    %   describe          - One-line human summary.
    %   coerce            - Clamp and round a value to this variable's type.
    %   toParameterSpec   - Arguments needed to build the matching hw.Parameter.
    %   validate          - Check the variable for self-consistency.
    %   toStruct          - Serialize to a plain struct.
    %   fromStruct        - (static) Rebuild from a struct written by toStruct.
    %
    % Example
    %   v = teensy.Variable("HoldTime", Type="Integer", Value=500, ...
    %       Min=100, Max=2000, Units="ms");
    %   c = teensy.Condition.digitalLevel("Poke", 1, teensy.varRef(v.Name));
    %
    % See also: teensy.varRef, teensy.isVarRef, hw.Parameter

    properties
        Name (1,1) string = ""

        Type (1,1) string {mustBeMember(Type, ["Float","Integer","Boolean"])} = "Float"

        Value (1,1) double = 0

        Min (1,1) double = -Inf

        Max (1,1) double = Inf

        Units (1,1) string = ""

        Description (1,1) string = ""

        UpdateEveryTrial (1,1) logical = true

        Access (1,1) string {mustBeMember(Access, ["Any","Read"])} = "Any"
    end

    methods
        function obj = Variable(name, options)
            % obj = teensy.Variable(name, Name=Value)
            % Construct a variable. Every argument is optional so the class works
            % as an array element and as ClassName.empty.
            %
            % Parameters
            %   name       - Variable name.
            %   Name=Value - Any property may be set by name.
            %
            % Returns
            %   obj - Configured teensy.Variable.
            arguments
                name (1,1) string = ""
                options.Type (1,1) string {mustBeMember(options.Type, ["Float","Integer","Boolean"])}
                options.Value (1,1) double
                options.Min (1,1) double
                options.Max (1,1) double
                options.Units (1,1) string
                options.Description (1,1) string
                options.UpdateEveryTrial (1,1) logical
                options.Access (1,1) string {mustBeMember(options.Access, ["Any","Read"])}
            end

            obj.Name = name;

            fn = fieldnames(options);
            for i = 1:numel(fn)
                obj.(fn{i}) = options.(fn{i});
            end
        end

        function s = describe(obj)
            % s = obj.describe()
            % Return a one-line summary for the variables table or a tooltip.
            %
            % Returns
            %   s - Scalar string, e.g. "HoldTime = 500 ms [100..2000]".
            arguments
                obj (1,1) teensy.Variable
            end

            if obj.Type == "Boolean"
                if obj.Value ~= 0
                    valueText = "true";
                else
                    valueText = "false";
                end
            else
                valueText = string(sprintf('%g', obj.Value));
            end

            s = obj.Name + " = " + valueText;
            if strlength(obj.Units) > 0
                s = s + " " + obj.Units;
            end
            if isfinite(obj.Min) || isfinite(obj.Max)
                s = s + sprintf(" [%g..%g]", obj.Min, obj.Max);
            end
            if obj.Access == "Read"
                s = s + " (read-only)";
            end
        end

        function value = coerce(obj, value)
            % value = obj.coerce(value)
            % Clamp a value into [Min, Max] and round it to this variable's type.
            %
            % The simulator and the compiler both use this so a value entered in
            % the GUI behaves exactly as the firmware would treat it.
            %
            % Parameters
            %   value - Candidate numeric value.
            %
            % Returns
            %   value - Coerced value.
            arguments
                obj (1,1) teensy.Variable
                value (1,1) double
            end

            value = min(max(value, obj.Min), obj.Max);

            switch obj.Type
                case "Integer"
                    value = round(value);
                case "Boolean"
                    value = double(value ~= 0);
            end
        end

        function spec = toParameterSpec(obj)
            % spec = obj.toParameterSpec()
            % Return everything hw.Module.add_parameter needs for this variable.
            %
            % UpdateEveryTrial is returned separately because add_parameter does
            % not accept it; assign it on the parameter that add_parameter
            % returns.
            %
            % Returns
            %   spec - Struct with fields:
            %       Name             - char name for add_parameter
            %       Value            - default value
            %       Options          - struct of add_parameter name-value options
            %       UpdateEveryTrial - logical to assign after creation
            %
            % Example
            %   spec = v.toParameterSpec();
            %   nv = namedargs2cell(spec.Options);
            %   P = module.add_parameter(spec.Name, spec.Value, nv{:});
            %   P.UpdateEveryTrial = spec.UpdateEveryTrial;
            arguments
                obj (1,1) teensy.Variable
            end

            options = struct( ...
                'Description', obj.Description, ...
                'Unit', char(obj.Units), ...
                'Access', char(obj.Access), ...
                'Type', char(obj.Type), ...
                'Min', obj.Min, ...
                'Max', obj.Max);

            spec = struct( ...
                'Name', char(obj.Name), ...
                'Value', obj.coerce(obj.Value), ...
                'Options', options, ...
                'UpdateEveryTrial', obj.UpdateEveryTrial);
        end

        function iss = validate(obj, program, options)
            % iss = obj.validate()
            % iss = obj.validate(program, Where=where)
            % Check the variable for self-consistency.
            %
            % Duplicate-name detection across the whole program belongs to
            % teensy.Program.validate; what is checked here is the variable on
            % its own, plus a readability warning when its name collides with a
            % channel name.
            %
            % Parameters
            %   program - Owning teensy.Program. Optional.
            %   Where   - Location text carried into every issue. Defaults to
            %       "Variable '<Name>'".
            %
            % Returns
            %   iss - 1xN issue struct array; see teensy.issue.
            arguments
                obj (1,1) teensy.Variable
                program = []
                options.Where (1,1) string = ""
            end

            where = options.Where;
            if strlength(where) == 0
                where = sprintf("Variable '%s'", obj.Name);
            end

            iss = teensy.issue();

            if strlength(obj.Name) == 0
                iss(end+1) = teensy.issue("error", "Name", ...
                    "Variable has no name.", Where = where, ...
                    Remedy = "Give the variable a short name such as HoldTime.");
            elseif ~isvarname(char(obj.Name))
                iss(end+1) = teensy.issue("error", "Name", ...
                    sprintf("'%s' is not a valid name.", obj.Name), Where = where, ...
                    Remedy = "Use a letter followed by letters, digits or underscores.");
            elseif strlength(obj.Name) > 23
                iss(end+1) = teensy.issue("error", "Name", ...
                    sprintf("'%s' is longer than the 23 character wire limit.", obj.Name), ...
                    Where = where, Remedy = "Shorten the name.");
            end

            if obj.Min > obj.Max
                iss(end+1) = teensy.issue("error", "Bounds", ...
                    sprintf("Min (%g) is above Max (%g).", obj.Min, obj.Max), ...
                    Where = where, Remedy = "Swap the two bounds.");
            elseif obj.Value < obj.Min || obj.Value > obj.Max
                iss(end+1) = teensy.issue("warning", "Bounds", ...
                    sprintf("The default %g is outside [%g, %g] and will be clamped.", ...
                        obj.Value, obj.Min, obj.Max), Where = where, ...
                    Remedy = "Move the default inside the bounds.");
            end

            if obj.Type == "Integer" && obj.Value ~= round(obj.Value)
                iss(end+1) = teensy.issue("warning", "Type", ...
                    sprintf("The default %g will be rounded to %g.", obj.Value, round(obj.Value)), ...
                    Where = where, Remedy = "Enter a whole number, or change Type to Float.");
            end

            if obj.Type == "Boolean" && ~ismember(obj.Value, [0 1])
                iss(end+1) = teensy.issue("error", "Type", ...
                    sprintf("A Boolean variable cannot default to %g.", obj.Value), ...
                    Where = where, Remedy = "Use 0 or 1.");
            end

            if obj.Access == "Read" && obj.UpdateEveryTrial
                iss(end+1) = teensy.issue("warning", "Access", ...
                    "A read-only variable cannot be written each trial.", Where = where, ...
                    Remedy = "Clear UpdateEveryTrial, or change Access to Any.");
            end

            if obj.Type ~= "Boolean" && ~isfinite(obj.Min) && ~isfinite(obj.Max)
                iss(end+1) = teensy.issue("info", "Bounds", ...
                    "No bounds are set, so the GUI cannot offer a slider.", ...
                    Where = where, Remedy = "Set Min and Max to the usable range.");
            end

            if ~isempty(program) && ismember(obj.Name, namesOf_(program.Channels))
                iss(end+1) = teensy.issue("warning", "Name", ...
                    sprintf("'%s' is also a channel name, which makes references hard to read.", obj.Name), ...
                    Where = where, Remedy = "Rename the variable or the channel.");
            end
        end

        function S = toStruct(obj)
            % S = obj.toStruct()
            % Serialize variables to a plain struct array for saving or undo.
            %
            % Returns
            %   S - Struct array shaped like obj with one field per property.
            arguments
                obj teensy.Variable
            end

            S = repmat(templateStruct_(), size(obj));
            for k = 1:numel(obj)
                S(k).Name = obj(k).Name;
                S(k).Type = obj(k).Type;
                S(k).Value = obj(k).Value;
                S(k).Min = obj(k).Min;
                S(k).Max = obj(k).Max;
                S(k).Units = obj(k).Units;
                S(k).Description = obj(k).Description;
                S(k).UpdateEveryTrial = obj(k).UpdateEveryTrial;
                S(k).Access = obj(k).Access;
            end
        end
    end

    methods (Static)
        function obj = fromStruct(S)
            % obj = teensy.Variable.fromStruct(S)
            % Rebuild variables from structs written by toStruct.
            %
            % Fields missing from an older save fall back to the current
            % defaults, and an unrecognised enumeration value is replaced by the
            % default rather than raising an error.
            %
            % Parameters
            %   S - Struct array from toStruct, or a teensy.Variable array.
            %
            % Returns
            %   obj - 1xN teensy.Variable.
            if isa(S, 'teensy.Variable')
                obj = reshape(S, 1, []);
                return
            end

            if ~isstruct(S) || isempty(S)
                obj = teensy.Variable.empty(1, 0);
                return
            end

            d = teensy.Variable();
            obj = teensy.Variable.empty(1, 0);

            for k = 1:numel(S)
                v = teensy.Variable(string(teensy.getFieldOr(S(k), 'Name', d.Name)));
                v.Type = pickMember_(teensy.getFieldOr(S(k), 'Type', d.Type), ...
                    ["Float","Integer","Boolean"], d.Type);
                v.Value = double(teensy.getFieldOr(S(k), 'Value', d.Value));
                v.Min = double(teensy.getFieldOr(S(k), 'Min', d.Min));
                v.Max = double(teensy.getFieldOr(S(k), 'Max', d.Max));
                v.Units = string(teensy.getFieldOr(S(k), 'Units', d.Units));
                v.Description = string(teensy.getFieldOr(S(k), 'Description', d.Description));
                v.UpdateEveryTrial = logical(teensy.getFieldOr(S(k), 'UpdateEveryTrial', d.UpdateEveryTrial));
                v.Access = pickMember_(teensy.getFieldOr(S(k), 'Access', d.Access), ...
                    ["Any","Read"], d.Access);
                obj(end+1) = v;
            end
        end
    end
end


function S = templateStruct_()
% S = templateStruct_()
% Return the 1x1 serialization struct with the canonical field order.
S = struct( ...
    'Name', "", ...
    'Type', "", ...
    'Value', 0, ...
    'Min', -Inf, ...
    'Max', Inf, ...
    'Units', "", ...
    'Description', "", ...
    'UpdateEveryTrial', true, ...
    'Access', "");
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


function names = namesOf_(items)
% names = namesOf_(items)
% Return the Name of every element of an object or struct array as a 1xN string.
if isempty(items)
    names = strings(1, 0);
    return
end
names = reshape(string({items.Name}), 1, []);
end
