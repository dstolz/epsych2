classdef Module < handle
    % obj = hw.Module(HW, Label, Name, Index)
    % Container for a hardware module and its parameters.
    %
    % A Module groups hw.Parameter objects under a named hardware unit
    % (real hardware or a software shim) for use by hw.Interface.
    %
    % Properties (selected):
    %   parent     - Parent hw.Interface instance.
    %   Parameters - Array of hw.Parameter handles belonging to this module.
    %
    % Methods:
    %   add_parameter          - Convenience method for creating/adding a parameter.
    %   writeParametersJSON    - Serialize Parameters to a JSON file.
    %   readParametersJSON     - Load Parameters from a JSON file.
    %
    % Limitations:
    %   PostUpdateFcnArgs is not serialized by writeParametersJSON/readParametersJSON
    %   because heterogeneous cell arrays do not round-trip reliably through JSON.
        
    properties (SetAccess = immutable)
        parent (1,1)  % parent hardware interface (inherits hw.Interface)

        Label   (1,:) char
        Name    (1,:) char
        Index   (1,1) uint8
    end
    


    properties
        Fs (1,1) double {mustBePositive,mustBeFinite,mustBeNonNan} = 1
        
        Parameters (1,:) hw.Parameter

        Info (1,1) struct % fields defined by parent
    end

    methods
        writeParametersJSON(obj, filepath) % serialize Parameters to a JSON file
        readParametersJSON(obj, filepath)  % load Parameters from a JSON file

        function obj = Module(HW,Label,Name,Index)
            arguments
                HW (1,1)  % parent hardware interface (inherits hw.Interface)
                Label   (1,:) char
                Name    (1,:) char
                Index   (1,1) uint8
            end

            obj.parent = HW;
            obj.Label = Label;
            obj.Name = Name;
            obj.Index = Index;
        end

        
        function P = add_parameter(obj,name,value,options)
            arguments
            obj
            name (1,:) char {mustBeText}
            value
            options.Description (1,1) string = ""
            options.Unit (1,:) char = ''
            options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Read / Write'})} = 'Read / Write'
            options.Type (1,:) char {mustBeMember(options.Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','Undefined'})} = 'Float'
            options.Format (1,:) char = '%g'
            options.Visible (1,1) logical = true
            options.UserData = []
            options.isArray (1,1) logical = false
            options.isTrigger (1,1) logical = false
            options.isRandom (1,1) logical = false
            options.Min (1,1) double = -inf
            options.Max (1,1) double = inf
            end

            if isstring(value), value = char(value); end

            nopts = namedargs2cell(options);
            P = hw.Parameter(obj.parent,nopts{:});

            P.Name = name;
            if ischar(value)
                P.Type = "String";
            end            
            P.Value = value;

            obj.Parameters(end+1) = P;
        end

    end

    methods (Access = private)
        S = parameterToStruct(obj, P)      % convert one hw.Parameter to a serialization-safe struct
        applyParameterStruct(obj, P, S)    % apply a decoded struct onto an hw.Parameter
    end

end