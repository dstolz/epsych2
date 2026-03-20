function applyParameterStruct(~, P, S)
% applyParameterStruct(obj, P, S)
% Apply a decoded JSON struct onto an existing hw.Parameter.
%
% String-encoded function handles are restored via str2func. String
% sentinel values ("Inf", "-Inf", "NaN") for Min and Max are converted
% back to their numeric equivalents.
%
% Parameters
%   P - scalar hw.Parameter handle to update
%   S - struct decoded from JSON with serialized parameter fields

% Metadata
P.Name        = S.Name;
P.Description = string(S.Description);
P.Unit        = S.Unit;
P.Access      = S.Access;
P.Type        = S.Type;
P.Format      = S.Format;
P.Visible     = logical(S.Visible);

% Callbacks
P.PreUpdateFcn  = strToFcn(S.PreUpdateFcn);
P.EvaluatorFcn  = strToFcn(S.EvaluatorFcn);
P.PostUpdateFcn = strToFcn(S.PostUpdateFcn);

% Flags
P.isArray   = logical(S.isArray);
P.isTrigger = logical(S.isTrigger);
P.isRandom  = logical(S.isRandom);

% Bounds
P.Min = safeToNumeric(S.Min);
P.Max = safeToNumeric(S.Max);

% Value (set after Type/bounds so validation context is correct)
P.Value = S.Value;

% Timestamp
P.lastUpdated = S.lastUpdated;

% General-purpose data
P.UserData = S.UserData;

end


function f = strToFcn(s)
% Convert a non-empty string back to a function_handle; return [] otherwise.
if isstring(s), s = char(s); end
if ischar(s) && ~isempty(s)
    f = str2func(s);
else
    f = [];
end
end


function v = safeToNumeric(x)
% Decode string sentinels "Inf", "-Inf", "NaN" back to numeric values.
if isstring(x) || ischar(x)
    x = char(x);
    switch x
        case 'Inf',  v = Inf;
        case '-Inf', v = -Inf;
        case 'NaN',  v = NaN;
        otherwise,   v = str2double(x);
    end
else
    v = double(x);
end
end
