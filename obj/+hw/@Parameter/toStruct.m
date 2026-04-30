
function S = toStruct(obj)
% S = toStruct(obj)
% Convert a hw.Parameter object to a serialization-safe struct.
%
% Returns:
%	S	- Struct containing metadata, design-time values, runtime state, and user data.

S = struct();

% Metadata
%S.InterfaceType = obj.Parent.Type;

S.Name = obj.Name;
S.Description = obj.Description;
S.Unit = obj.Unit;
S.Access = obj.Access;
S.Type = obj.Type;
S.Format = obj.Format;
S.Visible = obj.Visible;

%{
% Callbacks
S.PreUpdateFcn = obj.fcnToStr_(obj.PreUpdateFcn);
S.EvaluatorFcn = obj.fcnToStr_(obj.EvaluatorFcn);
S.PostUpdateFcn = obj.fcnToStr_(obj.PostUpdateFcn);

S.PreUpdateFcnArgs = obj.PreUpdateFcnArgs;
S.EvaluatorFcnArgs = obj.EvaluatorFcnArgs;
S.PostUpdateFcnArgs = obj.PostUpdateFcnArgs;


S.PreUpdateFcnArgs = obj.argsToStr_(obj.PreUpdateFcnArgs);
S.EvaluatorFcnArgs = obj.argsToStr_(obj.EvaluatorFcnArgs);
S.PostUpdateFcnArgs = obj.argsToStr_(obj.PostUpdateFcnArgs);

S.PreUpdateFcnEnabled = obj.PreUpdateFcnEnabled;
S.EvaluatorFcnEnabled = obj.EvaluatorFcnEnabled;
S.PostUpdateFcnEnabled = obj.PostUpdateFcnEnabled;
%}


% Design-time trial levels
S.Values = obj.Values;

% Value and state (runtime; not restored on load)
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
