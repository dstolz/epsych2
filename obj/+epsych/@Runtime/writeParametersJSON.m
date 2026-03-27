
function writeParametersJSON(obj, filepath)
% writeParametersJSON(obj, filepath)
% Serialize hw.Parameter objects to a human-readable JSON file.
%
% This function writes module metadata (Label, Name, Index, Fs) and all publicly writable properties of each hw.Parameter to a JSON file. Function handles are stored as strings, callback enabled flags are included, and Inf/-Inf/NaN bounds are stored as string sentinels. PostUpdateFcnArgs is excluded due to unreliable round-tripping through JSON.
%
% Parameters:
%   obj (1,1) hw.Runtime
%       The runtime object containing the parameters.
%   filepath (1,:) string
%       Path to the output JSON file. If not provided or invalid, prompts user to select location.
%
% Returns:
%   None. Writes JSON file to disk.
%
% See also: hw.Parameter, jsonencode
% For more details, see documentation/Parameter_Control.md

arguments
    obj (1,1) hw.Runtime
    filepath (1,:) string = ""
end

if filepath == "" || ~isfile(filepath)
    [fn,pth] = uiputfile('*.json','Save Current Parameters');
    if isequal(fn,0) || isequal(pth,0)
        vprintf(3,'User canceled save operation.')
        return
    end
    filepath = fullfile(pth, fn);
end

% retrieve all software parameters from the runtime
Parameters = obj.getAllParameters(includeTriggers=true, ...
                                    includeInvisible=true, ...
                                    includeArray=true, ...
                                    Access='Any');



% Serialize each Parameter
% TO DO: May be able to simply use jsonencode(Parameters) direclty : https://www.mathworks.com/help/releases/R2024b/matlab/import_export/customize-json-encoding-for-matlab-classes.html
nP = numel(Parameters);
paramStructs = cell(1, nP);
for k = 1:nP
    paramStructs{k} = Parameters(k).toStruct;
end

if nP == 0
    data.Parameters = struct.empty;
elseif nP == 1
    data.Parameters = paramStructs{1};
else
    data.Parameters = [paramStructs{:}];
end

% remove the "UserData" field if present, as it can contain non-serializable data.
data.Parameters = rmfield(data.Parameters, 'UserData');

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
