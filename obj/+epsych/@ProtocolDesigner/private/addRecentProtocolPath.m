function addRecentProtocolPath(obj, filePath)
    if isstring(filePath)
        filePath = char(filePath);
    end

    filePath = strtrim(filePath);
    if isempty(filePath)
        return
    end

    recentPaths = obj.getRecentProtocolPaths();
    recentPaths(strcmpi(recentPaths, filePath)) = [];
    recentPaths = [{filePath}, recentPaths];
    recentPaths = recentPaths(1:min(9, numel(recentPaths)));
    setappdata(0, 'EPsychProtocolDesignerRecentProtocols', recentPaths);
end