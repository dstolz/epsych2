function jsonText = toJSON(obj)
% jsonText = toJSON(obj)
% Serialize this hw.Parameter to a pretty-printed JSON string via toStruct.
% UserData is excluded and ParentType is appended. If called with no output,
% the JSON text is copied to the clipboard instead.
%
% Parameters:
%   obj  - hw.Parameter instance to serialize.
%
% Returns:
%   jsonText - Pretty-printed JSON string representing this parameter.
%
% See also: hw.Parameter.toStruct, hw.Parameter.fromStruct, epsych.Runtime.writeParametersJSON

S = obj.toStruct();
S = rmfield(S, 'UserData');
S.ParentType = obj.Parent.Type;

jsonText = jsonencode(S, PrettyPrint=true);

if nargout == 0
    clipboard('copy', jsonText);
    vprintf(3, 'JSON for parameter "%s" copied to clipboard.', obj.Name)
end
