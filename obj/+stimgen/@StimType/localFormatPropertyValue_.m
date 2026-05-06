function text = localFormatPropertyValue_(value)
% localFormatPropertyValue_(value)
% Format a numeric value for a GUI text edit field.
if isscalar(value)
    text = num2str(double(value), '%g');
else
    text = mat2str(double(value));
end
end
