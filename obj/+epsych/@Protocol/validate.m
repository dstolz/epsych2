function report = validate(obj)
% report = validate(obj)
%
% Validate protocol for structural and logical errors.
%
% Returns:
%   report - struct array with fields: field, message, severity
%            severity: 0=info, 1=warning, 2=error
%
% See also: validate_internal

report = obj.validate_internal();
end
