classdef Parameter < matlab.mixin.SetGet
   
    properties (SetAccess = immutable)
        Parent (1,1) % hw object
        HW (1,1)  % handle to hardware interface; reflects parent object's handle
    end

    properties
        handle (1,1) % handle to an associated gui object

        Name    (1,:) char
        Description (1,1) string
        Unit (1,:) char
        Module (1,1) %hw.Module

        Min (1,1) double = -inf
        Max (1,1) double = inf
        Access (1,:) char {mustBeMember(Access,{'Read','Write','Read / Write'})} = 'Read / Write'
        Type (1,:) char {mustBeMember(Type,{'Float','Integer','Buffer','Coefficient Buffer','String','Undefined'})} = 'Float'
        Format (1,:) char = '%g'


        isArray (1,1) logical = false
        isTrigger (1,1) logical = false
        isRandom (1,1) logical = false
        
        Visible (1,1) logical = true % optionally hide parameter 

        EvaluatorFcn (1,1) % handle to custom function to handle evaluation of updated values

        PreUpdateFcn (1,1) % handle ot custom function called before value has been updated
                            % note that this gets called prior to the
                            % EvaluatorFcn
        PostUpdateFcn (1,1) % handle to custom function called after value has been updated
    end

    properties (SetObservable,GetObservable,AbortSet) 
        Value
        lastUpdated (1,1) datetime = datetime("now");
    end

    properties (Dependent)
        ValueStr
        validName
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
                feval(obj.PreUpdateFcn);
            end

            if isa(obj.EvaluatorFcn,'function_handle')
                value = obj.EvaluatorFcn(obj,value);
            end

            obj.Value = value;
            obj.Parent.set_parameter(obj,value);

            if isa(obj.PostUpdateFcn,'function_handle')
                feval(obj.PostUpdateFcn);
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
            
            vstr = sprintf(obj.Format, obj.Value);
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
            obj.lastUpdated = datetime("now");
        end
    end

    

end