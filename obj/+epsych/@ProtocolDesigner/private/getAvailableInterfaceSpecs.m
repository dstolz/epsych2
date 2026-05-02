function specs = getAvailableInterfaceSpecs(~)
    specs = {
        localSoftwareSpec_(), ...
        localSerializedSynapseSpec_(), ...
        localSerializedRPcoxSpec_(), ...
        localSerializedIntanRHXSpec_() ...
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
    iface = hw.Intan_RHX(char(opts.host), double(opts.port), Connect = false);
end

