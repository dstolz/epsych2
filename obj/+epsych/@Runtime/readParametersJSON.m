function readParametersJSON(obj, filepath)
% readParametersJSON(obj, filepath)
% Load Parameters from a JSON file into this Module.
%
% Reads a JSON file previously written by writeParametersJSON and restores Parameter properties.
% Existing Parameters are matched by Name and updated in-place. Parameters present in the file
% but not in the Module are created via add_parameter. Issues a warning if Module metadata
% (Label, Name, Index) in the file does not match this Module.
%
% Function handle strings are restored via str2func, callback enabled flags are restored when present,
% and string sentinels for Inf/-Inf/NaN are converted back to numeric values. PostUpdateFcnArgs is not restored.
%
% Parameters:
%   obj                  The runtime object to update.
%   filepath (1,:) string
%                        Path to the input JSON file. If not provided or invalid, prompts user to select file.
%
% Returns:
%   None. Updates Parameters in-place.
%
% See also: writeParametersJSON, hw.Parameter, jsondecode

arguments
    obj 
    filepath (1,:) string = ""
end


% If filepath is not provided or invalid, prompt user to select file
if filepath == "" || ~isfile(filepath)
    [fn,pth] = uigetfile('*.json','Select JSON File to Load Parameters');
    if isequal(fn,0) || isequal(pth,0)
        vprintf(3,'User canceled load operation.')
        return
    end
    filepath = fullfile(pth, fn);
end


% Open and read JSON file
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


existingParameters = obj.getAllParameters;
existingModuleNames = arrayfun(@(x) string(x.Module.Name),existingParameters);
existingModuleNames = unique(existingModuleNames);

% match parameters by Name and update in-place, create new parameters for unmatched entries
for k = 1:nP
    P = paramData(k);

    vprintf(4,'Processing parameter %d/%d: "%s" (Module: "%s")', k, nP, P.Name, P.ModuleName)

    % Match existing HW Parameter by Name
    i = find(existingModuleNames == P.ModuleName, 1);
    if isempty(i)
        vprintf(0,1, 'No matching module found for parameter "%s" with ModuleName "%s". Skipping.', P.Name, P.ModuleName)
        continue
    end
        
    if P.ModuleName == "Software"
        obj.S.fromStruct(obj.S.Parameters(P.Name), P);
    else
        obj.HW(i).fromStruct(obj.HW(i).Parameters(P.Name), P);
    end
end

% append metadata about the loaded phase to the obj.Phase property (create if it doesn't exist). This can be used by the GUI to display information about the currently loaded phase.
if ~isprop(obj,'Phase'), obj.addprop('Phase'); end
obj.Phase(end+1).Description = data.Description;
obj.Phase(end).ParametersLoaded = true;
obj.Phase(end).JSONPath = filepath;
obj.Phase(end).ParameterData = paramData;
obj.Phase(end).LoadTimestamp = datetime('now');
obj.Phase(end).Source = "JSON";
obj.Phase(end).Metadata = rmfield(data, 'Parameters');

vprintf(3, 'Read %d parameters from %s', nP, filepath)

end

