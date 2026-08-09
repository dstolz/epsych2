function uniqueItems = makeUniqueDisplayItems(~, items)
    uniqueItems = items;
    for idx = 1:numel(items)
        duplicateCount = sum(strcmp(items{idx}, items(1:idx)));
        if duplicateCount > 1
            uniqueItems{idx} = sprintf('%s [%d]', items{idx}, duplicateCount);
        end
    end
end

