function [paramData, metadata] = phaseParameterData(filepath)
% [paramData, metadata] = epsych.Runtime.phaseParameterData(filepath)
% Parse a phase file into a uniform parameter struct array plus metadata.
%
% Phases are stored as protocol files (.eprot/.prot; see epsych.Protocol) or as
% legacy JSON parameter snapshots (writeParametersJSON). Both are reduced here to
% the same shape so loading (readParameters) and previewing (gui.PhaseSelector)
% have a single format to resolve: one struct per parameter carrying the fields
% produced by hw.Parameter.toStruct plus ParentType, the owning interface Type
% used to match the entry to a live interface.
%
% Parameters:
%   filepath - Path to a .eprot/.prot protocol file or a legacy .json parameter file.
%
% Returns:
%   paramData - 1xN struct array of parameter entries (empty struct array if the
%               file defines no parameters).
%   metadata  - Struct with fields:
%                 Description - phase description (protocol Info or JSON Description)
%                 Source      - "Protocol" or "JSON"
%                 Extra       - remaining file metadata (protocol meta struct, or
%                               the JSON document minus Parameters)
%
% See also: readParameters, writeParametersProtocol, epsych.Protocol.load

arguments
    filepath (1,1) string {mustBeFile}
end

[~,~,ext] = fileparts(filepath);

if strcmpi(ext, '.json')
    data = jsondecode(fileread(filepath));
    if isfield(data, 'Parameters') && isstruct(data.Parameters)
        paramData = reshape(data.Parameters, 1, []);
    else
        paramData = struct([]);
    end
    metadata.Description = "";
    if isfield(data, 'Description')
        metadata.Description = string(data.Description);
    end
    metadata.Source = "JSON";
    if isfield(data, 'Parameters')
        metadata.Extra = rmfield(data, 'Parameters');
    else
        metadata.Extra = data;
    end
    return
end

% Anything that is not JSON is treated as a protocol file. Protocol.load
% reconstructs the interfaces without connecting hardware, and restores each
% parameter's metadata, design-time Values, Expression, and saved Value.
proto = epsych.Protocol.load(char(filepath));

entries = {};
for iface = proto.Interfaces
    modules = iface.Module;
    if ~isa(modules, 'hw.Module'), continue, end
    for module = reshape(modules, 1, [])
        for p = reshape(module.Parameters, 1, [])
            S = p.toStruct();
            S.ParentType = char(iface.Type);
            entries{end+1} = S; %#ok<AGROW>
        end
    end
end

if isempty(entries)
    paramData = struct([]);
else
    paramData = [entries{:}];
end

metadata.Description = string(proto.Info);
metadata.Source = "Protocol";
metadata.Extra = proto.meta;

end
