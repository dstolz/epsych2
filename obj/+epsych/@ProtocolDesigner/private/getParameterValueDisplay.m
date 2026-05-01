function valueText = getParameterValueDisplay(obj, parameter)
% valueText = getParameterValueDisplay(obj, parameter)
% Format parameter values for compact display in the parameter table.
%
% Parameters:
%	parameter	- Parameter whose current Values content is being rendered.
%
% Returns:
%	valueText	- Display string shown in the table Value column.
    if isequal(parameter.Type, 'String')
        valueText = obj.formatStringParameterValue(parameter.Values);
        return
    end

    if isequal(parameter.Type, 'StimType')
        if isempty(parameter.Values)
            valueText = '';
        else
            names = cellfun(@(v) char(string(v.DisplayName)), parameter.Values, 'UniformOutput', false);
            names = names(~cellfun(@isempty, names));
            if isempty(names)
                valueText = '';
            else
                valueText = strjoin(names, ';  ');
            end
        end
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

