function [value, isArrayValue] = coerceValueForType(obj, rawValue, targetType)
    switch targetType
        case 'Float'
            numericValue = obj.coerceNumericValue(rawValue, false);
            value = double(numericValue);
            isArrayValue = numel(value) > 1;
        case 'Integer'
            numericValue = obj.coerceNumericValue(rawValue, false);
            value = round(double(numericValue));
            isArrayValue = numel(value) > 1;
        case 'Boolean'
            value = obj.coerceLogicalValue(rawValue);
            isArrayValue = numel(value) > 1;
        case {'Buffer', 'Coefficient Buffer'}
            numericValue = obj.coerceNumericValue(rawValue, true);
            value = double(numericValue);
            isArrayValue = numel(value) > 1;
        case 'String'
            value = obj.normalizeCompiledPreviewValueAsText(rawValue);
            isArrayValue = false;
        case 'Undefined'
            value = 0;
            isArrayValue = false;
        otherwise
            value = rawValue;
            isArrayValue = iscell(rawValue) || (isstring(rawValue) && numel(rawValue) > 1) || (isnumeric(rawValue) && numel(rawValue) > 1) || (islogical(rawValue) && numel(rawValue) > 1);
    end
end

