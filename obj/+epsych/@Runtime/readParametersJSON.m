function P = readParametersJSON(obj, filepath)
% P = readParametersJSON(obj, filepath)
% Load Parameters from a JSON file and return the resolved hw.Parameter objects.
%
% Reads a JSON file previously written by writeParametersJSON, resolves each entry to the
% live hw.Parameter that owns it (matched to an interface by ParentType and to a parameter
% by Name), and restores the saved properties. Serialized metadata and design-time Values are
% applied via fromStruct; the runtime Value is restored here for writable parameters (fromStruct
% intentionally leaves Value untouched). When a parameter defines an Expression, that expression
% is the source of truth and its evaluated result (the restored design-time Values) is used;
% otherwise the saved literal Value is restored. Writes to disconnected hardware are no-ops, so
% restoring Value is safe whether or not the backend is connected.
%
% Function handle strings are restored via str2func and string sentinels for Inf/-Inf/NaN are
% converted back to numeric values. PostUpdateFcnArgs is not restored. Entries with no matching
% interface or parameter are skipped.
%
% The resolved parameters are returned so the caller can apply them as needed (e.g.
% updateTrialsFromParameters). This avoids re-reading parameters via all_parameters, which would
% discard the loaded values.
%
% Parameters:
%   obj                  The runtime object to update.
%   filepath (1,:) string
%                        Path to the input JSON file. If not provided or invalid, prompts user to select file.
%
% Returns:
%   P  hw.Parameter array of the resolved parameters, in file order. Empty if the load is
%      canceled or the file cannot be read.
%
% See also: writeParametersJSON, updateTrialsFromParameters, hw.Parameter, jsondecode

arguments
    obj
    filepath (1,:) string = ""
end

P = hw.Parameter.empty(1,0);

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


interfaceTypes = arrayfun(@(x) string(x.Type), obj.Interfaces);

% Resolve each file entry to its live hw.Parameter and restore its saved properties.
for k = 1:nP
    S = paramData(k);

    parentType = string(S.ParentType);
    S = rmfield(S, 'ParentType'); % remove ParentType from struct before applying to Parameter since it's not an actual field of hw.Parameter and is only used for matching to the correct interface during load

    vprintf(4,'Processing parameter %d/%d: "%s" (Module: "%s")', k, nP, S.Name, parentType)

    % Match the interface that owns this parameter by its Type
    iface = obj.Interfaces(interfaceTypes == parentType);
    if isempty(iface)
        vprintf(0,1, 'No matching interface found for parameter "%s" with parent "%s". Skipping.', S.Name, parentType)
        continue
    end

    xp = iface(1).find_parameter(S.Name,includeInvisible=true);
    if isempty(xp)
        % find_parameter already warned; nothing to resolve against.
        continue
    end
    xp = xp(1);

    % Restore metadata and design-time Values. fromStruct deliberately leaves the runtime Value
    % alone, so set it here for writable, non-StimType parameters (StimType Value is handled by
    % fromStruct). When the parameter defines an Expression, that expression is the source of
    % truth: its evaluated result is the restored (design-time) Values, so derive the value from
    % those rather than the saved literal, which may have drifted from the expression at save
    % time. Otherwise restore the saved literal value. The set.Value setter clamps to bounds and
    % disconnected backends ignore the hardware write.
    xp.fromStruct(S);
    if ~strcmp(xp.Type,'StimType') && ~strcmp(xp.Access,'Read')
        if strlength(xp.Expression) > 0 && ~isempty(xp.Values)
            xp.Value = xp.Values{1};
        % else
        %     xp.Value = S.Value;
        end
    end

    P(end+1) = xp;
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

vprintf(3, 'Read %d parameters from %s', numel(P), filepath)

end
