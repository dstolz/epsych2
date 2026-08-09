classdef TDT_RPcox < hw.Interface

    % obj = hw.TDT_RPcox(RPvdsFile, moduleType, moduleAlias)
    % Hardware interface for TDT RPvds devices via the TDTRP wrapper.
    %
    % This interface implements the hw.Interface contract for reading and
    % writing RPvds tags/parameters and for issuing trigger pulses.
    %
    % Parameters
    %   RPvdsFile - RPvds circuit file or files to load, one per module.
    %   moduleType - Hardware model/type for each RPvds circuit.
    %   moduleAlias - EPsych module label for each configured device.
    %
    % Properties
    %   ExperimentInfo - Experiment metadata populated by the backend.
    %   ConnectionType - Shared transport used by the interface ('GB' or 'USB').
    %   Module - Array of configured hw.Module objects.
    %   mode - Current hw.DeviceState derived from RP status.
    %
    % Methods
    %   trigger, set_parameter, get_parameter - Interface I/O methods.
    %
    % See also: documentation/hw/hw_Interface.md, hw.Module, hw.Parameter


    properties
        ExperimentInfo
    end

    properties (Dependent)
        IsConnected
    end

    properties (SetAccess = protected)
        HW TDTRP % handle to RPcoX device(s) (TDTRP); untyped for cross-machine MAT-file compatibility

        Server  (1,:) char
        ConnectionType (1,:) char = 'GB'

        Module
    end

    properties (Access = private)
        ModeState_ (1,1) hw.DeviceState = hw.DeviceState.Idle
    end

    properties (SetObservable,AbortSet)
        mode
    end

    properties (Constant)
        Type = "TDT_RPcox"
    end



    methods
        % constructor
        function obj = TDT_RPcox(RPvdsFile,moduleType,moduleAlias, options)
            arguments
                RPvdsFile = {}
                moduleType = {}
                moduleAlias = {}
                options.Interface (1,:) char = 'GB'
                options.Number (1,:) double {mustBeInteger, mustBePositive} = 1
                options.Fs (1,:) double {mustBeNonnegative, mustBeFinite} = 0
                options.Connect (1,1) logical = true
            end

            obj.Module = hw.Module.empty(1, 0);

            RPvdsFile = cellstr(RPvdsFile);
            moduleType = cellstr(moduleType);
            moduleAlias = cellstr(moduleAlias);
            moduleCount = numel(moduleType);

            if numel(RPvdsFile) ~= moduleCount
                error('hw:TDT_RPcox:ModuleCountMismatch', ...
                    'RPvdsFile and moduleType must contain the same number of entries.');
            end

            if isempty(moduleAlias)
                moduleAlias = moduleType;
            elseif moduleCount == 0
                moduleAlias = {};
            elseif isscalar(moduleAlias) && moduleCount > 1
                moduleAlias = repmat(moduleAlias, 1, moduleCount);
            elseif numel(moduleAlias) ~= moduleCount
                error('hw:TDT_RPcox:ModuleAliasCountMismatch', ...
                    'moduleAlias must be empty, scalar, or one entry per module.');
            end

            if moduleCount == 0
                options.Number = double.empty(1, 0);
            elseif isscalar(options.Number) && moduleCount > 1
                options.Number = repmat(options.Number, 1, moduleCount);
            elseif numel(options.Number) ~= moduleCount
                error('hw:TDT_RPcox:ModuleNumberCountMismatch', ...
                    'Number must be scalar or one value per module.');
            end

            if moduleCount == 0
                options.Fs = double.empty(1, 0);
            elseif isscalar(options.Fs) && moduleCount > 1
                options.Fs = repmat(options.Fs, 1, moduleCount);
            elseif numel(options.Fs) ~= moduleCount
                error('hw:TDT_RPcox:ModuleFsCountMismatch', ...
                    'Fs must be scalar or one value per module.');
            end

            options.Interface = upper(options.Interface);
            if ~ismember(options.Interface, {'USB', 'GB'})
                error('hw:TDT_RPcox:InvalidInterface', ...
                    'Interface must be either "USB" or "GB".');
            end

            obj.ConnectionType = options.Interface;

            if options.Connect && moduleCount > 0
                obj.setup_interface(RPvdsFile,moduleType,moduleAlias, options);
                obj.ModeState_ = obj.mode;
            end
        end

        function connect(obj)
            if obj.IsConnected
                return
            end

            if isempty(obj.Module)
                error('hw:TDT_RPcox:OfflineConfigurationMissing', ...
                    'No modules are configured for this offline TDT_RPcox interface.');
            end

            % Tear down any stale HW before rebuilding. We only reach here when
            % IsConnected is false, so existing entries are dead links (e.g. a
            % deserialized protocol). Deleting them now ensures a displaced
            % TDTRP's destructor (which calls Halt on the shared device) runs
            % before the new circuit is started, not after.
            if ~isempty(obj.HW)
                obj.close_interface();
            end

            obj.ConnectionType = localNormalizeConnectionType_(obj.ConnectionType);

            for idx = 1:length(obj.Module)
                module = obj.Module(idx);
                [rpvdsFile, deviceNumber, fsOverride] = localGetModuleConfig_(module, idx);
                obj.HW(idx) = TDTRP(rpvdsFile, module.Label, ...
                    'INTERFACE', obj.ConnectionType, ...
                    'NUMBER', deviceNumber, ...
                    'FS', fsOverride);

                module.Fs = obj.HW(idx).RP.GetSFreq;
                module.Info.RPvdsFile = rpvdsFile;
                module.Info.Number = double(deviceNumber);
                module.Info.FsOverride = double(fsOverride);
                module.Info.ConnectionType = obj.ConnectionType;

                if isempty(module.Parameters)
                    pt = obj.HW(idx).PARTAG;
                    obj.populateModuleParametersFromTags(module, [pt{:}]);
                end
            end

            obj.ensureUniqueParameterNames();
            obj.ModeState_ = obj.mode;
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
            % Check that every module has a loadable RPvds circuit and that the
            % TDT ActiveX layer is installed. The non-invasive pass touches no
            % hardware: a missing .rcx or an absent driver is the usual cause of
            % a failed connect, and both are visible from disk.
            %
            % See also: hw.Interface.selfTest
            arguments
                obj
                options.Invasive (1,1) logical = false
            end

            results = hw.Interface.selfTestResult();

            % TDT driver layer
            if isempty(which('TDTRP'))
                results(end+1) = hw.Interface.selfTestResult('TDT driver', 'fail', ...
                    'TDTRP is not on the MATLAB path.', ...
                    Remedy = "Run epsych_startup, and install TDT ActiveX (TDT Drivers/RPvdsEx).");
            else
                results(end+1) = hw.Interface.selfTestResult('TDT driver', 'pass', ...
                    sprintf('TDTRP found: %s', which('TDTRP')));
            end

            % Circuits. connect() errors on a module with no RPvdsFile, and
            % TDTRP errors on one that does not exist -- both are cheap to
            % detect here instead.
            if isempty(obj.Module)
                results(end+1) = hw.Interface.selfTestResult('RPvds circuits', 'fail', ...
                    'No modules are configured for this interface.', ...
                    Remedy = "Add at least one module to the interface in ProtocolDesigner.");
            else
                missing = strings(1,0);
                found   = strings(1,0);
                for idx = 1:numel(obj.Module)
                    module = obj.Module(idx);
                    if ~isfield(module.Info, 'RPvdsFile') || isempty(module.Info.RPvdsFile)
                        missing(end+1) = sprintf("%s: no RPvdsFile configured", module.Name);
                        continue
                    end
                    rcx = char(string(module.Info.RPvdsFile));
                    if isfile(rcx)
                        found(end+1) = sprintf("%s: %s", module.Name, rcx);
                    else
                        missing(end+1) = sprintf("%s: %s", module.Name, rcx);
                    end
                end

                if isempty(missing)
                    results(end+1) = hw.Interface.selfTestResult('RPvds circuits', 'pass', ...
                        sprintf('All %d circuit file(s) present.', numel(found)), ...
                        Detail = found);
                else
                    results(end+1) = hw.Interface.selfTestResult('RPvds circuits', 'fail', ...
                        sprintf('%d of %d module(s) have a missing or unset circuit file.', ...
                        numel(missing), numel(obj.Module)), ...
                        Detail = missing, ...
                        Remedy = "Re-point the module's RPvdsFile in ProtocolDesigner, or restore the .rcx file.");
                end
            end

            if ~options.Invasive
                return
            end

            % Invasive: load the circuits onto the hardware, restoring the
            % connection state we found.
            wasConnected = obj.IsConnected;
            try
                if ~wasConnected
                    obj.connect();
                end

                detail = arrayfun(@(m) sprintf("%s (%s): Fs = %g Hz, %d parameter(s)", ...
                    m.Name, m.Label, m.Fs, numel(m.Parameters)), obj.Module);
                results(end+1) = hw.Interface.selfTestResult('Circuit load', 'pass', ...
                    sprintf('%d module(s) running over %s.', numel(obj.Module), obj.ConnectionType), ...
                    Detail = detail);
            catch ME
                results(end+1) = hw.Interface.selfTestResult('Circuit load', 'fail', ...
                    'Failed to load circuits onto the hardware.', ...
                    Detail = string(ME.message), ...
                    Remedy = "Power-cycle the TDT rack, confirm the connection type (USB/GB), and check zBus cabling.");
            end

            if ~wasConnected
                try
                    obj.disconnect();
                catch ME
                    vprintf(0, 1, ME);
                end
            end
        end

        function tf = canReadHardwareParameters(obj, module)
            % Discovery works from the live PARTAG scan when connected, or
            % offline from the module's configured RPvds circuit file.
            arguments
                obj
                module (1,1) hw.Module
            end
            tf = obj.IsConnected || ...
                (isfield(module.Info, 'RPvdsFile') && ~isempty(module.Info.RPvdsFile));
        end

        function setModules(obj, modules)
            if obj.IsConnected
                error('hw:TDT_RPcox:ConnectedModuleEdit', ...
                    'Modules can only be reassigned while the interface is offline.');
            end

            obj.Module = modules;
            if ~isempty(modules) && isfield(modules(1).Info, 'ConnectionType') && ~isempty(modules(1).Info.ConnectionType)
                obj.ConnectionType = localNormalizeConnectionType_(modules(1).Info.ConnectionType);
            end
        end
    end

    methods (Static)
        function spec = getCreationSpec()
            spec = hw.InterfaceSpec( ...
                char(hw.TDT_RPcox.Type), ...
                'TDT RPcoX', ...
                'Connect to one or more RPcoX devices using RPvds circuits and a transport interface.', ...
                [ ...
                hw.InterfaceSpecOption( ...
                    'name', 'connectionType', 'label', 'Connection Type', 'defaultValue', 'GB', ...
                    'required', true, 'inputType', 'choice', 'choices', {'GB', 'USB'}, ...
                    'isList', false, 'scope', 'interface', 'allowScalarExpansion', false, ...
                    'controlType', 'dropdown', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select Connection Type', ...
                    'description', 'Transport used to connect to the hardware interface.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'RPvdsFile', 'label', 'RPvds File', 'defaultValue', '', ...
                    'required', true, 'inputType', 'text', 'choices', {}, ...
                    'isList', true, 'scope', 'module', 'allowScalarExpansion', false, ...
                    'controlType', 'textarea', 'getFile', true, 'getFolder', false, ...
                    'fileFilter', {{'*.rcx;*.rco;*.rpx;*.rpvds', 'TDT Circuit Files (*.rcx, *.rco, *.rpx, *.rpvds)'; '*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select RPvds Circuit Files', ...
                    'description', 'One or more RPvds circuit files.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'moduleType', 'label', 'Device Type', 'defaultValue', '', ...
                    'required', false, 'inputType', 'text', ...
                    'choices', {'RP2', 'RA16', 'RL2', 'RV8', 'RM1', 'RM2', 'RX5', 'RX6', 'RX7', 'RX8', 'RZ2', 'RZ5', 'RZ6','RZ10'}, ...
                    'isList', true, 'scope', 'module', 'allowScalarExpansion', false, ...
                    'controlType', 'textarea', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select Device Type Definitions', ...
                    'description', 'One or more TDT device types, one per circuit.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'moduleAlias', 'label', 'Module Alias', 'defaultValue', '', ...
                    'required', false, 'inputType', 'text', 'choices', {}, ...
                    'isList', true, 'scope', 'module', 'allowScalarExpansion', false, ...
                    'controlType', 'textarea', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select Module Alias Source', ...
                    'description', 'Optional aliases for the created modules.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'number', 'label', 'Device Number', 'defaultValue', 1, ...
                    'required', false, 'inputType', 'numeric', 'choices', {}, ...
                    'isList', true, 'scope', 'module', 'allowScalarExpansion', true, ...
                    'controlType', 'textarea', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select Device Number', ...
                    'description', 'Device number as enumerated by zBusMon, one per module. A single value is applied to all modules.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'fs', 'label', 'Sample Rate Override', 'defaultValue', 0, ...
                    'required', false, 'inputType', 'numeric', 'choices', {}, ...
                    'isList', true, 'scope', 'module', 'allowScalarExpansion', true, ...
                    'controlType', 'textarea', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select Sample Rate Source', ...
                    'description', 'Optional sample rate override passed to TDTRP, one per module. A single value is applied to all modules.')], ...
                @(opts) hw.TDT_RPcox(opts.RPvdsFile, opts.moduleType, opts.moduleAlias, ...
                    Interface = char(opts.connectionType), Number = opts.number, Fs = opts.fs));
        end
    end





    methods (Access = protected)% INHERITED FROM ABSTRACT CLASS hw.Interface
        setup_interface(obj,RPvdsFile,moduleType,moduleAlias,options) % Initialize RPvds modules and parameters.

        [nAdded, nSkipped] = populateModuleParametersFromTags(obj, module, tags) % Create hw.Parameter objects from RPvds tag metadata.


        function close_interface(obj)
            if isempty(obj.HW)
                return
            end

            if obj.mode > hw.DeviceState.Idle
                obj.mode = hw.DeviceState.Idle;
            end

            try %#ok<TRYNC>
                delete(obj.HW)
            end

            obj.HW = TDTRP.empty(1, 0);
        end

    end



    methods




        function set.mode(obj,mode)
            obj.applyModeState_(mode);
        end


        function m = get.mode(obj)
            m = obj.queryModeState_();
        end

        function tf = get.IsConnected(obj)
            % Connected means the device link is live and a circuit is loaded
            % (GetStatus bits 1 and 2). It deliberately does NOT require the
            % circuit to be running (bit 3): a halted device (e.g. after Stop)
            % is still connected, and TDTRP.status() throws when not running.
            % Conflating "connected" with "running" would force a
            % delete/recreate of the backend on every rerun, which TDT
            % RPcoX/zBus cannot survive (see epsych.Runtime.delete).
            if isempty(obj.HW)
                tf = false;
                return
            end
            try
                tf = all(arrayfun(@localIsLoaded_, obj.HW));
            catch
                tf = false;
            end
        end






        % trigger a hardware event
        function t = trigger(obj,name)
            % t = trigger(obj,name);
            % t = trigger(obj,hw.Parameter)

            if isa(name,'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end

            if ~obj.IsConnected || isempty(obj.HW)
                t = now;
                return
            end

            trig = obj.getHardwareParameterName(P);
            hwHandle = obj.HW(P.Module.Index);
            e = hwHandle.write(trig,1);
            
            t = now;
            
            if ~e, throwerrormsg(module,trig); end
            pause(0.001)
            
            e = hwHandle.write(trig,0);
            if e
                vprintf(3,'Triggered "%s"',P.Name)
            else
                vprintf(0,1,'UNABLE TO TRIGGER "%s" ON MODULE "%s"',trig,module)
                % error('UNABLE TO TRIGGER "%s" ON MODULE "%s"',trig,module)
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

            % An unset parameter has nothing to write. A 'StimType' legitimately
            % sits empty until a stimulus is chosen, and the element count
            % asserted below would otherwise fail mid-trial dispatch.
            if isempty(value)
                e = true;
                return
            end

            if isvector(P) && isscalar(value)
                value = repmat(value,size(P));
            end

            assert(numel(value) == numel(P));

            for i = 1:length(P)
                p = P(i);
                v = value(i);
                if iscell(v), v = v{1}; end % array
                parameterName = obj.getHardwareParameterName(p);
                hwHandle = obj.HW(p.Module.Index);

                if isa(v,'stimgen.StimType')
                    e = obj.writeStimulus_(p, v, parameterName, hwHandle);
                    continue
                end

                e = hwHandle.write(parameterName,v);
                if e
                    vstr = p.ValueStr;
                    vprintf(4,'Updated parameter: %s = %s',p.Name,vstr)
                else
                    vprintf(0,1,'Failed to write value to "%s"',p.Name)
                end
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
                parameterName = obj.getHardwareParameterName(p);
                hwHandle = obj.HW(p.Module.Index);

                value{i} = hwHandle.read(parameterName);
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
        function e = writeStimulus_(~, p, stim, parameterName, hwHandle)
            % e = writeStimulus_(obj, p, stim, parameterName, hwHandle)
            % Write a 'StimType' parameter to its RPvds tag as a waveform.
            %
            % An RPvds buffer holds samples, not objects, so what the circuit
            % needs out of a stimulus is the calibrated signal generated at the
            % device's own rate — stimulusPayload handles that reconciliation
            % against the module's Fs, which connect() reads from the hardware.
            % The tag itself bounds the write: TDTRP.write refuses a signal
            % longer than the tag can hold, so a stimulus that overruns the
            % circuit's buffer is reported rather than silently truncated.
            %
            % Returns:
            %   e - True when the waveform was written (or there was nothing to
            %       write), false when the tag write failed.

            if isempty(stim)
                e = true;
                return
            end

            payload = hw.Interface.stimulusPayload(stim, p.Module.Fs);

            % Several stimuli on one tag would need a concatenation order the
            % circuit never declares, so play the selected one and say so.
            if numel(payload) > 1
                vprintf(0,1,['"%s" holds %d stimuli but tag "%s" is a single ' ...
                    'buffer; writing the first ("%s") only.'], ...
                    p.Name, numel(payload), parameterName, payload(1).DisplayName)
                payload = payload(1);
            end

            if isempty(payload.Signal)
                vprintf(1,'Stimulus "%s" for "%s" has an empty signal; nothing written', ...
                    payload.DisplayName, p.Name)
                e = true;
                return
            end

            e = hwHandle.write(parameterName, payload.Signal);
            if e
                vprintf(4,'Updated parameter: %s = %s (%d samples @ %g Hz)', ...
                    p.Name, payload.DisplayName, payload.N, payload.Fs)
            else
                vprintf(0,1,'Failed to write stimulus "%s" (%d samples) to "%s"', ...
                    payload.DisplayName, payload.N, parameterName)
            end
        end

        function applyModeState_(obj, mode)
            obj.ModeState_ = mode;
            if ~obj.IsConnected || isempty(obj.HW)
                return
            end

            if mode > hw.DeviceState.Idle
                obj.HW.run;
            else
                obj.HW.halt;
            end
            vprintf(2,'HW mode: %s',char(obj.queryModeState_()))
        end

        function mode = queryModeState_(obj)
            if ~obj.IsConnected || isempty(obj.HW)
                mode = obj.ModeState_;
                return
            end

            status = double(obj.HW.RP.GetStatus);
            switch status
                case 0
                    mode = hw.DeviceState.Error;
                case 1
                    mode = hw.DeviceState.Idle;
                case 3
                    mode = hw.DeviceState.Standby;
                case 5
                    mode = hw.DeviceState.Standby;
                case 7
                    mode = hw.DeviceState.Record;
                otherwise
                    mode = obj.ModeState_;
            end
            obj.ModeState_ = mode;
        end
    end


    
end

function tf = localIsLoaded_(h)
% True when the TDTRP device link is live and a circuit is loaded.
% Bit 1 = device connected, bit 2 = circuit loaded, bit 3 = running.
status = double(h.RP.GetStatus);
tf = bitget(status, 1) == 1 && bitget(status, 2) == 1;
end

function connectionType = localNormalizeConnectionType_(connectionType)
connectionType = upper(char(string(connectionType)));
if ~ismember(connectionType, {'USB', 'GB'})
    error('hw:TDT_RPcox:InvalidInterface', ...
        'Interface must be either "USB" or "GB".');
end
end

function [rpvdsFile, deviceNumber, fsOverride] = localGetModuleConfig_(module, defaultNumber)
if ~isfield(module.Info, 'RPvdsFile') || isempty(module.Info.RPvdsFile)
    error('hw:TDT_RPcox:MissingRPvdsFile', ...
        'Module "%s" is missing RPvdsFile in Module.Info.', module.Name);
end

rpvdsFile = char(string(module.Info.RPvdsFile));

if isfield(module.Info, 'Number') && ~isempty(module.Info.Number)
    deviceNumber = double(module.Info.Number);
else
    deviceNumber = double(defaultNumber);
end

if isfield(module.Info, 'FsOverride') && ~isempty(module.Info.FsOverride)
    fsOverride = double(module.Info.FsOverride);
else
    fsOverride = 0;
end
end
