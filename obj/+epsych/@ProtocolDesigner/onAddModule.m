function onAddModule(obj)
    interfaceIndex = obj.getSelectedInterfaceRowIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        obj.setStatus('No interface selected for Add Module', ...
            'Select an interface in the tree first.');
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    if ~obj.canEditInterfaceModules(iface)
        obj.setStatus(sprintf('Modules for %s are managed by the interface itself', char(iface.Type)), ...
            'Review the interface options instead of adding modules manually.');
        return
    end

    try
        [spec, interfaceOptions] = obj.getInterfaceEditState(iface);
    catch
        spec = [];
        interfaceOptions = struct();
    end

    if ~isempty(spec) && localHasModuleScopedFields_(spec)
        defaultName = obj.getUniqueModuleText(iface, sprintf('Module%d', length(iface.Module) + 1), 'Name');
        defaultLabel = obj.getUniqueModuleText(iface, defaultName, 'Label');
        initialOptions = localBuildModuleInitialOptions_(spec, interfaceOptions, length(iface.Module) + 1, defaultName, defaultLabel);

        try
            moduleOptions = obj.promptForInterfaceOptions(spec, initialOptions, 'Add Module', 'module');
            if isempty(moduleOptions)
                obj.setStatus(sprintf('Add module cancelled for %s', char(iface.Type)), ...
                    'Review the module options and try again when ready.');
                return
            end

            newModule = localBuildModuleFromOptions_(iface, moduleOptions, defaultLabel);
        catch ME
            obj.setStatus(sprintf('Add module failed: %s', ME.message), ...
                'Check the module options and required hardware files, then try again.');
            uialert(obj.Figure, ME.message, 'Add Module Failed');
            return
        end
    else
        defaultName = obj.getUniqueModuleText(iface, sprintf('Module%d', length(iface.Module) + 1), 'Name');
        defaultLabel = obj.getUniqueModuleText(iface, defaultName, 'Label');
        answer = inputdlg({'Module Name', 'Module Label'}, 'Add Module', 1, {defaultName, defaultLabel});
        if isempty(answer)
            obj.setStatus(sprintf('Add module cancelled for %s', char(iface.Type)), ...
                'Enter a module name and label when you are ready to add one.');
            return
        end

        requestedName = strtrim(answer{1});
        requestedLabel = strtrim(answer{2});
        if isempty(requestedName)
            requestedName = defaultName;
        end
        if isempty(requestedLabel)
            requestedLabel = requestedName;
        end

        moduleName = obj.getUniqueModuleText(iface, requestedName, 'Name');
        moduleLabel = obj.getUniqueModuleText(iface, requestedLabel, 'Label');
        newModule = hw.Module(iface, moduleLabel, moduleName, uint8(length(iface.Module) + 1));
    end

    modules = iface.Module;
    modules(end + 1) = newModule;
    obj.replaceInterfaceModules(iface, modules);

    obj.SelectedInterfaceRow = interfaceIndex;
    obj.setSelectedModuleRow(length(modules));
    obj.refreshParameterTab();
    obj.setStatus(sprintf('Added module %s to %s', newModule.Name, char(iface.Type)), ...
        'Add parameters to the new module, then compile to preview trials.');
end

function tf = localHasModuleScopedFields_(spec)
    tf = any(arrayfun(@(field) strcmpi(char(string(field.scope)), 'module'), spec.options));
end

function initialOptions = localBuildModuleInitialOptions_(spec, interfaceOptions, nextIndex, defaultName, ~)
    initialOptions = struct();
    for idx = 1:numel(spec.options)
        field = spec.options(idx);
        if ~strcmpi(char(string(field.scope)), 'module')
            continue
        end

        switch field.name
            case 'moduleAlias'
                initialOptions.(field.name) = defaultName;
            case 'moduleType'
                initialOptions.(field.name) = localGetModuleTypeInitialValue_(field, interfaceOptions);
            case 'number'
                initialOptions.(field.name) = nextIndex;
            otherwise
                if isfield(interfaceOptions, field.name) && ~isempty(interfaceOptions.(field.name))
                    initialOptions.(field.name) = localGetFieldDefaultValue_(interfaceOptions.(field.name), field.defaultValue);
                else
                    initialOptions.(field.name) = field.defaultValue;
                end
        end
    end
end

function value = localGetModuleTypeInitialValue_(field, interfaceOptions)
    if isfield(interfaceOptions, field.name) && ~isempty(interfaceOptions.(field.name))
        candidate = localGetFieldDefaultValue_(interfaceOptions.(field.name), field.defaultValue);
        if localIsAllowedChoice_(candidate, field.choices)
            value = candidate;
            return
        end
    end

    if ~isempty(field.choices)
        value = field.choices{1};
        return
    end

    value = field.defaultValue;
end

function tf = localIsAllowedChoice_(value, choices)
    if isempty(choices)
        tf = true;
        return
    end

    tf = any(strcmp(char(string(value)), choices));
end

function value = localGetFieldDefaultValue_(existingValue, fallbackValue)
    if isnumeric(existingValue)
        if isempty(existingValue)
            value = fallbackValue;
        else
            value = existingValue(end);
        end
        return
    end

    if iscell(existingValue)
        if isempty(existingValue)
            value = fallbackValue;
        else
            value = existingValue{end};
        end
        return
    end

    if isstring(existingValue)
        existingValue = cellstr(existingValue);
        value = localGetFieldDefaultValue_(existingValue, fallbackValue);
        return
    end

    value = existingValue;
end

function newModule = localBuildModuleFromOptions_(iface, moduleOptions, defaultLabel)
    switch char(iface.Type)
        case 'TDT_RPcox'
            moduleLabel = localGetModuleText_(moduleOptions, 'moduleType', defaultLabel);
            moduleName = localGetModuleText_(moduleOptions, 'moduleAlias', moduleLabel);

            moduleLabel = localGetUniqueModuleText_(iface, moduleLabel, 'Label');
            moduleName = localGetUniqueModuleText_(iface, moduleName, 'Name');
            newModule = hw.Module(iface, moduleLabel, moduleName, uint8(length(iface.Module) + 1));
            newModule.Info.RPvdsFile = localGetSingleModuleText_(moduleOptions, 'RPvdsFile', '');
            newModule.Info.Number = localGetSingleModuleNumeric_(moduleOptions, 'number', double(length(iface.Module) + 1));
            newModule.Info.FsOverride = localGetSingleModuleNumeric_(moduleOptions, 'fs', 0);
            if isprop(iface, 'ConnectionType') && ~isempty(iface.ConnectionType)
                newModule.Info.ConnectionType = iface.ConnectionType;
            else
                newModule.Info.ConnectionType = 'GB';
            end
        otherwise
            error('Add Module options are not implemented for interface type %s.', char(iface.Type));
    end
end

function textValue = localGetModuleText_(moduleOptions, fieldName, fallbackValue)
    textValue = localGetSingleModuleText_(moduleOptions, fieldName, fallbackValue);
    if isempty(strtrim(textValue))
        textValue = fallbackValue;
    end
end

function textValue = localGetSingleModuleText_(moduleOptions, fieldName, fallbackValue)
    if ~isfield(moduleOptions, fieldName)
        textValue = fallbackValue;
        return
    end

    rawValue = moduleOptions.(fieldName);
    if iscell(rawValue)
        if isempty(rawValue)
            textValue = fallbackValue;
            return
        end
        if numel(rawValue) ~= 1
            error('Module option "%s" must contain exactly one value when adding a module.', fieldName);
        end
        textValue = char(string(rawValue{1}));
        return
    end

    if isstring(rawValue)
        rawValue = char(rawValue);
    end
    textValue = char(string(rawValue));
end

function numericValue = localGetSingleModuleNumeric_(moduleOptions, fieldName, fallbackValue)
    if ~isfield(moduleOptions, fieldName)
        numericValue = fallbackValue;
        return
    end

    rawValue = moduleOptions.(fieldName);
    if isempty(rawValue)
        numericValue = fallbackValue;
        return
    end
    if numel(rawValue) ~= 1
        error('Module option "%s" must contain exactly one value when adding a module.', fieldName);
    end

    numericValue = double(rawValue);
    if isnan(numericValue)
        numericValue = fallbackValue;
    end
end

function text = localGetUniqueModuleText_(iface, requestedText, propertyName)
    text = strtrim(char(string(requestedText)));
    if isempty(text)
        text = 'Module';
    end

    existingValues = cell(1, length(iface.Module));
    for idx = 1:length(iface.Module)
        existingValues{idx} = iface.Module(idx).(propertyName);
    end

    if ~any(strcmp(existingValues, text))
        return
    end

    baseText = text;
    suffix = 2;
    while any(strcmp(existingValues, text))
        text = sprintf('%s_%d', baseText, suffix);
        suffix = suffix + 1;
    end
end