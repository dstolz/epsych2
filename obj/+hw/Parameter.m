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
    %   isArray, isTrigger, isRandom, Min, Max - Runtime flags and bounds.
    %
    % Methods
    %   Parameter - Construct and initialize a parameter instance.
    %   Trigger - Trigger the associated hardware event when enabled.
    %
    % Example
    %   p = hw.Parameter(parent, Name='PulseWidth', Unit='ms', ...
    %       Type='Float', Min=0, Max=50);
    %   p.Value = 10;
    %   disp(p.ValueStr)
    %
    % See also: documentation/hw_Parameter.md
   
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

        Access  (1,:) char {mustBeMember(Access,{'Read','Write','Read / Write'})} = 'Read / Write'
        Type    (1,:) char {mustBeMember(Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','Undefined'})} = 'Float'
        Format  (1,:) char = '%g' % default format for displaying value

        Visible (1,1) logical = true % optionally hide parameter 

        PreUpdateFcn (1,1) % handle ot custom function called before value has been updated
                            % note that this gets called prior to the
                            % EvaluatorFcn

        EvaluatorFcn (1,1) % handle to custom function to handle evaluation of updated values

        PostUpdateFcn (1,1) % handle to custom function called after value has been updated

        % TO DO: Make this available for all custom fcn
        PostUpdateFcnArgs (1,:) cell = {} % optional extra arguments passed to EvaluatorFcn

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



    methods
        function obj = Parameter(Parent, options)
            % obj = hw.Parameter(Parent)
            % obj = hw.Parameter(Parent, Name=Value)
            % Construct a parameter and initialize its metadata and behavior.
            %
            % Parameters
            %   Parent - Parent object that provides the backing hardware or
            %       software interface.
            %   Name=Value - Optional constructor settings for metadata,
            %       callbacks, visibility, and bounds.
            %
            % Returns
            %   obj - Configured hw.Parameter instance.
            arguments
            Parent (1,1)
            options.Name (1,:) char = 'Param'
            options.Description (1,1) string = ""
            options.Unit (1,:) char = ''
            options.Module (1,1) = matlab.lang.OnUndefinedVariableBehavior.error
            options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Read / Write'})} = 'Read / Write'
            options.Type (1,:) char {mustBeMember(options.Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','Undefined'})} = 'Float'
            options.Format (1,:) char = '%g'
            options.Visible (1,1) logical = true
            options.PreUpdateFcn (1,1) = []
            options.EvaluatorFcn (1,1) = []
            options.PostUpdateFcn (1,1) = []
            options.PostUpdateFcnArgs (1,:) cell = {}
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
            if ~isequal(options.Module, matlab.lang.OnUndefinedVariableBehavior.error)
            obj.Module = options.Module;
            end
            obj.Access = options.Access;
            obj.Type = options.Type;
            obj.Format = options.Format;
            obj.Visible = options.Visible;
            obj.PreUpdateFcn = options.PreUpdateFcn;
            obj.EvaluatorFcn = options.EvaluatorFcn;
            obj.PostUpdateFcn = options.PostUpdateFcn;
            obj.PostUpdateFcnArgs = options.PostUpdateFcnArgs;
            obj.UserData = options.UserData;
            obj.isArray = options.isArray;
            obj.isTrigger = options.isTrigger;
            obj.isRandom = options.isRandom;
            obj.Min = options.Min;
            obj.Max = options.Max;
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
            
            if isa(obj.Parent,'hw.Software') % special case
                v = obj.Value;
            else
                v = obj.Parent.get_parameter(obj,includeInvisible=true);
            end

            if isnumeric(v)
                v = double(v);
            end
        end

        function Trigger(obj)
            % obj.Trigger()
            % Trigger the parent event associated with this parameter.
            %
            % Trigger only performs an action when isTrigger is true. On
            % success, lastUpdated is set from the parent trigger call.
            if ~obj.isTrigger
                vprintf(0,'"%s" is not recognized as a parameter',obj.Name)
                return
            end

            obj.lastUpdated = obj.Parent.trigger(obj);
            vprintf(3,'%s triggered',obj.Name)

        end

        function set.Value(obj,value)

            if isa(obj.PreUpdateFcn ,'function_handle')
                obj.PreUpdateFcn(obj,value);
            end

            if obj.isRandom
                value = obj.randomize_value();
            end

            if isa(obj.EvaluatorFcn,'function_handle')
                value = obj.EvaluatorFcn(obj,value);
            end

            obj.Value = value;
            obj.isArray = numel(value) > 1;
            if obj.isArray, value = {value}; end

            obj.Parent.set_parameter(obj,value);

            % `now` is much faster than `datetime("now")`
            % use: dt = datetime(obj.lastUpdated, 'ConvertFrom','datenum', 'TimeZone','local');
            % convert to ms: ts = uint64((obj.lastUpdated - 719529) * 86400 * 1000);
             obj.lastUpdated = now;
        
            if isa(obj.PostUpdateFcn,'function_handle')
                if isempty(obj.PostUpdateFcnArgs)
                    obj.PostUpdateFcn(obj,value);
                else
                    obj.PostUpdateFcn(obj,value,obj.PostUpdateFcnArgs{:});
                end
            end
        end



        function vstr = get.ValueStr(obj)
            if isempty(obj.Format)
                if isequal(obj.Type,'String')
                    obj.Format = '%s';
                else
                    obj.Format = '%g';
                end
            end
            
            v = obj.Value;
            if obj.isArray
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
            if isequal(obj.Type,'String')
                obj.Format = '%s';
            else
                obj.Format = '%g';
            end
        end
    end

    methods (Access = protected)
        
        function v = randomize_value(obj)
            if ~obj.isRandom
                v = obj.Value;
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

            if ~isequal(obj.Type,'String') && (value < obj.Min || value > obj.Max)
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

    

end