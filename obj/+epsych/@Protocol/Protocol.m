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
    %   dependencyGraph  - Parameter dependency graph implied by Expressions
    %   estimateDuration - Estimate trial duration in seconds
    %   save             - Serialize protocol to .eprot MAT file
    %   load             - Static factory to deserialize from .eprot file
    %   listVersions     - Static: every version an .eprot holds (current + embedded archive)
    %   loadVersion      - Static: load one archived version as a Protocol
    %   restoreVersion   - Static: rewrite an .eprot back to an archived version
    %   compareVersions  - Static: what changed between two versions (one file or two)
    %   diffStructs      - Static: differences between two serialized protocols
    %
    % Example:
    %   P = epsych.Protocol('MyProtocol');
    %   P.addParameter('SoftwareModule', 'ToneFreq', [1000 2000 4000], Unit='Hz', Type='Float');
    %   P.compile();
    %   P.save('MyProtocol.eprot');
    %
    % See also: hw.Interface, hw.Parameter, hw.Software, hw.Module,
    %   documentation/epsych/epsych_Protocol.md

    properties (SetAccess = protected)
        Interfaces (1,:) hw.Interface = hw.Interface.empty()
    end

    properties
        Options struct = struct(...
            'trialFunc', '', ...
            'compileAtRuntime', false, ...
            'IncludeWAVBuffers', true, ...
            'ConnectionType', 'GB')
        
        Info (1,:) char = ''
        
        COMPILED struct = struct(...
            'parameters', [], ...
            'trials', {{}}, ...
            'writeparams', {{}}, ...
            'OPTIONS', struct(), ...
            'ntrials', 0, ...
            'compiledAt', NaT)
        
        meta struct = struct(...
            'formatVersion', 1.0, ...
            'epsychVersion', '', ...
            'createdDate', '', ...
            'lastModified', '', ...
            'protocolVersion', '')  % vN.YYMMDD, incremented on each save
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

        addInterface(obj, interface, options)           % Add an hw.Interface to this protocol - addInterface.m
        removeInterface(obj, identifier)                 % Remove an interface by index or type - removeInterface.m
        replaceInterface(obj, identifier, interface)     % Replace an existing interface - replaceInterface.m
        hwif = findInterface(obj, name)                  % Find an interface by name or type - findInterface.m

        % ===== PARAMETER MANAGEMENT =====

        p = addParameter(obj, interfaceName, name, value, options)  % Add a hw.Parameter to an interface - addParameter.m
        removeParameter(obj, interfaceName, name)                     % Remove a parameter from an interface - removeParameter.m

        % ===== PROTOCOL OPTIONS =====

        setOption(obj, name, value)  % Update a protocol option field - setOption.m

        % ===== COMPILATION & VALIDATION =====

        compile(obj)                  % Compile protocol trials - compile.m
        report = validate(obj)        % Validate protocol - validate.m

        analysis = analyzeExpressions(obj)          % Static analysis of parameter Expressions - analyzeExpressions.m
        report = dryRunExpressions(obj, options)    % Simulate runtime expression evaluation per trial - dryRunExpressions.m
        report = sweepExpressions(obj, options)     % Exhaustive expression evaluation over input cross-products - sweepExpressions.m
        graphData = dependencyGraph(obj, analysis)  % Parameter dependency graph implied by Expressions - dependencyGraph.m

        tf = needsCompile(obj)       % True if compile() must be called before use - needsCompile.m
        dur_sec = estimateDuration(obj) % Estimate total trial duration in seconds - estimateDuration.m

        % ===== SERIALIZATION =====

        save(obj, filename)             % Serialize to .eprot or .json - save.m
        toJSON(obj, filename)           % Serialize to JSON - toJSON.m
        struct_out = toStruct(obj)      % Convert to serializable struct - toStruct.m
        fromStruct(obj, struct_in)      % Restore state from struct - fromStruct.m

        restoreLink = linkInterfacesForValueRestore(obj, extraInterfaces)  % Temporarily expose this Protocol as the interfaces' Runtime so Value restore resolves cross-interface Expressions - linkInterfacesForValueRestore.m

    end

    methods (Static)
        obj = load(filename)       % Deserialize from .eprot or .json - load.m
        obj = fromJSON(filename)   % Deserialize from JSON - fromJSON.m

        v = versionOnDisk(filename)      % Peek at a file's protocolVersion without loading it - versionOnDisk.m
        n = versionNumber(versionString) % Comparable integer N from 'vN.YYMMDD' - versionNumber.m

        % ===== VERSION HISTORY =====
        % Every save archives the superseded content inside the .eprot itself
        % (see writeProtocolFile), so a user can go back to an earlier version.
        index = listVersions(filename)             % Current version + embedded archive, payloads untouched - listVersions.m
        tf = hasVersion(filename, version)         % True when the file's content or archive holds this version - hasVersion.m
        [obj, S] = loadVersion(filename, version)  % Load one version (current or archived) as a Protocol - loadVersion.m
        report = restoreVersion(filename, version, options)  % Rewrite the file back to an archived version - restoreVersion.m

        % What changed between two versions, read from the stored structs
        % alone so no interface, module, or parameter is reconstructed.
        changes = diffStructs(A, B, options)                             % Differences between two toStruct payloads - diffStructs.m
        report = compareVersions(fileA, versionA, fileB, versionB, options)  % Compare two versions, in one file or two - compareVersions.m
    end

    methods (Static, Hidden)
        % Low-level chokepoint every .eprot write routes through: archives the
        % superseded version, writes atomically, clears the phase cache.
        % Hidden rather than private because Runtime.writeParametersProtocol
        % uses it for phase saves.
        writeProtocolFile(filename, protocolStruct, options)  % writeProtocolFile.m
    end

    methods (Static, Access = private)
        [P, H, info] = readRaw_(filename)  % Selectively read the protocol struct + embedded history - readRaw_.m
    end

    methods (Access = private)
        % Serialization helpers - separate method files
        [interface, parameters, paramStructs] = createInterfaceFromStruct_(obj, ifaceStruct)  % Reconstruct interface (metadata only) from struct - createInterfaceFromStruct_.m
        interface = createRecoveredInterfaceFromCompiled_(obj)           % Recover interface from COMPILED - createRecoveredInterfaceFromCompiled_.m

        % Compilation helpers - separate method files
        compile_internal(obj)                                            % Core compile logic - compile_internal.m
        trials_out = expand_cross_product(obj, trials_in, paramMetadata) % Cross-product expansion - expand_cross_product.m

        % Validation helpers - separate method files
        report = validate_internal(obj)                                  % Core validate logic - validate_internal.m
        issues = expressionIssues_(obj, analysis)                        % Map expression analysis to validate()-style issues - expressionIssues_.m

        parameterType = inferSerializedParameterType_(obj, trials, colIdx)  % Infer parameter type from compiled trial data - inferSerializedParameterType_.m

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

        parameters = resolveCompiledParameters_(obj)  % Rebuild COMPILED.parameters from writeparams and interfaces - resolveCompiledParameters_.m

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

        values = normalizeParameterValuesForTrials_(obj, value)  % Normalize parameter values to a cell row vector - normalizeParameterValuesForTrials_.m
    end

end
