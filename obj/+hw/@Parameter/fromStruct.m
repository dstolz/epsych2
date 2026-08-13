
function fromStruct(obj, S, restoreValue)
% fromStruct(obj, S, restoreValue)
% Restore serialized metadata and design-time values onto a hw.Parameter object.
%
% Parameters:
%	S	         - Struct produced by toStruct().
%	restoreValue - Whether to also restore the runtime Value (default: true).
%	               Set false when the caller is reconstructing a whole set of
%	               sibling/cross-module parameters and needs every parameter
%	               wired into its Module before any Value is assigned; Value
%	               assignment evaluates obj.Expression against sibling
%	               parameters, which fails if not all siblings exist yet.
%	               Callers that pass false are responsible for restoring
%	               Value afterward via a second fromStruct call.

arguments
    obj (1,1) hw.Parameter
    S (1,1) struct
    restoreValue (1,1) logical = true
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
obj.isTrigger = logical(S.isTrigger); % set.isTrigger defaults UpdateEveryTrial; explicit value restored below wins
if isfield(S, 'UpdateEveryTrial')
    obj.UpdateEveryTrial = logical(S.UpdateEveryTrial);
end
% Legacy structs predate SetOnce; default false so a loaded protocol keeps its
% original dispatch behavior (the Coefficient Buffer default applies only to
% newly created parameters).
if isfield(S, 'SetOnce')
    obj.SetOnce = logical(S.SetOnce);
else
    obj.SetOnce = false;
end
% PersistWithPhase is deliberately NOT restored. It is set in code by whoever
% owns the parameter (a trial selector declaring its own session toggle), not
% authored in the file, so the live parameter is the authority and a file only
% ever echoes what some past session happened to know. Restoring it would let
% one phase saved before the owner was updated demote a persistent setting
% back to a momentary button -- permanently, since every later save would then
% record the demotion too. Readers that need it (readParameters,
% gui.PhaseSelector) take it from the live parameter instead.

% Bounds
obj.Min = obj.safeToNumeric_(S.Min);
obj.Max = obj.safeToNumeric_(S.Max);
obj.isRandom = logical(S.isRandom);

if isfield(S, 'UserData')
    obj.UserData = S.UserData;
end

if isfield(S, 'Expression')
    obj.Expression = string(S.Expression);
elseif isfield(S, 'UserData') && isstruct(S.UserData) && isfield(S.UserData, 'Expression')
    obj.Expression = string(S.UserData.Expression);

    if isstruct(obj.UserData) && isfield(obj.UserData, 'Expression')
        obj.UserData = rmfield(obj.UserData, 'Expression');
    end
end

if isfield(S, 'lastUpdated')
    obj.lastUpdated = double(S.lastUpdated);
end

% Design-time trial levels
if isequal(obj.Type, 'StimType')
    restored = cell(1, numel(S.Values));
    for k = 1:numel(S.Values)
        entry = S.Values{k};
        if isstruct(entry) && isfield(entry, 'Class')
            restored{k} = stimgen.StimType.fromStruct(entry);
        else
            restored{k} = entry;
        end
    end
    obj.Values = restored;
elseif isfield(S,'Values')
    % jsondecode collapses a JSON array of uniform numbers into a numeric
    % vector rather than a cell, so coerce back to the 1xN cell that
    % Values requires.
    obj.Values = hw.Parameter.normalizeValues(S.Values);
end

% Restore current Value for StimType parameters
if restoreValue
    if isequal(obj.Type, 'StimType') && isfield(S, 'Value') && ~isempty(S.Value)
        if isstruct(S.Value) && isfield(S.Value, 'Class')
            obj.Value = stimgen.StimType.fromStruct(S.Value);
        elseif iscell(S.Value)
            objs = cellfun(@(e) stimgen.StimType.fromStruct(e), S.Value, 'UniformOutput', false);
            obj.Value = [objs{:}];
        end
    elseif ~isequal(obj.Access,'Read')
        obj.Value = S.Value;
    end
end

end


function access = normalizeLegacyAccess(access)
if isequal(access, 'Read / Write')
    access = 'Any';
end
end

