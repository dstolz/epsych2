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
        valueText = obj.formatStringParameterValue(parameter.Value);
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

    v = parameter.Value;
    if isempty(v)
        valueText = '';
        return
    end

    if isscalar(v)
        valueText = sprintf(parameter.Format, v);
    else
        valueText = mat2str(v, 6);
    end

    if ~isempty(parameter.Unit)
        valueText = [valueText ' ' parameter.Unit];
    end
end
