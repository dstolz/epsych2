function fromStruct(obj, S)
% obj.fromStruct(S)
% Apply a decoded serialized struct onto this parameter.
%
% Parameters
%   S - struct decoded from JSON with serialized parameter fields.

arguments
    obj (1,1) hw.Parameter
    S (1,1) struct
end

% Metadata
obj.Name = char(S.Name);
obj.Description = string(S.Description);
obj.Unit = char(S.Unit);
obj.Access = char(S.Access);
obj.Type = char(S.Type);
obj.Format = char(S.Format);
obj.Visible = logical(S.Visible);

% Callbacks
obj.PreUpdateFcn = obj.strToFcn_(S.PreUpdateFcn);
obj.EvaluatorFcn = obj.strToFcn_(S.EvaluatorFcn);
obj.PostUpdateFcn = obj.strToFcn_(S.PostUpdateFcn);

% Flags
obj.isArray = logical(S.isArray);
obj.isTrigger = logical(S.isTrigger);
obj.isRandom = logical(S.isRandom);

% Bounds
obj.Min = obj.safeToNumeric_(S.Min);
obj.Max = obj.safeToNumeric_(S.Max);

% Value (set after Type/bounds so validation context is correct)
obj.Value = S.Value;

% Timestamp
obj.lastUpdated = S.lastUpdated;

% General-purpose data
obj.UserData = S.UserData;
end