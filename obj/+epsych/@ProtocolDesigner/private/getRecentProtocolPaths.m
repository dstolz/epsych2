function recentPaths = getRecentProtocolPaths(~)
    recentPaths = getappdata(0, 'EPsychProtocolDesignerRecentProtocols');
    if isempty(recentPaths)
        recentPaths = {};
        return
    end

    if isstring(recentPaths)
        recentPaths = cellstr(recentPaths);
    elseif ischar(recentPaths)
        recentPaths = {recentPaths};
    end

    recentPaths = recentPaths(:).';
    recentPaths = recentPaths(~cellfun(@isempty, recentPaths));
end