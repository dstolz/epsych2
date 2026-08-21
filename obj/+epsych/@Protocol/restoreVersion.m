function report = restoreVersion(filename, version, options)
    % report = epsych.Protocol.restoreVersion(filename, version)
    % report = epsych.Protocol.restoreVersion(..., Mode='newversion'|'exact')
    %
    % Rewrite a protocol file back to a version in its embedded archive.
    %
    % Two modes, differing in what the version string becomes:
    %
    %   'newversion' (default) - the archived content comes back as a NEW
    %       version, minted past everything the file has ever held, the way
    %       git revert works. The counter stays monotonic, so a subject
    %       recorded on the superseded version correctly reads as behind the
    %       restored one everywhere versions are compared.
    %
    %   'exact' - the file's current protocol struct becomes the archived one
    %       verbatim, old version string included. This is what a roster
    %       revert needs (LastProtocolVersion must match the file again), but
    %       note the counter rewinds: anyone recorded on a newer version now
    %       reads as ahead of the file.
    %
    % Either way the content being replaced is archived first, so a restore
    % is itself undoable, and the write is atomic.
    %
    % Parameters:
    %   filename - .eprot/.prot protocol file
    %   version  - archived version string to bring back
    %
    % Options:
    %   Mode - 'newversion' (default) or 'exact'
    %
    % Returns:
    %   report - struct with fields ok, File, RestoredVersion, NewVersion
    %            (the version string the file now holds), Mode, message.
    %            Expected failures (no such version, JSON, foreign file)
    %            come back as ok=false with a plain message, in the roster's
    %            report idiom, rather than as errors.
    %
    % See also: epsych.Protocol.listVersions, epsych.Protocol.loadVersion,
    %   epsych.SubjectRoster.revertProtocol

    arguments
        filename (1,:) char
        version (1,:) char
        options.Mode (1,:) char {mustBeMember(options.Mode, {'newversion', 'exact'})} = 'newversion'
    end

    report = struct('ok', false, 'File', filename, 'RestoredVersion', version, ...
        'NewVersion', '', 'Mode', options.Mode, 'message', '');

    if ~isfile(filename)
        report.message = sprintf('File not found: %s', filename);
        return
    end

    [~, ~, ext] = fileparts(filename);
    if strcmpi(ext, '.json')
        report.message = 'JSON protocol files keep no version history, so there is nothing to restore.';
        return
    end

    [P, H] = epsych.Protocol.readRaw_(filename);
    if isempty(P)
        report.message = sprintf('Not a protocol file: %s', filename);
        return
    end

    cur = '';
    if isfield(P, 'protocolVersion'), cur = char(string(P.protocolVersion)); end

    if strcmp(version, cur)
        if strcmp(options.Mode, 'exact')
            % Nothing to do, and saying so beats failing: the file already
            % holds exactly what was asked for.
            report.ok = true;
            report.NewVersion = cur;
            report.message = sprintf('%s is already the current version.', version);
            return
        end
        report.message = sprintf(['%s is already the current version; restoring it as a ' ...
            'new version would only duplicate the current content.'], version);
        return
    end

    hit = [];
    if ~isempty(H)
        hit = find(strcmp({H.Version}, version), 1);
    end
    if isempty(hit)
        report.message = sprintf(['The version archive of %s does not hold %s. ' ...
            'Files last saved by an older EPsych keep no archive.'], filename, version);
        return
    end

    target = H(hit).Protocol;

    if strcmp(options.Mode, 'exact')
        % The restored entry becomes the current content, so it leaves the
        % archive — within one file a version string identifies content, and
        % the same version must not exist in both places.
        H(hit) = [];
        S = target;
        report.NewVersion = version;
    else
        % Mint past everything the file has ever held, current included.
        ns = [epsych.Protocol.versionNumber(cur), ...
            arrayfun(@(e) epsych.Protocol.versionNumber(e.Version), H)];
        maxN = max([ns, 0], [], 'omitnan');
        S = target;
        S.protocolVersion = sprintf('v%d.%s', maxN + 1, ...
            char(datetime('now', 'Format', 'yyMMdd')));
        S.lastModified = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
        report.NewVersion = S.protocolVersion;
    end

    % Archive the content being replaced, so the restore is undoable.
    if ~isempty(H)
        H = H(~strcmp({H.Version}, cur));
    end
    entry = struct();
    entry.Version  = cur;
    entry.SavedAt  = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    entry.Origin   = 'restore';
    entry.Protocol = P;
    H = [entry, H];

    try
        epsych.Protocol.writeProtocolFile(filename, S, Origin='restore', ...
            History=H, UseExplicitHistory=true);
    catch ME
        vprintf(0, 1, ME);
        report.message = sprintf('Could not write %s: %s', filename, ME.message);
        return
    end

    report.ok = true;
    if strcmp(options.Mode, 'exact')
        report.message = sprintf('Restored %s exactly; %s moved into the version archive.', ...
            version, localOrUnknown(cur));
    else
        report.message = sprintf('Restored the content of %s as %s.', ...
            version, report.NewVersion);
    end
    vprintf(1, 'Restored %s of "%s" (%s mode); file now holds %s', ...
        version, filename, options.Mode, report.NewVersion);
end

% -----------------------------------------------------------------------
function s = localOrUnknown(version)
    s = version;
    if isempty(s), s = 'an unknown version'; end
end
