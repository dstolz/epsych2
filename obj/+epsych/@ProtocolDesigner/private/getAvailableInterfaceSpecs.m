function specs = getAvailableInterfaceSpecs(~)
    specs = {
        localSoftwareSpec_(), ...
        localSerializedSynapseSpec_(), ...
        localSerializedRPcoxSpec_(), ...
        localSerializedIntanRHXSpec_(), ...
        localSerializedTeensySpec_(), ...
        localSerializedBpodSpec_(), ...
        localSerializedNE1000Spec_() ...
        };
    for specIdx = 1:numel(specs)
        specs{specIdx} = hw.InterfaceSpec.normalize(specs{specIdx});
    end
end

function spec = localSoftwareSpec_()
    spec = hw.InterfaceSpec.normalize(hw.Software.getCreationSpec());
end

function spec = localSerializedSynapseSpec_()
    spec = hw.InterfaceSpec.normalize(hw.TDT_Synapse.getCreationSpec());
    spec.createFcn = @localCreateSerializedSynapse_;
end

function spec = localSerializedRPcoxSpec_()
    spec = hw.InterfaceSpec.normalize(hw.TDT_RPcox.getCreationSpec());
    spec.createFcn = @localCreateSerializedRPcox_;
end

function iface = localCreateSerializedSynapse_(opts)
    iface = hw.TDT_Synapse(char(opts.server), Connect = false);
end

function iface = localCreateSerializedRPcox_(opts)
    iface = hw.TDT_RPcox({}, {}, {}, Interface = char(opts.connectionType), Connect = false);
end

function spec = localSerializedIntanRHXSpec_()
    spec = hw.InterfaceSpec.normalize(hw.Intan_RHX.getCreationSpec());
    spec.createFcn = @localCreateSerializedIntanRHX_;
end

function iface = localCreateSerializedIntanRHX_(opts)
    settingsFile = '';
    if isfield(opts, 'settingsFile') && ~isempty(opts.settingsFile)
        settingsFile = char(opts.settingsFile);
    end
    samplingRate = 0;
    if isfield(opts, 'samplingRate') && ~isempty(opts.samplingRate)
        samplingRate = double(opts.samplingRate);
    end
    controllerType = '';
    if isfield(opts, 'controllerType') && ~isempty(opts.controllerType)
        controllerType = char(opts.controllerType);
    end
    iface = hw.Intan_RHX(char(opts.host), double(opts.port), Connect = false, ...
        SettingsFile = settingsFile, SamplingRate = samplingRate, ControllerType = controllerType);
end

function spec = localSerializedTeensySpec_()
    spec = hw.InterfaceSpec.normalize(hw.Teensy.getCreationSpec());
    spec.createFcn = @localCreateSerializedTeensy_;
end

function iface = localCreateSerializedTeensy_(opts)
    port = '';
    if isfield(opts, 'port') && ~isempty(opts.port)
        port = char(opts.port);
    end
    baudRate = 115200;
    if isfield(opts, 'baudRate') && ~isempty(opts.baudRate)
        baudRate = double(opts.baudRate);
    end
    autoDetect = false;
    if isfield(opts, 'autoDetect') && ~isempty(opts.autoDetect)
        autoDetect = logical(opts.autoDetect);
    end
    deviceSerial = '';
    if isfield(opts, 'deviceSerial') && ~isempty(opts.deviceSerial)
        deviceSerial = char(opts.deviceSerial);
    end
    iface = hw.Teensy(port, Connect = false, BaudRate = baudRate, ...
        AutoDetect = autoDetect, DeviceSerial = deviceSerial);
end

function spec = localSerializedBpodSpec_()
    spec = hw.InterfaceSpec.normalize(hw.Bpod.getCreationSpec());
    spec.createFcn = @localCreateSerializedBpod_;
end

function iface = localCreateSerializedBpod_(opts)
    % Connect = false: the designer constructs an interface every time one is
    % added or modified, and hw.Bpod's constructor default connects. That would
    % open the serial port, pay the Arduino Due boot delay, and (with
    % AutoDetect) probe every port on the machine just to edit a protocol.
    port = '';
    if isfield(opts, 'port') && ~isempty(opts.port)
        port = char(opts.port);
    end
    autoDetect = false;
    if isfield(opts, 'autoDetect') && ~isempty(opts.autoDetect)
        autoDetect = logical(opts.autoDetect);
    end
    boxID = 1;
    if isfield(opts, 'boxID') && ~isempty(opts.boxID)
        % string() before double() so a value that arrives as text ('2' from an
        % edit control) parses as the number 2 and not its character code; the
        % constructor demands a positive integer, and max() ignores NaN so an
        % unparseable entry falls back to box 1 rather than erroring the dialog.
        boxID = max(1, round(double(string(opts.boxID))));
    end
    stateMatrixFcn = '';
    if isfield(opts, 'stateMatrixFcn') && ~isempty(opts.stateMatrixFcn)
        stateMatrixFcn = char(opts.stateMatrixFcn);
    end
    iface = hw.Bpod(port, Connect = false, AutoDetect = autoDetect, ...
        BoxID = boxID, StateMatrixFcn = stateMatrixFcn);
end

function spec = localSerializedNE1000Spec_()
    spec = hw.InterfaceSpec.normalize(hw.NE1000.getCreationSpec());
    spec.createFcn = @localCreateSerializedNE1000_;
end

function iface = localCreateSerializedNE1000_(opts)
    % Connect = false: the designer constructs an interface every time one is
    % added or modified, and connecting would open the serial port (and with
    % AutoDetect probe every port) just to edit a protocol.
    port = '';
    if isfield(opts, 'port') && ~isempty(opts.port)
        port = char(opts.port);
    end
    % string() before double() so dropdown/edit values that arrive as text
    % ('19200') parse as numbers and not their character codes.
    baudRate = 19200;
    if isfield(opts, 'baudRate') && ~isempty(opts.baudRate)
        baudRate = double(string(opts.baudRate));
    end
    address = 0;
    if isfield(opts, 'address') && ~isempty(opts.address)
        % max() ignores NaN, so an unparseable entry falls back to address 0
        % rather than erroring the dialog.
        address = max(0, round(double(string(opts.address))));
    end
    syringeDiameter = 0;
    if isfield(opts, 'syringeDiameter') && ~isempty(opts.syringeDiameter)
        syringeDiameter = max(0, double(string(opts.syringeDiameter)));
    end
    rateUnits = 'MH';
    if isfield(opts, 'rateUnits') && ~isempty(opts.rateUnits)
        rateUnits = char(opts.rateUnits);
    end
    autoDetect = false;
    if isfield(opts, 'autoDetect') && ~isempty(opts.autoDetect)
        autoDetect = logical(opts.autoDetect);
    end
    ttlTrigger = false;
    if isfield(opts, 'ttlTrigger') && ~isempty(opts.ttlTrigger)
        ttlTrigger = logical(opts.ttlTrigger);
    end
    iface = hw.NE1000(port, Connect = false, BaudRate = baudRate, ...
        Address = address, SyringeDiameter = syringeDiameter, ...
        RateUnits = rateUnits, TTLTrigger = ttlTrigger, AutoDetect = autoDetect);
end

