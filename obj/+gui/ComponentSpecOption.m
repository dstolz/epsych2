classdef ComponentSpecOption
    % gui.ComponentSpecOption
    % Value object describing a single option of a gui.ComponentSpec.
    %
    % Mirrors hw.InterfaceSpecOption. Two things differ, both deliberate:
    %
    %   hasDefault - false means the component has NO default for this
    %                option, so gui.BehaviorGUI.add must not pass one. That
    %                is what lets a component fall back to the operator's
    %                own saved preference instead of being handed a value
    %                nobody chose. defaultValue = [] with hasDefault = true
    %                is a real default of [], which is a different thing.
    %   inputType  - adds 'param' and 'paramlist', which gui.BehaviorBuilder
    %                renders as a parameter picker over the protocol
    %                snapshot rather than as a free-text field.
    %
    % See also gui.ComponentSpec, gui.BehaviorGUI.add

    properties
        name (1,:) char = ''
        label (1,:) char = ''
        defaultValue = []
        hasDefault (1,1) logical = false
        inputType (1,:) char = 'text'   % text|numeric|logical|choice|param|paramlist
        choices cell = {}
        isList (1,1) logical = false
        description (1,:) char = ''
    end

    methods
        function obj = ComponentSpecOption(varargin)
            if nargin == 1 && (isstruct(varargin{1}) || isa(varargin{1},'gui.ComponentSpecOption'))
                obj = gui.ComponentSpecOption.fromStruct(varargin{1});
                return
            end
            if mod(nargin, 2) ~= 0
                error('gui:ComponentSpecOption:InvalidArguments', ...
                    'ComponentSpecOption expects name/value pairs or a single struct.');
            end
            for idx = 1:2:nargin
                obj.(varargin{idx}) = varargin{idx + 1};
            end
            % Naming a default is how you declare that there IS one.
            if any(strcmpi(varargin(1:2:end), 'defaultValue'))
                obj.hasDefault = true;
            end
            obj = obj.normalized();
        end

        function f = toPromptField(obj)
            % f = toPromptField(obj)
            % Row for gui.BehaviorBuilder.promptFields, which already speaks
            % Name/Label/Kind/Items/Value.
            % Kind must be one of the four promptFieldsImpl_ renders --
            % 'text' | 'numeric' | 'logical' | 'choice' -- anything else
            % silently becomes a text field.
            switch lower(obj.inputType)
                case 'numeric',              kind = 'numeric';
                case {'logical','boolean'},  kind = 'logical';
                case 'choice',               kind = 'choice';
                case {'param','paramlist'},  kind = 'text'; % shown as names, comma-separated
                otherwise,                   kind = 'text';
            end
            v = obj.defaultValue;
            if ~obj.hasDefault, v = []; end
            f = struct('Name', obj.name, ...
                'Label', gui.ComponentSpecOption.displayLabel(obj), ...
                'Kind',  kind, ...
                'Items', {obj.choices}, ...
                'Value', v);
        end
    end

    methods (Static)
        function obj = fromStruct(s)
            if isa(s, 'gui.ComponentSpecOption'), obj = s; return; end
            obj = gui.ComponentSpecOption();
            p = properties(obj);
            for idx = 1:numel(p)
                if isfield(s, p{idx}), obj.(p{idx}) = s.(p{idx}); end
            end
            if isfield(s,'defaultValue') && ~isfield(s,'hasDefault')
                obj.hasDefault = true;
            end
            obj = obj.normalized();
        end

        function options = normalizeArray(data)
            if isempty(data)
                options = gui.ComponentSpecOption.empty(1,0);
                return
            end
            if isa(data, 'gui.ComponentSpecOption')
                options = data;
                for idx = 1:numel(options), options(idx) = options(idx).normalized(); end
                return
            end
            if isstruct(data)
                options = repmat(gui.ComponentSpecOption(), 1, numel(data));
                for idx = 1:numel(data)
                    options(idx) = gui.ComponentSpecOption.fromStruct(data(idx));
                end
                return
            end
            error('gui:ComponentSpecOption:UnsupportedOptionData', ...
                'Options must be gui.ComponentSpecOption objects or structs.');
        end

        function label = displayLabel(obj)
            label = obj.label;
            if isempty(label)
                label = regexprep(obj.name, '([a-z0-9])([A-Z])', '$1 $2');
                label = strrep(label, '_', ' ');
            end
        end
    end

    methods
        function obj = normalized(obj)
            obj.name        = char(string(obj.name));
            obj.label       = char(string(obj.label));
            obj.inputType   = char(string(obj.inputType));
            obj.description = char(string(obj.description));
            if isstring(obj.choices), obj.choices = cellstr(obj.choices); end
            if isempty(obj.choices),  obj.choices = {}; end
            if iscell(obj.choices) && isscalar(obj.choices) && iscell(obj.choices{1})
                obj.choices = obj.choices{1};
            end
        end
    end
end
