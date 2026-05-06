function text = format_summary_value_(value)
% format_summary_value_(value)
% Format a selected property value for compact summary text.
if isstring(value)
    text = strjoin(value, ',');
elseif ischar(value)
    text = string(value);
elseif islogical(value)
    if isscalar(value)
        text = string(matlab.lang.OnOffSwitchState(value));
    else
        text = string(mat2str(value));
    end
elseif isnumeric(value)
    if isscalar(value)
        text = string(num2str(double(value), '%g'));
    else
        text = string(mat2str(double(value)));
    end
else
    text = string(value);
end
end
