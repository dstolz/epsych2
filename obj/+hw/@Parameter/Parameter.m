classdef Parameter < matlab.mixin.SetGet
    % obj = hw.Parameter(Parent)
    % obj = hw.Parameter(Parent, Name=Value)
    % Represent a hardware or software parameter exposed to EPsych.
    %
    % A Parameter stores metadata used by GUIs and experiment code together
    % with a current Value. For software-backed parents, Value can be stored
    % locally. For hardware-backed parents, reads and writes delegate to the
    % parent interface.
    %
    % Parameters
    %   Parent - Parent object that owns the parameter and implements the
    %       backing read/write operations.
    %   Name=Value - Optional metadata and behavior settings including Name,
    %       Description, Unit, Access, Type, Format, callbacks, and bounds.
    %
    % Properties
    %   Name, Description, Unit, Module - Display and grouping metadata.
    %   Access, Type, Format, Visible - Access rules and display behavior.
    %   UpdateEveryTrial - When true, the runtime trial dispatcher refreshes
    %       this parameter on every trial; when false, it is left unchanged.
    %   Value, ValueStr, lastUpdated - Current value and display state.
    %   PreUpdateFcnEnabled, EvaluatorFcnEnabled, PostUpdateFcnEnabled -
    %       Callback enable flags.
    %   isArray, isTrigger, isRandom, Min, Max - Runtime flags and bounds.
    %
    % Methods
    %   Parameter - Construct and initialize a parameter instance.
    %   toStruct - Serialize parameter metadata and value to a struct.
    %   fromStruct - Apply serialized parameter data to this instance.
    %   toJSON - Serialize this parameter to a pretty-printed JSON string.
    %   Trigger - Trigger the associated hardware event when enabled.
    %
    % Example
    %   p = hw.Parameter(parent, Name='PulseWidth', Unit='ms', ...
    %       Type='Float', Min=0, Max=50);
    %   p.Value = 10;
    %   disp(p.ValueStr)
    %
    % See also: documentation/hw/hw_Parameter.md

    properties (SetAccess = immutable)
        Parent (1,1) % handle to parent object (hw.Module)
        HW (1,1)  % handle to hardware interface; reflects parent object's handle
    end

    properties
        handle (1,1) % handle to an associated gui object

        Name    (1,:) char = 'Param' % name of parameter


        Description (1,1) string = ""; % short description of parameter
        Unit    (1,:) char = ''; % unit string (e.g., 'V', 'ms', etc.)
        Module  (1,1) % handle to module object that this parameter belongs to

        Access  (1,:) char {mustBeMember(Access,{'Read','Write','Any','Read / Write'})} = 'Any'
        Type    (1,:) char {mustBeMember(Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','File','Undefined','StimType'})} = 'Float'
        Format  (1,:) char = '%g' % default format for displaying value

        Visible (1,1) logical = true % optionally hide parameter

        UpdateEveryTrial (1,1) logical = true % when true, epsych.Runtime.dispatchNextTrial updates this parameter each trial; when false, it is set once and left unchanged across trials

        Values (1,:) cell = {} % design-time trial levels; one cell element per level; set via add_parameter; expanded by compile()

        PreUpdateFcn = [] % handle ot custom function called before value has been updated
                            % note that this gets called prior to the
                            % EvaluatorFcn

        EvaluatorFcn = [] % handle to custom function to handle evaluation of updated values

        PostUpdateFcn = [] % handle to custom function called after value has been updated

        PreUpdateFcnEnabled (1,1) logical = true % flag to enable or disable PreUpdateFcn without removing the function handle
        EvaluatorFcnEnabled (1,1) logical = true % flag to enable or disable EvaluatorFcn without removing the function handle
        PostUpdateFcnEnabled (1,1) logical = true % flag to enable or disable PostUpdateFcn without removing the function handle

        % Cell array of optional extra arguments passed to PreUpdateFcn, EvaluatorFcn, and PostUpdateFcn
        PreUpdateFcnArgs (1,:) cell = {} % optional extra arguments passed to PreUpdateFcn
        EvaluatorFcnArgs (1,:) cell = {} % optional extra arguments passed to EvaluatorFcn
        PostUpdateFcnArgs (1,:) cell = {} % optional extra arguments passed to PostUpdateFcn

        UserData % general-purpose field for storing any additional data related to the parameter

        % MATLAB expression string evaluated just before EvaluatorFcn to derive Value.
        % Must be a single expression (no assignments, no ';') whose result becomes
        % the new value, e.g. "1000 / FreqHz". The incoming value is available as the
        % variable `Value`; same-module parameters by their Name; cross-module
        % parameters as ModuleName.ParamName; properties as Param.Prop or
        % ModuleName.Param.Prop (Prop: Min, Max, Values, Value). Skipped at runtime
        % when the parameter has more than one design-time level (numel(Values) > 1).
        % For 'String' and 'StimType' parameters the result is instead a 1-based
        % index that selects one of the items in Values, so those types stay live
        % with many items; see hw.Parameter.expressionSelectsIndex.
        % Leave empty ("") to skip expression evaluation.
        Expression (1,1) string = ""
    end

    properties (SetObservable,GetObservable)
        Value % current/settable value of parameter
        % convert to datetime: dt = datetime(obj.lastUpdated, 'ConvertFrom','datenum', 'TimeZone','local');
        % convert to ms: ts = uint64((obj.lastUpdated - 719529) * 86400 * 1000);

    end

    properties (SetObservable,GetObservable,AbortSet)
        lastUpdated (1,1) double = 0;

        isArray     (1,1) logical = false
        isTrigger   (1,1) logical = false
        isRandom    (1,1) logical = false

        Min (1,1) double = -inf % minimum valid value
        Max (1,1) double = inf % maximum valid value
        BoundsInclusive (1,2) logical = [true true] % whether Min [1] and Max [2] bounds are inclusive
    end

    properties (Dependent)
        ValueStr % string representation of Value based on Format
        validName % valid MATLAB variable name based on Name
        FullName  % full name including parent module (e.g., "ModuleName.ParamName");
    end

    methods (Static)
        values = normalizeValues(value) % convert any value type to a uniform 1xN cell array of trial levels

        % Shared expression-evaluation core used by the runtime (set.Value) and
        % design-time tools (Protocol Designer calculation checker)
        [rewrittenText, context, info] = resolveExpressionContext(expressionText, currentValue, targetParam, siblingsFcn, allParamsFcn, valueFcn)
        result = evalExpressionInContext(rewrittenText, context, targetName)
        order = orderByDependencies(dispatchParams, allParams) % permutation placing expression parameters after the dispatched parameters whose values they read
        tf = expressionSelectsIndex(type) % true when an Expression on this Type indexes into Values instead of producing the value
        tf = isTransientControl(P) % true when the value is live session-control state (trigger or operator toggle) that a phase load must not restore
        [item, index] = selectValueByIndex(result, values, paramName) % validate an index-valued expression result and return the selected item
    end

    methods
        S = toStruct(obj)           % serialize this parameter to a struct
        fromStruct(obj, S, restoreValue) % restore this parameter from a struct; restoreValue (default true) controls whether Value is also restored
        jsonText = toJSON(obj)      % serialize this parameter to a JSON string

        function obj = Parameter(Parent, options)
            % obj = hw.Parameter(Parent)
            % obj = hw.Parameter(Parent, Name=Value)
            % Construct a parameter and initialize its metadata and behavior.
            %
            % Parameters
            %   Parent - Parent object that provides the backing hardware or
            %       software interface.
            %   Name=Value - Optional constructor settings for metadata,
            %       callbacks, callback enable flags, visibility, and bounds.
            %
            % Returns
            %   obj - Configured hw.Parameter instance.
            arguments
                Parent (1,1)
                options.Name (1,:) char = 'Param'
                options.Description (1,1) string = ""
                options.Unit (1,:) char = ''
                options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Any','Read / Write'})} = 'Any'
                options.Type (1,:) char {mustBeMember(options.Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','File','Undefined','StimType'})} = 'Float'
                options.Format (1,:) char = '%g'
                options.Visible (1,1) logical = true
                options.UpdateEveryTrial (1,1) logical % default: true, or false for trigger parameters; see below
                options.PreUpdateFcnEnabled (1,1) logical = true
                options.EvaluatorFcnEnabled (1,1) logical = true
                options.PostUpdateFcnEnabled (1,1) logical = true
                options.UserData = []
                options.isArray (1,1) logical = false
                options.isTrigger (1,1) logical = false
                options.isRandom (1,1) logical = false
                options.Min (1,1) double = -inf
                options.Max (1,1) double = inf
            end

            obj.Parent = Parent;
            if ~isempty(Parent.HW)
                obj.HW = Parent.HW;
            end

            % Set all provided options
            obj.Name = options.Name;
            obj.Description = options.Description;
            obj.Unit = options.Unit;
            obj.Access = normalizeLegacyAccess(options.Access);
            obj.Type = options.Type;
            obj.Format = options.Format;
            obj.Visible = options.Visible;
            obj.PreUpdateFcnEnabled = options.PreUpdateFcnEnabled;
            obj.EvaluatorFcnEnabled = options.EvaluatorFcnEnabled;
            obj.PostUpdateFcnEnabled = options.PostUpdateFcnEnabled;
            obj.UserData = options.UserData;
            obj.Min = options.Min;
            obj.Max = options.Max;
            obj.isArray = options.isArray;
            obj.isTrigger = options.isTrigger; % set.isTrigger defaults UpdateEveryTrial to false for triggers
            obj.isRandom = options.isRandom;

            % An explicit UpdateEveryTrial always wins over the isTrigger-based default.
            if isfield(options, 'UpdateEveryTrial')
                obj.UpdateEveryTrial = options.UpdateEveryTrial;
            end
        end

        % function disp(obj)
        %     fprintf('Module "%s" (%d)\t%s = %s\n', ...
        %         obj.Parent.Name,obj.Parent.Index, ...
        %         obj.Name, obj.ValueStr);
        % end

        function v = get.Value(obj)
            if isequal(obj.Access,'Write')
                vprintf(0,1,'"%s" is a write-only parameter',obj.Name)
                v = nan;
                return
            end

            % 'StimType' reads locally on every backend. The write sends the
            % stimulus down and the device keeps whatever it took from it —
            % samples in a buffer, at best — so a hardware read would return
            % that derived data, not the stimulus. The object is host-side
            % state; this parameter is where it lives.
            if isequal(obj.Type,'StimType') || isa(obj.Parent,'hw.Software') ...
                    || (isprop(obj.Parent, 'IsConnected') && ~obj.Parent.IsConnected)
                v = obj.Value;
            else
                try
                    v = obj.Parent.get_parameter(obj,includeInvisible=true);
                catch ME
                    if strcmp(ME.identifier, 'MATLAB:TooManyInputs') || contains(ME.message, 'Too many input arguments')
                        % Backward-compatible fallback for legacy interface implementations.
                        v = obj.Parent.get_parameter(obj);
                    else
                        rethrow(ME)
                    end
                end
            end

            if isnumeric(v)
                v = double(v);
            end
        end

        function M = get.Module(obj)
            if ~(isempty(obj.Module) || isequal(obj.Module,0))
                M = obj.Module;
                return
            end

            if isa(obj.Parent, 'hw.Module')
                M = obj.Parent;
                obj.Module = M;
                return
            end

            if isprop(obj.Parent, 'Module')
                parentModules = obj.Parent.Module;
                if isscalar(parentModules)
                    M = parentModules;
                    obj.Module = M;
                    return
                end

                matchMask = false(1, numel(parentModules));
                for moduleIdx = 1:numel(parentModules)
                    moduleParameters = parentModules(moduleIdx).Parameters;
                    if any(arrayfun(@(p) isequal(p, obj), moduleParameters))
                        matchMask(moduleIdx) = true;
                    end
                end

                if nnz(matchMask) == 1
                    M = parentModules(find(matchMask, 1, 'first'));
                    obj.Module = M;
                    return
                end
            end

            error('hw:Parameter:ModuleUnresolved', ...
                'Could not resolve owner module for parameter "%s".', obj.Name);
        end

        function fn = get.FullName(obj)
            M = obj.Module;
            if ~isempty(M) && ~isequal(M,0)
                fn = sprintf('%s.%s', M.Name, obj.Name);
            else
                fn = obj.Name;
            end
        end

        function Trigger(obj)
            % obj.Trigger()
            % Trigger the parent event associated with this parameter.
            %
            % Trigger only performs an action when isTrigger is true. On
            % success, lastUpdated is set from the parent trigger call.
            if ~obj.isTrigger
                vprintf(0,'"%s" is not recognized as a trigger',obj.Name)
                return
            end

            obj.lastUpdated = obj.Parent.trigger(obj);
            vprintf(3,'%s triggered',obj.Name)

        end

        function set.Value(obj,value)
            if isequal(obj.Access, 'Read')
                error('hw:Parameter:WriteAccessViolation', ...
                    'Cannot set value of read-only parameter "%s".', obj.Name);
            end
            
            % An index-selecting expression replaces the incoming value with an
            % item from Values, so a bare index may legitimately be assigned to a
            % StimType parameter; check the resolved value instead of the input.
            selectsIndex = strlength(obj.Expression) > 0 && hw.Parameter.expressionSelectsIndex(obj.Type);

            if ~selectsIndex
                obj.validateStimTypeValue_(value);
            end

            obj.execute_PreUpdateFcn(value);

            value = obj.randomize_value(value); % if isRandom is false, this will just return the original value

            if strlength(obj.Expression) > 0
                value = obj.evaluateExpression_(value);
            end

            if selectsIndex
                obj.validateStimTypeValue_(value);
            end

            value = obj.execute_EvaluatorFcn(value);

            value = obj.clamp_value_(value);

            obj.Value = value;
            obj.isArray = numel(value) > 1;

            % 'StimType' is written like any other type: the backend receives the
            % stimulus object and decides what to do with it (see
            % hw.Interface.stimulusPayload). Backends with no waveform sink log
            % and keep the value host-side.
            if obj.isArray, value = {value}; end
            obj.Parent.set_parameter(obj,value);

            % `now` is much faster than `datetime("now")`
            % use: dt = datetime(obj.lastUpdated, 'ConvertFrom','datenum', 'TimeZone','local');
            % convert to ms: ts = uint64((obj.lastUpdated - 719529) * 86400 * 1000);
             obj.lastUpdated = now;

            obj.execute_PostUpdateFcn(value);
        end

        function vstr = get.ValueStr(obj)
            if isempty(obj.Format)
                if ismember(obj.Type, {'String', 'File'})
                    obj.Format = '%s';
                else
                    obj.Format = '%g';
                end
            end

            v = obj.Value;
            if isequal(obj.Type, 'StimType')
                vstr = obj.formatStimTypeValue_(v);
            elseif isequal(obj.Type, 'File')
                vstr = obj.formatFileValue_(v);
            elseif isequal(obj.Type, 'String')
                vstr = obj.formatTextValue_(v);
            elseif obj.isArray
                ov = length(v);
                n = min(12,ov);
                v = v(1:n);
                vstr = num2str(v,[obj.Format ' ']);
                vstr = sprintf('[%s ... (%d values)]',vstr,ov);
            else
                vstr = sprintf(obj.Format, v);
            end

            if ~isempty(obj.Unit)
                vstr = [vstr ' ' obj.Unit];
            end

        end

        function vn = get.validName(obj)
            vn = matlab.lang.makeValidName(obj.Name);
        end

        function set.Type(obj,type)
            obj.Type = type;
            if ismember(obj.Type, {'String', 'File', 'StimType'})
                obj.Format = '%s';
            else
                obj.Format = '%g';
            end
        end

        function set.isTrigger(obj, isTrigger)
            % Trigger parameters fire once per call rather than carrying a
            % per-trial value, so default UpdateEveryTrial to match: false
            % while marked as a trigger, true otherwise.
            obj.isTrigger = logical(isTrigger);
            obj.UpdateEveryTrial = ~obj.isTrigger;
        end

        function set.isRandom(obj, isRandom)
            if isRandom && ~obj.hasFiniteRandomBounds()
                error('hw:Parameter:RandomBoundsRequired', ...
                    'Random parameter "%s" must have finite Min and Max values.', obj.Name);
            end
            obj.isRandom = logical(isRandom);
        end

        function set.Min(obj, minValue)
            if obj.isRandom && ~isfinite(minValue)
                error('hw:Parameter:RandomMinFinite', ...
                    'Min must be finite when parameter "%s" is random.', obj.Name);
            end
            obj.Min = minValue;
        end

        function set.Max(obj, maxValue)
            if obj.isRandom && ~isfinite(maxValue)
                error('hw:Parameter:RandomMaxFinite', ...
                    'Max must be finite when parameter "%s" is random.', obj.Name);
            end
            obj.Max = maxValue;
        end

        function [value, wasClamped] = clampValue(obj, value)
            % [value, wasClamped] = obj.clampValue(value)
            % Preview how a candidate value would be clamped by set.Value,
            % without assigning it. Used by design-time calculation checks.
            original = value;
            value = obj.clamp_value_(value);
            wasClamped = ~isequaln(original, value);
        end
    end

    methods (Access = protected)
        function execute_PreUpdateFcn(obj, newValue)
            if isa(obj.PreUpdateFcn ,'function_handle') && obj.PreUpdateFcnEnabled
                if isempty(obj.PreUpdateFcnArgs)
                    obj.PreUpdateFcn(obj,newValue);
                else
                    obj.PreUpdateFcn(obj,newValue,obj.PreUpdateFcnArgs{:});
                end
            end
        end

        function v = execute_EvaluatorFcn(obj, newValue)
            if isa(obj.EvaluatorFcn,'function_handle') && obj.EvaluatorFcnEnabled
                if isempty(obj.EvaluatorFcnArgs)
                    v = obj.EvaluatorFcn(obj,newValue);
                else
                    v = obj.EvaluatorFcn(obj,newValue,obj.EvaluatorFcnArgs{:});
                end
            else
                v = newValue;
            end
        end

        function execute_PostUpdateFcn(obj, newValue)
            if isa(obj.PostUpdateFcn,'function_handle') && obj.PostUpdateFcnEnabled
                if isempty(obj.PostUpdateFcnArgs)
                    obj.PostUpdateFcn(obj,newValue);
                else
                    obj.PostUpdateFcn(obj,newValue,obj.PostUpdateFcnArgs{:});
                end
            end
        end

        v = randomize_value(obj, value) % randomize value if isRandom; otherwise return value as-is
        set_value(obj, value)           % apply value directly, checking access and bounds

        function value = clamp_value_(obj, value)
            % value = clamp_value_(obj, value)
            % Clamp a numeric value within [Min, Max] for inclusive bounds.
            % Non-numeric types and types that don't support bounds are returned unchanged.
            %
            % Parameters
            %   value - Candidate value to clamp.
            %
            % Returns
            %   value - Value clamped to Min (if BoundsInclusive(1)) and/or Max (if BoundsInclusive(2)).
            if ~isnumeric(value) || ismember(obj.Type, {'StimType','String','File','Buffer','Coefficient Buffer'})
                return
            end
            if obj.BoundsInclusive(1)
                value = max(value, obj.Min);
            end
            if obj.BoundsInclusive(2)
                value = min(value, obj.Max);
            end
        end
    end

    methods (Access = private)
        function validateStimTypeValue_(obj, value)
            % Enforce that a 'StimType' parameter only ever holds a stimulus object.
            if isequal(obj.Type, 'StimType') && ~(isempty(value) || isa(value,'stimgen.StimType'))
                error('hw:Parameter:InvalidStimTypeValue', ...
                    'Value for StimType parameter "%s" must be a stimgen.StimType object or empty.', obj.Name);
            end
        end

        valueText = formatFileValue_(~, value) % format file path(s) for display as a string

        valueText = formatTextValue_(~, value) % format text/string value for display

        function tf = hasFiniteRandomBounds(obj)
            tf = isfinite(obj.Min) && isfinite(obj.Max);
        end

        vstr = formatStimTypeValue_(~, value) % format StimType value(s) for display

        function s = argsToStr_(obj, args)
            s = cell(size(args));
            for i = 1:numel(args)
                if isa(args{i}, 'function_handle')
                    s{i} = func2str(args{i});
                elseif isobject(args{i})
                    s{i} = class(args{i});
                else
                    s{i} = args{i};
                end
            end
        end

        function args = strToFcnArgs_(obj, s)
            args = cell(size(s));
            for i = 1:numel(s)
                if startsWith(s{i}, '@')
                    args{i} = str2func(s{i}(2:end));
                else
                    args{i} = s{i};
                end
            end
        end
        
        function s = fcnToStr_(~, f)
            if isa(f, 'function_handle')
                s = func2str(f);
            else
                s = "";
            end
        end

        function f = strToFcn_(~, s)
            if isempty(s)
                f = 0;
            elseif isstring(s) || ischar(s)
                f = str2func(s);
            else
                f = s;
            end
        end

        function v = numericToSafe_(~, x)
            if isnan(x)
                v = "NaN";
            elseif isinf(x) && x > 0
                v = "Inf";
            elseif isinf(x) && x < 0
                v = "-Inf";
            else
                v = x;
            end
        end

        v = safeToNumeric_(~, x) % convert safe sentinel strings ('Inf', '-Inf', 'NaN') to numeric

        result = evaluateExpression_(obj, currentValue) % evaluate obj.Expression to derive a new parameter value
    end
end


function access = normalizeLegacyAccess(access)
if isequal(access, 'Read / Write')
    access = 'Any';
end
end
