classdef InterfaceSpec
    % hw.InterfaceSpec(type, label, description, options, createFcn)
    % Value object describing how a hw.Interface can be created in tools.
    %
    % Properties
    %   type        - Stable interface type identifier.
    %   label       - Human-readable display label.
    %   description - Short help text shown in the designer.
    %   options     - Array of hw.InterfaceSpecOption definitions.
    %   createFcn   - Factory function that accepts an options struct.

    properties
        type (1,:) char = ''
        label (1,:) char = ''
        description (1,:) char = ''
        options (1,:) hw.InterfaceSpecOption = hw.InterfaceSpecOption.empty(1, 0)
        createFcn = []
    end

    methods
        function obj = InterfaceSpec(type, label, description, options, createFcn)
            if nargin >= 1
                obj.type = char(string(type));
            end
            if nargin >= 2
                obj.label = char(string(label));
            end
            if nargin >= 3
                obj.description = char(string(description));
            end
            if nargin >= 4
                obj.options = hw.InterfaceSpecOption.normalizeArray(options);
            end
            if nargin >= 5
                obj.createFcn = createFcn;
            end
            obj = obj.normalized();
        end
    end

    methods (Static)
        function obj = fromStruct(specStruct)
            obj = hw.InterfaceSpec();
            if isa(specStruct, 'hw.InterfaceSpec')
                obj = specStruct;
                return
            end

            if isfield(specStruct, 'type')
                obj.type = char(string(specStruct.type));
            end
            if isfield(specStruct, 'label')
                obj.label = char(string(specStruct.label));
            end
            if isfield(specStruct, 'description')
                obj.description = char(string(specStruct.description));
            end
            if isfield(specStruct, 'options')
                obj.options = hw.InterfaceSpecOption.normalizeArray(specStruct.options);
            end
            if isfield(specStruct, 'createFcn')
                obj.createFcn = specStruct.createFcn;
            end
            obj = obj.normalized();
        end

        function obj = normalize(specData)
            if isa(specData, 'hw.InterfaceSpec')
                obj = specData;
            else
                obj = hw.InterfaceSpec.fromStruct(specData);
            end

            obj = obj.normalized();
        end
    end

    methods
        function obj = normalized(obj)
            obj.type = char(string(obj.type));
            obj.label = char(string(obj.label));
            obj.description = char(string(obj.description));
            obj.options = hw.InterfaceSpecOption.normalizeArray(obj.options);
        end
    end
end