function readParametersJSON(obj, filepath)
% obj.readParametersJSON(filepath)
% Load Parameters from a JSON file into this Module.
%
% Reads a JSON file previously written by writeParametersJSON and
% restores Parameter properties. Existing Parameters are matched by
% Name and updated in-place. Parameters present in the file but not
% in the Module are created via add_parameter. A warning is issued if
% the Module metadata (Label, Name, Index) in the file does not match
% this Module.
%
% Function handle strings are restored via str2func. String sentinels
% for Inf/-Inf/NaN are converted back to numeric values.
% PostUpdateFcnArgs is not restored (see class-level Limitations note).
%
% Parameters
%   filepath - path to the input JSON file (char or string)

arguments
    obj (1,1) hw.Module
    filepath (1,:) {mustBeText}
end

filepath = char(filepath);

fid = fopen(filepath, 'r');
if fid == -1
    vprintf(0, 1, 'Failed to open file for reading: %s', filepath)
    return
end
cleanupObj = onCleanup(@() fclose(fid));
jsonStr = fread(fid, '*char')';

data = jsondecode(jsonStr);

% Warn on metadata mismatch
if ~isequal(data.Label, obj.Label) || ~isequal(data.Name, obj.Name) || data.Index ~= obj.Index
    vprintf(2, 1, 'Module metadata mismatch: file has "%s/%s/%d", target is "%s/%s/%d". Proceeding anyway.', ...
        data.Label, data.Name, data.Index, obj.Label, obj.Name, obj.Index)
end

if ~isfield(data, 'Parameters') || isempty(data.Parameters)
    vprintf(3, 'No parameters found in %s', filepath)
    return
end

paramData = data.Parameters;

% jsondecode returns a struct array when all elements share the same fields
if isstruct(paramData)
    nP = numel(paramData);
else
    nP = 0;
end

for k = 1:nP
    S = paramData(k);

    % Match existing Parameter by Name
    idx = findParameterByName(obj, S.Name);

    if isempty(idx)
        % Create new Parameter with default value, then apply full struct
        P = obj.add_parameter(S.Name, S.Value, ...
            Access=S.Access, Type=S.Type);
        obj.applyParameterStruct(P, S);
    else
        obj.applyParameterStruct(obj.Parameters(idx), S);
    end
end

vprintf(3, 'Read %d parameters from %s', nP, filepath)

end


function idx = findParameterByName(obj, name)
% Return the index of the first Parameter whose Name matches, or [].
if isstring(name), name = char(name); end
for k = 1:numel(obj.Parameters)
    if isequal(obj.Parameters(k).Name, name)
        idx = k;
        return
    end
end
idx = [];
end
