function S = toStruct(obj)
% S = obj.toStruct()
% Convert this parameter to a struct safe for JSON serialization.
%
% Returns
%   S - struct with serialization-safe field values.

S = struct();

% Metadata
S.Name = obj.Name;
S.Description = obj.Description;
S.Unit = obj.Unit;
S.Access = obj.Access;
S.Type = obj.Type;
S.Format = obj.Format;
S.Visible = obj.Visible;

% Callbacks
S.PreUpdateFcn = obj.fcnToStr_(obj.PreUpdateFcn);
S.EvaluatorFcn = obj.fcnToStr_(obj.EvaluatorFcn);
S.PostUpdateFcn = obj.fcnToStr_(obj.PostUpdateFcn);
S.PreUpdateFcnEnabled = obj.PreUpdateFcnEnabled;
S.EvaluatorFcnEnabled = obj.EvaluatorFcnEnabled;
S.PostUpdateFcnEnabled = obj.PostUpdateFcnEnabled;

% Value and state
S.Value = obj.Value;
S.lastUpdated = obj.lastUpdated;
S.isArray = obj.isArray;
S.isTrigger = obj.isTrigger;
S.isRandom = obj.isRandom;

% Bounds
S.Min = obj.numericToSafe_(obj.Min);
S.Max = obj.numericToSafe_(obj.Max);

% General-purpose data
S.UserData = obj.UserData;
end