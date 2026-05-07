function onExportProtocolToWorkspace(obj)
% onExportProtocolToWorkspace(obj)
% Export a detached copy of the current Protocol object to the base workspace.
    protocolCopy = epsych.Protocol();
    protocolCopy.fromStruct(obj.Protocol.toStruct());

    assignin('base', 'Protocol', protocolCopy);
    obj.setStatus('Exported Protocol object to workspace variable "Protocol"', ...
        'Inspect Protocol in the base workspace or save it to a file from MATLAB.');
end