classdef Module < handle
    % obj = hw.Module(HW, Label, Name, Index)
    % Hardware module container for parameters and metadata.
    %
    % A Module represents a named hardware unit, grouping hw.Parameter objects
    % under a label and index. Modules are typically owned by a hw.Interface subclass
    % and provide the organization layer for GUIs, runtime code, and JSON parameter import/export.
    %
    % Parameters
    %   HW      - Parent hw.Interface instance that owns this module.
    %   Label   - Short module label for display and serialization.
    %   Name    - Hardware-specific module name.
    %   Index   - Module index within the parent interface.
    %
    % Properties
    %   parent      - Parent hw.Interface instance.
    %   Fs          - Module sample rate or update rate metadata.
    %   Parameters  - Array of hw.Parameter handles belonging to this module.
    %   Info        - Module-specific metadata defined by the parent interface.
    %
    % Methods
    %   add_parameter          - Create and add a hw.Parameter to this module.
    %   writeParametersJSON    - Serialize Parameters to a JSON file.
    %   readParametersJSON     - Load Parameters from a JSON file.
    %
    % Limitations
    %   PostUpdateFcnArgs is not serialized by writeParametersJSON/readParametersJSON
    %   because heterogeneous cell arrays do not round-trip reliably through JSON.
    %
    % Usage Example
    %   m = hw.Module(hw, 'AMP', 'Amplifier', 1);
    %   p = m.add_parameter('Gain', 1.0, Description="Amplifier gain");
    %
    % For more details, see: documentation/hw_Module.md
    % See also: hw.Interface, hw.Parameter
        
    properties (SetAccess = immutable)
        parent (1,1)  % Parent hw.Interface instance
        Label   (1,:) char   % Short module label
        Name    (1,:) char   % Hardware-specific module name
        Index   (1,1) uint8  % Module index within parent interface
    end
    


    properties
        Fs (1,1) double {mustBePositive,mustBeFinite,mustBeNonNan} = 1   % Module sample/update rate
        Parameters (1,:) hw.Parameter    % Array of hw.Parameter handles
        Info (1,1) struct               % Module-specific metadata (fields defined by parent)
    end

    methods
        writeParametersJSON(obj, filepath) % Serialize Parameters to a JSON file
        readParametersJSON(obj, filepath)  % Load Parameters from a JSON file

        function obj = Module(HW,Label,Name,Index)
            % obj = hw.Module(HW, Label, Name, Index)
            % Construct a hardware module container.
            %
            % Parameters
            %   HW      - Parent hw.Interface instance.
            %   Label   - Short module label for display/serialization.
            %   Name    - Hardware-specific module name.
            %   Index   - Module index within parent interface.
            obj.parent = HW;
            obj.Label = Label;
            obj.Name = Name;
            obj.Index = Index;
        end

        function P = add_parameter(obj, name, value, options)
            % P = obj.add_parameter(name, value)
            % P = obj.add_parameter(name, value, Name=Value)
            % Create, initialize, and append a hw.Parameter to this Module.
            %
            % Parameters
            %   name    - Display name for the new parameter (char).
            %   value   - Initial parameter value. String scalars are converted to char and force Type to 'String'.
            %   options - Name=Value pairs for hw.Parameter metadata (Description, Unit, Access, Type, Format, Visible, callback flags, UserData, isArray, isTrigger, isRandom, Min, Max).
            %
            % Returns
            %   P       - Created hw.Parameter handle.
            %
            % See also: hw.Parameter, documentation/hw_Module.md
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
            P = hw.Parameter(obj.parent, nopts{:});
            P.Name = name;
            if ischar(value)
                P.Type = "String";
            end
            P.Value = value;
            obj.Parameters(end+1) = P;
        end
    end

    methods (Access = private)
        S = toStruct(obj, P)   % Convert one hw.Parameter to a serialization-safe struct
        fromStruct(obj, P, S)  % Apply a decoded struct onto an hw.Parameter
    end

end