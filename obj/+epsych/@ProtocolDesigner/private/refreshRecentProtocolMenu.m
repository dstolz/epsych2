function refreshRecentProtocolMenu(obj)
    if isempty(obj.RecentProtocolsMenu) || ~isvalid(obj.RecentProtocolsMenu)
        return
    end

    delete(allchild(obj.RecentProtocolsMenu));

    recentPaths = obj.getRecentProtocolPaths();
    if isempty(recentPaths)
        uimenu(obj.RecentProtocolsMenu, 'Text', '(None)', 'Enable', 'off');
        return
    end

    for idx = 1:numel(recentPaths)
        filePath = recentPaths{idx};
        label = sprintf('%d. %s', idx, localBuildRecentProtocolLabel_(filePath));
        uimenu(obj.RecentProtocolsMenu, ...
            'Text', label, ...
            'MenuSelectedFcn', @(~, ~) obj.onOpenRecentProtocol(filePath));
    end
end

function label = localBuildRecentProtocolLabel_(filePath)
    [~, fileName, extension] = fileparts(filePath);
    label = sprintf('%s%s | %s', fileName, extension, filePath);
end