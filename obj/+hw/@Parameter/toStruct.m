
function S = toStruct(obj)
% S = toStruct(obj)
% Convert this hw.Parameter object to a struct safe for JSON serialization.
%
% Serializes all relevant fields, including metadata, callbacks, value, bounds, and user data, into a struct suitable for JSON encoding. Used for saving parameter state to disk or transferring between sessions.
%
% Parameters:
%   obj (1,1) hw.Parameter
%       The parameter object to serialize.
%
% Returns:
%   S (1,1) struct
%       Struct with serialization-safe field values.
%
% See also: fromStruct, writeParametersJSON, jsonencode

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

% Callbacks
S.PreUpdateFcn = obj.fcnToStr_(obj.PreUpdateFcn);
S.EvaluatorFcn = obj.fcnToStr_(obj.EvaluatorFcn);
S.PostUpdateFcn = obj.fcnToStr_(obj.PostUpdateFcn);

S.PreUpdateFcnArgs = obj.PreUpdateFcnArgs;
S.EvaluatorFcnArgs = obj.EvaluatorFcnArgs;
S.PostUpdateFcnArgs = obj.PostUpdateFcnArgs;

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
