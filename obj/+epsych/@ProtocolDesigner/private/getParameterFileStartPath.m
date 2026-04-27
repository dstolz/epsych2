function startPath = getParameterFileStartPath(obj, parameter, configuredInitialPath)
    startPath = obj.getLastBrowseDirectory();
    if nargin >= 3 && ~isempty(configuredInitialPath) && isfolder(configuredInitialPath)
        startPath = configuredInitialPath;
    end
    currentValues = parameter.Values;

    if ~isempty(currentValues)
        firstValue = currentValues{1};
        if iscell(firstValue) && ~isempty(firstValue)
            firstValue = firstValue{1};
        end
        candidatePath = fileparts(char(string(firstValue)));
        if isfolder(candidatePath)
            startPath = candidatePath;
        end
    end

    if isempty(startPath) || ~isfolder(startPath)
        startPath = obj.getRepositoryRoot();
    end
end

