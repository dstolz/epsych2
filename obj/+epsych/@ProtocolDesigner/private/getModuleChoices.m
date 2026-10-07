function [modules, labels] = getModuleChoices(obj)
% [modules, labels] = getModuleChoices(obj)
% List every module in the protocol, in interface order, with the
% "Interface > Module" label the Find and Replace preview also uses.
%
% Returns:
%	modules	- 1xN hw.Module array.
%	labels	- 1xN cellstr, e.g. '2: TDT_RPcox > 1: RPA [RP2]'.
    modules = hw.Module.empty(1, 0);
    labels = {};
    for ifaceIdx = 1:length(obj.Protocol.Interfaces)
        iface = obj.Protocol.Interfaces(ifaceIdx);
        ifaceLabel = obj.interfaceLabel(iface, ifaceIdx);
        for moduleIdx = 1:length(iface.Module)
            module = iface.Module(moduleIdx);
            modules(end + 1) = module;
            labels{end + 1} = sprintf('%s > %s', ifaceLabel, ...
                obj.moduleDisplayLabel(module, moduleIdx));
        end
    end
end
