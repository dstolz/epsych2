classdef TDT_Synapse < hw.Interface

    % obj = hw.TDT_Synapse(Server)
    % obj = hw.TDT_Synapse(Server, Connect=false)
    % Hardware interface for TDT Synapse through the SynapseAPI HTTP client.
    %
    % A module is one Synapse object that answers getParameterNames: a
    % gizmo, or a processor running in LEGACY mode, where Synapse loads an
    % RPvdsEx circuit onto the device whole and exposes the circuit's
    % parameter tags as that processor's own parameters. The Synapse name
    % ('RZ6(1)', 'PulseGen1') is what every read, write and trigger is
    % addressed to, and a protocol-authored module carries it in its Label
    % -- or in its Name, which hw.Module documents as the hardware-specific
    % field; whichever of the two Synapse recognizes is used, Label first,
    % and recorded on the module as Info.SynapseName. Connect refuses a
    % module it cannot place and names what Synapse has.
    %
    % Legacy mode in particular (see documentation/hw/hw_TDT_Synapse.md):
    %   - the legacy processor is its own gizmo, category 'Legacy', with NO
    %     parent (getGizmoParent answers nothing), so its sample rate is read
    %     under its own name;
    %   - Synapse reports a tag's type as 'Float'/'Int'/'Logic' and its size
    %     as 'Yes' at design time but a NUMBER at runtime (the manual's
    %     getParameterInfo entry), neither of which hw.Parameter accepts
    %     verbatim; parameterSpecFromInfo is the one translation;
    %   - a stimulus is written into the circuit's buffer tag with
    %     setParameterValues, as hw.TDT_RPcox writes it with WriteTagV, so
    %     the same .rcx plays the same sound under either backend;
    %   - nothing has to be reset between runs: ep_TimerFcn_Stop puts Synapse
    %     in Idle, which unloads the circuit, and the next Run reloads it.
    %
    % Parameters
    %   Server - Synapse server host name. Defaults to 'localhost'.
    %
    % Properties
    %   ExperimentInfo - Current Synapse user, subject, experiment, tank,
    %       and block metadata.
    %   Module - Array of hw.Module objects, one per Synapse gizmo.
    %   mode - Current hw.DeviceState reported by Synapse.
    %
    % Methods
    %   update_experiment_info - Refresh ExperimentInfo from Synapse.
    %   trigger, set_parameter, get_parameter - Interface I/O methods.
    %   parameterSpecFromInfo - (static) the SynapseAPI -> hw.Parameter map.
    %
    % See also: documentation/hw/hw_TDT_Synapse.md, documentation/hw/hw_Interface.md,
    %   hw.Module, hw.Parameter, SynapseAPI


    properties
        ExperimentInfo (1,1) struct
        IsConnected = false
    end


    properties (SetObservable,AbortSet)
        mode
    end


    properties (SetAccess = protected)
        HW = [] % SynapseAPI client while connected

        Server  (1,:) char

        Module
    end

    properties
        % Seconds to wait for Synapse to reach a requested mode. A mode
        % change loads or unloads every circuit and device in the rig and
        % takes seconds (5.5 s Idle to Preview on the lab's RZ6 and camera);
        % the HTTP request itself can time out server-side (503) while the
        % change goes on, so the answer is read back by polling, not from
        % the request's return.
        ModeTimeout (1,1) double {mustBePositive} = 20
    end

    properties (Access = private)
        ModeState_ (1,1) hw.DeviceState = hw.DeviceState.Idle

        % Element counts by 'gizmo.tag', asked of Synapse once per
        % connection. Two reasons: a stimulus write is bounded by the tag
        % that receives it, and the SynapseAPI client's own size cache
        % cannot hold a gizmo name with parentheses -- 'RZ6(2)_Stim' is not
        % a struct field name -- so an array read of a legacy processor
        % must carry its count and never let the client look it up. Created
        % in the constructor: a handle default would be one map shared by
        % every instance.
        ParameterSizes_
    end

    properties (Constant)
        Type = "TDT_Synapse"
    end

    properties (Constant, Hidden)
        % Synapse's HTTP port; SynapseAPI.PORT is not reachable from here.
        SYNAPSE_PORT = 24414

        % getGizmoInfo categories of a processor-level object: a legacy
        % processor, and a processor in its normal mode. Neither has a
        % parent, and asking is a 404.
        LEGACY_CATEGORY = 'Legacy'
        PROCESSOR_CATEGORIES = {'Legacy', 'Hardware Access'}

        % hw.Parameter Types that are read and written as arrays.
        ARRAY_TYPES = {'Buffer', 'Coefficient Buffer'}

        % Seconds between mode polls.
        MODE_POLL_PERIOD = 0.25
    end






    methods
        % constructor
        function obj = TDT_Synapse(Server, options)
            arguments
                Server (1,:) char = 'localhost'
                options.Connect (1,1) logical = true
            end

            obj.Server = Server;
            obj.Module = hw.Module.empty(1, 0);
            obj.ParameterSizes_ = containers.Map('KeyType', 'char', 'ValueType', 'double');

            if options.Connect
                obj.connect();
            end
        end

        function connect(obj)
            % connect(obj)
            % Open the SynapseAPI client, bring Synapse to Standby, and bind
            % the modules: the ones this interface already holds (a protocol
            % loaded from disk) are kept and checked against the server, and
            % an interface with none discovers them. Parameters are populated
            % only on a module that has none, so a protocol's Values, trial
            % options and triggers survive the connection the way they do on
            % hw.TDT_RPcox.
            if obj.IsConnected
                return
            end

            try
                obj.setup_interface();
            catch ME
                % A failed connect must not leave Synapse in the Standby the
                % attempt put it in, nor a half-built client on the object.
                obj.close_interface();
                rethrow(ME)
            end

            obj.IsConnected = true;
            obj.ModeState_ = obj.mode;
            obj.update_experiment_info();
        end

        function disconnect(obj)
            if ~obj.IsConnected
                return
            end

            obj.close_interface();
        end

        function results = selfTest(obj, options)
            % results = selfTest(obj)
            % results = selfTest(obj, Invasive=true)
            % Check that the Synapse API is installed and its server is
            % listening. Only a bare TCP socket is opened in the non-invasive
            % pass: connecting for real drives Synapse into Standby (see
            % setup_interface), which must never happen behind the operator's back.
            %
            % See also: hw.Interface.selfTest
            arguments
                obj
                options.Invasive (1,1) logical = false
            end

            results = hw.Interface.selfTestResult();

            if isempty(which('SynapseAPI'))
                results(end+1) = hw.Interface.selfTestResult('Synapse API', 'fail', ...
                    'SynapseAPI is not on the MATLAB path.', ...
                    Remedy = "Run epsych_startup so TDTfun/SynapseAPI is added to the path.");
            else
                results(end+1) = hw.Interface.selfTestResult('Synapse API', 'pass', ...
                    sprintf('SynapseAPI found: %s', which('SynapseAPI')));
            end

            target = sprintf('%s:%d', obj.Server, obj.SYNAPSE_PORT);
            if obj.IsConnected
                results(end+1) = hw.Interface.selfTestResult('Synapse server reachable', 'pass', ...
                    sprintf('Already connected to %s.', target));
            else
                probe = [];
                try
                    probe = tcpclient(obj.Server, obj.SYNAPSE_PORT, 'Timeout', 1);
                    results(end+1) = hw.Interface.selfTestResult('Synapse server reachable', 'pass', ...
                        sprintf('TCP connect to %s succeeded.', target));
                catch ME
                    results(end+1) = hw.Interface.selfTestResult('Synapse server reachable', 'fail', ...
                        sprintf('Cannot reach the Synapse server at %s.', target), ...
                        Detail = string(ME.message), ...
                        Remedy = "Start Synapse on the target machine and confirm the Server name in ProtocolDesigner.");
                end
                if ~isempty(probe)
                    clear probe
                end
            end

            if ~options.Invasive
                return
            end

            % Invasive: connecting puts Synapse in Standby, so restore whatever
            % connection state we found.
            wasConnected = obj.IsConnected;
            try
                if ~wasConnected
                    obj.connect();
                end

                info = obj.ExperimentInfo;
                detail = strings(1,0);
                if isstruct(info) && ~isempty(fieldnames(info))
                    for f = string(fieldnames(info))'
                        detail(end+1) = sprintf("%s: %s", f, string(info.(f)));
                    end
                end
                for m = obj.Module
                    detail(end+1) = sprintf("%s: %d parameter(s) @ %g Hz%s", ...
                        m.Label, numel(m.Parameters), m.Fs, obj.legacySuffix_(m));
                end

                results(end+1) = hw.Interface.selfTestResult('Synapse session', 'pass', ...
                    sprintf('Connected; mode: %s; %d module(s)', string(obj.mode), numel(obj.Module)), ...
                    Detail = detail);
            catch ME
                results(end+1) = hw.Interface.selfTestResult('Synapse session', 'fail', ...
                    'Reached the server but could not establish a Synapse session.', ...
                    Detail = string(ME.message), ...
                    Remedy = "Confirm a rig is loaded in Synapse, Standby is enabled in its Preferences, and no other client controls it.");
            end

            if ~wasConnected
                try
                    obj.disconnect();
                catch ME
                    vprintf(0, 1, ME);
                end
            end
        end

        function tf = canReadHardwareParameters(~, module)
            % Synapse can always be asked for a gizmo's parameters; an
            % unreachable server is a runtime failure reported by
            % readHardwareParameters, not a capability gap.
            arguments
                ~
                module (1,1) hw.Module
            end
            tf = true;
        end

        function setModules(obj, modules)
            if obj.IsConnected
                error('hw:TDT_Synapse:ConnectedModuleEdit', ...
                    'Modules can only be reassigned while the interface is offline.');
            end

            obj.Module = modules;
        end

        function tf = isLegacyModule(~, module)
            % tf = isLegacyModule(obj, module)
            % True when the module is a processor running an RPvdsEx circuit
            % in legacy mode, as recorded in Info.Legacy by connect or
            % readHardwareParameters. False for a module never bound to a
            % server, which is also what a legacy processor looks like before
            % the first connect.
            arguments
                ~
                module (1,1) hw.Module
            end
            tf = isfield(module.Info, 'Legacy') && isequal(module.Info.Legacy, true);
        end
    end

    methods (Static)
        function spec = getCreationSpec()
            spec = hw.InterfaceSpec( ...
                char(hw.TDT_Synapse.Type), ...
                'TDT Synapse', ...
                'Connect to a Synapse server and discover its gizmos (including processors in legacy mode) and their parameters.', ...
                hw.InterfaceSpecOption( ...
                    'name', 'server', ...
                    'label', 'Server', ...
                    'defaultValue', 'localhost', ...
                    'required', false, ...
                    'inputType', 'text', ...
                    'choices', {}, ...
                    'isList', false, ...
                    'scope', 'interface', ...
                    'allowScalarExpansion', false, ...
                    'controlType', 'text', ...
                    'getFile', false, ...
                    'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select Synapse Server Target', ...
                    'description', 'Synapse server host name.'), ...
                @(opts) hw.TDT_Synapse(char(opts.server)));
        end

        [spec, notes] = parameterSpecFromInfo(name, info) % SynapseAPI parameter info -> hw.Parameter metadata, plus what fell back.

        [keep, dropped] = filterParameterNames(names) % Remove tags the API cannot address or EPsych never exposes.
    end


    methods
        function update_experiment_info(obj)
            % update_experiment_info(obj)
            % Refresh ExperimentInfo from Synapse. User, subject, experiment
            % and tank exist in every mode; a BLOCK exists only once Synapse
            % is in Preview or Record (asking in Standby is a 404), so it is
            % read then and left empty otherwise. The mode setter calls this
            % again on entering a recording mode, so a saving function that
            % reads ExperimentInfo.block gets the block the data went into.
            if ~obj.IsConnected || isempty(obj.HW)
                obj.ExperimentInfo = struct();
                return
            end

            obj.ExperimentInfo.user         = obj.HW.getCurrentUser();
            obj.ExperimentInfo.subject      = obj.HW.getCurrentSubject();
            obj.ExperimentInfo.experiment   = obj.HW.getCurrentExperiment();
            obj.ExperimentInfo.tank         = obj.HW.getCurrentTank();

            block = '';
            if obj.ModeState_ >= hw.DeviceState.Preview
                block = obj.HW.getCurrentBlock();
                if ~(ischar(block) || isstring(block))
                    block = '';
                end
            end
            obj.ExperimentInfo.block = char(block);
        end
    end




    methods (Access=protected) % INHERITED FROM ABSTRACT CLASS hw.Interface
        setup_interface(obj) % Open the client, enter Standby, bind or discover modules.

        [nAdded, nSkipped] = populateModuleParametersFromGizmo(obj, module, api) % Create hw.Parameter objects from Synapse gizmo metadata.

        function api = createApi_(obj)
            % api = createApi_(obj)
            % The one place a SynapseAPI client is constructed, so a test
            % double can stand in for the server (tmp/TDT_Synapse_Mock
            % overrides it) without the class knowing.
            if isempty(which('SynapseAPI'))
                error('hw:TDT_Synapse:ApiMissing', ...
                    'SynapseAPI not found on MATLAB''s path. Run epsych_startup.');
            end
            api = SynapseAPI(obj.Server);
        end

        function releaseApi_(~, api)
            % releaseApi_(obj, api)
            % Dispose of a client createApi_ made, whether the connection's
            % own or a temporary one for a read. The pair exists so a test
            % double that hands out one shared client can keep it.
            if ~isempty(api) && isvalid(api)
                delete(api)
            end
        end

        function close_interface(obj)
            obj.ParameterSizes_ = containers.Map('KeyType', 'char', 'ValueType', 'double');

            if isempty(obj.HW)
                obj.IsConnected = false;
                return
            end

            % Leave Synapse as it was found: Idle. A client that walked away
            % in Standby would keep the processors loaded and the rig
            % apparently busy.
            try
                if obj.HW.getMode() > double(hw.DeviceState.Idle)
                    obj.HW.setMode(double(hw.DeviceState.Idle));
                end
            catch ME
                vprintf(2, 'Could not return Synapse to Idle on disconnect: %s', ME.message)
            end

            obj.releaseApi_(obj.HW);

            obj.HW = [];
            obj.IsConnected = false;
        end
    end




    methods % INHERITED FROM ABSTRACT CLASS hw.Interface

        function set.mode(obj,mode)
            obj.applyModeState_(mode);
        end


        function m = get.mode(obj)
            m = obj.queryModeState_();
        end


        % trigger a hardware event
        function t = trigger(obj,name)
            % t = trigger(obj,name);
            % t = trigger(obj,P);
            %
            % Pulse a logical parameter high then low. Returns the time of
            % the rising edge as a datenum, which is what
            % hw.Parameter.lastUpdated stores.
            %
            % name      name of an existing parameter
            % P         handle to a parameter object

            if isa(name,'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end

            if ~obj.IsConnected || isempty(obj.HW)
                t = now;
                return
            end

            gizmo = obj.gizmoName_(P.Module);
            tag = obj.getHardwareParameterName(P);

            ok = obj.HW.setParameterValue(gizmo, tag, 1);
            t = now;
            if ~ok
                % Nothing fired: the trial this edge was to start has not
                % started, which the trial loop must hear about.
                error('hw:TDT_Synapse:TriggerFailed', ...
                    'Unable to raise trigger "%s" on "%s" (Synapse mode: %s).', ...
                    tag, gizmo, char(obj.queryModeState_()));
            end

            pause(0.001)

            ok = obj.HW.setParameterValue(gizmo, tag, 0);
            if ok
                vprintf(3,'Triggered "%s"',P.Name)
            else
                % The edge fired; the line is now stuck high, which the next
                % pulse will not deliver. Report, do not abort the trial.
                vprintf(0,1,'Trigger "%s" on "%s" fired but could not be returned low', tag, gizmo)
            end
        end


        % set new value to one or more hardware parameters
        % returns TRUE if successful, FALSE otherwise
        function e = set_parameter(obj,name,value)

            if ~obj.IsConnected || isempty(obj.HW)
                e = true;
                return
            end

            if isa(name,'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end

            % An unset parameter has nothing to write. A 'StimType'
            % legitimately sits empty until a stimulus is chosen, and the
            % element count asserted below would otherwise fail mid-dispatch.
            if isempty(value)
                e = true;
                return
            end

            % Array values arrive wrapped in a scalar cell (hw.Parameter.set.Value),
            % so one cell is one parameter's value, never a value per parameter.
            % A bare array handed to a single parameter means the same thing.
            if ~iscell(value) && isscalar(P)
                value = {value};
            elseif ~iscell(value) && isscalar(value)
                value = repmat({value}, size(P));
            elseif ~iscell(value)
                value = num2cell(value);
            end

            assert(numel(value) == numel(P), 'hw:TDT_Synapse:ValueCountMismatch', ...
                '%d value(s) for %d parameter(s).', numel(value), numel(P));

            e = true;
            for i = 1:numel(P)
                p = P(i);
                v = value{i};
                gizmo = obj.gizmoName_(p.Module);
                tag = obj.getHardwareParameterName(p);

                if isa(v, 'stimgen.StimType')
                    ok = obj.writeStimulus_(p, v, gizmo, tag);
                    e = e && ok;
                    continue
                end

                if ischar(v) || isstring(v)
                    % Synapse parameters are numbers. A text value is a
                    % protocol mistake ('String' type on a gizmo tag), and
                    % char codes written in its place would be worse.
                    vprintf(0,1,'"%s" holds text, which has no Synapse parameter to go to; value kept host-side', p.Name)
                    continue
                end

                v = double(v);
                if isscalar(v)
                    ok = obj.HW.setParameterValue(gizmo, tag, v);
                else
                    % setParameterValues is the only path into an array
                    % parameter; the scalar call warns and forwards, but a
                    % write of N samples should not go through a scalar API.
                    ok = obj.HW.setParameterValues(gizmo, tag, reshape(v, 1, []));
                end

                if ok
                    % Format the value just written rather than reading
                    % p.ValueStr back: the read-back is a round trip per
                    % parameter per trial, and on a write-only tag it has
                    % nothing to return.
                    vprintf(4,'Updated parameter: %s = %s',p.Name,p.formatValue(v))
                else
                    vprintf(0,1,'Failed to write %s = %s to %s.%s (Synapse mode: %s)', ...
                        p.Name, p.formatValue(v), gizmo, tag, char(obj.queryModeState_()))
                end
                e = e && ok;
            end
        end


        % read current value for one or more hardware parameters
        function value = get_parameter(obj,name,options)
            arguments
                obj
                name
                options.includeInvisible (1,1) logical = false
                options.silenceParameterNotFound (1,1) logical = false
            end

            if isa(name,'hw.Parameter')
                P = name;
                name = {P.Name};
            else
                P = obj.find_parameter(name, ...
                    includeInvisible = options.includeInvisible, ...
                    silenceParameterNotFound=options.silenceParameterNotFound);
            end

            if ~obj.IsConnected || isempty(obj.HW)
                value = cell(size(P));
                for i = 1:length(P)
                    value{i} = P(i).Value;
                end

                [~,idx] = ismember(name,{P.Name});
                value = value(idx);
                if isscalar(value)
                    value = value{1};
                end
                return
            end

            value = cell(size(P));
            for i = 1:length(P)
                p = P(i);
                gizmo = obj.gizmoName_(p.Module);
                tag = obj.getHardwareParameterName(p);

                % A read that fails is one parameter's NaN, not the end of
                % the trial loop: ep_TimerFcn_RunTime reads every parameter
                % at every trial completion, and one tag Synapse will not
                % answer for must not take the session with it.
                try
                    v = obj.readOne_(p, gizmo, tag);
                catch ME
                    vprintf(0,1,'Read of %s.%s failed: %s', gizmo, tag, ME.message)
                    v = nan;
                end

                % The client answers a refused request with '' (and warns
                % when Synapse is not in a runtime mode). NaN is what the
                % rest of the toolbox reads as "no value".
                if ischar(v) || isstring(v)
                    vprintf(2,'No value from Synapse for %s.%s', gizmo, tag)
                    v = nan;
                end
                value{i} = v;
            end

            % return in original order
            [~,idx] = ismember(name,{P.Name});
            value = value(idx);

            if isscalar(value)
                value = value{1};
            end
        end


    end

    methods (Access = private)
        function v = readOne_(obj, p, gizmo, tag)
            % v = readOne_(obj, p, gizmo, tag)
            % One parameter off the device. An array parameter is read with
            % its element count stated, for two reasons: the count is what
            % decides scalar from array on the device, whatever the protocol
            % says (a scalar tag a protocol marks isArray is still read as a
            % scalar), and a count the client has to look up itself goes
            % through its size cache, which cannot hold a legacy processor's
            % name (see ParameterSizes_).
            if ~(p.isArray || ismember(p.Type, obj.ARRAY_TYPES))
                v = obj.HW.getParameterValue(gizmo, tag);
                return
            end

            n = obj.parameterSize_(gizmo, tag);
            if ~isfinite(n)
                vprintf(0,1,'Size of %s.%s unknown; its value cannot be read', gizmo, tag)
                v = nan;
            elseif n <= 1
                v = obj.HW.getParameterValue(gizmo, tag);
            else
                v = obj.HW.getParameterValues(gizmo, tag, n);
            end
        end

        function applyModeState_(obj, mode)
            obj.ModeState_ = mode;
            if ~obj.IsConnected || isempty(obj.HW)
                return
            end

            target = obj.synapseMode_(mode);
            actual = obj.awaitMode_(target);
            if actual ~= target
                error('hw:TDT_Synapse:ModeRejected', ...
                    'Synapse did not enter %s within %g s; it is in %s.%s', ...
                    char(target), obj.ModeTimeout, char(actual), obj.modeRemedy_(target));
            end
            vprintf(2,'HW mode: %s',char(actual))

            % A block exists only from here on.
            if target >= hw.DeviceState.Preview
                obj.update_experiment_info();
            end
        end

        function actual = awaitMode_(obj, target)
            % actual = awaitMode_(obj, target)
            % Ask Synapse for a mode and poll until it reports it, or
            % ModeTimeout passes. The request's own return is not the
            % answer: setMode reports false when Synapse is already there,
            % and the server answers 503 when the change outlasts the HTTP
            % request, while the change itself carries on.
            target = hw.DeviceState(target);
            obj.HW.setMode(double(target));

            % Asked of the client directly, not through queryModeState_:
            % setup_interface runs this before IsConnected is set, and the
            % query answers the cached state until then.
            deadline = tic;
            while true
                actual = hw.DeviceState(obj.HW.getMode());
                obj.ModeState_ = actual;
                if actual == target || toc(deadline) >= obj.ModeTimeout
                    return
                end
                pause(obj.MODE_POLL_PERIOD)
            end
        end

        function s = modeRemedy_(~, target)
            if target == hw.DeviceState.Standby
                s = ' Enable Standby Mode in Synapse under Menu > Preferences, and confirm an experiment is loaded.';
            else
                s = ' Check Synapse for an error dialog; a device or camera that failed to start holds the mode change.';
            end
        end

        function mode = queryModeState_(obj)
            if ~obj.IsConnected || isempty(obj.HW)
                mode = obj.ModeState_;
                return
            end

            mode = hw.DeviceState(obj.HW.getMode());
            obj.ModeState_ = mode;
        end

        function target = synapseMode_(~, mode)
            % Synapse knows Idle, Standby, Preview and Record. The toolbox's
            % other states are transitions a backend with no such state must
            % still land somewhere sensible: a stop or an error is Idle, a
            % pause keeps the circuit loaded but out of the record.
            switch hw.DeviceState(mode)
                case {hw.DeviceState.Idle, hw.DeviceState.Standby, ...
                      hw.DeviceState.Preview, hw.DeviceState.Record}
                    target = hw.DeviceState(mode);
                case hw.DeviceState.Pause
                    target = hw.DeviceState.Standby;
                otherwise
                    target = hw.DeviceState.Idle;
            end
        end

        function ok = writeStimulus_(obj, p, stim, gizmo, tag)
            % ok = writeStimulus_(obj, p, stim, gizmo, tag)
            % Write a 'StimType' parameter into the circuit's buffer tag as a
            % waveform. A legacy circuit's buffer holds samples, not objects,
            % so what Synapse receives is the calibrated signal generated at
            % the processor's own rate; stimulusPayload does that against
            % the module's Fs, which connect reads from the server. The tag
            % bounds the write: a stimulus longer than the buffer is refused
            % and reported rather than truncated by whatever Synapse does
            % with the overrun, matching TDTRP.write under hw.TDT_RPcox.

            if isempty(stim)
                ok = true;
                return
            end

            payload = hw.Interface.stimulusPayload(stim, p.Module.Fs);

            % Several stimuli on one tag would need a concatenation order the
            % circuit never declares, so play the selected one and say so.
            if numel(payload) > 1
                vprintf(0,1,['"%s" holds %d stimuli but tag "%s" is a single ' ...
                    'buffer; writing the first ("%s") only.'], ...
                    p.Name, numel(payload), tag, payload(1).DisplayName)
                payload = payload(1);
            end

            if isempty(payload.Signal)
                vprintf(1,'Stimulus "%s" for "%s" has an empty signal; nothing written', ...
                    payload.DisplayName, p.Name)
                ok = true;
                return
            end

            capacity = obj.parameterSize_(gizmo, tag);
            if payload.N > capacity
                vprintf(0,1,'Stimulus "%s" (%d samples) overruns tag "%s.%s" (%d samples); not written', ...
                    payload.DisplayName, payload.N, gizmo, tag, capacity)
                ok = false;
                return
            end

            ok = obj.HW.setParameterValues(gizmo, tag, reshape(payload.Signal, 1, []));
            if ok
                vprintf(4,'Updated parameter: %s = %s (%d samples @ %g Hz)', ...
                    p.Name, payload.DisplayName, payload.N, payload.Fs)
            else
                vprintf(0,1,'Failed to write stimulus "%s" (%d samples) to "%s.%s"', ...
                    payload.DisplayName, payload.N, gizmo, tag)
            end
        end

        function n = parameterSize_(obj, gizmo, tag)
            % n = parameterSize_(obj, gizmo, tag)
            % Element count of a parameter, from Synapse once per connection.
            % A size it will not give is reported as Inf: a write then goes
            % ahead and its own result says whether it fit; a read is
            % declined, since the client cannot be asked to find the count.
            key = [gizmo '.' tag];
            if obj.ParameterSizes_.isKey(key)
                n = obj.ParameterSizes_(key);
                return
            end

            n = inf;
            try
                reported = double(obj.HW.getParameterSize(gizmo, tag));
                if isscalar(reported) && isfinite(reported) && reported > 0
                    n = reported;
                end
            catch ME
                vprintf(2,'Could not read the size of %s.%s: %s', gizmo, tag, ME.message)
            end
            obj.ParameterSizes_(key) = n;
        end

        function s = legacySuffix_(obj, module)
            if obj.isLegacyModule(module)
                s = ' [legacy]';
            else
                s = '';
            end
        end

        function gizmo = gizmoName_(~, module)
            % gizmo = gizmoName_(obj, module)
            % The Synapse name a module's parameters are addressed to: what
            % resolveGizmo_ recorded at connect or at a parameter read, else
            % the Label, for a module never checked against a server.
            gizmo = module.Label;
            if isfield(module.Info, 'SynapseName') && ~isempty(module.Info.SynapseName)
                gizmo = char(module.Info.SynapseName);
            end
        end

        function [gizmo, known] = resolveGizmo_(obj, api, module)
            % [gizmo, known] = resolveGizmo_(obj, api, module)
            % Find the Synapse object a module stands for, by its Label first
            % and its Name second, and record the answer as Info.SynapseName.
            % hw.Module documents Name as the hardware-specific field and
            % Label as the display one, while hw.TDT_RPcox uses the Label
            % for the device; a protocol author can reasonably have put the
            % Synapse name in either, and the API does not care which.
            %
            % Returns:
            %   gizmo - The matching Synapse name, '' when neither field is
            %           one.
            %   known - cellstr of every name Synapse listed.
            known = api.getGizmoNames();
            if isempty(known)
                known = {};
            elseif ischar(known) || isstring(known)
                known = cellstr(known);
            end
            known = reshape(known, 1, []);

            gizmo = '';
            for candidate = {module.Label, module.Name}
                name = candidate{1};
                if ~isempty(name) && any(strcmp(known, name))
                    gizmo = name;
                    break
                end
            end

            if isempty(gizmo)
                return
            end

            if ~strcmp(gizmo, module.Label)
                vprintf(2,'Module "%s": Synapse object matched by its Name; the Label "%s" is not one', ...
                    module.Name, module.Label)
            end

            info = module.Info;
            info.SynapseName = gizmo;
            module.Info = info;

            vprintf(3,'Module "%s" (label "%s") is Synapse object "%s" at %s', ...
                module.Name, module.Label, gizmo, obj.Server)
        end
    end


    methods (Access = private)
        modules = discoverModules_(obj, api) % Build one hw.Module per gizmo that has API parameters.

        bindModules_(obj, api) % Check protocol-authored modules against the server and fill in what only it knows.

        bindGizmoInfo_(obj, api, module, rates) % Record a gizmo's category, processor and sample rate on its module.
    end

end
