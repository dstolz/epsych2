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
        IsConnected = false
    end

    properties (SetAccess = protected)
        HW = [] % handle to RPcoX device(s) (TDTRP); untyped for cross-machine MAT-file compatibility

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
                obj.IsConnected = true;
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

            obj.HW = TDTRP.empty(1, 0);
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
                    localPopulateModuleParameters_(obj, module, obj.HW(idx));
                end
            end

            obj.ensureUniqueParameterNames();
            obj.IsConnected = true;
            obj.ModeState_ = obj.mode;
        end

        function disconnect(obj)
            if ~obj.IsConnected
                return
            end

            obj.close_interface();
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
                    'choices', {'RP2', 'RA16', 'RL2', 'RV8', 'RM1', 'RM2', 'RX5', 'RX6', 'RX7', 'RX8', 'RZ2', 'RZ5', 'RZ6'}, ...
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


        function close_interface(obj)
            if isempty(obj.HW)
                obj.IsConnected = false;
                return
            end

            if obj.HW.Mode > hw.DeviceState.Idle
                obj.HW.mode = hw.DeviceState.Idle;
            end

            try %#ok<TRYNC>
                delete(obj.HW)
            end

            obj.HW = TDTRP.empty(1, 0);
            obj.IsConnected = false;
        end

    end



    methods




        function set.mode(obj,mode)
            obj.applyModeState_(mode);
        end


        function m = get.mode(obj)
            m = obj.queryModeState_();
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

function localPopulateModuleParameters_(obj, module, hwHandle)
pt = hwHandle.PARTAG;
pt = [pt{:}];
ind = arrayfun(@(tag) tag.tag_name(1) == '%', pt);
pt(ind) = [];
for paramIdx = 1:length(pt)
    parameter = hw.Parameter(obj);
    parameter.Name = pt(paramIdx).tag_name;
    obj.setHardwareParameterName(parameter, pt(paramIdx).tag_name);
    parameter.isArray = pt(paramIdx).tag_size > 1;
    parameter.isTrigger = parameter.Name(1) == '!';
    parameter.Visible = ~any(parameter.Name(1) == '_~#%');

    switch pt(paramIdx).tag_type
        case 68
            parameter.Type = 'Buffer';
        case 73
            parameter.Type = 'Integer';
        case 78
            parameter.Type = 'Logical';
        case 83
            parameter.Type = 'Float';
        case 80
            parameter.Type = 'Coefficient Buffer';
        case 65
            parameter.Type = 'Undefined';
    end

    parameter.Module = module;
    module.Parameters(paramIdx) = parameter;
end
end
