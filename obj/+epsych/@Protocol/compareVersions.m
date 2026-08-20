function report = compareVersions(fileA, versionA, fileB, versionB, options)
    % report = epsych.Protocol.compareVersions(file, versionA, file, versionB)
    % report = epsych.Protocol.compareVersions(fileA, versionA, fileB, versionB)
    % report = epsych.Protocol.compareVersions(file, version)   % against its current content
    %
    % Compare two protocol versions and say what changed between them.
    %
    % The two sides may live in the same file — the current content against
    % one of the versions archived inside it — or in two different files,
    % which is the case a subject's protocol history produces when a protocol
    % was revised by saving it under a new name.
    %
    % This never throws. A version that cannot be produced (the file is gone,
    % or it was last written by an EPsych release that kept no archive) is
    % reported as ok = false with a message written for an operator, because
    % every caller so far is a dialog that has to say so rather than fail.
    %
    % Only the two protocol structs are read; no hw.Interface, hw.Module or
    % hw.Parameter is reconstructed. A version naming a backend class this
    % installation does not have still compares.
    %
    % Parameters:
    %   fileA    - .eprot/.prot/.json protocol file holding the OLDER side
    %   versionA - version string; '' means that file's current content
    %   fileB    - file holding the NEWER side. Default: fileA
    %   versionB - version string; '' means that file's current content
    %
    % Options:
    %   IncludeTimestamps - pass through to diffStructs; off by default
    %
    % Returns:
    %   report - struct with fields:
    %     ok        - both versions were read
    %     message   - why not, when ok is false; '' otherwise
    %     A, B      - struct(File, Version, Label, Found) per side. Version is
    %                 what was actually read, so a '' request comes back
    %                 resolved to the file's current version
    %     Changes   - epsych.Protocol.diffStructs output
    %     Counts    - struct(Added, Removed, Changed, Total)
    %     Identical - true when the two versions differ in nothing reported
    %     Summary   - one line of counts, for a dialog header
    %
    % Example:
    %   r = epsych.Protocol.compareVersions(f, 'v3.260814');
    %   fprintf('%s\n', r.Summary);
    %
    % See also: epsych.Protocol.diffStructs, epsych.Protocol.listVersions,
    %   epsych.Protocol.loadVersion, gui.compareProtocolVersions

    arguments
        fileA (1,:) char
        versionA (1,:) char = ''
        fileB (1,:) char = ''
        versionB (1,:) char = ''
        options.IncludeTimestamps (1,1) logical = false
    end

    if isempty(fileB), fileB = fileA; end

    report = struct();
    report.ok        = false;
    report.message   = '';
    report.A         = localSide(fileA, versionA);
    report.B         = localSide(fileB, versionB);
    report.Changes   = epsych.Protocol.diffStructs(struct(), struct());
    report.Counts    = struct('Added', 0, 'Removed', 0, 'Changed', 0, 'Total', 0);
    report.Identical = false;
    report.Summary   = '';

    [sA, report.A, msgA] = localRead(report.A);
    [sB, report.B, msgB] = localRead(report.B);

    if ~isempty(msgA) || ~isempty(msgB)
        report.message = strtrim(strjoin({msgA, msgB}, ' '));
        report.Summary = report.message;
        return
    end

    report.Changes = epsych.Protocol.diffStructs(sA, sB, ...
        IncludeTimestamps = options.IncludeTimestamps);

    kinds = {report.Changes.Change};
    report.Counts.Added   = sum(strcmp(kinds, 'added'));
    report.Counts.Removed = sum(strcmp(kinds, 'removed'));
    report.Counts.Changed = sum(strcmp(kinds, 'changed'));
    report.Counts.Total   = numel(report.Changes);

    report.Identical = report.Counts.Total == 0;
    report.ok = true;

    if report.Identical
        report.Summary = 'No differences.';
    else
        report.Summary = sprintf('%d difference(s): %d added, %d removed, %d changed.', ...
            report.Counts.Total, report.Counts.Added, report.Counts.Removed, ...
            report.Counts.Changed);
    end
end

% -----------------------------------------------------------------------
function s = localSide(file, version)
    s = struct('File', file, 'Version', version, 'Label', '', 'Found', false);
end

% -----------------------------------------------------------------------
function [S, side, msg] = localRead(side)
    % Read one side's protocol struct. Everything a dialog needs to explain a
    % failure is decided here, so the caller has one message to show.
    S = struct();
    msg = '';

    [~, fn, fe] = fileparts(side.File);
    label = [fn, fe];

    if isempty(side.File)
        msg = 'No protocol file to compare.';
        side.Label = '(none)';
        return
    end

    if ~isfile(side.File)
        msg = sprintf('%s is missing, so there is nothing to compare it with.', label);
        side.Label = sprintf('%s (missing)', label);
        return
    end

    if strcmpi(fe, '.json')
        % JSON protocols keep no archive, so only the current content exists.
        try
            P = epsych.Protocol.load(side.File);
            S = P.toStruct();
        catch ME
            msg = sprintf('%s could not be read: %s', label, ME.message);
            side.Label = label;
            return
        end
    else
        [P, H] = epsych.Protocol.readRaw_(side.File);
        if isempty(P)
            msg = sprintf('%s is not a readable protocol file.', label);
            side.Label = label;
            return
        end

        cur = '';
        if isfield(P, 'protocolVersion'), cur = char(string(P.protocolVersion)); end

        if isempty(side.Version) || strcmp(side.Version, cur)
            S = P;
            side.Version = cur;
        else
            hit = [];
            if ~isempty(H), hit = find(strcmp({H.Version}, side.Version), 1); end
            if isempty(hit)
                msg = sprintf(['%s no longer holds %s and keeps no archived copy ' ...
                    'of it, so there is nothing to compare.'], label, side.Version);
                side.Label = sprintf('%s %s (not in file)', label, side.Version);
                return
            end
            S = H(hit).Protocol;
        end
    end

    if isempty(side.Version) && isfield(S, 'protocolVersion')
        side.Version = char(string(S.protocolVersion));
    end
    side.Found = true;
    side.Label = strtrim(sprintf('%s %s', label, side.Version));
end
