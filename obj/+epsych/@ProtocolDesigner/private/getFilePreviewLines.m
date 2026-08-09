function previewLines = getFilePreviewLines(~, selectedItems, allItems)
    if ~isempty(selectedItems)
        previewLines = selectedItems(:);
        return
    end
    if isempty(allItems)
        previewLines = {'No files selected.'};
    else
        previewLines = {'Select a file to view its full path.'};
    end
end

