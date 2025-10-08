classdef Parameter < matlab.mixin.SetGet
   
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

        Min (1,1) double = -inf % minimum valid value
        Max (1,1) double = inf % maximum valid value
        Access  (1,:) char {mustBeMember(Access,{'Read','Write','Read / Write'})} = 'Read / Write'
        Type    (1,:) char {mustBeMember(Type,{'Float','Integer','Buffer','Coefficient Buffer','String','Undefined'})} = 'Float'
        Format  (1,:) char = '%g' % default format for displaying value

        isArray     (1,1) logical = false 
        isTrigger   (1,1) logical = false
        isRandom    (1,1) logical = false
        
        Visible (1,1) logical = true % optionally hide parameter 

        EvaluatorFcn (1,1) % handle to custom function to handle evaluation of updated values

        PreUpdateFcn (1,1) % handle ot custom function called before value has been updated
                            % note that this gets called prior to the
                            % EvaluatorFcn
        PostUpdateFcn (1,1) % handle to custom function called after value has been updated
    end

    properties (SetObservable,GetObservable,AbortSet) 
        Value % current/settable value of parameter
        % convert to datetime: dt = datetime(obj.lastUpdated, 'ConvertFrom','datenum', 'TimeZone','local');
        % convert to ms: ts = uint64((obj.lastUpdated - 719529) * 86400 * 1000);
        lastUpdated (1,1) double = 0; 
    end

    properties (Dependent)
        ValueStr % string representation of Value based on Format
        validName % valid MATLAB variable name based on Name
    end


    methods
        function obj = Parameter(Parent)
            obj.Parent = Parent;
            if ~isempty(Parent.HW) % ex: hw.Software
                obj.HW = Parent.HW;
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
            
            if isa(obj.Parent,'hw.Software') % special case
                v = obj.Value;
            else
                v = obj.Parent.get_parameter(obj,includeInvisible=true);
            end

            if isnumeric(v)
                v = double(v);
            end
        end

        function set.Value(obj,value)

            if isa(obj.PreUpdateFcn ,'function_handle')
                obj.PreUpdateFcn(obj,value);
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
                obj.PostUpdateFcn(obj,value);
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