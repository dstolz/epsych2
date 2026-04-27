classdef Protocol < handle & matlab.mixin.SetGet
    % epsych.Protocol
    % 
    % Create and manage a protocol for hardware parameter definitions, parameter values,
    % and trial compilation.
    %
    % A Protocol owns one or more hw.Interface instances (hw.Software, hw.TDT_RPcox,
    % hw.TDT_Synapse, or custom interfaces). By default, a new Protocol contains a
    % hw.Software instance as a design-time parameter store. Users can add parameters
    % to any interface via addParameter(), and compile() generates trials from the
    % cross-product of parameter values and their paired groups.
    %
    % Properties:
    %   Interfaces       - Array of hw.Interface instances owned by this protocol
    %   Options          - Struct holding trialFunc, compileAtRuntime
    %   Info             - User-provided description string
    %   COMPILED         - Struct output from compile() with writeparams, readparams, trials
    %   meta             - Metadata including EPsych version, creation date, format version
    %
    % Primary Methods:
    %   addInterface     - Add an hw.Interface instance (Software, TDT_RPcox, etc.)
    %   removeInterface  - Remove an interface by name
    %   findInterface    - Find an interface by name
    %   addParameter     - Add a parameter to a specific interface
    %   removeParameter  - Remove a parameter from an interface
    %   setOption        - Update Options fields
    %   compile          - Generate COMPILED trials, writeparams, readparams
    %   validate         - Check protocol for errors without modifying state
    %   estimateDuration - Estimate trial duration in seconds
    %   save             - Serialize protocol to .eprot MAT file
    %   load             - Static factory to deserialize from .eprot file
    %
    % Example:
    %   P = epsych.Protocol('MyProtocol');
    %   P.addParameter('SoftwareModule', 'ToneFreq', [1000 2000 4000], Unit='Hz', Type='Float');
    %   P.compile();
    %   P.save('MyProtocol.eprot');
    %
    % See also: hw.Interface, hw.Parameter, hw.Software, hw.Module, 
    %   documentation/protocol/epsych_Protocol.md

    properties (SetAccess = protected)
        Interfaces (1,:) hw.Interface = hw.Interface.empty()
    end

    properties
        Options struct = struct(...
            'trialFunc', '', ...
            'compileAtRuntime', false, ...
            'IncludeWAVBuffers', true, ...
            'UseOpenEx', true, ...
            'ConnectionType', 'GB')
        
        Info (1,:) char = ''
        
        COMPILED struct = struct(...
            'parameters', [], ...
            'trials', {{}}, ...
            'writeparams', {{}}, ...
            'OPTIONS', struct(), ...
            'ntrials', 0)
        
        meta struct = struct(...
            'formatVersion', 1.0, ...
            'epsychVersion', '', ...
            'createdDate', '', ...
            'lastModified', '')
    end

    properties (SetAccess = private)
        SoftwareModule (1,1) hw.Software  % Internal reference to default Software module
    end

    methods
        function obj = Protocol(options)
            % obj = epsych.Protocol()
            % obj = epsych.Protocol(Name=Name, Info=info_string)
            %
            % Create a new Protocol. By default, contains one hw.Software interface
            % that serves as the design-time parameter store.
            %
            % Parameters:
            %   Name (char, default='UntitledProtocol') - Protocol name
            %   Info (char, default='') - User description
            %
            % Returns:
            %   obj - Initialized epsych.Protocol instance
            arguments
                options.Name (1,:) char = 'UntitledProtocol'
                options.Info (1,:) char = ''
            end

            % Initialize EPsych metadata
            E = EPsychInfo;
            obj.meta.epsychVersion = sprintf('EPsych v%s (Data v%s)', E.latestTag, E.DataVersion);
            obj.meta.createdDate = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            obj.meta.lastModified = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            obj.meta.formatVersion = 1.0;

            % Create default hw.Software interface
            obj.SoftwareModule = hw.Software();
            obj.Interfaces = obj.SoftwareModule;

            % Set user-provided info
            obj.Info = options.Info;
        end

        % ===== INTERFACE MANAGEMENT =====

        function addInterface(obj, interface, options)
            % addInterface(obj, interface, varargin)
            % 
            % Add an hw.Interface instance to this protocol.
            %
            % Parameters:
            %   interface - An hw.Interface subclass (hw.TDT_RPcox, hw.TDT_Synapse, etc.)
            %   Name (char, default=interface.Type) - Optional alias for this interface
            arguments
                obj
                interface (1,1) hw.Interface
                options.Name (1,:) char = char(interface.Type)
            end

            % Check for duplicate interface types
            existing_types = arrayfun(@(iface) char(iface.Type), obj.Interfaces, 'UniformOutput', false);
            if any(strcmp(char(interface.Type), existing_types))
                vprintf(0, 1, 'Interface of type "%s" already exists', char(interface.Type));
                return
            end

            % Append interface
            obj.Interfaces = [obj.Interfaces, interface];

            if isa(interface, 'hw.Software')
                obj.SoftwareModule = interface;
            end
        end

        function removeInterface(obj, identifier)
            % removeInterface(obj, identifier)
            %
            % Remove an interface by index or type. Cannot remove the only interface.
            %
            % Parameters:
            %   identifier (char | numeric) - Interface type/name or 1-based index to remove

            if length(obj.Interfaces) == 1
                vprintf(0, 1, 'Cannot remove the only interface (Software)');
                return
            end

            idx = [];

            if isnumeric(identifier) && isscalar(identifier)
                if identifier >= 1 && identifier <= length(obj.Interfaces)
                    idx = double(identifier);
                end
            elseif isstring(identifier) || ischar(identifier)
                name = char(identifier);
                for i = 1:length(obj.Interfaces)
                    iface_type = char(obj.Interfaces(i).Type);
                    if strcmp(iface_type, name)
                        idx = i;
                        break
                    end
                end
            end

            if isempty(idx)
                vprintf(0, 1, 'Interface not found');
                return
            end

            removed_is_software = isa(obj.Interfaces(idx), 'hw.Software');
            obj.Interfaces(idx) = [];

            if removed_is_software
                replacement = [];
                for i = 1:length(obj.Interfaces)
                    if isa(obj.Interfaces(i), 'hw.Software')
                        replacement = obj.Interfaces(i);
                        break
                    end
                end

                if isempty(replacement)
                    replacement = hw.Software();
                    obj.Interfaces = [replacement, obj.Interfaces];
                end

                obj.SoftwareModule = replacement;
            end
        end

        function replaceInterface(obj, identifier, interface)
            % replaceInterface(obj, identifier, interface)
            %
            % Replace one existing interface by index or type.
            %
            % Parameters:
            %   identifier - numeric index or interface type string
            %   interface - replacement hw.Interface instance
            arguments
                obj
                identifier
                interface (1,1) hw.Interface
            end

            idx = [];

            if isnumeric(identifier) && isscalar(identifier)
                if identifier >= 1 && identifier <= length(obj.Interfaces)
                    idx = double(identifier);
                end
            elseif isstring(identifier) || ischar(identifier)
                name = char(identifier);
                for i = 1:length(obj.Interfaces)
                    ifaceType = char(obj.Interfaces(i).Type);
                    if strcmp(ifaceType, name)
                        idx = i;
                        break
                    end
                end
            end

            if isempty(idx)
                error('Interface not found');
            end

            obj.Interfaces(idx) = interface;

            if isa(interface, 'hw.Software')
                obj.SoftwareModule = interface;
            elseif idx == 1 && isa(obj.SoftwareModule, 'hw.Software') && isa(obj.Interfaces(1), 'hw.Software')
                obj.SoftwareModule = obj.Interfaces(1);
            end
        end

        function hwif = findInterface(obj, name)
            % hwif = findInterface(obj, name)
            %
            % Find and return an interface by name or type.
            %
            % Parameters:
            %   name (char) - Name or Type of interface to find
            %
            % Returns:
            %   hwif - hw.Interface handle, or empty if not found
            arguments
                obj
                name (1,:) char
            end

            hwif = [];
            
            % Try exact name match first
            for i = 1:length(obj.Interfaces)
                if isprop(obj.Interfaces(i), 'Name') && ~isempty(obj.Interfaces(i).Name)
                    if strcmp(obj.Interfaces(i).Name, name)
                        hwif = obj.Interfaces(i);
                        return
                    end
                end
            end
            
            % Fall back to type match (compare Type property)
            for i = 1:length(obj.Interfaces)
                iface_type = char(obj.Interfaces(i).Type);
                if strcmp(iface_type, name)
                    hwif = obj.Interfaces(i);
                    return
                end
            end
        end

        % ===== PARAMETER MANAGEMENT =====

        function p = addParameter(obj, interfaceName, name, value, options)
            % p = addParameter(obj, interfaceName, name, value, varargin)
            %
            % Add a hw.Parameter to a specific interface within this protocol.
            % Delegates to hw.Interface.add_parameter().
            %
            % Parameters:
            %   interfaceName (char) - Name of target interface (default 'Software')
            %   name (char) - Parameter name
            %   value - Initial parameter value (numeric, logical, or cell)
            %   Description, Unit, Access, Type, Format, Visible, Min, Max, etc. - hw.Parameter options
            %
            % Returns:
            %   p - Created hw.Parameter handle
            arguments
                obj
                interfaceName (1,:) char = 'Software'
                name (1,:) char = ''
                value = 1
                options.Description (1,1) string = ""
                options.Unit (1,:) char = ''
                options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Any','Read / Write'})} = 'Any'
                options.Type (1,:) char {mustBeMember(options.Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','File','Undefined'})} = 'Float'
                options.Format (1,:) char = '%g'
                options.Visible (1,1) logical = true
                options.isArray (1,1) logical = false
                options.isTrigger (1,1) logical = false
                options.isRandom (1,1) logical = false
                options.Min (1,1) double = -inf
                options.Max (1,1) double = inf
                options.UserData = []
            end

            if isempty(name)
                vprintf(0, 1, 'Parameter name cannot be empty');
                p = [];
                return
            end

            hwif = obj.findInterface(interfaceName);
            if isempty(hwif)
                vprintf(0, 1, 'Interface "%s" not found in protocol', interfaceName);
                p = [];
                return
            end

            % Build name-value pairs for hw.Interface.add_parameter
            copts = namedargs2cell(options);
            p = hwif.add_parameter(name, value, copts{:});
        end

        function removeParameter(obj, interfaceName, name)
            % removeParameter(obj, interfaceName, name)
            %
            % Remove a parameter from a specific interface.
            %
            % Parameters:
            %   interfaceName (char) - Name of target interface
            %   name (char) - Parameter name to remove
            arguments
                obj
                interfaceName (1,:) char
                name (1,:) char
            end

            hwif = obj.findInterface(interfaceName);
            if isempty(hwif)
                vprintf(0, 1, 'Interface "%s" not found', interfaceName);
                return
            end

            % Find and remove parameter from all modules
            for m = 1:length(hwif.Module)
                idx = [];
                for p = 1:length(hwif.Module(m).Parameters)
                    if strcmp(hwif.Module(m).Parameters(p).Name, name)
                        idx = p;
                        break
                    end
                end
                if ~isempty(idx)
                    hwif.Module(m).Parameters(idx) = [];
                    return
                end
            end

            vprintf(0, 1, 'Parameter "%s" not found in interface "%s"', name, interfaceName);
        end

        % ===== PROTOCOL OPTIONS =====

        function setOption(obj, name, value)
            % setOption(obj, name, value)
            %
            % Update a protocol option field.
            %
            % Parameters:
            %   name (char) - Option field name (e.g., 'trialFunc', 'compileAtRuntime')
            %   value - New value for the option
            arguments
                obj
                name (1,:) char
                value
            end

            if ~isfield(obj.Options, name)
                vprintf(0, 1, 'Unknown option "%s"', name);
                return
            end

            obj.Options.(name) = value;
        end

        % ===== COMPILATION & VALIDATION =====

        compile(obj)                  % Compile protocol trials - compile.m
        report = validate(obj)        % Validate protocol - validate.m

        function dur_sec = estimateDuration(obj)
            % dur_sec = estimateDuration(obj)
            %
            % Estimate total trial duration in seconds based on COMPILED trials.
            %
            % Returns:
            %   dur_sec (double) - Estimated duration in seconds, or NaN if compilation incomplete
            
            if isempty(obj.COMPILED.trials)
                dur_sec = nan;
                return
            end

            ntrials = size(obj.COMPILED.trials, 1);
            trial_duration_sec = 2;  % Assume 2 sec per trial (baseline)
            
            dur_sec = ntrials * trial_duration_sec;
        end

        % ===== SERIALIZATION =====

        save(obj, filename)             % Serialize to .eprot or .json - save.m
        toJSON(obj, filename)           % Serialize to JSON - toJSON.m
        struct_out = toStruct(obj)      % Convert to serializable struct - toStruct.m
        fromStruct(obj, struct_in)      % Restore state from struct - fromStruct.m

    end

    methods (Static)
        obj = load(filename)       % Deserialize from .eprot or .json - load.m
        obj = fromJSON(filename)   % Deserialize from JSON - fromJSON.m
    end

    methods (Access = private)
        % Serialization helpers - separate method files
        interface = createInterfaceFromStruct_(obj, ifaceStruct)        % Reconstruct interface from struct - createInterfaceFromStruct_.m
        interface = createRecoveredInterfaceFromCompiled_(obj)           % Recover interface from COMPILED - createRecoveredInterfaceFromCompiled_.m

        % Compilation helpers - separate method files
        compile_internal(obj)                                            % Core compile logic - compile_internal.m
        trials_out = expand_cross_product(obj, trials_in, paramMetadata) % Cross-product expansion - expand_cross_product.m

        % Validation helpers - separate method files
        report = validate_internal(obj)                                  % Core validate logic - validate_internal.m

        % Calibration / WAV buffer helpers - separate method files
        out_vals = apply_calibration(obj, in_vals, cal_struct)           % Apply calibration - apply_calibration.m
        trials_out = apply_wav_buffers(obj, trials_in, wav_data)         % Expand WAV buffers - apply_wav_buffers.m

        function parameterType = inferSerializedParameterType_(~, trials, colIdx)
            parameterType = 'String';
            if isempty(trials)
                return
            end

            sampleValue = trials{1, colIdx};
            if islogical(sampleValue)
                parameterType = 'Boolean';
            elseif isnumeric(sampleValue)
                if all(abs(sampleValue(:) - round(sampleValue(:))) < 1e-9)
                    parameterType = 'Integer';
                else
                    parameterType = 'Float';
                end
            elseif ischar(sampleValue) || isstring(sampleValue)
                [~, fileName, extension] = fileparts(char(string(sampleValue)));
                if ~isempty(fileName) || ~isempty(extension)
                    parameterType = 'File';
                end
            elseif iscell(sampleValue)
                parameterType = 'File';
            end
        end

        function value = getRecoveredParameterValue_(~, trials, colIdx)
            if isempty(trials)
                value = '';
            else
                value = trials{1, colIdx};
            end
        end

        function values = normalizeRecoveredValue_(~, value)
            if iscell(value)
                values = value;
            elseif isstring(value)
                values = cellstr(value);
            elseif isnumeric(value) || islogical(value)
                values = num2cell(value);
            else
                values = {value};
            end
        end

        function fullName = getCompiledParameterName_(~, parameter, interfaceType, module)
            if strcmp(interfaceType, 'Software')
                fullName = parameter.Name;
            else
                fullName = sprintf('%s.%s', module.Name, parameter.Name);
            end
        end

        function pairName = getParameterPairName_(~, parameter)
            pairName = '';
            userData = parameter.UserData;
            if ~isstruct(userData)
                return
            end

            if isfield(userData, 'Pair') && ~isempty(userData.Pair)
                pairName = strtrim(char(string(userData.Pair)));
            elseif isfield(userData, 'Buddy') && ~isempty(userData.Buddy)
                pairName = strtrim(char(string(userData.Buddy)));
            end
        end

        function values = normalizeParameterValuesForTrials_(~, value)
            if isnumeric(value) || islogical(value)
                if isempty(value) || isscalar(value)
                    values = {value};
                else
                    values = num2cell(reshape(value, 1, []));
                end
                return
            end

            if isstring(value)
                if isscalar(value)
                    values = {char(value)};
                else
                    values = reshape(cellstr(value), 1, []);
                end
                return
            end

            if ischar(value)
                values = {value};
                return
            end

            if iscell(value)
                if isempty(value)
                    values = {value};
                else
                    values = reshape(value, 1, []);
                end
                return
            end

            values = {value};
        end
    end

end
