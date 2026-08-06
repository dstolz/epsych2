function specs = getAvailableInterfaceSpecs(~)
    specs = {
        localSoftwareSpec_(), ...
        localSerializedSynapseSpec_(), ...
        localSerializedRPcoxSpec_(), ...
        localSerializedIntanRHXSpec_(), ...
        localSerializedTeensySpec_() ...
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

