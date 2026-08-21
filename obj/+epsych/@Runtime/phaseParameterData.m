function [paramData, metadata] = phaseParameterData(filepath, options)
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
% Results are memoized by epsych.Runtime.phaseCache, keyed on the file's path,
% modification time, and size. One preview-plus-load of a phase asks for the same
% file three times and browsing a dropdown asks once per selection, while parsing
% an .eprot is expensive, so the parse is done once and reused. A phase re-saved
% mid-session is re-parsed automatically. Pass UseCache=false to force a parse;
% epsych.Runtime.phaseCache('clear'|'disable') is the session-wide escape hatch.
%
% A saved protocol already stores the parameter structs this function returns, so
% they are read straight out of the MAT file whenever its shape is recognized in
% full; anything else falls back to epsych.Protocol.load, which rebuilds the whole
% object graph. Pass FastParse=false to force the fallback.
%
% Parameters:
%   filepath - Path to a .eprot/.prot protocol file or a legacy .json parameter file.
%   options.UseCache - logical (default=true). Consult and populate the phase cache.
%   options.FastParse - logical (default=true). Read parameter structs directly from
%               a recognized .eprot instead of reconstructing an epsych.Protocol.
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
% See also: readParameters, writeParametersProtocol, phaseCache, epsych.Protocol.load

arguments
    filepath (1,1) string {mustBeFile}
    options.UseCache (1,1) logical = true
    options.FastParse (1,1) logical = true
end

if options.UseCache
    [hit, cached] = epsych.Runtime.phaseCache('get', filepath);
    if hit
        paramData = cached.paramData;
        metadata  = cached.metadata;
        return
    end
end
epsych.Runtime.phaseCache('parsed');

[paramData, metadata] = localParse(filepath, options.FastParse);

% The cache hands out its stored value directly rather than a copy. MATLAB
% structs are values, so a caller's rmfield or field assignment cannot reach back
% into it -- but a handle nested in a parameter's UserData would be shared. Such
% an entry is simply not cached, keeping "the cache holds values only" an
% enforced invariant rather than an assumption.
if options.UseCache && localIsCacheable(paramData)
    epsych.Runtime.phaseCache('put', filepath, ...
        struct('paramData', paramData, 'metadata', metadata));
end

end


function [paramData, metadata] = localParse(filepath, fastParse)
% Read the file, with no cache involvement.

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

% Anything that is not JSON is treated as a protocol file. A saved protocol
% stores exactly the parameter structs this function returns (see
% epsych.Protocol.toStruct), so read them straight out of the file when its
% shape is recognized in full. The fallback below is the authority: it
% reconstructs every interface, module, parameter and stimgen object -- without
% connecting hardware -- only for those structs to be serialized again, which
% costs seconds on a real protocol.
if fastParse
    [paramData, metadata, ok] = localFastParse(filepath);
    if ok
        return
    end
    vprintf(3, 'Phase parse: unrecognized file shape, falling back to Protocol.load for "%s"', filepath)
end

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


function [paramData, metadata, ok] = localFastParse(filepath)
% Read the saved parameter structs directly, skipping the object graph.
%
% An .eprot is a MAT file holding one 'protocol' struct whose
% InterfaceData{i}.Modules{m}.Parameters{k} entries are literally
% hw.Parameter.toStruct output -- this function's own output contract. Where
% the round trip through live objects does change a field (an expression's
% Value is re-evaluated, a random Value is re-drawn, 'Read / Write' normalizes
% to 'Any', lastUpdated is stamped) every consumer either re-derives that field
% from the live parameter or overwrites it, so reading the file as written is
% equivalent -- and for StimType entries it is more faithful, since the live
% hw.Parameter.fromStruct wants exactly the raw struct form.
%
% Any shape this function does not recognize in full returns ok=false, and the
% caller falls back to epsych.Protocol.load. That covers legacy handle-object
% files, the COMPILED.writeparams recovery branch, hand-built files, and any
% future format revision, none of which are worth second-guessing here.

% hw.Parameter.toStruct's complete field set, in toStruct's order. Requiring
% all of REQUIREDFIELDS IS the shape gate: a file missing even one is not
% something to guess about. SetOnce and PersistWithPhase (both added 2026-08)
% are the exceptions: phases saved before each lack the field, so they are
% defaulted below to what the fallback's load-then-toStruct round trip
% produces for such a file, keeping this parse equivalent for old and new
% files alike. Any field added to toStruct must be added here too -- an
% unlisted field is an unrecognized shape and drops every newly saved phase
% back to the slow path.
PARAMFIELDS = {'Name','Description','Unit','Access','Type','Format','Visible', ...
    'UpdateEveryTrial','SetOnce','PersistWithPhase','Values','Value','lastUpdated', ...
    'isArray','isTrigger','isRandom','Min','Max','UserData','Expression'};
REQUIREDFIELDS = setdiff(PARAMFIELDS, {'SetOnce','PersistWithPhase'}, 'stable');

% epsych.Protocol's meta property, in declaration order, which is the order
% metadata.Extra carries on the fallback path.
METAFIELDS = {'formatVersion','epsychVersion','createdDate','lastModified','protocolVersion'};

ok = false;
paramData = struct([]);
metadata = struct();

% Load only the protocol variable: an .eprot written with an embedded version
% archive (epsych.Protocol.writeProtocolFile) also carries every superseded
% version, and decompressing that here would cost exactly the time this fast
% path exists to save. The archive is a sibling MAT variable, never a field
% of 'protocol', so the shape gate below is unaffected.
vars = {whos('-file', char(filepath)).name};
if ~ismember('protocol', vars)
    return   % 'protocol_struct' layout, or not a protocol file at all
end
S = builtin('load', char(filepath), '-mat', 'protocol');
if ~isstruct(S.protocol)
    return   % legacy handle-object layout
end
P = S.protocol;

if ~isfield(P, 'formatVersion') || ~isequal(double(P.formatVersion), 1.0)
    return
end
if ~all(isfield(P, METAFIELDS))
    return
end
% An empty InterfaceData means the interfaces are recovered from
% COMPILED.writeparams instead (see epsych.Protocol.fromStruct); only the full
% path can do that.
if ~isfield(P, 'InterfaceData') || ~iscell(P.InterfaceData) || isempty(P.InterfaceData)
    return
end

entries = {};
for ifaceIdx = 1:numel(P.InterfaceData)
    IF = P.InterfaceData{ifaceIdx};
    if isempty(IF), continue, end
    if ~isstruct(IF) || ~all(isfield(IF, {'Type','Modules'})) || ~iscell(IF.Modules)
        return
    end
    parentType = char(string(IF.Type));
    for moduleIdx = 1:numel(IF.Modules)
        M = IF.Modules{moduleIdx};
        if ~isstruct(M) || ~isfield(M, 'Parameters') || ~iscell(M.Parameters)
            return
        end
        for paramIdx = 1:numel(M.Parameters)
            s = M.Parameters{paramIdx};
            if ~isstruct(s) || ~isscalar(s) || ~all(isfield(s, REQUIREDFIELDS))
                return
            end
            if ~isfield(s, 'SetOnce')
                s.SetOnce = false;   % pre-2026-08 file; hw.Parameter.fromStruct default
            end
            if ~isfield(s, 'PersistWithPhase')
                % A file predating the flag says nothing about it, and the
                % fallback path reconstructs such a parameter fresh, where the
                % property default is false.
                s.PersistWithPhase = false;
            end
            s.ParentType = parentType;
            % [entries{:}] requires identical field order across entries.
            % toStruct is deterministic, but a hand-edited file need not be.
            % Note orderfields with a name list errors on any field outside
            % the list, so an extra/unknown field falls back to Protocol.load
            % via the caller's shape guard rather than parsing here.
            if ~isempty(setdiff(fieldnames(s), [PARAMFIELDS {'ParentType'}]))
                return
            end
            entries{end+1} = orderfields(s, [PARAMFIELDS {'ParentType'}]); %#ok<AGROW>
        end
    end
end

if ~isempty(entries)
    paramData = [entries{:}];
end

if isfield(P, 'Info')
    metadata.Description = string(P.Info);
else
    metadata.Description = "";
end
metadata.Source = "Protocol";
metadata.Extra = orderfields(struct( ...
    'formatVersion',   P.formatVersion, ...
    'epsychVersion',   P.epsychVersion, ...
    'createdDate',     P.createdDate, ...
    'lastModified',    P.lastModified, ...
    'protocolVersion', P.protocolVersion), METAFIELDS);

ok = true;
end


function tf = localIsCacheable(paramData)
% Every field of an entry is a value except UserData, which
% hw.Parameter.toStruct passes through untouched. In practice it holds a
% hardware name, but a handle there would be shared with every later reader of
% the cached entry, so such a file is left uncached rather than deep-copied.
tf = true;
if ~isfield(paramData, 'UserData')
    return   % legacy JSON entries may omit it entirely
end
for k = 1:numel(paramData)
    u = paramData(k).UserData;
    if isa(u, 'handle') || (isstruct(u) && isscalar(u) && any(structfun(@(v) isa(v,'handle'), u)))
        tf = false;
        vprintf(3, 'Phase cache: not caching -- parameter "%s" carries a handle in UserData', ...
            paramData(k).Name)
        return
    end
end
end
