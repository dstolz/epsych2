function lastPath = getLastBrowseDirectory(~)
    lastPath = getappdata(0, 'EPsychProtocolDesignerLastBrowseDirectory');
    if isempty(lastPath)
        lastPath = '';
    end
end

