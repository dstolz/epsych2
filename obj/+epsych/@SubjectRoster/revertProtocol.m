function report = revertProtocol(self, subjectId, projectId, options)
% report = revertProtocol(self, subjectId, projectId)
% report = revertProtocol(self, subjectId, projectId, Index = 2)
% report = revertProtocol(self, subjectId, projectId, Protocol = pfn, Version = v)
% report = revertProtocol(self, ..., RestoreContent = true)
% Put a subject back on a protocol it was on before.
%
% What this can and cannot do
% ---------------------------
% It restores the protocol *file and version* recorded for this subject, and —
% when asked — the file's CONTENT at that version. The revert is exact in
% either of two cases: the entry names a file that still holds the version it
% was recorded at (protocols revised as separate files), or the version sits
% in the file's embedded archive — epsych.Protocol.save keeps every superseded
% version inside the .eprot, and RestoreContent = true rewrites the file back
% to it via epsych.Protocol.restoreVersion. The report's Source field says
% which case applies ('disk' or 'archive'); Recoverable covers both.
%
% RestoreContent defaults to false because rewriting a protocol file is more
% than roster bookkeeping: the file may be shared, and every subject on it
% gets the restored content. OthersOnFile lists the other subjects in this
% roster recorded on the same file at a different version, so a caller can
% warn before opting in.
%
% Only a file last written by an EPsych release without version archiving can
% still defeat a revert (Source = 'none'): the pointer and recorded version
% come back, and the report says plainly that the content does not.
%
% Reverting is itself undoable: the protocol being left is pushed onto the
% history — and a content restore archives the content being replaced — so
% the same call run twice returns to where it started.
%
% Parameters:
%   subjectId - SubjectID or subject Name.
%   projectId - ProjectID or project Name.
%
% Options:
%   Index          - which history entry, 1 being the most recent. Default 1.
%   Protocol       - revert to this file instead of a history entry.
%   Version        - version to record with Protocol. Default: read from the file.
%   RestoreContent - also rewrite the file back to the recorded version when
%                    it sits in the file's version archive. Default false.
%
% Returns:
%   report - struct with fields ok, From, FromVersion, To, ToVersion,
%            Recoverable, Source ('disk'|'archive'|'none'), ContentRestored,
%            OthersOnFile (SubjectIDs recorded on the same file at another
%            version), message.
%
% See also: epsych.SubjectRoster.protocolHistory, epsych.Protocol.restoreVersion,
%   epsych.SubjectRoster.updateProtocol
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
    options.Index (1,1) double {mustBePositive, mustBeInteger} = 1
    options.Protocol (1,:) char = ''
    options.Version (1,:) char = char.empty
    options.RestoreContent (1,1) logical = false
end

report = struct('ok', false, 'From', '', 'FromVersion', '', ...
    'To', '', 'ToVersion', '', 'Recoverable', false, 'Source', 'none', ...
    'ContentRestored', false, 'OthersOnFile', {{}}, 'message', '');

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
if ~isempty(onDisk) && strcmp(onDisk, targetVersion)
    report.Source = 'disk';
elseif epsych.Protocol.hasVersion(target, targetVersion)
    report.Source = 'archive';
end
report.Recoverable = ~strcmp(report.Source, 'none');

% Other subjects recorded on this same file at another version: rewriting the
% file back changes what THEY run too, so a caller deciding on RestoreContent
% needs to know before, not after.
for mIdx = 1:numel(self.Memberships)
    m = self.Memberships(mIdx);
    if strcmp(m.SubjectID, sid) && strcmp(m.ProjectID, pid), continue, end
    if localSamePath(m.LastProtocol, target) && ~strcmp(m.LastProtocolVersion, targetVersion)
        report.OthersOnFile{end+1} = m.SubjectID;
    end
end
report.OthersOnFile = unique(report.OthersOnFile, 'stable');

if ~isfile(target)
    report.message = sprintf('That protocol file no longer exists: %s', target);
    vprintf(0, 1, 'Cannot revert "%s" to a missing protocol file: %s', subjectId, target);
    return
end

% Rewrite the file first, roster second: a failed restore must leave the
% roster untouched, while a failed roster write after a successful restore
% still leaves the file recoverable forward (the replaced content is archived).
if options.RestoreContent && strcmp(report.Source, 'archive')
    rr = epsych.Protocol.restoreVersion(target, targetVersion, Mode = 'exact');
    if ~rr.ok
        report.message = sprintf('Could not restore %s in %s: %s', ...
            localOrUnknown(targetVersion), target, rr.message);
        vprintf(0, 1, 'Revert for "%s" stopped before touching the roster: %s', ...
            subjectId, report.message);
        return
    end
    report.ContentRestored = true;
end

self.mutate_(@applyRevert);

report.ok = true;
[~, tn, te] = fileparts(target);
if report.ContentRestored
    report.message = sprintf(['Restored %s from the version archive of %s%s ' ...
        'and reverted.'], localOrUnknown(targetVersion), tn, te);
elseif strcmp(report.Source, 'archive')
    report.message = sprintf(['Reverted to %s%s and recorded version %s. The file ' ...
        'now holds %s, but %s is in its version archive — revert with content ' ...
        'restore (or epsych.Protocol.restoreVersion) to bring it back exactly.'], ...
        tn, te, localOrUnknown(targetVersion), localOrUnknown(onDisk), ...
        localOrUnknown(targetVersion));
elseif report.Recoverable
    report.message = sprintf('Reverted to %s%s (%s).', tn, te, localOrUnknown(targetVersion));
else
    report.message = sprintf(['Reverted to %s%s and recorded version %s, but that file ' ...
        'now holds %s and its version archive does not include %s — files last saved ' ...
        'by an older EPsych keep no archive, so the earlier content is not recoverable.'], ...
        tn, te, localOrUnknown(targetVersion), localOrUnknown(onDisk), ...
        localOrUnknown(targetVersion));
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

% -----------------------------------------------------------------------
function tf = localSamePath(a, b)
% Same file by path text: case-insensitive with normalized separators on
% Windows, exact elsewhere. Mirrors protocolStatus's comparison.
a = localNormPath(a);
b = localNormPath(b);
tf = ~isempty(a) && strcmp(a, b);
end

% -----------------------------------------------------------------------
function p = localNormPath(p)
p = char(p);
if ispc
    p = lower(strrep(p, '/', '\'));
end
end
