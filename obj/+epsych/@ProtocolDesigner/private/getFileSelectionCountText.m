function text = getFileSelectionCountText(~, fileList, allowMultiple)
    count = numel(fileList);
    if allowMultiple
        text = sprintf('%d file(s) selected', count);
    elseif count == 0
        text = 'No file selected';
    else
        text = '1 file selected';
    end
end

