function [fileValue, cancelled] = promptForParameterFileValue(obj, parameter, allowMultiple)
    fileConfig = obj.getParameterFileConfig(parameter);
    startPath = obj.getParameterFileStartPath(parameter, fileConfig.initialPath);
    fileFilter = obj.normalizeDialogFileFilter(fileConfig.fileFilter);
    dialogTitle = fileConfig.dialogTitle;

    if allowMultiple
        [fileName, folder] = uigetfile(fileFilter, dialogTitle, startPath, 'MultiSelect', 'on');
    else
        [fileName, folder] = uigetfile(fileFilter, dialogTitle, startPath);
    end

    if isequal(fileName, 0)
        fileValue = [];
        cancelled = true;
        return
    end

    if iscell(fileName)
        fileValue = cellfun(@(name) fullfile(folder, name), fileName, 'UniformOutput', false);
    else
        fileValue = fullfile(folder, fileName);
    end

    selectedPaths = cellstr(fileValue);
    [isValidSelection, allowedExtensions] = obj.validateDialogSelectionPaths(selectedPaths, fileFilter);
    if ~isValidSelection
        uialert(obj.Figure, sprintf('Selected files must use one of these extensions: %s', strjoin(allowedExtensions, ', ')), 'Invalid File Selection');
        fileValue = [];
        cancelled = true;
        return
    end

    obj.setLastBrowseDirectory(folder);

    cancelled = false;
end

