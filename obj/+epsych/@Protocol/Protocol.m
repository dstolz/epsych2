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
    % cross-product of parameter values and their buddy groups.
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
            % The MAT file contains a single variable 'protocol_struct' for
            % deserialization.
            
            arguments
                obj
                filename (1,:) char
            end

            % Update modification time
            obj.meta.lastModified = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');

            % Convert to struct for MAT serialization
            protocol_struct = obj.toStruct();

            % Save to MAT file using builtin save function
            builtin('save', filename, 'protocol_struct', '-mat');
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
            struct_out.formatVersion = '1.0';
            struct_out.epsychVersion = '1.0.0';
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

                    restoredInterface = obj.createSerializedInterface_(ifaceStruct);
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
            % obj = epsych.Protocol.load(filename) - Deserialize protocol from .eprot MAT file
            % Static method for loading protocols

            arguments
                filename (1,:) char
            end

            if ~isfile(filename)
                error('File not found: %s', filename);
            end

            % Load MAT file using builtin function
            S = builtin('load', filename, '-mat');
            
            % Determine what variable name was used
            if isfield(S, 'protocol_struct')
                struct_in = S.protocol_struct;
            elseif isfield(S, 'protocol')
                struct_in = S.protocol;
            else
                error('MAT file does not contain expected protocol data');
            end

            % Create new Protocol and populate from struct
            obj = epsych.Protocol();
            obj.fromStruct(struct_in);
            
            fprintf('[INFO] Protocol loaded from: %s\n', filename);
        end
    end

    methods (Access = private)
        function interface = createSerializedInterface_(~, ifaceStruct)
            ifaceType = char(string(ifaceStruct.Type));
            switch ifaceType
                case 'Software'
                    interface = hw.Software();
                case 'TDT_Synapse'
                    interface = hw.SerializedTDT_Synapse();
                case 'TDT_RPcox'
                    interface = hw.SerializedTDT_RPcox();
                otherwise
                    interface = hw.SerializedTDT_RPcox();
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
                interface = hw.SerializedTDT_RPcox();
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
            % 1. Gather parameters and calibrations from all interfaces
            % 2. Build writeparams/readparams arrays
            % 3. Apply calibration injection
            % 4. Apply WAV buffer expansion
            % 5. Cross-product expansion (includes partner grouping and randomization)
            % 6. Apply repetitions and randomization at trial level
            
            % Initialize output fields
            writeparams = {};
            readparams = {};
            randparams = [];
            trials = {};
            partner_groups = {};
            
            % === PHASE 1: Gather parameters from all interfaces ===
            col_idx = 1;
            param_metadata = {};  % Track {name, access, partner, calibration} for later use
            
            for iface_idx = 1:length(obj.Interfaces)
                iface = obj.Interfaces(iface_idx);
                iface_type = char(iface.Type);
                
                for mod_idx = 1:length(iface.Module)
                    module = iface.Module(mod_idx);
                    
                    for param_idx = 1:length(module.Parameters)
                        p = module.Parameters(param_idx);
                        
                        % Skip hidden/internal parameters
                        if ~p.Visible
                            continue
                        end
                        
                        % Build fully qualified parameter name
                        if strcmp(iface_type, 'Software')
                            full_name = p.Name;  % Software params use simple names
                        else
                            full_name = sprintf('%s.%s', module.Name, p.Name);
                        end
                        
                        % Add to param lists based on access
                        if ~strcmp(p.Access, 'Write')
                            readparams{end+1} = full_name;  %#ok<AGROW>
                        end
                        if ~strcmp(p.Access, 'Read')
                            writeparams{end+1} = full_name;  %#ok<AGROW>
                        end
                        
                        % Track random flag (simplified; no calibration complexity yet)
                        randparams(end+1) = p.isRandom;  %#ok<AGROW>
                        
                        % Initialize trial column with parameter values
                        if isscalar(p.Value)
                            trials{1, col_idx} = p.Value;
                        else
                            trials{1, col_idx} = p.Value;
                        end
                        
                        param_metadata{col_idx} = struct(...
                            'name', full_name, ...
                            'access', p.Access, ...
                            'partner', '', ...
                            'calibration', '', ...
                            'type', p.Type, ...
                            'isArray', p.isArray);  %#ok<AGROW>
                        
                        col_idx = col_idx + 1;
                    end
                end
            end
            

            % === PHASE 2: Calibration injection (if needed) ===
            % If calibration is required, apply it to relevant parameters before expansion.
            % (Extend this logic as needed for your protocol/calibration system)
            if isprop(obj, 'Calibration') && ~isempty(obj.Calibration)
                vprintf(2, 'Applying calibration to parameters...');
                % Example: apply to all numeric parameters (customize as needed)
                for col = 1:numel(param_metadata)
                    if isfield(param_metadata{col}, 'calibration') && ~isempty(param_metadata{col}.calibration)
                        trials{1, col} = obj.apply_calibration(trials{1, col}, obj.Calibration);
                    end
                end
            end

            % === PHASE 3: WAV buffer handling (if enabled) ===
            if isfield(obj.Options, 'IncludeWAVBuffers') && obj.Options.IncludeWAVBuffers
                if isprop(obj, 'WAVBuffers') && ~isempty(obj.WAVBuffers)
                    vprintf(2, 'Applying WAV buffer expansion...');
                    trials = obj.apply_wav_buffers(trials, obj.WAVBuffers);
                end
            end

            % === PHASE 4: Cross-product expansion ===
            trials = obj.expand_cross_product(trials, randparams);

            vprintf(2, 'After expansion: trials size %dx%d', size(trials));

            if isempty(trials)
                vprintf(0, 1, 'No trials generated after cross-product expansion');
                obj.COMPILED.writeparams = {};
                obj.COMPIILED.readparams = {};
                obj.COMPILED.randparams = [];
                obj.COMPILED.trials = {};
                obj.COMPILED.OPTIONS = obj.Options;
                obj.COMPILED.ntrials = 0;
                return
            end
            
            % === PHASE 3: Apply repetitions without reordering ===
            nreps = obj.Options.numReps;
            if ~isinf(nreps) && nreps > 0
                % Preserve compiled row order even when the protocol requests
                % randomized execution so previewed compiled trials remain stable.
                trials = repmat(trials, nreps, 1);
            end
            
            % === OUTPUT ===
            obj.COMPILED.writeparams = writeparams;
            obj.COMPILED.readparams = readparams;
            obj.COMPILED.randparams = randparams;
            obj.COMPILED.trials = trials;
            obj.COMPILED.OPTIONS = obj.Options;
            obj.COMPILED.ntrials = size(trials, 1);
            
            vprintf(2, 'Protocol compiled: %d unique trials, %d total with %d repetitions', ...
                size(trials,1)/nreps, obj.COMPILED.ntrials, nreps);
        end

        function trials_out = expand_cross_product(~, trials_in, ~)
            % expand_cross_product(obj, trials_in, randparams_in)
            % 
            % Perform cross-product expansion on initial trial rows.
            % Detects parameters with multiple values and generates all combinations.
            
            if isempty(trials_in)
                trials_out = {};
                return
            end
            
            % Find columns that have arrays or file lists that need expansion.
            n_cols = size(trials_in, 2);
            expand_cols = [];
            expand_values = {};
            
            for col = 1:n_cols
                val = trials_in{1, col};
                if isnumeric(val) && numel(val) > 1
                    expand_cols(end+1) = col; %#ok<AGROW>
                    expand_values{end+1} = num2cell(val(:).'); %#ok<AGROW>
                elseif isstring(val) && numel(val) > 1
                    expand_cols(end+1) = col; %#ok<AGROW>
                    expand_values{end+1} = cellstr(val(:).'); %#ok<AGROW>
                elseif iscell(val) && numel(val) > 1
                    expand_cols(end+1) = col; %#ok<AGROW>
                    expand_values{end+1} = reshape(val, 1, []); %#ok<AGROW>
                end
            end
            
            if isempty(expand_cols)
                % No expansion needed, return as-is
                trials_out = trials_in;
                return
            end
            
            % Generate all combinations of the expandable value indices.
            n_expand = length(expand_cols);
            if n_expand == 1
                combos = (1:numel(expand_values{1}))';
            else
                grid_args = cell(1, n_expand);
                for i = 1:n_expand
                    grid_args{i} = 1:numel(expand_values{i});
                end
                
                [grid{1:n_expand}] = ndgrid(grid_args{:});
                
                combos = zeros(numel(grid{1}), n_expand);
                for i = 1:n_expand
                    combos(:, i) = grid{i}(:);
                end
            end
            
            % Create expanded trials matrix
            n_combos = size(combos, 1);
            trials_out = cell(n_combos, n_cols);
            
            for combo_idx = 1:n_combos
                for col = 1:n_cols
                    if ismember(col, expand_cols)
                        expand_idx = find(expand_cols == col);
                        value_idx = combos(combo_idx, expand_idx);
                        trials_out{combo_idx, col} = expand_values{expand_idx}{value_idx};
                    else
                        trials_out{combo_idx, col} = trials_in{1, col};
                    end
                end
            end
        end

        function report = validate_internal(obj)
            % validate_internal(obj)
            % Internal implementation of validate().

            report = struct('field', {}, 'message', {}, 'severity', {});
            idx = 1;

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
                    end
                end
            end

            if idx == 1
                report = struct('field', {}, 'message', {}, 'severity', {});
            end
        end
    end

end
