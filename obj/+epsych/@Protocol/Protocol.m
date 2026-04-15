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
    %   Options          - Struct holding randomize, numReps, ISI, trialFunc, compileAtRuntime
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
    %   P.setOption('randomize', true);
    %   P.setOption('numReps', 3);
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
            'randomize', true, ...
            'numReps', 1, ...
            'ISI', 1000, ...
            'trialFunc', '', ...
            'compileAtRuntime', false, ...
            'IncludeWAVBuffers', true, ...
            'UseOpenEx', true, ...
            'ConnectionType', 'GB')
        
        Info (1,:) char = ''
        
        COMPILED struct = struct(...
            'writeparams', {{}}, ...
            'readparams', {{}}, ...
            'randparams', {[]}, ...
            'trials', {{}}, ...
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
            obj.meta.epsychVersion = sprintf('EPsych v%s (Data v%s)', E.Version, E.DataVersion);
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

            % Check for duplicate names
            existing_names = [];
            for i = 1:length(obj.Interfaces)
                if isprop(obj.Interfaces(i), 'Name')
                    existing_names = [existing_names, {obj.Interfaces(i).Name}]; %#ok<AGROW>
                end
            end
            
            if any(strcmp(options.Name, existing_names))
                vprintf(0, 1, 'Interface with name "%s" already exists', options.Name);
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
            %   name (char) - Option field name (e.g., 'randomize', 'numReps', 'ISI', 'trialFunc')
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

        function compile(obj)
            % compile(obj)
            %
            % Compile protocol into COMPILED struct containing writeparams, readparams,
            % randparams, trials, and OPTIONS. Calls validate() first; errors abort compilation.
            %
            % Sets obj.COMPILED with fields:
            %   writeparams - cell array of writable parameter names
            %   readparams  - cell array of readable parameter names
            %   randparams  - array indicating which params are randomized
            %   trials      - cell array (Ntrials x Nparams) of trial values
            %   OPTIONS     - copy of obj.Options
            %   ntrials     - number of compiled trials
            
            % Validate first
            report = obj.validate();
            if ~isempty(report)
                severity_levels = [report.severity];
                if any(severity_levels == 2)  % error level
                    vprintf(0, 1, 'Cannot compile: validation errors present. Call validate() for details.');
                    return
                end
            end

            % Delegate to compile method
            obj.compile_internal();
        end

        function save(obj, filename)
            % save(obj, filename)
            %
            % Serialize protocol to .eprot MAT file.
            %
            % Parameters:
            %   filename (char) - Output filename (should end in .eprot)
            %
            % The MAT file contains a single variable 'protocol' for
            % deserialization.
            
            arguments
                obj
                filename (1,:) char
            end

            % Update modification time
            obj.meta.lastModified = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');

            % Convert to struct for MAT serialization
            protocol = obj.toStruct();

            % Save to MAT file using builtin save function
            builtin('save', filename, 'protocol', '-mat');
            fprintf('[INFO] Protocol saved to: %s\n', filename);
        end

        function report = validate(obj)
            % report = validate(obj)
            %
            % Validate protocol for logical and structural errors.
            %
            % Returns:
            %   report - struct array with fields {field, message, severity}
            %       severity: 0=warning, 1=warning, 2=error
            %
            % See validate.m for implementation
            report = obj.validate_internal();
        end

        function dur_sec = estimateDuration(obj)
            % dur_sec = estimateDuration(obj)
            %
            % Estimate total trial duration in seconds based on COMPILED trials and ISI.
            %
            % Returns:
            %   dur_sec (double) - Estimated duration in seconds, or NaN if compilation incomplete
            
            if isempty(obj.COMPILED.trials)
                dur_sec = nan;
                return
            end

            ntrials = size(obj.COMPILED.trials, 1);
            isi_sec = obj.Options.ISI / 1000;  % ISI is in ms
            trial_duration_sec = 2;  % Assume 2 sec per trial (baseline)
            
            dur_sec = ntrials * (trial_duration_sec + isi_sec);
        end

        % ===== SERIALIZATION =====

        function struct_out = toStruct(obj)
            % struct_out = toStruct(obj)
            %
            % Convert protocol to a serializable struct. Called by save().
            %
            % Returns:
            %   struct_out - Struct with fields: Options, Info, COMPILED, meta, InterfaceData
            
            % Start with basic structure
            struct_out = struct();
            struct_out.formatVersion = obj.meta.formatVersion;
            struct_out.epsychVersion = obj.meta.epsychVersion;
            struct_out.createdDate = datestr(now);
            struct_out.lastModified = datestr(now);
            
            % Protocol options and info
            struct_out.Options = obj.Options;
            struct_out.Info = obj.Info;
            struct_out.COMPILED = obj.COMPILED;
            
            % Serialize interfaces, modules, and parameters.
            struct_out.InterfaceCount = length(obj.Interfaces);
            struct_out.InterfaceData = cell(1, length(obj.Interfaces));
            for ifaceIdx = 1:length(obj.Interfaces)
                iface = obj.Interfaces(ifaceIdx);
                ifaceStruct = struct();
                ifaceStruct.Type = char(iface.Type);
                ifaceStruct.ClassName = class(iface);
                if isprop(iface, 'Server') && ~isempty(iface.Server)
                    ifaceStruct.Server = iface.Server;
                end
                if isprop(iface, 'ConnectionType') && ~isempty(iface.ConnectionType)
                    ifaceStruct.ConnectionType = iface.ConnectionType;
                end
                ifaceStruct.Modules = cell(1, length(iface.Module));
                for moduleIdx = 1:length(iface.Module)
                    module = iface.Module(moduleIdx);
                    moduleStruct = struct();
                    moduleStruct.Label = module.Label;
                    moduleStruct.Name = module.Name;
                    moduleStruct.Index = double(module.Index);
                    moduleStruct.Fs = module.Fs;
                    moduleStruct.Info = module.Info;
                    moduleStruct.Parameters = cell(1, length(module.Parameters));
                    for paramIdx = 1:length(module.Parameters)
                        moduleStruct.Parameters{paramIdx} = module.Parameters(paramIdx).toStruct();
                    end
                    ifaceStruct.Modules{moduleIdx} = moduleStruct;
                end
                struct_out.InterfaceData{ifaceIdx} = ifaceStruct;
            end
        end

        function obj = fromStruct(obj, struct_in)
            % fromStruct(obj, struct_in) - Restore protocol state from struct
            % 
            % Parameters:
            %   struct_in - Struct with fields matching toStruct() output
            %
            % This method restores the protocol from a serialized struct.
            
            arguments
                obj
                struct_in struct
            end
            
            % Restore from struct
            if isfield(struct_in, 'Options')
                obj.Options = struct_in.Options;
            end
            
            if isfield(struct_in, 'Info')
                obj.Info = struct_in.Info;
            end
            
            if isfield(struct_in, 'COMPILED')
                obj.COMPILED = struct_in.COMPILED;
            end

            obj.Interfaces = hw.Interface.empty();
            obj.SoftwareModule = hw.Software();

            if isfield(struct_in, 'InterfaceData') && ~isempty(struct_in.InterfaceData)
                for ifaceIdx = 1:length(struct_in.InterfaceData)
                    ifaceStruct = struct_in.InterfaceData{ifaceIdx};
                    if isempty(ifaceStruct)
                        continue
                    end

                    restoredInterface = obj.createInterfaceFromStruct_(ifaceStruct);
                    obj.Interfaces(end + 1) = restoredInterface; %#ok<AGROW>
                    if isa(restoredInterface, 'hw.Software')
                        obj.SoftwareModule = restoredInterface;
                    end
                end
            elseif isfield(obj.COMPILED, 'writeparams') && ~isempty(obj.COMPILED.writeparams)
                recoveredInterface = obj.createRecoveredInterfaceFromCompiled_();
                obj.Interfaces = recoveredInterface;
                if isa(recoveredInterface, 'hw.Software')
                    obj.SoftwareModule = recoveredInterface;
                end
            else
                obj.Interfaces = obj.SoftwareModule;
            end
        end

    end

    methods (Static)
        function obj = load(filename)
            % obj = epsych.Protocol.load(filename)
            % Deserialize protocol from an .eprot MAT file or a .json file.
            %
            % Parameters:
            %   filename (char) - File to load (.eprot, .prot, or .json)
            %
            % Returns:
            %   obj - Deserialized epsych.Protocol instance

            arguments
                filename (1,:) char
            end

            if ~isfile(filename)
                error('epsych:Protocol:FileNotFound', 'File not found: %s', filename);
            end

            [~, ~, ext] = fileparts(filename);
            if strcmpi(ext, '.json')
                obj = epsych.Protocol.fromJSON(filename);
                return
            end

            % Load MAT file using builtin function
            S = builtin('load', filename, '-mat');

            % Direct object load (current format)
            if isfield(S, 'protocol') && isa(S.protocol, 'epsych.Protocol')
                obj = S.protocol;
                fprintf('[INFO] Protocol loaded from: %s\n', filename);
                return
            end

            % Legacy fallback: struct-based files
            if isfield(S, 'protocol_struct')
                struct_in = S.protocol_struct;
            elseif isfield(S, 'protocol')
                struct_in = S.protocol;
            else
                error('epsych:Protocol:InvalidFile', 'MAT file does not contain expected protocol data');
            end

            obj = epsych.Protocol();
            obj.fromStruct(struct_in);
            fprintf('[INFO] Protocol loaded from: %s\n', filename);
        end

        function obj = fromJSON(filename)
            % obj = epsych.Protocol.fromJSON(filename)
            % Deserialize a protocol from a JSON file.
            %
            % Parameters:
            %   filename (char) - Path to a .json protocol file
            %
            % Returns:
            %   obj - Initialized epsych.Protocol instance
            %
            % Implementation is provided by fromJSON.m in the class folder,
            % which takes precedence over this inline definition per MATLAB rules.
            arguments
                filename (1,:) char
            end
            error('epsych:Protocol:MissingMethodFile', ...
                'fromJSON.m not found in the @Protocol class folder.');
        end
    end

    methods (Access = private)
        function interface = createInterfaceFromStruct_(~, ifaceStruct)
            ifaceType = char(string(ifaceStruct.Type));
            switch ifaceType
                case 'Software'
                    interface = hw.Software();
                case 'TDT_Synapse'
                    server = 'localhost';
                    if isfield(ifaceStruct, 'Server') && ~isempty(ifaceStruct.Server)
                        server = char(string(ifaceStruct.Server));
                    end
                    interface = hw.TDT_Synapse(server, Connect = false);
                case 'TDT_RPcox'
                    connectionType = 'GB';
                    if isfield(ifaceStruct, 'ConnectionType') && ~isempty(ifaceStruct.ConnectionType)
                        connectionType = char(string(ifaceStruct.ConnectionType));
                    elseif isfield(ifaceStruct, 'Modules') && ~isempty(ifaceStruct.Modules) ...
                            && isfield(ifaceStruct.Modules{1}.Info, 'ConnectionType') && ~isempty(ifaceStruct.Modules{1}.Info.ConnectionType)
                        connectionType = char(string(ifaceStruct.Modules{1}.Info.ConnectionType));
                    end
                    interface = hw.TDT_RPcox({}, {}, {}, Interface = connectionType, Connect = false);
                otherwise
                    interface = hw.TDT_RPcox({}, {}, {}, Connect = false);
            end

            modules = hw.Module.empty(1, 0);
            if isfield(ifaceStruct, 'Modules') && ~isempty(ifaceStruct.Modules)
                for moduleIdx = 1:length(ifaceStruct.Modules)
                    moduleStruct = ifaceStruct.Modules{moduleIdx};
                    module = hw.Module(interface, char(moduleStruct.Label), char(moduleStruct.Name), uint8(moduleStruct.Index));
                    if isfield(moduleStruct, 'Fs') && ~isempty(moduleStruct.Fs)
                        module.Fs = double(moduleStruct.Fs);
                    end
                    if isfield(moduleStruct, 'Info') && isstruct(moduleStruct.Info)
                        module.Info = moduleStruct.Info;
                    end
                    if isfield(moduleStruct, 'Parameters') && ~isempty(moduleStruct.Parameters)
                        for paramIdx = 1:length(moduleStruct.Parameters)
                            paramStruct = moduleStruct.Parameters{paramIdx};
                            parameter = hw.Parameter(interface);
                            parameter.Module = module;
                            parameter.fromStruct(paramStruct);
                            module.Parameters(end + 1) = parameter; %#ok<AGROW>
                        end
                    end
                    modules(end + 1) = module; %#ok<AGROW>
                end
            end

            if isa(interface, 'hw.Software')
                interface.set_module(modules);
            else
                interface.setModules(modules);
            end
        end

        function interface = createRecoveredInterfaceFromCompiled_(obj)
            writeparams = obj.COMPILED.writeparams;
            trials = obj.COMPILED.trials;
            hasModuleNames = any(contains(string(writeparams), '.'));

            if hasModuleNames
                connectionType = 'GB';
                if isfield(obj.Options, 'ConnectionType') && ~isempty(obj.Options.ConnectionType)
                    connectionType = char(string(obj.Options.ConnectionType));
                end
                interface = hw.TDT_RPcox({}, {}, {}, Interface = connectionType, Connect = false);
            else
                interface = hw.Software();
            end

            moduleMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            modules = hw.Module.empty(1, 0);
            for colIdx = 1:numel(writeparams)
                writeParamName = char(string(writeparams{colIdx}));
                if contains(writeParamName, '.')
                    parts = split(string(writeParamName), '.');
                    moduleName = char(parts(1));
                    parameterName = char(parts(2));
                else
                    moduleName = 'Params';
                    parameterName = writeParamName;
                end

                if ~isKey(moduleMap, moduleName)
                    module = hw.Module(interface, moduleName, moduleName, uint8(length(modules) + 1));
                    modules(end + 1) = module; %#ok<AGROW>
                    moduleMap(moduleName) = module;
                end
                module = moduleMap(moduleName);

                parameter = hw.Parameter(interface, Type = obj.inferSerializedParameterType_(trials, colIdx));
                parameter.Name = parameterName;
                parameter.Module = module;
                parameter.Value = obj.getRecoveredParameterValue_(trials, colIdx);
                parameter.Access = 'Any';
                parameter.Visible = true;
                parameter.isArray = numel(obj.normalizeRecoveredValue_(parameter.Value)) > 1;
                module.Parameters(end + 1) = parameter; %#ok<AGROW>
            end

            if isa(interface, 'hw.Software')
                interface.set_module(modules);
            else
                interface.setModules(modules);
            end
        end

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

        function compile_internal(obj)
            % compile_internal(obj) - Private method implementing the compile logic
            %
            % Migrates the multi-stage process from legacy ep_CompileProtocol:
            % 1. Gather parameters from all interfaces
            % 2. Build writeparams/readparams arrays
            % 3. Expand parameter values while preserving paired groups
            % 4. Apply repetitions without reordering preview rows

            writeparams = {};
            readparams = {};
            randparams = [];
            trials = cell(1, 0);
            colIdx = 1;
            paramMetadata = {};

            for iface_idx = 1:length(obj.Interfaces)
                iface = obj.Interfaces(iface_idx);
                iface_type = char(iface.Type);

                for mod_idx = 1:length(iface.Module)
                    module = iface.Module(mod_idx);

                    for param_idx = 1:length(module.Parameters)
                        p = module.Parameters(param_idx);

                        if ~p.Visible
                            continue
                        end

                        full_name = obj.getCompiledParameterName_(p, iface_type, module);
                        if ~strcmp(p.Access, 'Write')
                            readparams{end+1} = full_name;  %#ok<AGROW>
                        end

                        if strcmp(p.Access, 'Read')
                            continue
                        end

                        writeparams{end+1} = full_name;  %#ok<AGROW>
                        randparams(end+1) = p.isRandom;  %#ok<AGROW>

                        trials{1, colIdx} = p.Value;
                        paramMetadata{colIdx} = struct(...
                            'name', full_name, ...
                            'pair', obj.getParameterPairName_(p)); %#ok<AGROW>

                        colIdx = colIdx + 1;
                    end
                end
            end

            if isempty(writeparams)
                obj.COMPILED.writeparams = {};
                obj.COMPILED.readparams = readparams;
                obj.COMPILED.randparams = [];
                obj.COMPILED.trials = {};
                obj.COMPILED.OPTIONS = obj.Options;
                obj.COMPILED.ntrials = 0;
                return
            end

            trials = obj.expand_cross_product(trials, paramMetadata);
            if isempty(trials)
                vprintf(0, 1, 'No trials generated after paired expansion');
                obj.COMPILED.writeparams = writeparams;
                obj.COMPILED.readparams = readparams;
                obj.COMPILED.randparams = randparams;
                obj.COMPILED.trials = {};
                obj.COMPILED.OPTIONS = obj.Options;
                obj.COMPILED.ntrials = 0;
                return
            end

            uniqueTrialCount = size(trials, 1);
            nreps = obj.Options.numReps;
            if ~isinf(nreps) && nreps > 0
                trials = repmat(trials, nreps, 1);
            end

            obj.COMPILED.writeparams = writeparams;
            obj.COMPILED.readparams = readparams;
            obj.COMPILED.randparams = randparams;
            obj.COMPILED.trials = trials;
            obj.COMPILED.OPTIONS = obj.Options;
            obj.COMPILED.ntrials = size(trials, 1);

            vprintf(2, 'Protocol compiled: %d unique trials, %d total with %d repetitions', ...
                uniqueTrialCount, obj.COMPILED.ntrials, nreps);
        end

        function trials_out = expand_cross_product(obj, trials_in, paramMetadata)
            % expand_cross_product(obj, trials_in, randparams_in)

            if isempty(trials_in)
                trials_out = {};
                return
            end

            nCols = size(trials_in, 2);
            groupKeys = {};
            groupColumns = {};
            groupValueSets = {};

            for col = 1:nCols
                valueSet = obj.normalizeParameterValuesForTrials_(trials_in{1, col});
                pairName = strtrim(char(string(paramMetadata{col}.pair)));
                if isempty(pairName)
                    groupKey = sprintf('__solo_%d__', col);
                else
                    groupKey = sprintf('pair:%s', pairName);
                end

                groupIdx = find(strcmp(groupKeys, groupKey), 1);
                if isempty(groupIdx)
                    groupKeys{end + 1} = groupKey; %#ok<AGROW>
                    groupColumns{end + 1} = col; %#ok<AGROW>
                    groupValueSets{end + 1} = {valueSet}; %#ok<AGROW>
                else
                    groupColumns{groupIdx}(end + 1) = col;
                    groupValueSets{groupIdx}{end + 1} = valueSet;
                end
            end

            groupLengths = ones(1, numel(groupKeys));
            for groupIdx = 1:numel(groupKeys)
                valueLengths = cellfun(@numel, groupValueSets{groupIdx});
                if any(valueLengths ~= valueLengths(1))
                    error('Pair group %s has mismatched value counts.', groupKeys{groupIdx});
                end
                groupLengths(groupIdx) = valueLengths(1);
            end

            if numel(groupLengths) == 1
                combos = (1:groupLengths(1)).';
            else
                gridArgs = cell(1, numel(groupLengths));
                for groupIdx = 1:numel(groupLengths)
                    gridArgs{groupIdx} = 1:groupLengths(groupIdx);
                end

                grid = cell(1, numel(groupLengths));
                [grid{:}] = ndgrid(gridArgs{:});
                combos = zeros(numel(grid{1}), numel(groupLengths));
                for groupIdx = 1:numel(groupLengths)
                    combos(:, groupIdx) = grid{groupIdx}(:);
                end
            end

            trials_out = cell(size(combos, 1), nCols);
            for comboIdx = 1:size(combos, 1)
                for groupIdx = 1:numel(groupKeys)
                    valueIdx = combos(comboIdx, groupIdx);
                    groupCols = groupColumns{groupIdx};
                    groupValues = groupValueSets{groupIdx};
                    for memberIdx = 1:numel(groupCols)
                        trials_out{comboIdx, groupCols(memberIdx)} = groupValues{memberIdx}{valueIdx};
                    end
                end
            end
        end

        function report = validate_internal(obj)
            % validate_internal(obj)
            % Internal implementation of validate().

            report = struct('field', {}, 'message', {}, 'severity', {});
            idx = 1;
            pairGroups = struct('name', {}, 'members', {}, 'valueCounts', {});

            if isempty(obj.Interfaces)
                report(idx).field = 'Interfaces';
                report(idx).message = 'No interfaces defined';
                report(idx).severity = 2;
                idx = idx + 1;
            end

            writeParamCount = 0;
            for ifaceIdx = 1:length(obj.Interfaces)
                iface = obj.Interfaces(ifaceIdx);
                for modIdx = 1:length(iface.Module)
                    for paramIdx = 1:length(iface.Module(modIdx).Parameters)
                        p = iface.Module(modIdx).Parameters(paramIdx);
                        if p.Visible && ~strcmp(p.Access, 'Read')
                            writeParamCount = writeParamCount + 1;
                        end
                    end
                end
            end

            if writeParamCount == 0
                report(idx).field = 'Parameters';
                report(idx).message = 'No writable parameters defined';
                report(idx).severity = 2;
                idx = idx + 1;
            end

            if ~isfinite(obj.Options.ISI) || obj.Options.ISI <= 0
                report(idx).field = 'Options.ISI';
                report(idx).message = sprintf('ISI must be positive (got %.1f)', obj.Options.ISI);
                report(idx).severity = 2;
                idx = idx + 1;
            end

            if ~isfinite(obj.Options.numReps) || (obj.Options.numReps < 1 && ~isinf(obj.Options.numReps))
                report(idx).field = 'Options.numReps';
                report(idx).message = sprintf('numReps must be >= 1 (got %.1f)', obj.Options.numReps);
                report(idx).severity = 2;
                idx = idx + 1;
            end

            if ~isempty(obj.Options.trialFunc) && ischar(obj.Options.trialFunc)
                try
                    funcHandle = str2func(obj.Options.trialFunc);
                    if isempty(functions(funcHandle))
                        report(idx).field = 'Options.trialFunc';
                        report(idx).message = sprintf('Trial function "%s" not found on path', obj.Options.trialFunc);
                        report(idx).severity = 2;
                        idx = idx + 1;
                    end
                catch
                    report(idx).field = 'Options.trialFunc';
                    report(idx).message = sprintf('Trial function "%s" not accessible', obj.Options.trialFunc);
                    report(idx).severity = 2;
                    idx = idx + 1;
                end
            end

            for ifaceIdx = 1:length(obj.Interfaces)
                iface = obj.Interfaces(ifaceIdx);
                ifaceType = char(iface.Type);
                for modIdx = 1:length(iface.Module)
                    module = iface.Module(modIdx);
                    for paramIdx = 1:length(module.Parameters)
                        p = module.Parameters(paramIdx);
                        if ~p.Visible
                            continue
                        end

                        fullName = sprintf('%s.%s.%s', ifaceType, module.Name, p.Name);
                        if p.Min > p.Max
                            report(idx).field = fullName;
                            report(idx).message = sprintf('Min (%.2f) > Max (%.2f)', p.Min, p.Max);
                            report(idx).severity = 2;
                            idx = idx + 1;
                        end

                        if p.isRandom && (~isfinite(p.Min) || ~isfinite(p.Max))
                            report(idx).field = fullName;
                            report(idx).message = 'Random parameters must have finite Min and Max values';
                            report(idx).severity = 2;
                            idx = idx + 1;
                        end

                        if isequal(p.Type, 'File')
                            if ~(ischar(p.Value) || isstring(p.Value) || iscellstr(p.Value))
                                report(idx).field = fullName;
                                report(idx).message = 'File parameters must contain a file path or a cell array of file paths';
                                report(idx).severity = 2;
                                idx = idx + 1;
                            end
                        elseif isnumeric(p.Value) && isscalar(p.Value)
                            if p.Value < p.Min || p.Value > p.Max
                                report(idx).field = fullName;
                                report(idx).message = sprintf('Value %.2f outside bounds [%.2f, %.2f]', p.Value, p.Min, p.Max);
                                report(idx).severity = 1;
                                idx = idx + 1;
                            end
                        end

                        if strcmp(p.Access, 'Read')
                            continue
                        end

                        pairName = obj.getParameterPairName_(p);
                        if isempty(pairName)
                            continue
                        end

                        valueCount = numel(obj.normalizeParameterValuesForTrials_(p.Value));
                        groupIdx = find(strcmp({pairGroups.name}, pairName), 1);
                        if isempty(groupIdx)
                            pairGroups(end + 1).name = pairName; %#ok<AGROW>
                            pairGroups(end).members = {fullName};
                            pairGroups(end).valueCounts = valueCount;
                        else
                            pairGroups(groupIdx).members{end + 1} = fullName;
                            pairGroups(groupIdx).valueCounts(end + 1) = valueCount;
                        end
                    end
                end
            end

            for groupIdx = 1:numel(pairGroups)
                valueCounts = pairGroups(groupIdx).valueCounts;
                if any(valueCounts ~= valueCounts(1))
                    memberNames = cellfun(@(name) char(string(name)), pairGroups(groupIdx).members, 'UniformOutput', false);
                    memberSummary = arrayfun(@(idx) sprintf('%s (%d)', memberNames{idx}, double(valueCounts(idx))), ...
                        1:numel(memberNames), 'UniformOutput', false);
                    report(idx).field = sprintf('Pair.%s', pairGroups(groupIdx).name);
                    report(idx).message = sprintf('Paired parameters must have the same number of values: %s', strjoin(memberSummary, ', '));
                    report(idx).severity = 2;
                    idx = idx + 1;
                end
            end

            if idx == 1
                report = struct('field', {}, 'message', {}, 'severity', {});
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
