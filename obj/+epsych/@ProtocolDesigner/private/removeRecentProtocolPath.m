function removeRecentProtocolPath(obj, filePath)
    if isstring(filePath)
        filePath = char(filePath);
    end

    recentPaths = obj.getRecentProtocolPaths();
    recentPaths(strcmpi(recentPaths, filePath)) = [];
    setappdata(0, 'EPsychProtocolDesignerRecentProtocols', recentPaths);
end