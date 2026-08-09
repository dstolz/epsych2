function startPath = getBrowseStartPath(obj, control, field)
    startPath = obj.getCurrentControlPath(control, field);
    if isempty(startPath)
        startPath = obj.getLastBrowseDirectory();
    end
    if isempty(startPath) || ~isfolder(startPath)
        startPath = obj.getRepositoryRoot();
    end
end

