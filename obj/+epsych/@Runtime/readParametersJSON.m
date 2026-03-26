
function readParametersJSON(obj, filepath)
% readParametersJSON(obj, filepath)
% Load Parameters from a JSON file into this Module.
%
% Reads a JSON file previously written by writeParametersJSON and restores Parameter properties. Existing Parameters are matched by Name and updated in-place. Parameters present in the file but not in the Module are created via add_parameter. Issues a warning if Module metadata (Label, Name, Index) in the file does not match this Module.
%
% Function handle strings are restored via str2func, callback enabled flags are restored when present, and string sentinels for Inf/-Inf/NaN are converted back to numeric values. PostUpdateFcnArgs is not restored.
%
% Parameters:
%   obj (1,1) hw.Runtime
%       The runtime object to update.
%   filepath (1,:) string
%       Path to the input JSON file. If not provided or invalid, prompts user to select file.
%
% Returns:
%   None. Updates Parameters in-place.
%
% See also: writeParametersJSON, hw.Parameter, jsondecode

arguments
    obj (1,1) hw.Runtime
    filepath (1,:) string = ""
end


if filepath == "" || ~isfile(filepath)
    [fn,pth] = uigetfile('*.json','Select JSON File to Load Parameters');
    if isequal(fn,0) || isequal(pth,0)
        vprintf(3,'User canceled load operation.')
        return
    end
    filepath = fullfile(pth, fn);
end

fid = fopen(filepath, 'r');
if fid == -1
    vprintf(0, 1, 'Failed to open file for reading: %s', filepath)
    return
end
cleanupObj = onCleanup(@() fclose(fid));
jsonStr = fread(fid, '*char')';

data = jsondecode(jsonStr);

paramData = data.Parameters;

% jsondecode returns a struct array when all elements share the same fields
if isstruct(paramData)
    nP = numel(paramData);
else
    nP = 0;
end

HW_names = string({obj.M.Name});

for k = 1:nP
    P = paramData(k);

    
    if P.ModuleName == "Software"
        obj.S.fromStruct(obj.S.Parameters(P.Name), P);
    else
        % Match existing HW Parameter by Name
        i = find(HW_names == P.ModuleName, 1);
        if isempty(i)
            vprintf(0,1, 'No matching module found for parameter "%s" with ModuleName "%s". Skipping.', P.Name, P.ModuleName)
            continue
        end
        obj.HW(i).fromStruct(obj.M(i).Parameters(P.Name), P);
    end

    
end

vprintf(3, 'Read %d parameters from %s', nP, filepath)

end

