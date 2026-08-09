function result = normalizeExpressionResult(~, parameter, result)
% result = normalizeExpressionResult(~, parameter, result)
% Validate an expression result and convert it to the target parameter type.
%
% Parameters:
%	parameter	- Target parameter that defines the required output type.
%	result		- Numeric or logical expression result to normalize.
%
% Returns:
%	result		- Type-correct value ready to assign back to the parameter.
    if ~(isnumeric(result) || islogical(result)) || isempty(result)
        error('Expression for %s must evaluate to a numeric or logical value.', parameter.Name);
    end

    if isnumeric(result) && any(~isfinite(result(:)))
        error('Expression for %s must evaluate to finite numeric values.', parameter.Name);
    end

    switch parameter.Type
        case 'Integer'
            rounded = round(double(result));
            if any(abs(double(result(:)) - rounded(:)) > 1e-9)
                error('Expression for %s must evaluate to integer values.', parameter.Name);
            end
            result = rounded;
        case 'Boolean'
            if isnumeric(result) && any(result(:) ~= 0 & result(:) ~= 1)
                error('Expression for %s must evaluate to boolean (0 or 1) values.', parameter.Name);
            end
            result = logical(result);
        otherwise
            result = double(result);
    end
end

