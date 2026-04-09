function startPath = getParameterFileStartPath(obj, parameter, configuredInitialPath)
    startPath = obj.getLastBrowseDirectory();
    if nargin >= 3 && ~isempty(configuredInitialPath) && isfolder(configuredInitialPath)
        startPath = configuredInitialPath;
    end
    currentValue = parameter.Value;

    if ischar(currentValue) || isstring(currentValue)
        candidatePath = fileparts(char(string(currentValue)));
        if isfolder(candidatePath)
            startPath = candidatePath;
        end
    elseif iscell(currentValue) && ~isempty(currentValue)
        firstValue = currentValue{1};
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

