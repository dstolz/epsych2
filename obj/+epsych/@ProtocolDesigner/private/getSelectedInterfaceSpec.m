function [spec, specIndex] = getSelectedInterfaceSpec(obj)
    specs = obj.getAddableInterfaceSpecs();
    if isempty(specs)
        error('All available interface types are already present in the protocol.');
    end

    % Falls back to the first addable spec when the Interfaces dialog is closed.
    labels = cellfun(@(entry) entry.label, specs, 'UniformOutput', false);
    selectedLabel = labels{1};
    if ~isempty(obj.DropDownInterfaceType) && isvalid(obj.DropDownInterfaceType) ...
            && ~isempty(obj.DropDownInterfaceType.Items)
        selectedLabel = obj.DropDownInterfaceType.Value;
    end

    specIndex = find(strcmp(selectedLabel, labels), 1);
    if isempty(specIndex)
        specIndex = 1;
    end
    spec = specs{specIndex};
end