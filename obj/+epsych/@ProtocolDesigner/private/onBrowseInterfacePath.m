function onBrowseInterfacePath(obj, control, field)
    startPath = obj.getBrowseStartPath(control, field);

    if field.isList
        [fileName, folder] = uigetfile(field.fileFilter, field.fileDialogTitle, fullfile(startPath, '*'), 'MultiSelect', 'on');
    elseif field.getFile
        [fileName, folder] = uigetfile(field.fileFilter, field.fileDialogTitle, fullfile(startPath, '*'));
    else
        folder = uigetdir(startPath, field.fileDialogTitle);
        if isequal(folder, 0)
            return
        end
        fileName = [];
    end

    if field.getFile && isequal(fileName, 0)
        return
    end

    if field.getFolder
        selectedPaths = {folder};
    elseif iscell(fileName)
        selectedPaths = cellfun(@(name) fullfile(folder, name), fileName, 'UniformOutput', false);
    else
        selectedPaths = {fullfile(folder, fileName)};
    end

    if field.getFolder
        obj.setLastBrowseDirectory(selectedPaths{1});
    else
        obj.setLastBrowseDirectory(fileparts(selectedPaths{1}));
    end

    if isa(control, 'matlab.ui.control.TextArea')
        control.Value = selectedPaths;
    else
        control.Value = selectedPaths{1};
    end

    if field.getFolder
        obj.LabelStatus.Text = sprintf('Selected folder for %s', field.label);
    else
        obj.LabelStatus.Text = sprintf('Selected %d file(s) for %s', numel(selectedPaths), field.label);
    end
end

