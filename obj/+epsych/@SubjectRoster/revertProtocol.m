function report = revertProtocol(self, subjectId, projectId, options)
% report = revertProtocol(self, subjectId, projectId)
% report = revertProtocol(self, subjectId, projectId, Index = 2)
% report = revertProtocol(self, subjectId, projectId, Protocol = pfn, Version = v)
% Put a subject back on a protocol it was on before.
%
% What this can and cannot do
% ---------------------------
% It restores the protocol *file and version* recorded for this subject. When
% the earlier entry names a different .eprot that still holds the version it
% named, the revert is exact: the subject runs that protocol again.
%
% It cannot resurrect the CONTENT of an .eprot that has since been saved over.
% epsych.Protocol.save overwrites the file in place and keeps no archive, so
% once a protocol goes from v4 to v5 there is no v4 anywhere on disk to go back
% to. Reverting to an entry in that state restores the pointer and the recorded
% version, and the report says plainly that the file no longer holds it
% (Recoverable = false) — better than a silent lie in either direction. Labs
% that need true version rollback should Save As a new file per revision, which
% this then reverts between exactly.
%
% Reverting is itself undoable: the protocol being left is pushed onto the
% history, so the same call run twice returns to where it started.
%
% Parameters:
%   subjectId - SubjectID or subject Name.
%   projectId - ProjectID or project Name.
%
% Options:
%   Index    - which history entry, 1 being the most recent. Default 1.
%   Protocol - revert to this file instead of a history entry.
%   Version  - version to record with Protocol. Default: read from the file.
%
% Returns:
%   report - struct with fields ok, From, FromVersion, To, ToVersion,
%            Recoverable, message.
%
% See also: epsych.SubjectRoster.protocolHistory, epsych.SubjectRoster.updateProtocol
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
    options.Index (1,1) double {mustBePositive, mustBeInteger} = 1
    options.Protocol (1,:) char = ''
    options.Version (1,:) char = char.empty
end

report = struct('ok', false, 'From', '', 'FromVersion', '', ...
    'To', '', 'ToVersion', '', 'Recoverable', false, 'message', '');

[rec, idx] = self.findMembership(subjectId, projectId);
if isempty(idx)
    report.message = 'That subject is not in that project, so it has no protocol history.';
    return
end

sid = rec.SubjectID;
pid = rec.ProjectID;

history = epsych.SubjectRoster.normalize_(rec.ProtocolHistory, ...
    epsych.SubjectRoster.blankHistory_());

if isempty(options.Protocol)
    if numel(history) < options.Index
        report.message = ['There is no earlier protocol on record for this subject. ' ...
            'History starts the first time its protocol changes.'];
        return
    end
    target        = history(options.Index).File;
    targetVersion = history(options.Index).Version;
    dropIndex     = options.Index;
else
    target        = options.Protocol;
    targetVersion = options.Version;
    if isempty(targetVersion)
        targetVersion = epsych.Protocol.versionOnDisk(target);
    end
    % Reverting to an explicitly named file still consumes a matching history
    % entry, so the list does not keep offering where we already are.
    dropIndex = [];
    if ~isempty(history)
        dropIndex = find(strcmp({history.File}, target) & ...
            strcmp({history.Version}, targetVersion), 1);
    end
end

onDisk = epsych.Protocol.versionOnDisk(target);
report.From        = rec.LastProtocol;
report.FromVersion = rec.LastProtocolVersion;
report.To          = target;
report.ToVersion   = targetVersion;
report.Recoverable = ~isempty(onDisk) && strcmp(onDisk, targetVersion);

if ~isfile(target)
    report.message = sprintf('That protocol file no longer exists: %s', target);
    vprintf(0, 1, 'Cannot revert "%s" to a missing protocol file: %s', subjectId, target);
    return
end

self.mutate_(@applyRevert);

report.ok = true;
[~, tn, te] = fileparts(target);
if report.Recoverable
    report.message = sprintf('Reverted to %s%s (%s).', tn, te, localOrUnknown(targetVersion));
else
    report.message = sprintf(['Reverted to %s%s and recorded version %s, but that file ' ...
        'now holds %s — saving a protocol overwrites it, so its earlier content is ' ...
        'not recoverable.'], tn, te, localOrUnknown(targetVersion), localOrUnknown(onDisk));
end
vprintf(1, 'Reverted protocol for "%s" in "%s": %s -> %s', subjectId, projectId, ...
    localOrUnknown(report.FromVersion), localOrUnknown(targetVersion));

    function applyRevert(r)
        [~, k] = r.findMembership(sid, pid);
        if isempty(k), return, end

        prior = r.Memberships(k);
        h = epsych.SubjectRoster.normalize_(prior.ProtocolHistory, ...
            epsych.SubjectRoster.blankHistory_());

        % Drop the entry being restored before pushing the one being left, so
        % the list always describes where this subject has been but is not now.
        if ~isempty(dropIndex) && numel(h) >= dropIndex
            h(dropIndex) = [];
        end
        if ~isempty(prior.LastProtocol)
            h = epsych.SubjectRoster.pushHistory_(h, prior.LastProtocol, ...
                prior.LastProtocolVersion);
        end

        r.Memberships(k).ProtocolHistory     = h;
        r.Memberships(k).LastProtocol        = target;
        r.Memberships(k).LastProtocolVersion = targetVersion;
        r.Memberships(k).Modified            = datetime('now');
    end

end

% -----------------------------------------------------------------------
function s = localOrUnknown(version)
s = version;
if isempty(s), s = 'an unknown version'; end
end
