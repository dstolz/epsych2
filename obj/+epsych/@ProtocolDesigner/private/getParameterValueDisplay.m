function valueText = getParameterValueDisplay(obj, parameter)
    if isequal(parameter.Type, 'String')
        valueText = obj.formatStringParameterValue(parameter.Values);
        return
    end

    if isempty(parameter.Values)
        valueText = '';
        return
    end

    if isequal(parameter.Type, 'File')
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
        return
    end

    % Numeric / Boolean / other types: format all levels
    fmt = parameter.Format;
    if isempty(fmt), fmt = '%g'; end
    if numel(parameter.Values) == 1
        valueText = sprintf(fmt, parameter.Values{1});
    else
        parts = cellfun(@(v) sprintf(fmt, v), parameter.Values, 'UniformOutput', false);
        valueText = strjoin(parts, '  ');
    end

    if ~isempty(parameter.Unit)
        valueText = [valueText ' ' parameter.Unit];
    end
end

