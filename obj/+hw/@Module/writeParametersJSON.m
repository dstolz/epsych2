function writeParametersJSON(obj, filepath)
% obj.writeParametersJSON(filepath)
% Serialize the Module's Parameters to a JSON file.
%
% Writes Module metadata (Label, Name, Index, Fs) and the publicly
% writable properties of each hw.Parameter to a human-readable JSON file.
% Function handles are stored as strings. Callback enabled flags are
% included. Inf/-Inf/NaN bounds are stored as string sentinels.
% PostUpdateFcnArgs is not included because heterogeneous cell arrays do
% not round-trip reliably through JSON.
%
% Parameters
%   filepath - path to the output JSON file (char or string)

arguments
    obj (1,1) hw.Module
    filepath (1,:) {mustBeText}
end

filepath = char(filepath);

% Module-level metadata
data = struct();
data.Label = obj.Label;
data.Name  = obj.Name;
data.Index = obj.Index;
data.Fs    = obj.Fs;

% Serialize each Parameter
nP = numel(obj.Parameters);
paramStructs = cell(1, nP);
for k = 1:nP
    paramStructs{k} = obj.toStruct(obj.Parameters(k));
end

if nP == 0
    data.Parameters = struct.empty;
elseif nP == 1
    data.Parameters = paramStructs{1};
else
    data.Parameters = [paramStructs{:}];
end

jsonStr = jsonencode(data, PrettyPrint=true);

fid = fopen(filepath, 'w');
if fid == -1
    vprintf(0, 1, 'Failed to open file for writing: %s', filepath)
    return
end
cleanupObj = onCleanup(@() fclose(fid));
fwrite(fid, jsonStr, 'char');

vprintf(3, 'Wrote %d parameters to %s', nP, filepath)

end
