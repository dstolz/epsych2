classdef InterfaceSpecOption
    % hw.InterfaceSpecOption
    % Value object describing a single creation option for a hw.InterfaceSpec.

    properties
        name (1,:) char = ''
        label (1,:) char = ''
        defaultValue = []
        required (1,1) logical = false
        inputType (1,:) char = 'text'
        choices cell = {}
        isList (1,1) logical = false
        scope (1,:) char = 'interface'
        allowScalarExpansion (1,1) logical = false
        controlType (1,:) char = ''
        getFile (1,1) logical = false
        getFolder (1,1) logical = false
        fileFilter = {'*.*', 'All Files (*.*)'}
        fileDialogTitle (1,:) char = ''
        description (1,:) char = ''
    end

    methods
        function obj = InterfaceSpecOption(varargin)
            if nargin == 1 && (isstruct(varargin{1}) || isa(varargin{1}, 'hw.InterfaceSpecOption'))
                obj = hw.InterfaceSpecOption.fromStruct(varargin{1});
                return
            end

            if mod(nargin, 2) ~= 0
                error('hw:InterfaceSpecOption:InvalidArguments', ...
                    'InterfaceSpecOption expects name/value pairs or a single struct.');
            end

            for idx = 1:2:nargin
                propertyName = varargin{idx};
                propertyValue = varargin{idx + 1};
                obj.(propertyName) = propertyValue;
            end

            obj = obj.normalized();
        end
    end

    methods (Static)
        function obj = fromStruct(optionStruct)
            if isa(optionStruct, 'hw.InterfaceSpecOption')
                obj = optionStruct;
                return
            end

            obj = hw.InterfaceSpecOption();
            propertyNames = properties(obj);
            for idx = 1:numel(propertyNames)
                propertyName = propertyNames{idx};
                if isfield(optionStruct, propertyName)
                    obj.(propertyName) = optionStruct.(propertyName);
                end
            end
            obj = obj.normalized();
        end

        function options = normalizeArray(optionData)
            if isempty(optionData)
                options = hw.InterfaceSpecOption.empty(1, 0);
                return
            end

            if isa(optionData, 'hw.InterfaceSpecOption')
                options = optionData;
                for idx = 1:numel(options)
                    options(idx) = options(idx).normalized();
                end
                return
            end

            if isstruct(optionData)
                options = repmat(hw.InterfaceSpecOption(), 1, numel(optionData));
                for idx = 1:numel(optionData)
                    options(idx) = hw.InterfaceSpecOption.fromStruct(optionData(idx));
                end
                return
            end

            error('hw:InterfaceSpecOption:UnsupportedOptionData', ...
                'Options must be provided as hw.InterfaceSpecOption objects or structs.');
        end
    end

    methods
        function obj = normalized(obj)
            obj.name = char(string(obj.name));
            obj.label = char(string(obj.label));
            obj.inputType = char(string(obj.inputType));
            obj.scope = char(string(obj.scope));
            obj.controlType = char(string(obj.controlType));
            obj.fileDialogTitle = char(string(obj.fileDialogTitle));
            obj.description = char(string(obj.description));

            if iscell(obj.choices) && isscalar(obj.choices) && iscell(obj.choices{1})
                obj.choices = obj.choices{1};
            end
            if isstring(obj.choices)
                obj.choices = cellstr(obj.choices);
            end

            if isempty(obj.scope)
                obj.scope = 'interface';
            end
            if isempty(obj.choices)
                obj.choices = {};
            end
            if isempty(obj.fileFilter)
                obj.fileFilter = {'*.*', 'All Files (*.*)'};
            end
            if isempty(obj.fileDialogTitle)
                obj.fileDialogTitle = char(string(obj.label));
            end
            if isempty(obj.controlType)
                obj.controlType = hw.InterfaceSpecOption.inferControlType(obj);
            end
        end
    end

    methods (Static, Access = private)
        function controlType = inferControlType(option)
            inputType = char(string(option.inputType));

            if option.isList
                if ~isempty(option.choices)
                    controlType = 'multiselect';
                else
                    controlType = 'textarea';
                end
                return
            end

            switch lower(inputType)
                case 'choice'
                    controlType = 'dropdown';
                case 'numeric'
                    controlType = 'numeric';
                case {'logical', 'boolean', 'bool'}
                    controlType = 'checkbox';
                otherwise
                    controlType = 'text';
            end
        end
    end
end