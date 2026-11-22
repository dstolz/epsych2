

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

        % Run the session with this backend deliberately disconnected. Set only
        % by the operator, from RunExpt's connect-failure prompt, and only for
        % backends whose canRunOffline says a session without them is coherent.
        % epsych.Runtime.Interfaces then neither connects nor asserts on it, so
        % the interface stays in the array — removing it would take its
        % parameters out of trial dispatch and out of readParameters' lookup.
        RunOffline (1,1) logical = false

        % Leave a 'StimType' waveform on the device when it is, sample for
        % sample in the device's own precision, what this interface last
        % uploaded to the same tag. The stimulus is still regenerated on
        % every write -- a noise token that draws new samples is therefore
        % uploaded every time -- and only the transfer is left out, which on
        % a long stimulus is most of what a trial dispatch costs.
        %
        % Honoured by the backends that upload a waveform (hw.TDT_RPcox,
        % hw.TDT_Synapse). They forget what they sent whenever the device
        % may no longer hold it: a connect, a circuit reload at the start of
        % a run, a mode change, a failed write, any other write to the tag.
        % Set false for a circuit that writes into its own stimulus buffer,
        % or one another program also writes: nothing here can see that.
        % Not saved with a protocol; set it from code.
        SkipUnchangedStimulus (1,1) logical = true

        % Leave out, during the trial loop's own dispatch, the write of a
        % parameter the device was read back holding moments earlier.
        %
        % The trial-end sweep reads every visible read/write parameter, and
        % the dispatch that follows it writes most of them back unchanged:
        % forty writes to say what the device has just reported. With this
        % on, a parameter is not written when (1) the backend read it from
        % the device since this trial ended, (2) nothing has written it or
        % invalidated the interface since, and (3) the backend says the
        % value read is the value to write, in the device's own precision
        % (holdsValue). Everything else set.Value does -- randomization, the
        % Expression, clamping, the callbacks, the PostSet event -- runs as
        % always; only the device call is left out.
        %
        % OFF by default, because it rests on one assumption nothing here
        % can check: that between the trial-end read and the dispatch, a
        % matter of milliseconds, only the host changes what a parameter
        % holds. A circuit whose reset trigger rewrites its own parameter
        % tags, or a device another program writes, breaks it. The first
        % dispatch of a run, a regenerated trial, and every write made
        % outside the trial loop are always sent. Backends that do not
        % implement holdsValue ignore the setting. RunExpt switches it on
        % at Run when preference EPsych/SkipUnchangedWrites is true.
        SkipUnchangedWrites (1,1) logical = false
    end

    properties (Transient, SetAccess = protected)
        % Parameter writes left out by SkipUnchangedWrites.
        WritesSkipped (1,1) double = 0

        % Counts up whenever the device may have stopped holding what was
        % read from it (invalidateDeviceValues). A parameter's read-back is
        % evidence only while the count it was taken under still stands.
        DeviceEpoch (1,1) double = 0
    end

    properties (Transient, SetAccess = protected)
        % Waveform uploads this interface sent, and the ones it left out
        % because the device already held the samples (SkipUnchangedStimulus).
        StimulusUploads (1,1) double = 0
        StimulusUploadsSkipped (1,1) double = 0
    end

    properties (Transient, Access = protected)
        % What each buffer tag was last uploaded, as sent: a containers.Map
        % made on first use (a default would be shared by every interface).
        StimulusSent_ = []
    end

    properties (Transient, Hidden)
        % True while epsych.Runtime.dispatchNextTrial is writing a trial's
        % parameters to this interface, from the ResetTrig pulse to the end
        % of the NewTrial pulse. A backend reads it to tell a dispatch write
        % from every other kind -- an operator's commit, a phase load, the
        % parameter debugger, calibration -- and may then leave its
        % per-write success record to the dispatcher's one summary record.
        % Nothing but the dispatcher sets it.
        InDispatch (1,1) logical = false

        % True only inside a dispatch the trial loop itself asked for
        % (dispatchNextTrial(i, AllowSkip=true)) on an interface with
        % SkipUnchangedWrites on. hw.Parameter.set.Value reads it. Nothing
        % but the dispatcher sets it.
        DispatchMaySkip (1,1) logical = false
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
            %   options - Name=Value pairs for hw.Parameter metadata (Description, Unit, Access, Type, Format, Visible, callback flags, UserData, isArray, isTrigger, isRandom, Min, Max, UpdateEveryTrial, SetOnce, PersistWithPhase).
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
                % No defaults: forwarded only when the caller passes them, so
                % the hw.Parameter constructor's isTrigger/Coefficient Buffer
                % defaulting still applies otherwise.
                options.UpdateEveryTrial (1,1) logical
                options.SetOnce (1,1) logical
                options.PersistWithPhase (1,1) logical = false
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

        % resetSession - Hook to return per-session device state to its start-of-run condition
        function resetSession(~, ~)
            % resetSession(obj, runtime)
            % Lifecycle hook invoked on every interface at the start of every
            % Run and Preview (see epsych.RunExpt.ExptDispatch), before
            % prepareRecording and the mode write, while the hardware is
            % halted. Interfaces are borrowed from the protocol and stay
            % connected between runs (see epsych.Runtime.delete), so whatever
            % the device accumulated during the previous run -- an RPvds
            % counter, a pump's dispensed volume -- is still there when the
            % next one starts. Backends with such state override this; the
            % default is a no-op. resetParametersToDesign_ is the shared pass
            % for host-side parameter values.
        end

        % ioReady - Connection check for the parameter I/O path
        function tf = ioReady(obj)
            % tf = ioReady(obj)
            % Whether a parameter read or write should go to the device --
            % the check hw.Parameter.get.Value makes before every read, and
            % the one a backend makes at the top of get_parameter,
            % set_parameter and trigger.
            %
            % IsConnected is the TRUTH and stays live: connect, connect
            % recovery, the self-test and the benchmark ask it. This is the
            % hot-path question, and a backend whose truth costs a device
            % round trip may answer it from a short-lived cache. On
            % hw.TDT_RPcox the probe is a GetStatus COM call per module, and
            % a single parameter read used to make it twice.
            %
            % The default is IsConnected itself, so a backend that does not
            % override this behaves exactly as before. An override must be
            % invalidated by everything that can change the answer: connect,
            % disconnect, a session reset, a failed read or write.
            tf = obj.IsConnected;
        end

        % holdsValue - Whether the device, read back as DEVICEVALUE, already holds VALUE
        function tf = holdsValue(~, ~, ~, ~)
            % tf = holdsValue(obj, p, deviceValue, value)
            % The question SkipUnchangedWrites turns on: is writing VALUE to
            % parameter P a no-op, given that the device was just read back
            % holding DEVICEVALUE?
            %
            % It is the backend's to answer because only the backend knows
            % what the device keeps of a value -- a float32, an integer, a
            % pump's four digits with their units. The default is FALSE,
            % which makes it the capability query too: a backend that does
            % not override this never has a write skipped. An override
            % answers true only when it is certain, and never for a trigger
            % or an array.
            %
            % A backend that overrides this must also do two things, or the
            % answer is never asked for: call p.noteDeviceRead(v,
            % obj.DeviceEpoch) where get_parameter has a value the device
            % itself returned, and call invalidateDeviceValues whenever the
            % device may have stopped holding it.
            %
            % See also: hw.Interface.SkipUnchangedWrites, hw.Parameter.noteDeviceRead
            tf = false;
        end

        % invalidateDeviceValues - The device may no longer hold what was read from it
        function invalidateDeviceValues(obj)
            % invalidateDeviceValues(obj)
            % Retire every read-back taken so far as evidence for
            % SkipUnchangedWrites. Called by a backend on connect, close, a
            % session reset, a mode change, a refused write; and by the
            % trial loop before each trial-end read, so that only what THAT
            % read finds can excuse a write in the dispatch after it.
            obj.DeviceEpoch = obj.DeviceEpoch + 1;
        end

        % displayLabel - Human-readable name for this backend, for operator messages
        function label = displayLabel(obj)
            % label = displayLabel(obj)
            % The name the designer shows for this backend ('NE-1000 Syringe
            % Pump'), falling back to the class when the spec cannot be built.
            % For dialogs and status text, where 'hw.NE1000' means nothing to
            % the person reading it.
            try
                spec = obj.getCreationSpec();
                label = spec.label;
            catch
                label = '';
            end
            if isempty(label)
                label = class(obj);
            end
        end

        % connectionRecoveryLabel - Menu label for operator recovery from a failed connect
        function label = connectionRecoveryLabel(~)
            % label = connectionRecoveryLabel(obj)
            % Label for the button RunExpt offers when connect() fails, or ''
            % when this backend has nothing an operator could fix from a
            % dialog. Doubles as the capability query for recoverConnection.
            %
            % The default is '': a backend that does not override this aborts
            % the session on a failed connect, exactly as before.
            label = '';
        end

        % recoverConnection - Let the operator fix whatever made connect() fail
        function tf = recoverConnection(~, ~)
            % tf = recoverConnection(obj, fig)
            % Invoked when connect() threw during session startup, with fig as
            % the modal parent. Change whatever the operator chooses (a serial
            % port, a host address) and return true to have the connection
            % retried; return false when they cancelled.
            %
            % Overrides must never throw: a dialog that fails is a false.
            tf = false;
        end

        % canRunOffline - Whether a session is coherent with this backend disconnected
        function tf = canRunOffline(~)
            % tf = canRunOffline(obj)
            % True when the operator may run the session with this backend
            % disconnected (see RunOffline). Reserved for peripherals a
            % paradigm can survive without — a reward pump on a rig being
            % shaped by hand, not the interface generating the stimulus or
            % acquiring the data, where continuing would silently produce
            % worthless sessions.
            tf = false;
        end

        % parameterCapacity - Element count the device storage behind a parameter holds
        function n = parameterCapacity(~, ~)
            % n = parameterCapacity(obj, P)
            % How many elements the device storage behind P holds -- an RPvds
            % tag's size, a Synapse array parameter's count -- or NaN when this
            % backend does not know. hw.benchmarkIO sizes its buffer writes
            % from this, so it never has to ask which backend it is talking to.
            %
            % The default is NaN: unknown. Overrides answer from what the
            % backend already holds (a tag map read at circuit load, a size
            % cache), must not add a device round trip for an answer already
            % cached, and must never throw.
            %
            % Parameters:
            %   P - hw.Parameter owned by this interface.
            %
            % Returns:
            %   n - element count, or NaN when unknown.
            n = NaN;
        end

        % isSimulated - Whether there is no device behind this interface
        function tf = isSimulated(~)
            % tf = isSimulated(obj)
            % True for a backend that answers from memory with no device behind
            % it, so it is usable whether or not it reports a connection and
            % what it costs describes EPsych rather than any transport.
            %
            % The default is false. hw.benchmarkIO refuses a disconnected
            % interface unless this is true: several backends report a write as
            % successful and serve the cached Value while disconnected, so
            % timing them would report numbers for I/O that never happened.
            tf = false;
        end

        % transferContext - What a reader needs to compare this backend's I/O timings
        function ctx = transferContext(~)
            % ctx = transferContext(obj)
            % One record per device link describing the conditions an I/O
            % time depends on and the interface does not otherwise expose:
            % the device model, the link, the calls a buffer transfer goes
            % through and their sample format, the sample rate, and how busy
            % the device's processor was. hw.benchmarkIO records it in
            % results.Environment.Transfer, so a timing can be held against a
            % vendor figure quoted for stated conditions (TDT's, for one, is
            % quoted at 50% cycle usage) without the benchmark asking which
            % backend it is talking to.
            %
            % The default is an empty record array: this backend says
            % nothing. Overrides build each record with
            % hw.Interface.transferContextRecord so every backend's records
            % concatenate, may make at most one cheap device query per link
            % (a live cycle-usage reading), must answer while disconnected
            % with what is known offline, and must never throw.
            %
            % Returns:
            %   ctx - struct array from hw.Interface.transferContextRecord.
            %
            % See also: hw.Interface.transferContextRecord, hw.benchmarkIO
            ctx = hw.Interface.transferContextRecord();
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

            % Short names are cheap to gather. Qualified names ('Module.Param')
            % cost a Module lookup per parameter, so they are built only if a
            % short-name match actually misses -- resolving a whole phase file
            % one name at a time would otherwise rebuild the list per entry.
            shortNames = {allP.Name};
            qualNames = {};
            haveQualNames = false;

            result = hw.Parameter.empty(1, 0);
            for k = 1:numel(name)
                n = name{k};
                idx = find(strcmp(shortNames, n), 1);
                if isempty(idx)
                    if ~haveQualNames
                        qualNames = arrayfun(@(p) [p.Module.Name '.' p.Name], allP, 'UniformOutput', false);
                        haveQualNames = true;
                    end
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

        function tf = sameInSingle_(~, p, deviceValue, value)
            % tf = sameInSingle_(obj, p, deviceValue, value)
            % holdsValue for a device that keeps scalars in single
            % precision: true when both are scalar numbers that agree as
            % singles. NaN never agrees with anything, so it is written.
            tf = ~p.isTrigger ...
                && isscalar(value) && isscalar(deviceValue) ...
                && (isnumeric(value) || islogical(value)) ...
                && (isnumeric(deviceValue) || islogical(deviceValue)) ...
                && single(deviceValue) == single(value);
        end

        % --- Waveform uploads (SkipUnchangedStimulus) -----------------------
        % A backend that uploads a 'StimType' waveform asks stimulusOnDevice_
        % before the transfer, calls noteStimulusSent_ after one that
        % succeeded, and forgetStimulusSent_ whenever the device may no
        % longer hold what was sent. SAMPLES must be exactly what goes on
        % the wire, in the device's own precision: the comparison is
        % isequal, so a stimulus that differs in one sample is uploaded.

        function tf = stimulusOnDevice_(obj, key, samples)
            % tf = stimulusOnDevice_(obj, key, samples)
            % True when the tag named by KEY was last uploaded exactly these
            % samples and nothing has invalidated that since. Counts the
            % skip; always false when SkipUnchangedStimulus is off.
            tf = false;
            if ~obj.SkipUnchangedStimulus || isempty(obj.StimulusSent_)
                return
            end
            if obj.StimulusSent_.isKey(key) && isequal(obj.StimulusSent_(key), samples)
                tf = true;
                obj.StimulusUploadsSkipped = obj.StimulusUploadsSkipped + 1;
            end
        end

        function noteStimulusSent_(obj, key, samples)
            % noteStimulusSent_(obj, key, samples)
            % Record a successful upload. Kept even when skipping is off, so
            % switching it on mid-session starts from what is known.
            if isempty(obj.StimulusSent_)
                obj.StimulusSent_ = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end
            obj.StimulusSent_(key) = samples;
            obj.StimulusUploads = obj.StimulusUploads + 1;
        end

        function forgetStimulusSent_(obj, key)
            % forgetStimulusSent_(obj)        every tag
            % forgetStimulusSent_(obj, key)   one tag
            % The device may no longer hold what was uploaded; the next
            % write of that tag is a real one.
            if isempty(obj.StimulusSent_)
                return
            end
            if nargin < 2
                obj.StimulusSent_ = [];
            elseif obj.StimulusSent_.isKey(key)
                remove(obj.StimulusSent_, key);
            end
        end
    end

    methods (Hidden)
        function countSkippedWrite(obj)
            % countSkippedWrite(obj)
            % hw.Parameter.set.Value left a write out (SkipUnchangedWrites).
            obj.WritesSkipped = obj.WritesSkipped + 1;
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

        function r = transferContextRecord(varargin)
            % r = hw.Interface.transferContextRecord()
            % r = hw.Interface.transferContextRecord(Name=Value)
            % Build one transferContext record, or the 1x0 empty prototype
            % when called with no arguments. Every field has an "unknown"
            % value ('' or NaN), so a backend fills in only what it knows.
            %
            % Name=Value options (all optional):
            %   Module           - module label the record describes.
            %   Device           - device model, e.g. 'RZ6'.
            %   Link             - transport as the backend names it, e.g. 'GB'.
            %   DeviceNumber     - device index on that link.
            %   SampleRate       - device sample rate, Hz.
            %   CycleUsage       - processor cycle usage, percent.
            %   CycleUsageSource - where CycleUsage came from, e.g. 'live'.
            %   WriteCall        - the driver call an array write is made with.
            %   ReadCall         - the driver call an array read is made with.
            %   SampleFormat     - the on-the-wire sample format, e.g. 'F32'.
            %   Notes            - anything else a reader of the timing needs.
            %
            % Returns:
            %   r - 1x1 record, or a 1x0 struct array with the same fields.
            %
            % See also: hw.Interface.transferContext
            % nargin is counted here and not in the validated helper: inside a
            % function with an arguments block it reads 0 for a name-value-only
            % call, which made every Name=Value record come back as the 1x0 prototype.
            r = hw.Interface.transferContextRecord_(varargin{:});
            if nargin == 0
                r = repmat(r, 1, 0);
            end
        end

        function r = transferContextRecord_(options)
            arguments
                options.Module (1,:) char = ''
                options.Device (1,:) char = ''
                options.Link (1,:) char = ''
                options.DeviceNumber (1,1) double = NaN
                options.SampleRate (1,1) double = NaN
                options.CycleUsage (1,1) double = NaN
                options.CycleUsageSource (1,:) char = ''
                options.WriteCall (1,:) char = ''
                options.ReadCall (1,:) char = ''
                options.SampleFormat (1,:) char = ''
                options.Notes (1,:) char = ''
            end

            r = options;
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

        function holdPulse(seconds)
            % hw.Interface.holdPulse(seconds)
            % Hold a trigger pulse high for SECONDS without giving up the
            % MATLAB thread.
            %
            % A trigger is a write of 1, a hold, and a write of 0. The hold
            % used to be pause(), and pause does more than wait: it processes
            % the event queue, so everything a NewData listener had just
            % queued -- a table rewrite, three plots -- was RENDERED inside
            % the ResetTrig pulse, before a single trial parameter had been
            % written. Measured in a timer callback on R2024b: pause(0.001)
            % after one uitable change took 24 ms (up to 50), a 1 ms spin
            % took 1 ms. It also let a queued button press run in the middle
            % of a dispatch. hw.Bpod made the same choice for the same
            % reason (see hw.Bpod trigger).
            %
            % The spin costs one core for the length of the pulse and
            % nothing else; graphics are drawn when the timer callback
            % returns, after the trial has started.
            %
            % Parameters:
            %   seconds - hold time. Non-positive returns at once.
            t0 = tic;
            while toc(t0) < seconds
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

    methods (Access = protected)
        function n = resetParametersToDesign_(obj)
            % n = resetParametersToDesign_(obj)
            % Return every writable parameter the trial dispatcher will NOT
            % write on the first trial to its design-time value, Values{1}.
            % Shared by the resetSession overrides (hw.Software, hw.TDT_RPcox).
            %
            % Selection mirrors epsych.Runtime.dispatchNextTrial: a Visible
            % parameter with UpdateEveryTrial or SetOnce is written from the
            % trial table on trial 1 of every new Runtime, so resetting it
            % here would only put a stimulus or a coefficient buffer on the
            % wire twice. What is left is the operator's toggles, invisible
            % setup values, and anything else the dispatcher never touches --
            % exactly the values that otherwise carry over from run to run.
            % Read-only parameters cannot be assigned, triggers hold only the
            % residue of their last firing, and a parameter with no Values has
            % no design-time value to return to.
            %
            % Assignment goes through set.Value, so randomize, Expression and
            % clamping apply as they do on dispatch (an isRandom parameter
            % resets to a fresh draw). Expression parameters are ordered after
            % what they read, across every interface of the owning runtime
            % when there is one. One failing parameter is logged, not fatal:
            % this runs at session start, where it must not end the run.
            %
            % Returns:
            %   n - number of parameters reset.
            n = 0;
            P = obj.all_parameters(includeInvisible=true);
            if isempty(P)
                return
            end

            keep = false(size(P));
            for i = 1:numel(P)
                p = P(i);
                keep(i) = ~strcmp(p.Access, 'Read') && ~p.isTrigger && ~isempty(p.Values) ...
                    && ~(p.Visible && (p.UpdateEveryTrial || p.SetOnce));
            end
            P = P(keep);
            n = numel(P);
            if n == 0
                return
            end

            scope = P;
            if isa(obj.Runtime, 'epsych.Runtime') && isvalid(obj.Runtime) && ~isempty(obj.Runtime.Interfaces)
                scope = hw.Parameter.empty(1, 0);
                for k = 1:numel(obj.Runtime.Interfaces)
                    scope = [scope, obj.Runtime.Interfaces(k).all_parameters(includeInvisible=true)];
                end
            end
            P = P(hw.Parameter.orderByDependencies(P, scope));

            for i = 1:n
                try
                    P(i).Value = P(i).Values{1};
                catch ME
                    vprintf(0, 1, ME)
                end
            end
            vprintf(2, '%s: %d parameter(s) reset to design-time values', obj.displayLabel(), n)
        end
    end
end
