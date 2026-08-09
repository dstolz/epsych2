function startPath = getProtocolFileDialogStartPath(obj, defaultPattern)
    if nargin < 2 || isempty(defaultPattern)
        defaultPattern = '*.eprot';
    end

    lastPath = obj.CurrentProtocolPath;
    if isempty(lastPath)
        lastPath = obj.getLastProtocolFilePath();
    end

    if ~isempty(lastPath)
        if isfile(lastPath)
            startPath = lastPath;
            return
        end

        parentFolder = fileparts(lastPath);
        if ~isempty(parentFolder) && isfolder(parentFolder)
            startPath = fullfile(parentFolder, defaultPattern);
            return
        end
    end

    lastBrowseDirectory = obj.getLastBrowseDirectory();
    if ~isempty(lastBrowseDirectory) && isfolder(lastBrowseDirectory)
        startPath = fullfile(lastBrowseDirectory, defaultPattern);
        return
    end

    startPath = defaultPattern;
end