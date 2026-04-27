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
        Parent (1,1) % handle to parent object (e.g., hw.Software)
        HW (1,1)  % handle to hardware interface; reflects parent object's handle
    end

    properties
        handle (1,1) % handle to an associated gui object

        Name    (1,:) char = 'Param' % name of parameter
        Description (1,1) string = ""; % short description of parameter
        Unit    (1,:) char = ''; % unit string (e.g., 'V', 'ms', etc.)
        Module  (1,1) % handle to module object that this parameter belongs to

        Access  (1,:) char {mustBeMember(Access,{'Read','Write','Any','Read / Write'})} = 'Any'
        Type    (1,:) char {mustBeMember(Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','File','Undefined'})} = 'Float'
        Format  (1,:) char = '%g' % default format for displaying value

        Visible (1,1) logical = true % optionally hide parameter

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
    end

    properties (Dependent)
        ValueStr % string representation of Value based on Format
        validName % valid MATLAB variable name based on Name
    end

    methods (Static)
        function values = normalizeValues(value)
            % values = hw.Parameter.normalizeValues(value)
            % Convert any scalar, vector, cell array, or string array to a uniform
            % 1×N cell array of individual trial levels, for storage in hw.Parameter.Values.
            %
            % Parameters:
            %   value - any type: numeric scalar/vector, logical, char, string array, or cell array
            %
            % Returns:
            %   values (1,:) cell - one element per trial level
            if isnumeric(value) || islogical(value)
                if isempty(value)
                    values = {};
                else
                    values = num2cell(reshape(value, 1, []));
                end
            elseif isstring(value)
                if isscalar(value)
                    values = {char(value)};
                else
                    values = reshape(cellstr(value), 1, []);
                end
            elseif ischar(value)
                values = {value};
            elseif iscell(value)
                values = reshape(value, 1, []);
            else
                values = {value};
            end
        end
    end

    methods
        S = toStruct(obj)           % serialize this parameter to a struct
        fromStruct(obj, S)          % restore this parameter from a struct
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
                options.Type (1,:) char {mustBeMember(options.Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','File','Undefined'})} = 'Float'
                options.Format (1,:) char = '%g'
                options.Visible (1,1) logical = true
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
            obj.isTrigger = options.isTrigger;
            obj.isRandom = options.isRandom;
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

            if isa(obj.Parent,'hw.Software') || (isprop(obj.Parent, 'IsConnected') && ~obj.Parent.IsConnected)
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

            obj.execute_PreUpdateFcn(value);

            value = obj.randomize_value(value); % if isRandom is false, this will just return the original value
            

            value = obj.execute_EvaluatorFcn(value);

            obj.Value = value;
            obj.isArray = numel(value) > 1;
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
            if isequal(obj.Type, 'File')
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
            if ismember(obj.Type, {'String', 'File'})
                obj.Format = '%s';
            else
                obj.Format = '%g';
            end
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

        function v = randomize_value(obj,value)
            if ~obj.isRandom
                v = value;
                return
            end

            try
                v = randi([obj.Min obj.Max]);
                vprintf(3,'Randomized parameter "%s" to value: %g',obj.Name,v)
            catch e
                vprintf(0,1,'Error randomizing parameter "%s": %s',obj.Name,getReport(e,'basic'))
            end
        end

        function set_value(obj,value)

            if isequal(obj.Access,'Read')
                vprintf(0,1,'"%s" is a read-only parameter',obj.Name)
                return
            end

            if ~ismember(obj.Type, {'String', 'File'}) && (value < obj.Min || value > obj.Max)
                vprintf(0,1,'Value for "%s" parameter is out of range: min = %g, max = %g, supplied = %g',obj.Min,obj.Max,value)
                return
            end

            obj.Value = value;
            if ~isequal(obj.HW,0)
                obj.HW.set_parameter(obj,value);
            end
            % `now` is much faster than `datetime("now")`
            % use: dt = datetime(obj.lastUpdated, 'ConvertFrom','datenum', 'TimeZone','local');
            % convert to ms: ts = uint64((obj.lastUpdated - 719529) * 86400 * 1000);
             obj.lastUpdated = now;
        end
    end

    methods (Access = private)
        function valueText = formatFileValue_(~, value)
            if isstring(value)
                value = cellstr(value);
            end

            if ischar(value)
                valueText = value;
                return
            end

            if iscell(value)
                flatValues = value;
                if numel(flatValues) == 1 && iscell(flatValues{1})
                    flatValues = flatValues{1};
                end
                flatValues = flatValues(~cellfun(@isempty, flatValues));
                if isempty(flatValues)
                    valueText = '';
                elseif numel(flatValues) == 1
                    valueText = char(string(flatValues{1}));
                else
                    previewCount = min(3, numel(flatValues));
                    preview = strjoin(cellfun(@char, flatValues(1:previewCount), UniformOutput = false), ', ');
                    if numel(flatValues) > previewCount
                        valueText = sprintf('[%s, ... (%d files)]', preview, numel(flatValues));
                    else
                        valueText = sprintf('[%s]', preview);
                    end
                end
                return
            end

            valueText = char(string(value));
        end

        function valueText = formatTextValue_(~, value)
            if isstring(value)
                value = cellstr(value);
            end

            if ischar(value)
                valueText = value;
                return
            end

            if iscell(value)
                flatValues = value;
                if numel(flatValues) == 1 && iscell(flatValues{1})
                    flatValues = flatValues{1};
                end
                flatValues = flatValues(~cellfun(@isempty, flatValues));
                if isempty(flatValues)
                    valueText = '';
                elseif numel(flatValues) == 1
                    valueText = char(string(flatValues{1}));
                else
                    previewCount = min(3, numel(flatValues));
                    preview = strjoin(cellfun(@(item) char(string(item)), flatValues(1:previewCount), UniformOutput = false), ', ');
                    if numel(flatValues) > previewCount
                        valueText = sprintf('[%s, ... (%d values)]', preview, numel(flatValues));
                    else
                        valueText = sprintf('[%s]', preview);
                    end
                end
                return
            end

            valueText = char(string(value));
        end

        function tf = hasFiniteRandomBounds(obj)
            tf = isfinite(obj.Min) && isfinite(obj.Max);
        end

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

        function v = safeToNumeric_(~, x)
            if isstring(x) || ischar(x)
                x = char(x);
                switch x
                    case 'Inf'
                        v = Inf;
                    case '-Inf'
                        v = -Inf;
                    case 'NaN'
                        v = NaN;
                    otherwise
                        v = str2double(x);
                end
            else
                v = double(x);
            end
        end
    end
end


function access = normalizeLegacyAccess(access)
if isequal(access, 'Read / Write')
    access = 'Any';
end
end
