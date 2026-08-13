function p = addParameter(obj, interfaceName, name, value, options)
% p = addParameter(obj, interfaceName, name, value, varargin)
%
% Add a hw.Parameter to a specific interface within this protocol.
% Delegates to hw.Interface.add_parameter().
%
% Parameters:
%   interfaceName (char) - Name of target interface (default 'Software')
%   name (char) - Parameter name
%   value - Initial parameter value (numeric, logical, or cell)
%   Description, Unit, Access, Type, Format, Visible, Min, Max, etc. - hw.Parameter options
%
% Returns:
%   p - Created hw.Parameter handle
arguments
    obj
    interfaceName (1,:) char = 'Software'
    name (1,:) char = ''
    value = 1
    options.Description (1,1) string = ""
    options.Unit (1,:) char = ''
    options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Any','Read / Write'})} = 'Any'
    options.Type (1,:) char {mustBeMember(options.Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','File','Undefined'})} = 'Float'
    options.Format (1,:) char = '%g'
    options.Visible (1,1) logical = true
    options.isArray (1,1) logical = false
    options.isTrigger (1,1) logical = false
    options.isRandom (1,1) logical = false
    options.Min (1,1) double = -inf
    options.Max (1,1) double = inf
    options.UserData = []
    % No defaults: forwarded only when the caller passes them, so the
    % hw.Parameter constructor's isTrigger/Coefficient Buffer defaulting
    % still applies otherwise.
    options.UpdateEveryTrial (1,1) logical
    options.SetOnce (1,1) logical
end

if isempty(name)
    vprintf(0, 1, 'Parameter name cannot be empty');
    p = [];
    return
end

hwif = obj.findInterface(interfaceName);
if isempty(hwif)
    vprintf(0, 1, 'Interface "%s" not found in protocol', interfaceName);
    p = [];
    return
end

% Build name-value pairs for hw.Interface.add_parameter
copts = namedargs2cell(options);
p = hwif.add_parameter(name, value, copts{:});
