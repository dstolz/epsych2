

classdef Interface < matlab.mixin.Heterogeneous & matlab.mixin.SetGet
    % Abstract base class for EPsych hardware interfaces.
    %
    % Concrete subclasses expose one or more hw.Module objects and implement
    % connection, parameter I/O, and trigger operations behind a common API.
    %
    % Important properties:
    %   Module      - Modules owned by the interface.
    %   Type        - Constant interface identifier.
    %   mode        - Current hw.DeviceState for the backend.
    %   IsConnected - True when the backend connection is ready.
    %
    % Key methods:
    %   add_parameter  - Add a parameter through the shared interface API.
    %   all_parameters - Return parameters across all modules.
    %   find_parameter - Resolve parameters by name.
    %   connect        - Establish the backend connection.
    %   trigger        - Issue a named hardware event.
    %
    % Documentation: documentation/hw/hw_Interface.md

    properties (Abstract,SetAccess = protected)
        Module
    end

    properties (Abstract,Constant)
        Type
    end

    properties (Abstract,SetObservable,AbortSet)
        mode
    end

    properties (Abstract,Dependent)
        IsConnected (1,1) logical   % true when the backend is connected and ready
    end


    properties
        h_listeners
        Runtime  % Reference to the owning epsych.Runtime; set when registered via Runtime.Interfaces
    end



    methods (Abstract,Access = protected)
        % close_interface()
        %   Release backend resources.
        close_interface()

        % setup_interface()
        %   Allocate or connect backend resources.
        setup_interface()
    end


    methods (Abstract)
        % value = get_parameter(name)
        %   Read current value for one or more hardware parameters.
        value  = get_parameter(name)

        % result = set_parameter(name, value)
        %   Set new value for one or more hardware parameters.
        %   Returns true if successful and false otherwise.
        result = set_parameter(name,value)

        % result = trigger(name)
        %   Trigger a named hardware event.
        result = trigger(name)

        % connect()
        %   Establish a connection to the hardware backend.
        %   Sets IsConnected to true on success.
        connect()
    end

    methods (Abstract, Static)
        % spec = getCreationSpec()
        %   Return a hw.InterfaceSpec describing the options required to create this
        %   interface, including defaults, UI control hints, and a factory function.
        %   Each spec.options entry may include fields such as:
        %     name, label, defaultValue, required, inputType, choices,
        %     isList, scope, allowScalarExpansion, controlType, getFile,
        %     getFolder, fileFilter, fileDialogTitle, and description.
        %   controlType is optional and can be used to steer GUIs toward a
        %   specific widget such as text, textarea, numeric, dropdown,
        %   multiselect, or checkbox.
        %   scope is optional and may be either 'interface' or 'module'.
        %   Module-scoped options represent one value per Module owned by
        %   the interface instance.
        %   allowScalarExpansion is optional and, when true, allows a
        %   single module-scoped value to be applied to every module.
        %   getFile is optional and, when true, indicates the GUI should
        %   provide a file picker backed by uigetfile for that option.
        %   getFolder is optional and, when true, indicates the GUI should
        %   provide a folder picker backed by uigetdir for that option.
        %   fileFilter and fileDialogTitle are optional picker settings
        %   used when getFile or getFolder are enabled.
        spec = getCreationSpec()
    end



    methods
        % add_parameter - Create, initialize, and append a hw.Parameter to this Module
        function P = add_parameter(obj, name, value, options)
            % P = obj.add_parameter(name, value)
            % P = obj.add_parameter(name, value, Name=Value)
            % Create, initialize, and append a hw.Parameter to the module.
            %
            % Parameters
            %   name    - Display name for the new parameter (char).
            %   value   - Initial parameter value. String scalars are converted to char and force Type to 'String'.
            %   options - Name=Value pairs for hw.Parameter metadata (Description, Unit, Access, Type, Format, Visible, callback flags, UserData, isArray, isTrigger, isRandom, Min, Max).
            %
            % Returns
            %   P       - Created hw.Parameter handle.
            %
            % See also: documentation/hw/hw_Module.md, documentation/hw/hw_Parameter.md, hw.Parameter
            arguments
                obj
                name (1,:) char {mustBeText}
                value
                options.Description (1,1) string = ""
                options.Unit (1,:) char = ''
                options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Any','Read / Write'})} = 'Any'
                options.Type (1,:) char {mustBeMember(options.Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','File','Undefined','StimType'})} = 'Float'
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
            copts = namedargs2cell(options);
            P = obj.Module.add_parameter(name, value, copts{:});
        end

        % prepareRecording - Hook to stage backend-side recording before a run
        function prepareRecording(~, ~)
            % prepareRecording(obj, runtime)
            % Lifecycle hook invoked on every interface immediately before the
            % run enters its mode (see epsych.RunExpt.ExptDispatch), while the
            % hardware is still stopped. Backends that must configure recording
            % from the reserved session filename (e.g. hw.Intan_RHX) override
            % this; the default is a no-op.
        end

        % selfTest - Optional diagnostic hook reporting on this backend's health
        function results = selfTest(~, options)
            % results = selfTest(obj)
            % results = selfTest(obj, Invasive=true)
            % Report on this interface's own health for pre-flight diagnostics.
            %
            % Only the backend can distinguish "not plugged in" from "wrong
            % circuit loaded", so each concrete interface is given the chance to
            % check itself. The default returns an empty array, meaning "this
            % backend provides no self-test", which lets callers fall back to
            % their own generic probes.
            %
            % Overrides must never throw: a failed probe is a 'fail' result, not
            % an exception.
            %
            % Parameters:
            %   options.Invasive - When false (default) the backend must not
            %                      change hardware state: no connect, no mode
            %                      writes, no recording configuration. When true
            %                      it may connect and query the live device, and
            %                      must restore the connection state it found.
            %
            % Returns:
            %   results - 1xN struct array built by hw.Interface.selfTestResult.
            %
            % See also: hw.Interface.selfTestResult, epsych.SelfTest,
            %   documentation/hw/hw_Interface.md
            arguments
                ~
                options.Invasive (1,1) logical = false
            end
            results = hw.Interface.selfTestResult();
        end

        % canReadHardwareParameters - Whether parameter discovery is possible for a module
        function tf = canReadHardwareParameters(~, module)
            % tf = canReadHardwareParameters(obj, module)
            % True when readHardwareParameters could discover this module's
            % parameter list right now, without side effects. The default is
            % false, meaning "this backend cannot discover parameters"; GUIs
            % use this to choose messaging before attempting a read.
            %
            % See also: hw.Interface.readHardwareParameters
            arguments
                ~
                module (1,1) hw.Module
            end
            tf = false;
        end

        % readHardwareParameters - Discover a module's parameters from the backend
        function [tf, msg] = readHardwareParameters(obj, module, options)
            % [tf, msg] = readHardwareParameters(obj, module)
            % [tf, msg] = readHardwareParameters(obj, module, Mode='replace')
            % Read the available parameter list from the hardware definition
            % (device, circuit file, or server) and populate module.Parameters.
            %
            % Not every backend can enumerate its parameters; the default
            % implementation declines with tf = false and an explanatory msg,
            % following the selfTest precedent.
            %
            % Override contract:
            %   - Never throw: failures return tf = false with a human-readable
            %     msg, not an exception.
            %   - Do not leave hardware in a changed state (no mode writes, no
            %     replacing obj.Module).
            %   - Call setHardwareParameterName for each discovered parameter
            %     and ensureUniqueParameterNames() before returning.
            %   - Mode='merge' (default): skip discovered parameters whose
            %     hardware name already exists on the module and append the
            %     rest, preserving user edits. Mode='replace': rebuild
            %     module.Parameters purely from the hardware definition.
            %
            % Returns:
            %   tf  - True when discovery ran (even if nothing new was found).
            %   msg - Outcome summary, e.g. 'RZ6: added 12 parameter(s)'.
            %
            % See also: hw.Interface.canReadHardwareParameters
            arguments
                obj
                module (1,1) hw.Module
                options.Mode (1,:) char {mustBeMember(options.Mode,{'merge','replace'})} = 'merge'
            end
            tf = false;
            msg = sprintf('%s does not support reading parameters from hardware.', char(obj.Type));
        end

        % all_parameters - Return all Parameters across all Modules, optionally filtered
        function P = all_parameters(obj, options)
            % P = all_parameters(obj, options)
            % Return all Parameters across all Modules, optionally filtered.
            %
            % Parameters:
            %   obj - hw.Interface. Hardware interface whose modules are queried.
            %   options.includeTriggers   - logical (default=true). Include trigger Parameters.
            %   options.includeInvisible  - logical (default=false). Include Parameters where Visible is false.
            %   options.includeArray      - logical (default=true). Include Parameters with array-valued contents.
            %   options.Access            - char (default='All'). Filter by access type: 'Read', 'Write', 'Any', or 'All'.
            %
            % Returns:
            %   P - hw.Parameter[]. Concatenated Parameters from every module after requested filters are applied.
            %
            % See also: documentation/hw/hw_Interface.md, documentation/hw/hw_Parameter.md
            arguments
                obj
                options.includeTriggers (1,1) logical = true
                options.includeInvisible (1,1) logical = false
                options.includeArray (1,1) logical = true
                options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Any','All','Read / Write'})} = 'All'
                options.asStruct (1,1) logical = false
            end
            P = [obj.Module(:).Parameters];
            if ~options.includeInvisible
                P=P([P.Visible]);
            end
            if ~options.includeTriggers
                P=P(~[P.isTrigger]);
            end
            if ~options.includeArray
                P=P(~[P.isArray]);
            end
            switch options.Access
                case 'Read'
                    P = P(~strcmp({P.Access}, 'Write'));
                case 'Write'
                    P = P(~strcmp({P.Access}, 'Read'));
                case {'Any', 'Read / Write'}
                    P = P(ismember({P.Access}, {'Any', 'Read / Write'}));
                otherwise
                    % no filtering needed
            end
            if options.asStruct
                P_ = struct();
                for k = 1:numel(P)
                    P_.(P(k).validName) = P(k);
                end
                P = P_;
            end

        end

        % filter_parameters - Filter Parameters by comparing a property to a target value
        function P = filter_parameters(obj, propertyName, propertyValue, options, poptions)
            % P = filter_parameters(obj, propertyName, propertyValue, options, poptions)
            % Filter Parameters by comparing a property to a target value.
            %
            % Parameters:
            %   obj           - hw.Interface. Hardware interface that owns the Parameters.
            %   propertyName  - char. Name of the hw.Parameter property to test.
            %   propertyValue - any. Target value or pattern passed to testFcn.
            %   options.testFcn - function_handle (default=@isequal). Comparator such as @isequal, @contains, or @startsWith.
            %   poptions.includeTriggers - logical (default=false). Include trigger Parameters in the candidate set.
            %   poptions.includeInvisible - logical (default=false). Include Parameters where Visible is false.
            %
            % Returns:
            %   P - hw.Parameter[]. Parameters whose selected property matches according to testFcn.
            %
            % See also: documentation/hw/hw_Interface.md, documentation/hw/hw_Parameter.md
            arguments
                obj
                propertyName (1,:) char
                propertyValue
                options.testFcn (1,1) function_handle = @isequal
                poptions.includeTriggers (1,1) logical = false
                poptions.includeInvisible (1,1) logical = false
            end
            poptions = namedargs2cell(poptions);
            P = obj.all_parameters(poptions{:});
            ind = arrayfun(@(a) obj.local_test(options.testFcn, a.(propertyName), propertyValue), P);
            P = P(ind);
        end

        % find_parameter - Return handle(s) to matching hw.Parameter objects by name
        function P = find_parameter(obj, name, options)
            % P = find_parameter(obj, name, options)
            % Return handle(s) to matching hw.Parameter objects by name.
            %
            % Parameters:
            %   obj    - hw.Interface. Hardware interface to search.
            %   name   - char | string | cellstr. Parameter name(s) to search for.
            %            Accepts both short names ('Param') and fully qualified
            %            names ('Module.Param').
            %   options.includeInvisible - logical (default=false). Include Parameters where Visible is false.
            %   options.silenceParameterNotFound - logical (default=false). Suppress warning output when no matches are found.
            %
            % Returns:
            %   P - hw.Parameter[]. Matching Parameter handle(s) in requested name order. Empty if no match.
            %
            % See also: documentation/hw/hw_Interface.md, documentation/hw/hw_Parameter.md
            arguments
                obj
                name
                options.includeInvisible (1,1) logical = false
                options.silenceParameterNotFound (1,1) logical = false
            end
            allP = obj.all_parameters(includeInvisible = options.includeInvisible);
            name = cellstr(name);

            % Build short and qualified name arrays for matching.
            % Qualified names have the form 'Module.Param'.
            shortNames = {allP.Name};
            qualNames  = arrayfun(@(p) [p.Module.Name '.' p.Name], allP, 'UniformOutput', false);

            result = hw.Parameter.empty(1, 0);
            for k = 1:numel(name)
                n = name{k};
                idx = find(strcmp(shortNames, n), 1);
                if isempty(idx)
                    idx = find(strcmp(qualNames, n), 1);
                end
                if ~isempty(idx)
                    result(end + 1) = allP(idx); %#ok<AGROW>
                elseif ~options.silenceParameterNotFound
                    vprintf(0, 1, 'Parameter "%s" was not found on any modules', n);
                end
            end

            if isempty(result)
                P = [];
            else
                P = result;
            end
        end
    end

    methods (Access = protected)
        function ensureUniqueParameterNames(obj)
            parameters = obj.all_parameters(includeInvisible = true, includeTriggers = true);
            if isempty(parameters)
                return
            end

            hardwareNames = arrayfun(@hw.Interface.getHardwareParameterName, parameters, 'UniformOutput', false);
            [uniqueNames, ~, groupIdx] = unique(hardwareNames, 'stable'); %#ok<ASGLU>
            counts = accumarray(groupIdx(:), 1);

            for paramIdx = 1:numel(parameters)
                if counts(groupIdx(paramIdx)) <= 1
                    continue
                end

                parameter = parameters(paramIdx);
                hardwareName = hardwareNames{paramIdx};
                parameter.Name = sprintf('%s[%d].%s', parameter.Module.Name, parameter.Module.Index, hardwareName);
            end
        end

        function setHardwareParameterName(~, parameter, hardwareName)
            if isempty(parameter.UserData) || ~isstruct(parameter.UserData)
                parameter.UserData = struct();
            end

            parameter.UserData.HardwareName = char(hardwareName);
        end
    end

    methods (Sealed)
        function set(obj, varargin)
            set@matlab.mixin.SetGet(obj, varargin{:});
        end

        function val = get(obj, varargin)
            val = get@matlab.mixin.SetGet(obj, varargin{:});
        end
    end

    methods (Static)
        function r = selfTestResult(name, status, summary, options)
            % r = hw.Interface.selfTestResult()
            % r = hw.Interface.selfTestResult(name, status, summary)
            % r = hw.Interface.selfTestResult(name, status, summary, Detail=..., Remedy=...)
            % Build one selfTest result, or the empty prototype when called with
            % no arguments. Backends use this instead of hand-rolling structs so
            % every result concatenates and every consumer sees the same fields.
            %
            % Parameters:
            %   name    - Short check name, e.g. "Command server reachable".
            %   status  - 'pass' | 'fail' | 'warn' | 'info' | 'skip'.
            %   summary - One-line result shown in the report.
            %   options.Detail - Additional lines shown in the detail pane.
            %   options.Remedy - Actionable fix; expected when status is fail/warn.
            %
            % Returns:
            %   r - 1x1 result struct, or a 0x0 empty struct array with the same
            %       fields when called with no arguments.
            %
            % See also: hw.Interface.selfTest
            arguments
                name (1,1) string = ""
                status (1,1) string {mustBeMember(status,["pass","fail","warn","info","skip",""])} = ""
                summary (1,1) string = ""
                options.Detail (1,:) string = strings(1,0)
                options.Remedy (1,1) string = ""
            end

            if nargin == 0
                r = struct('name',{},'status',{},'summary',{},'detail',{},'remedy',{});
                return
            end

            r = struct( ...
                'name',    name, ...
                'status',  status, ...
                'summary', summary, ...
                'detail',  {options.Detail}, ...
                'remedy',  options.Remedy);
        end

        function tf = isStimulusValue(value)
            % tf = hw.Interface.isStimulusValue(value)
            % True when a value handed to set_parameter is a stimulus object.
            %
            % A 'StimType' parameter passes the stimgen.StimType itself down to
            % the backend, so every set_parameter implementation needs to
            % recognize one before coercing the value to a number or a string.
            % Array-valued parameters arrive wrapped in a scalar cell, matching
            % the convention in hw.Parameter.set.Value.
            %
            % Parameters:
            %   value - Value as received by set_parameter.
            %
            % Returns:
            %   tf - logical scalar.
            %
            % See also: hw.Interface.stimulusPayload
            if iscell(value) && isscalar(value)
                value = value{1};
            end
            tf = isa(value, 'stimgen.StimType');
        end

        function payload = stimulusPayload(stim, Fs)
            % payload = hw.Interface.stimulusPayload(stim)
            % payload = hw.Interface.stimulusPayload(stim, Fs)
            % Reduce a stimulus to the plain data a backend writes to hardware.
            %
            % Backends receive the stimgen.StimType object itself and take what
            % they need from it. This gathers the fields they all need in one
            % place so the sample-rate reconciliation is not repeated — and not
            % forgotten. stimgen builds Signal against stim.Fs, so a stimulus
            % authored at one rate is the wrong duration and pitch on a device
            % running at another; passing Fs regenerates it at the device rate.
            % Fs is assigned on the stimulus itself rather than on a copy, so
            % a device-rate stimulus is reached once rather than rebuilt per
            % trial.
            %
            % update_signal is then called explicitly, as every other stimgen
            % consumer does (stimgen.StimPlayer, stimgen.StimInspector,
            % stimgen.calibration.Engine): Signal is empty on a freshly
            % constructed or freshly deserialized stimulus, and the rebuild the
            % Fs assignment triggers runs inside a PostSet listener, where
            % MATLAB downgrades an error to a warning and leaves the previous
            % signal in place. Calling it here is what makes a stimulus that
            % cannot be built at the device rate a reportable failure instead of
            % a silently stale waveform.
            %
            % Parameters:
            %   stim - stimgen.StimType, scalar or array.
            %   Fs   - Device sample rate in Hz. Omit, or pass hw.Module.Fs
            %          unchanged from its 1 Hz "unset" default, to take the
            %          stimulus at the rate it was authored with.
            %
            % Returns:
            %   payload - 1xN struct (one element per stimulus) with fields
            %             Signal, Fs, N, Duration, SoundLevel, Class,
            %             DisplayName. Empty when stim is empty.
            %
            % See also: hw.Interface.isStimulusValue, hw.TDT_RPcox.set_parameter
            arguments
                stim
                Fs (1,1) double = 0
            end

            % hw.Module.Fs cannot represent "unset": its validators forbid 0 and
            % NaN, so it sits at 1 Hz until a backend assigns it from the device.
            % Regenerating against that default would destroy the waveform.
            UNSET_MODULE_FS = 1;

            payload = struct('Signal',{},'Fs',{},'N',{},'Duration',{}, ...
                'SoundLevel',{},'Class',{},'DisplayName',{});

            for k = 1:numel(stim)
                s = stim(k);

                if Fs > UNSET_MODULE_FS && s.Fs ~= Fs
                    vprintf(2,'Regenerating stimulus "%s" at the device rate: %g -> %g Hz', ...
                        s.DisplayName, s.Fs, Fs)
                    s.Fs = Fs; % SetObservable; the listener rebuild is not catchable
                end

                try
                    s.update_signal();
                catch ME
                    throw(MException('hw:Interface:StimulusGenerationFailed', ...
                        'Could not generate stimulus "%s" (%s) at %g Hz: %s', ...
                        s.DisplayName, class(s), s.Fs, ME.message));
                end

                payload(k) = struct( ...
                    'Signal',      s.Signal, ...
                    'Fs',          s.Fs, ...
                    'N',           s.N, ...
                    'Duration',    s.Duration, ...
                    'SoundLevel',  s.SoundLevel, ...
                    'Class',       class(s), ...
                    'DisplayName', char(s.DisplayName));
            end
        end

        function name = getHardwareParameterName(parameter)
            name = parameter.Name;
            if isstruct(parameter.UserData) && isfield(parameter.UserData, 'HardwareName') && ~isempty(parameter.UserData.HardwareName)
                name = char(parameter.UserData.HardwareName);
            end
        end


        function tf = local_test(fcn, val, pat)
            % tf = local_test(fcn, val, pat)
            % Normalize comparison output to a logical scalar.
            %
            % Parameters:
            %   fcn - function_handle. Comparison function, e.g. @isequal, @contains.
            %   val - any. Value from the Parameter property.
            %   pat - any. Pattern/target value passed to the comparison function.
            %
            % Returns:
            %   tf - logical. True if the comparison indicates a match.
            %
            % See also: documentation/hw/hw_Interface.md
            res = fcn(val, pat);
            if islogical(res) && isscalar(res)
                tf = res;
            elseif isnumeric(res)
                % numeric (e.g. regexp indices) -> match if non-empty
                tf = ~isempty(res);
            elseif iscell(res)
                % cell of matches -> match if any non-empty element
                tf = any(~cellfun(@isempty, res));
            else
                tf = ~isempty(res);
            end
        end

    end
end
