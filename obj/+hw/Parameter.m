classdef Parameter < matlab.mixin.SetGet
   
    properties (SetAccess = immutable)
        Parent (1,1) %hw.Module % perhaps this can be useful without a parent?
        HW (1,1)  % handle to hardware interface; reflects parent object's handle

        %  bmn = ["RespCode","TrigState","NewTrial","ResetTrig","TrialNum", ...
        % 'TrialComplete','AcqBuffer','AcqBufferSize'];
    end

    properties
        handle (1,1) % handle to an associated gui object

        Name    (1,:) char
        Description (1,1) string
        Unit (1,:) char

        Min (1,1) double = -inf
        Max (1,1) double = inf
        Access (1,:) char {mustBeMember(Access,{'Read','Write','Read / Write'})} = 'Read / Write'
        Type (1,:) char {mustBeMember(Type,{'Float','Integer','Buffer','Coefficient Buffer','Undefined'})} = 'Float'
        Format (1,:) char = '%g%s'

        isArray (1,1) logical = false
        isTrigger (1,1) logical = false
        isRandom (1,1) logical = false
        
        Visible (1,1) logical = true % optionally hide parameter 
    end

    properties (SetObservable,GetObservable,AbortSet)
        Value  % set by parent function using obj.setValue()
        lastUpdated (1,1) datetime = datetime("now");
    end

    properties (Dependent)
        ValueStr
        validName
    end


    methods
        function obj = Parameter(Parent)
            if nargin == 1
                obj.Parent = Parent;

                obj.HW = Parent.HW;
            end
        end

        % function disp(obj)
        %     fprintf('Module "%s" (%d)\t%s = %s\n', ...
        %         obj.Parent.Name,obj.Parent.Index, ...
        %         obj.Name, obj.ValueStr);
        % end

        function v = get.Value(obj)
            v = obj.Parent.get_parameter(obj,includeInvisible=true);
        end

        function set_Value(obj,value)
            if isequal(obj.Access,'Read')
                vprintf(0,1,'"%s" is a read-only parameter',obj.Name)
                return
            end
            obj.Value = value;
            obj.lastUpdated = datetime("now");
        end

        function vstr = get.ValueStr(obj)
            if isempty(obj.Format)
                vstr = num2str(obj.Value);
            else
                vstr = sprintf(obj.Format, obj.Value, obj.Unit);
            end
        end



        function vn = get.validName(obj)
            vn = matlab.lang.makeValidName(obj.Name);
        end
    end

    

end