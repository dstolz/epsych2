function index = listVersions(filename)
    % index = epsych.Protocol.listVersions(filename)
    %
    % Every version a protocol file holds: the current one plus the archive
    % embedded by writeProtocolFile.
    %
    % Reads only the file's small variables — 'protocol' for the current
    % entry and 'historyIndex' for the rest — never the archived payloads.
    %
    % Parameters:
    %   filename - .eprot/.prot MAT protocol file, or .json
    %
    % Returns:
    %   index - (1,:) struct, current entry first then newest-first history,
    %           with fields Version, SavedAt, Origin ('save'|'phase'|
    %           'restore'), IsCurrent.
    %
    % A file written before version history existed lists only its current
    % version; JSON protocol files keep no history and list the same way.
    %
    % See also: epsych.Protocol.loadVersion, epsych.Protocol.restoreVersion,
    %   epsych.Protocol.hasVersion

    arguments
        filename (1,:) char
    end

    if ~isfile(filename)
        error('epsych:Protocol:FileNotFound', 'File not found: %s', filename);
    end

    [~, ~, ext] = fileparts(filename);
    if strcmpi(ext, '.json')
        S = jsondecode(fileread(filename));
        e = localEntry('', '', 'save', true);
        if isfield(S, 'protocolVersion'), e.Version = char(string(S.protocolVersion)); end
        if isfield(S, 'lastModified'),    e.SavedAt = char(string(S.lastModified)); end
        index = e;
        return
    end

    try
        vars = {whos('-file', filename).name};
    catch ME
        error('epsych:Protocol:InvalidFile', ...
            'Not a readable protocol file: %s (%s)', filename, ME.message);
    end

    % Current entry, from the 'protocol' variable alone.
    P = [];
    if ismember('protocol', vars)
        S = builtin('load', filename, '-mat', 'protocol');
        if isstruct(S.protocol)
            P = S.protocol;
        elseif isa(S.protocol, 'epsych.Protocol')
            P = S.protocol.toStruct();
        end
    elseif ismember('protocol_struct', vars)
        S = builtin('load', filename, '-mat', 'protocol_struct');
        if isstruct(S.protocol_struct)
            P = S.protocol_struct;
        end
    end
    if isempty(P)
        error('epsych:Protocol:InvalidFile', ...
            'MAT file does not contain expected protocol data: %s', filename);
    end

    cur = localEntry('', '', 'save', true);
    if isfield(P, 'protocolVersion'), cur.Version = char(string(P.protocolVersion)); end
    if isfield(P, 'lastModified'),    cur.SavedAt = char(string(P.lastModified)); end
    index = cur;

    % Archived entries, from the index; fall back to deriving from the full
    % history only when the index is missing or malformed (a hand-edited
    % file), since that load decompresses every payload.
    hi = struct([]);
    if ismember('historyIndex', vars)
        S = builtin('load', filename, '-mat', 'historyIndex');
        if isstruct(S.historyIndex) && all(isfield(S.historyIndex, {'Version', 'SavedAt', 'Origin'}))
            hi = S.historyIndex;
        end
    end
    if isempty(hi) && ismember('history', vars)
        [~, H] = epsych.Protocol.readRaw_(filename);
        if ~isempty(H)
            hi = rmfield(H, 'Protocol');
        end
    end

    for i = 1:numel(hi)
        index(end+1) = localEntry( ...
            char(string(hi(i).Version)), char(string(hi(i).SavedAt)), ...
            char(string(hi(i).Origin)), false);
    end
end

% -----------------------------------------------------------------------
function e = localEntry(version, savedAt, origin, isCurrent)
    e = struct();
    e.Version   = version;
    e.SavedAt   = savedAt;
    e.Origin    = origin;
    e.IsCurrent = isCurrent;
end
