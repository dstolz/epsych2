
function fromStruct(obj, S)
% fromStruct(obj, S)
% Restore serialized metadata and design-time values onto a hw.Parameter object.
%
% Parameters:
%	S	- Struct produced by toStruct().
%
% Does not restore the runtime Value property.

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
else
    obj.Values = S.Values;
end

% Restore current Value for StimType parameters
if isequal(obj.Type, 'StimType') && isfield(S, 'Value') && ~isempty(S.Value)
    if isstruct(S.Value) && isfield(S.Value, 'Class')
        obj.Value = stimgen.StimType.fromStruct(S.Value);
    elseif iscell(S.Value)
        objs = cellfun(@(e) stimgen.StimType.fromStruct(e), S.Value, 'UniformOutput', false);
        obj.Value = [objs{:}];
    end
end

end


function access = normalizeLegacyAccess(access)
if isequal(access, 'Read / Write')
    access = 'Any';
end
end

