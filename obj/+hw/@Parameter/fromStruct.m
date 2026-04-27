
function fromStruct(obj, S)
% fromStruct(obj, S)
% Apply a serialized struct to this hw.Parameter object.
%
% Restores metadata, flags, bounds, and design-time trial levels (Values).
% Does NOT restore Value (runtime-only state).
%
% Parameters:
%   obj (1,1) hw.Parameter
%   S (1,1) struct — struct from toStruct()

arguments
    obj (1,1) hw.Parameter
    S (1,1) struct
end


% Metadata
obj.Name = char(S.Name);
obj.Description = string(S.Description);
obj.Unit = char(S.Unit);
obj.Access = normalizeLegacyAccess(char(S.Access));
obj.Type = char(S.Type);
obj.Format = char(S.Format);
obj.Visible = logical(S.Visible);

%{
% Callbacks
obj.PreUpdateFcn = obj.strToFcn_(S.PreUpdateFcn);
obj.EvaluatorFcn = obj.strToFcn_(S.EvaluatorFcn);
obj.PostUpdateFcn = obj.strToFcn_(S.PostUpdateFcn);


obj.PreUpdateFcnArgs = obj.strToFcnArgs_(S.PreUpdateFcnArgs);
obj.EvaluatorFcnArgs = obj.strToFcnArgs_(S.EvaluatorFcnArgs);
obj.PostUpdateFcnArgs = obj.strToFcnArgs_(S.PostUpdateFcnArgs);

obj.PreUpdateFcnEnabled = logical(S.PreUpdateFcnEnabled);
obj.EvaluatorFcnEnabled = logical(S.EvaluatorFcnEnabled);
obj.PostUpdateFcnEnabled = logical(S.PostUpdateFcnEnabled);
%}

% Flags
obj.isArray = logical(S.isArray);
obj.isTrigger = logical(S.isTrigger);

% Bounds
obj.Min = obj.safeToNumeric_(S.Min);
obj.Max = obj.safeToNumeric_(S.Max);
obj.isRandom = logical(S.isRandom);

if isfield(S, 'UserData')
    obj.UserData = S.UserData;
end

if isfield(S, 'lastUpdated')
    obj.lastUpdated = double(S.lastUpdated);
end

% Design-time trial levels
obj.Values = S.Values;

end


function access = normalizeLegacyAccess(access)
if isequal(access, 'Read / Write')
    access = 'Any';
end
end

