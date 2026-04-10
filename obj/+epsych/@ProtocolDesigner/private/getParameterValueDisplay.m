function valueText = getParameterValueDisplay(obj, parameter)
    if isequal(parameter.Type, 'String')
        valueText = obj.formatStringParameterValue(parameter.Value);
        return
    end

    valueText = parameter.ValueStr;
    if ~isequal(parameter.Type, 'File')
        return
    end

    fileList = obj.getParameterFileList(parameter);
    if isempty(fileList)
        valueText = '';
        return
    end

    fileNames = cell(size(fileList));
    for idx = 1:numel(fileList)
        [~, fileName, extension] = fileparts(char(string(fileList{idx})));
        fileNames{idx} = sprintf('%s%s', fileName, extension);
    end

    valueText = strjoin(fileNames, '; ');
end

