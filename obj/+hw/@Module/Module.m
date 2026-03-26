classdef Module < handle
    % obj = hw.Module(HW, Label, Name, Index)
    % Represent one named hardware module and its exposed parameters.
    %
    % A Module groups hw.Parameter objects under a hardware unit label
    % and index. Modules are typically owned by a hw.Interface subclass
    % and provide the organization layer used by GUIs, runtime code, and
    % JSON parameter import/export helpers.
    %
    % Parameters
    %   HW - Parent hardware interface that owns this module.
    %   Label - Short module label used for display and serialization.
    %   Name - Hardware-specific module name.
    %   Index - Module index within the parent interface.
    %
    % Properties
    %   parent - Parent hw.Interface instance.
    %   Fs - Module sample rate or update rate metadata.
    %   Parameters - Array of hw.Parameter handles belonging to this module.
    %   Info - Module-specific metadata defined by the parent interface.
    %
    % Methods:
    %   add_parameter          - Convenience method for creating/adding a parameter.
    %   writeParametersJSON    - Serialize Parameters to a JSON file.
    %   readParametersJSON     - Load Parameters from a JSON file.
    %
    % Limitations:
    %   PostUpdateFcnArgs is not serialized by writeParametersJSON/readParametersJSON
    %   because heterogeneous cell arrays do not round-trip reliably through JSON.
    %
    % See also: documentation/hw_Module.md, hw.Interface, hw.Parameter
        
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
            % P = obj.add_parameter(name, value)
            % P = obj.add_parameter(name, value, Name=Value)
            % Create a hw.Parameter, initialize it, and append it to this Module.
            %
            % Parameters
            %   name - Display name for the new parameter.
            %   value - Initial parameter value. String scalars are converted to
            %       char and force the created parameter Type to 'String'.
            %   Name=Value - Optional metadata and behavior settings passed to
            %       hw.Parameter, including Description, Unit, Access, Type,
            %       Format, Visible, callback enable flags, UserData, array/
            %       trigger/random flags, and Min/Max bounds.
            %
            % Returns
            %   P - Created hw.Parameter handle.
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
        S = toStruct(obj, P)       % convert one hw.Parameter to a serialization-safe struct
        fromStruct(obj, P, S)      % apply a decoded struct onto an hw.Parameter
    end

end