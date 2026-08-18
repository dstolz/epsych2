function [P, H, info] = readRaw_(filename)
    % [P, H, info] = epsych.Protocol.readRaw_(filename)
    % Read a protocol MAT file's current struct and embedded version history
    % without reconstructing any objects.
    %
    % Selective per-variable loads keep this cheap: MAT v7 compresses per
    % variable, so asking for 'protocol' never decompresses the archive.
    %
    % Never throws: a missing, unreadable, or foreign file returns P = [].
    %
    % Parameters:
    %   filename - .eprot/.prot MAT protocol file
    %
    % Returns:
    %   P    - current protocol struct, or [] when the file holds none. A
    %          legacy live-object layout is converted through toStruct so its
    %          content can still be archived (info.WasObject = true).
    %   H    - (1,:) history struct array, newest first, fields Version,
    %          SavedAt, Origin, Protocol. Empty for files written before
    %          version history existed.
    %   info - struct with Variables (MAT variable names), HasHistory,
    %          WasObject.
    %
    % See also: epsych.Protocol.writeProtocolFile, epsych.Protocol.listVersions

    arguments
        filename (1,:) char
    end

    P = [];
    H = localBlankHistory();
    info = struct('Variables', {{}}, 'HasHistory', false, 'WasObject', false);

    if isempty(filename) || ~isfile(filename), return, end

    try
        info.Variables = {whos('-file', filename).name};
    catch ME
        vprintf(3, 'Not a readable MAT protocol file: "%s" (%s)', filename, ME.message);
        return
    end

    try
        if ismember('protocol', info.Variables)
            S = builtin('load', filename, '-mat', 'protocol');
            if isstruct(S.protocol)
                P = S.protocol;
            elseif isa(S.protocol, 'epsych.Protocol')
                P = S.protocol.toStruct();
                info.WasObject = true;
            end
        elseif ismember('protocol_struct', info.Variables)
            S = builtin('load', filename, '-mat', 'protocol_struct');
            if isstruct(S.protocol_struct)
                P = S.protocol_struct;
            end
        end
    catch ME
        vprintf(3, 'Could not read a protocol struct from "%s": %s', filename, ME.message);
        P = [];
    end

    if ismember('history', info.Variables)
        try
            S = builtin('load', filename, '-mat', 'history');
            H = localNormalizeHistory(S.history);
            info.HasHistory = ~isempty(H);
        catch ME
            vprintf(3, 'Could not read the version history from "%s": %s', filename, ME.message);
            H = localBlankHistory();
        end
    end
end

% -----------------------------------------------------------------------
function H = localBlankHistory()
    H = struct('Version', {}, 'SavedAt', {}, 'Origin', {}, 'Protocol', {});
end

% -----------------------------------------------------------------------
function H = localNormalizeHistory(raw)
    % Coerce a stored history variable to the canonical shape, dropping any
    % entry that carries no protocol struct: an entry that cannot be restored
    % is not history, and keeping it would only make listVersions lie.
    H = localBlankHistory();
    if ~isstruct(raw) || isempty(raw), return, end

    for i = 1:numel(raw)
        e = raw(i);
        if ~isfield(e, 'Protocol') || ~isstruct(e.Protocol) || ~isscalar(e.Protocol)
            vprintf(3, 'Dropping malformed protocol history entry %d: no protocol struct', i);
            continue
        end
        n = struct();
        n.Version = '';
        n.SavedAt = '';
        n.Origin  = 'save';
        if isfield(e, 'Version'), n.Version = char(string(e.Version)); end
        if isfield(e, 'SavedAt'), n.SavedAt = char(string(e.SavedAt)); end
        if isfield(e, 'Origin'),  n.Origin  = char(string(e.Origin));  end
        n.Protocol = e.Protocol;
        H(end+1) = n;
    end
end
