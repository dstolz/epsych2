function value = getGuiPreference(~, name, defaultValue)
% getGuiPreference(~, name, defaultValue)
% Read a saved ProtocolDesigner GUI preference or return the default.
    if ispref('ProtocolDesigner', name)
        value = getpref('ProtocolDesigner', name);
    else
        value = defaultValue;
    end
end