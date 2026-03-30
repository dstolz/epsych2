function writeParametersJSON(obj, filepath, description)
% writeParametersJSON(obj, filepath)
% Serialize hw.Parameter objects to a human-readable JSON file.
%
% Writes module metadata (Label, Name, Index, Fs) and all publicly writable properties of each hw.Parameter
% to a JSON file. Function handles are stored as strings, callback enabled flags are included, and Inf/-Inf/NaN
% bounds are stored as string sentinels. PostUpdateFcnArgs is excluded due to unreliable round-tripping through JSON.
%
% Parameters:
%   obj                         The runtime object containing the parameters.
%   filepath (1,:) string       Path to the output JSON file. If not provided or invalid, prompts user to select location.
%   description (1,1) string    Optional description for the JSON file. Defaults to creation timestamp.
%
% Returns:
%   None. Writes JSON file to disk.
%
% See also: hw.Parameter, jsonencode

arguments
    obj
    filepath (1,:) string = ""
    description (1,1) string = "Created on " + string(datetime('now'))
end

% If filepath is not provided or invalid, prompt user to select file
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
nP = numel(Parameters);
paramStructs = cell(1, nP);
for k = 1:nP
    paramStructs{k} = Parameters(k).toStruct;
    paramStructs{k} = rmfield(paramStructs{k}, 'UserData'); % exclude UserData from JSON output since it can contain non-serializable data and is not essential for parameter reconstruction
end

% Create output struct with metadata and parameter data
data = struct();
data.Description = description;
data.Timestamp   = datetime('now');
data.Parameters  = [paramStructs{:}];


% Convert to JSON string with pretty printing
jsonStr = jsonencode(data, PrettyPrint=true);

% Write JSON string to file
fid = fopen(filepath, 'w');
if fid == -1
    vprintf(0, 1, 'Failed to open file for writing: %s', filepath)
    return
end
fwrite(fid, jsonStr, 'char');
fclose(fid);

vprintf(3, 'Wrote %d parameters to %s', nP, filepath)

end
