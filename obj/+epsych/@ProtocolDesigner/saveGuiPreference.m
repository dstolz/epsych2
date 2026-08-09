function saveGuiPreference(~, name, value)
% saveGuiPreference(~, name, value)
% Persist a ProtocolDesigner GUI preference between MATLAB sessions.
    setpref('ProtocolDesigner', name, value);
end