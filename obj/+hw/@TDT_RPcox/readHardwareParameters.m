function [tf, msg] = readHardwareParameters(obj, module, options)
% [tf, msg] = readHardwareParameters(obj, module)
% [tf, msg] = readHardwareParameters(obj, module, Mode='replace')
% Discover the module's parameter tags from its RPvds circuit.
%
% When connected, tags come from the live TDTRP PARTAG scan. Offline, the
% circuit file in module.Info.RPvdsFile is read directly through the RPco.X
% COM server (ReadCOF), so no hardware is required — this is the path
% ProtocolDesigner exercises, since designer interfaces are never connected.
%
% See also: hw.Interface.readHardwareParameters,
%   hw.TDT_RPcox.populateModuleParametersFromTags

arguments
    obj
    module (1,1) hw.Module
    options.Mode (1,:) char {mustBeMember(options.Mode,{'merge','replace'})} = 'merge'
end

tf = false;

if ~any(obj.Module == module)
    msg = sprintf('Module "%s" does not belong to this %s interface.', ...
        module.Name, char(obj.Type));
    return
end

try
    if obj.IsConnected
        tags = obj.HW(module.Index).PARTAG;
        tags = [tags{:}];
    else
        if ~isfield(module.Info, 'RPvdsFile') || isempty(module.Info.RPvdsFile)
            msg = sprintf('Module "%s" has no RPvds circuit file configured.', module.Name);
            return
        end

        rcxFile = char(string(module.Info.RPvdsFile));
        if ~isfile(rcxFile)
            msg = sprintf('RPvds circuit file not found: %s', rcxFile);
            return
        end

        tags = localReadCircuitTags_(rcxFile);
    end

    if strcmp(options.Mode, 'replace')
        module.Parameters = hw.Parameter.empty(1, 0);
    end

    [nAdded, nSkipped] = obj.populateModuleParametersFromTags(module, tags);
    obj.ensureUniqueParameterNames();

    tf = true;
    msg = sprintf('%s: added %d parameter(s), %d already present.', ...
        module.Name, nAdded, nSkipped);
catch ME
    vprintf(2, 'readHardwareParameters failed for module "%s": %s', module.Name, ME.message)
    msg = ME.message;
end

end


function tags = localReadCircuitTags_(rcxFile)
% Enumerate parameter tags from an RPvds circuit file without hardware.
% Mirrors TDTfun/ReadRPvdsTags but returns the TDTRP.PARTAG struct shape
% (tag_name/tag_type/tag_size) so one populate helper serves both paths.

% Must be actxserver with this exact ProgID spelling, matching TDTRP: MATLAB
% caches one COM wrapper class per CLSID per session, keyed to the first
% instantiation. Creating RPco.x as an actxcontrol here binds every later
% TDTRP actxserver instance to the stale control wrapper, and all of its
% method dispatch fails ("Unrecognized method ... COM.RPco_x").
try
    RP = actxserver('RPco.X');
catch ME
    error('hw:TDT_RPcox:ActiveXUnavailable', ...
        'The RPco.X COM server could not be created (%s). Install the TDT drivers (RPvdsEx).', ...
        ME.message);
end

cleanup = onCleanup(@() localReleaseReader_(RP));

r = RP.ReadCOF(rcxFile);
% The control sometimes fails the first read attempt (see TDTfun/ReadRPvdsTags).
for k = 1:10
    if r, break; end
    r = RP.ReadCOF(rcxFile);
end
if ~r
    error('hw:TDT_RPcox:ReadCOFFailed', ...
        'Unable to read parameter tags from RPvds file: %s', rcxFile);
end

tags = struct('tag_name', {}, 'tag_type', {}, 'tag_size', {});
n = RP.GetNumOf('ParTag');
for i = 1:n
    name = RP.GetNameOf('ParTag', i);
    % skip error messages and OpenEx proprietary tags
    if any(ismember(name, '/\|')) || contains(name, 'rPvDsHElpEr')
        continue
    end
    tags(end+1).tag_name = name;
    tags(end).tag_type = RP.GetTagType(name);
    tags(end).tag_size = RP.GetTagSize(name);
end

end


function localReleaseReader_(RP)
try
    delete(RP)
catch
end
end
