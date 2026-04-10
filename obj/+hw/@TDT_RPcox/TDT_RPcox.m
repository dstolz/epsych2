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

    properties (SetAccess = protected)
        HW (1,:) TDTRP

        Server  (1,:) char
        ConnectionType (1,:) char = 'GB'

        Module
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
                RPvdsFile
                moduleType
                moduleAlias = {}
                options.Interface (1,:) char = 'GB'
                options.Number (1,:) double {mustBeInteger, mustBePositive} = 1
                options.Fs (1,:) double {mustBeNonnegative, mustBeFinite} = 0
            end

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
            elseif isscalar(moduleAlias) && moduleCount > 1
                moduleAlias = repmat(moduleAlias, 1, moduleCount);
            elseif numel(moduleAlias) ~= moduleCount
                error('hw:TDT_RPcox:ModuleAliasCountMismatch', ...
                    'moduleAlias must be empty, scalar, or one entry per module.');
            end

            if isscalar(options.Number) && moduleCount > 1
                options.Number = repmat(options.Number, 1, moduleCount);
            elseif numel(options.Number) ~= moduleCount
                error('hw:TDT_RPcox:ModuleNumberCountMismatch', ...
                    'Number must be scalar or one value per module.');
            end

            if isscalar(options.Fs) && moduleCount > 1
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

            obj.setup_interface(RPvdsFile,moduleType,moduleAlias, options);
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
                    'required', true, 'inputType', 'choice', 'choices', {{'GB', 'USB'}}, ...
                    'isList', false, 'scope', 'interface', 'allowScalarExpansion', false, ...
                    'controlType', 'dropdown', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select Connection Type', ...
                    'description', 'Transport used to connect to the hardware interface.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'RPvdsFile', 'label', 'RPvds File', 'defaultValue', '', ...
                    'required', true, 'inputType', 'text', 'choices', {{}}, ...
                    'isList', true, 'scope', 'module', 'allowScalarExpansion', false, ...
                    'controlType', 'textarea', 'getFile', true, 'getFolder', false, ...
                    'fileFilter', {{'*.rcx;*.rco;*.rpx;*.rpvds', 'TDT Circuit Files (*.rcx, *.rco, *.rpx, *.rpvds)'; '*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select RPvds Circuit Files', ...
                    'description', 'One or more RPvds circuit files.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'moduleType', 'label', 'Device Type', 'defaultValue', '', ...
                    'required', false, 'inputType', 'text', ...
                    'choices', {{'RP2', 'RA16', 'RL2', 'RV8', 'RM1', 'RM2', 'RX5', 'RX6', 'RX7', 'RX8', 'RZ2', 'RZ5', 'RZ6'}}, ...
                    'isList', true, 'scope', 'module', 'allowScalarExpansion', false, ...
                    'controlType', 'textarea', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select Device Type Definitions', ...
                    'description', 'One or more TDT device types, one per circuit.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'moduleAlias', 'label', 'Module Alias', 'defaultValue', '', ...
                    'required', false, 'inputType', 'text', 'choices', {{}}, ...
                    'isList', true, 'scope', 'module', 'allowScalarExpansion', false, ...
                    'controlType', 'textarea', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select Module Alias Source', ...
                    'description', 'Optional aliases for the created modules.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'number', 'label', 'Device Number', 'defaultValue', 1, ...
                    'required', false, 'inputType', 'numeric', 'choices', {{}}, ...
                    'isList', true, 'scope', 'module', 'allowScalarExpansion', true, ...
                    'controlType', 'textarea', 'getFile', false, 'getFolder', false, ...
                    'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                    'fileDialogTitle', 'Select Device Number', ...
                    'description', 'Device number as enumerated by zBusMon, one per module. A single value is applied to all modules.'), ...
                hw.InterfaceSpecOption( ...
                    'name', 'fs', 'label', 'Sample Rate Override', 'defaultValue', 0, ...
                    'required', false, 'inputType', 'numeric', 'choices', {{}}, ...
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
            if obj.HW.Mode > hw.DeviceState.Idle
                obj.HW.mode = hw.DeviceState.Idle;
            end

            try %#ok<TRYNC>
                delete(obj.HW)
            end
        end

    end



    methods




        function set.mode(obj,mode)
            e.oldMode = obj.mode;
            e.mode = mode;

            if mode > hw.DeviceState.Idle
                obj.HW.run;
            else
                obj.HW.halt;
            end
            vprintf(2,'HW mode: %s',char(obj.mode))
        end


        function m = get.mode(obj)
            % m = obj.HW.status();
            m = double(obj.HW.RP.GetStatus);
            switch m
                case 0
                    m = hw.DeviceState.Error; % ?
                case 1
                    m = hw.DeviceState.Idle;
                case 3
                    m = hw.DeviceState.Standby;
                case 5
                    m = hw.DeviceState.Standby; % i think this is correct
                case 7
                    m = hw.DeviceState.Record;
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


    
end
