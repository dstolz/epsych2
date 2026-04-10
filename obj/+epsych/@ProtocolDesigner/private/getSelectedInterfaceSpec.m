function [spec, specIndex] = getSelectedInterfaceSpec(obj)
    specs = obj.getAvailableInterfaceSpecs();
    if isempty(specs)
        error('No interface specifications are available.');
    end

    labels = cellfun(@(entry) entry.label, specs, 'UniformOutput', false);
    selectedLabel = labels{1};
    if ~isempty(obj.DropDownInterfaceType.Items)
        selectedLabel = obj.DropDownInterfaceType.Value;
    end

    specIndex = find(strcmp(selectedLabel, labels), 1);
    if isempty(specIndex)
        specIndex = 1;
    end
    spec = specs{specIndex};
end