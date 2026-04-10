function [fileValue, cancelled] = promptForParameterFileValue(obj, parameter, allowMultiple)
    fileConfig = obj.getParameterFileConfig(parameter);
    startPath = obj.getParameterFileStartPath(parameter, fileConfig.initialPath);
    fileFilter = obj.normalizeDialogFileFilter(fileConfig.fileFilter);
    dialogTitle = fileConfig.dialogTitle;

    if allowMultiple
        [fileName, folder] = uigetfile(fileFilter, dialogTitle, fullfile(startPath, '*'), 'MultiSelect', 'on');
    else
        [fileName, folder] = uigetfile(fileFilter, dialogTitle, fullfile(startPath, '*'));
    end

    if isequal(fileName, 0)
        fileValue = [];
        cancelled = true;
        return
    end

    if iscell(fileName)
        fileValue = cellfun(@(name) fullfile(folder, name), fileName, 'UniformOutput', false);
        obj.setLastBrowseDirectory(folder);
    else
        fileValue = fullfile(folder, fileName);
        obj.setLastBrowseDirectory(folder);
    end

    cancelled = false;
end

