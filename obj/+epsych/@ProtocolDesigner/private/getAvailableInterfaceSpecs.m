function specs = getAvailableInterfaceSpecs(~)
    specs = {
        hw.Software.getCreationSpec(), ...
        hw.TDT_Synapse.getCreationSpec(), ...
        hw.TDT_RPcox.getCreationSpec() ...
        };
    for specIdx = 1:numel(specs)
        specs{specIdx} = hw.InterfaceSpec.normalize(specs{specIdx});
    end
end

