function valueText = getParameterValueFull(obj, parameter)
    % getParameterValueFull(obj, parameter)
    % Return the complete, untruncated value string for a parameter.
    % Used to populate the Value cell when entering edit mode, so the user
    % can read or copy the full contents rather than the abbreviated display.
    %
    % Parameters:
    %   parameter   - hw.Parameter instance to format.
    %
    % Returns:
    %   valueText   - Full string representation of the parameter value.

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

    if isequal(parameter.Type, 'File')
        fileList = obj.getParameterFileList(parameter);
        if isempty(fileList)
            valueText = '';
            return
        end
        paths = cellfun(@(p) char(string(p)), fileList, 'UniformOutput', false);
        valueText = strjoin(paths, '; ');
        return
    end

    v = parameter.Values;
    if isempty(v)
        valueText = '';
        return
    end

    fmt = parameter.Format;
    if isempty(fmt), fmt = '%g'; end
    if numel(v) == 1
        if isnumeric(v{1}) && ~isscalar(v{1})
            % Buffer-style level: full untruncated vector for copy/paste
            valueText = mat2str(reshape(v{1}, 1, []), 15);
        else
            valueText = sprintf(fmt, v{1});
        end
    elseif all(cellfun(@(x) isnumeric(x) && isscalar(x), v))
        nums = cellfun(@(x) x, v);
        valueText = mat2str(nums, 6);
    else
        parts = cellfun(@(x) mat2str(reshape(x, 1, []), 6), v, 'UniformOutput', false);
        valueText = strjoin(parts, ';  ');
    end

    if ~isempty(parameter.Unit)
        valueText = [valueText ' ' parameter.Unit];
    end
end
