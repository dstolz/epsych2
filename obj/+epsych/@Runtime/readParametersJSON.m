function P = readParametersJSON(obj, filepath)
% P = readParametersJSON(obj, filepath)
% Load Parameters from a phase file and return the resolved hw.Parameter objects.
%
% Kept for backward compatibility with the JSON-only phase format; delegates to
% readParameters, which handles both protocol phase files (.eprot/.prot) and
% legacy JSON snapshots.
%
% Parameters:
%   obj                  The runtime object to update.
%   filepath (1,:) string
%                        Path to the input file. If not provided or invalid, prompts
%                        user to select a file.
%
% Returns:
%   P  hw.Parameter array of the resolved parameters, in file order. Empty if the
%      load is canceled or the file cannot be read.
%
% See also: readParameters, writeParametersProtocol, writeParametersJSON

arguments
    obj
    filepath (1,:) string = ""
end

P = obj.readParameters(filepath);

end
