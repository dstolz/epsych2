function S = parameterToStruct(~, P)
% S = parameterToStruct(obj, P)
% Convert one hw.Parameter to a struct safe for JSON serialization.
%
% Function handles are converted to their string representation via
% func2str. Non-finite numeric values (Inf, -Inf, NaN) in Min and Max
% are stored as string sentinels because jsonencode maps them to null.
%
% PostUpdateFcnArgs is intentionally excluded because heterogeneous cell
% arrays do not round-trip reliably through JSON.
%
% Parameters
%   P - scalar hw.Parameter object
%
% Returns
%   S - struct with serialization-safe field values

S = struct();

% Metadata
S.Name        = P.Name;
S.Description = P.Description;
S.Unit        = P.Unit;
S.Access      = P.Access;
S.Type        = P.Type;
S.Format      = P.Format;
S.Visible     = P.Visible;

% Callbacks → string via func2str
S.PreUpdateFcn  = fcnToStr(P.PreUpdateFcn);
S.EvaluatorFcn  = fcnToStr(P.EvaluatorFcn);
S.PostUpdateFcn = fcnToStr(P.PostUpdateFcn);

% Value and state
S.Value       = P.Value;
S.lastUpdated = P.lastUpdated;
S.isArray     = P.isArray;
S.isTrigger   = P.isTrigger;
S.isRandom    = P.isRandom;

% Bounds → string sentinels for non-finite values
S.Min = numericToSafe(P.Min);
S.Max = numericToSafe(P.Max);

% General-purpose data
S.UserData = P.UserData;

end


function s = fcnToStr(f)
% Convert a function_handle to its string name; return "" for anything else.
if isa(f, 'function_handle')
    s = func2str(f);
else
    s = "";
end
end


function v = numericToSafe(x)
% Encode Inf, -Inf, NaN as string sentinels so jsonencode preserves them.
if isnan(x)
    v = "NaN";
elseif isinf(x) && x > 0
    v = "Inf";
elseif isinf(x) && x < 0
    v = "-Inf";
else
    v = x;
end
end
