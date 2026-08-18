function writeProtocolFile(filename, protocolStruct, options)
    % epsych.Protocol.writeProtocolFile(filename, protocolStruct)
    % epsych.Protocol.writeProtocolFile(..., Origin='save'|'phase'|'restore')
    %
    % Single low-level chokepoint for writing a protocol MAT file.
    %
    % Every .eprot write goes through here so the file's embedded version
    % history survives no matter who writes. When the incoming struct carries
    % a protocolVersion different from the file's current one, the current
    % content is archived first; when it carries the same one, the content is
    % replaced without an archive entry — within one file a version string
    % identifies content, so a same-version write is a content update, not a
    % new version.
    %
    % The file holds four MAT variables:
    %   protocol      - unchanged toStruct layout (formatVersion stays 1.0,
    %                   so phase fast-parse and every legacy reader still work)
    %   history       - full superseded protocol structs, newest first
    %   historyIndex  - Version/SavedAt/Origin only, so listing versions
    %                   never decompresses the archived payloads
    %   historyFormat - container format version (1)
    %
    % The write is atomic (same-directory temp + movefile, the
    % SubjectRoster.saveAtomic_ idiom) and always ends by dropping any
    % Runtime.phaseCache entry for the path: a rewrite landing within the
    % filesystem's timestamp resolution could otherwise serve a stale parse.
    %
    % Parameters:
    %   filename       - target .eprot/.prot path
    %   protocolStruct - epsych.Protocol.toStruct output
    %
    % Options:
    %   Origin - recorded on the archived entry: 'save' (default), 'phase',
    %            or 'restore'.
    %   History / UseExplicitHistory - restoreVersion supplies a history it
    %            has already rearranged; by default the history is read from
    %            the existing file.
    %
    % See also: epsych.Protocol.save, epsych.Protocol.restoreVersion,
    %   epsych.Runtime.writeParametersProtocol

    arguments
        filename (1,:) char
        protocolStruct (1,1) struct
        options.Origin (1,:) char {mustBeMember(options.Origin, {'save','phase','restore'})} = 'save'
        options.History struct = struct([])
        options.UseExplicitHistory (1,1) logical = false
    end

    newVersion = '';
    if isfield(protocolStruct, 'protocolVersion')
        newVersion = char(string(protocolStruct.protocolVersion));
    end

    if options.UseExplicitHistory
        history = options.History;
    else
        [Pold, history] = epsych.Protocol.readRaw_(filename);
        if ~isempty(Pold)
            oldVersion = '';
            if isfield(Pold, 'protocolVersion')
                oldVersion = char(string(Pold.protocolVersion));
            end
            if ~strcmp(oldVersion, newVersion)
                % Archive the superseded content. One entry per version
                % string: drop any earlier snapshot of the same version.
                if ~isempty(history)
                    history = history(~strcmp({history.Version}, oldVersion));
                end
                entry = struct();
                entry.Version  = oldVersion;
                entry.SavedAt  = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
                entry.Origin   = options.Origin;
                entry.Protocol = Pold;
                history = [entry, history];
            end
        end
    end

    if isempty(history)
        % Keep the variables' shape stable even when there is nothing in them.
        history = struct('Version', {}, 'SavedAt', {}, 'Origin', {}, 'Protocol', {});
        historyIndex = struct('Version', {}, 'SavedAt', {}, 'Origin', {});
    else
        historyIndex = rmfield(history, 'Protocol');
    end
    historyFormat = 1;
    protocol = protocolStruct;

    % Atomic write: temp file in the same directory (same volume makes the
    % movefile a rename), so a crash or full disk leaves the previous good
    % file — and its archive — untouched.
    tmp = sprintf('%s.%d-%s.tmp', filename, feature('getpid'), ...
        lower(dec2hex(randi([0, 16^4 - 1]), 4)));
    try
        builtin('save', tmp, 'protocol', 'history', 'historyIndex', 'historyFormat', '-mat');
        movefile(tmp, filename, 'f');
    catch ME
        if isfile(tmp)
            try
                delete(tmp);
            catch
            end
        end
        rethrow(ME);
    end

    % The phase cache keys on modification time and size; drop the entry
    % outright so a rewrite landing within the filesystem's timestamp
    % resolution cannot serve the old parse. Never let a cache problem fail
    % a protocol save.
    try
        epsych.Runtime.phaseCache('clear', string(filename));
    catch ME
        vprintf(3, 'Could not clear the phase cache for "%s": %s', filename, ME.message);
    end

    % Keep-all retention can grow a heavily saved file without bound; say so
    % once it gets big rather than surprising a lab at MAT v7's 2 GB
    % per-variable ceiling.
    d = dir(filename);
    if ~isempty(d) && d(1).bytes > 200e6
        vprintf(1, ['Protocol file %s is %.0f MB: its version archive keeps every save. ' ...
            'Consider starting a fresh file with Save As.'], filename, d(1).bytes / 1e6);
    end
end
