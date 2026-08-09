function onReadHardwareParams(obj)
% onReadHardwareParams(obj)
% Read the parameter list from the hardware definition for the selected
% target module, or for every module of the target interface when no
% specific module is selected.
%
% Modules that already have parameters prompt for Merge / Replace / Cancel:
% Merge appends newly discovered parameters and preserves user edits;
% Replace rebuilds the list purely from the hardware definition. Outcomes
% are reported through the status bar only.
%
% See also: hw.Interface.readHardwareParameters

interfaceIndex = obj.selectedTargetInterfaceIndex();
if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
    obj.setStatus('No interface selected');
    return
end

iface = obj.Protocol.Interfaces(interfaceIndex);

modules = obj.getSelectedTargetModule();
if isempty(modules)
    modules = iface.Module;
end

if isempty(modules)
    obj.setStatus('No module selected');
    return
end

anyChanged = false;
messages = strings(1, 0);

for k = 1:length(modules)
    module = modules(k);

    if ~iface.canReadHardwareParameters(module)
        messages(end+1) = sprintf('%s: reading parameters from hardware is not supported or not configured.', ...
            module.Name);
        continue
    end

    mode = 'merge';
    if ~isempty(module.Parameters)
        choice = uiconfirm(obj.Figure, ...
            sprintf(['Module "%s" already has %d parameter(s).\n\n' ...
            'Merge adds newly discovered parameters and keeps existing ones untouched. ' ...
            'Replace discards the existing parameters, including any configured values and expressions.'], ...
            module.Name, numel(module.Parameters)), ...
            'Read Hardware Parameters', ...
            'Options', {'Merge', 'Replace', 'Cancel'}, ...
            'DefaultOption', 'Merge', ...
            'CancelOption', 'Cancel');

        switch choice
            case 'Merge'
                mode = 'merge';
            case 'Replace'
                mode = 'replace';
            otherwise
                messages(end+1) = sprintf('%s: cancelled.', module.Name);
                continue
        end
    end

    parameterCountBefore = numel(module.Parameters);

    % The interface contract says readHardwareParameters never throws, but a
    % GUI action must not error out regardless.
    try
        [tf, msg] = iface.readHardwareParameters(module, Mode=mode);
    catch ME
        vprintf(0, 1, ME);
        tf = false;
        msg = ME.message;
    end

    if tf
        if strcmp(mode, 'replace') || numel(module.Parameters) ~= parameterCountBefore
            anyChanged = true;
        end
        messages(end+1) = string(msg);
    else
        messages(end+1) = sprintf('Read hardware parameters failed: %s', msg);
    end
end

if anyChanged
    obj.IsModified_ = true;
end

obj.refreshParameterTab();
obj.setStatus(strjoin(messages, ' | '));

end
