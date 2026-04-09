function config = getParameterFileConfig(obj, parameter)
    config = struct( ...
        'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
        'dialogTitle', sprintf('Select File Value for %s', parameter.Name), ...
        'allowMultiple', [], ...
        'initialPath', '');

    userData = parameter.UserData;
    if ~isstruct(userData)
        return
    end

    if isfield(userData, 'FileFilter') && ~isempty(userData.FileFilter)
        config.fileFilter = userData.FileFilter;
    elseif isfield(userData, 'FileExtensions') && ~isempty(userData.FileExtensions)
        config.fileFilter = obj.buildFileFilterFromExtensions(userData.FileExtensions);
    end

    if isfield(userData, 'FileDialogTitle') && ~isempty(userData.FileDialogTitle)
        config.dialogTitle = char(string(userData.FileDialogTitle));
    end

    if isfield(userData, 'AllowMultipleFiles') && ~isempty(userData.AllowMultipleFiles)
        config.allowMultiple = logical(userData.AllowMultipleFiles);
    elseif isfield(userData, 'FileMultiSelect') && ~isempty(userData.FileMultiSelect)
        config.allowMultiple = logical(userData.FileMultiSelect);
    end

    if isfield(userData, 'InitialPath') && ~isempty(userData.InitialPath)
        candidatePath = char(string(userData.InitialPath));
        if isfolder(candidatePath)
            config.initialPath = candidatePath;
        end
    elseif isfield(userData, 'FileInitialPath') && ~isempty(userData.FileInitialPath)
        candidatePath = char(string(userData.FileInitialPath));
        if isfolder(candidatePath)
            config.initialPath = candidatePath;
        end
    end
end

