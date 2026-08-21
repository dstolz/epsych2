function report = updateProtocol(self, subjectIds, projectId, options)
% report = updateProtocol(self, subjectIds, projectId)
% report = updateProtocol(self, subjectIds, projectId, UseProjectDefault = true)
% report = updateProtocol(self, subjectIds, projectId, Protocol = pfn)
% Bring one subject, or a whole project's worth, onto the current protocol.
%
% With no options this records the version the protocol file holds right now,
% for whatever file each subject is already on — the answer to "the protocol
% was edited; put everyone on the new one". UseProjectDefault additionally
% moves each subject onto the project's default file, and Protocol onto a named
% file.
%
% Nothing about a protocol's *content* changes here, and nothing needs to: a
% session loads the .eprot at commit time, so the newest saved version is what
% runs regardless. What is recorded is which version each subject is expected
% to be on, which is what turns the check green and what revertProtocol offers
% back.
%
% The one subject for which that is not already true is one revertProtocol
% HELD on an archived version -- its sessions load that version rather than the
% file's content. Updating is what releases the hold, which is the same thing as
% bringing it forward, so nothing special is needed here: recording a different
% version is what clears the pin (see rememberProtocol).
%
% The previous file and version go onto the membership's ProtocolHistory before
% being replaced, so an update is undoable.
%
% Parameters:
%   subjectIds - SubjectID or Name; char for one, cellstr/string for many.
%   projectId  - project whose memberships are updated. Required: protocol
%                memory is per-membership, so there is nothing to write without
%                one.
%
% Options:
%   UseProjectDefault - point each subject at the project's DefaultProtocol.
%   Protocol          - point each subject at this .eprot. Wins over
%                       UseProjectDefault.
%
% Returns:
%   report - struct with fields:
%     ok       - true when at least one subject was updated
%     updated  - (1,:) struct: SubjectID, Name, From, FromVersion, To, ToVersion
%     skipped  - (1,:) struct: Name, reason
%     message  - one-line summary suitable for a status bar
%
% Example:
%   ids = {R.subjectsInProject(p).SubjectID};
%   rep = R.updateProtocol(ids, p);        % everyone onto the latest version
%
% See also: epsych.SubjectRoster.protocolStatus, epsych.SubjectRoster.revertProtocol,
%   epsych.SubjectRoster.rememberProtocol
arguments
    self
    subjectIds
    projectId (1,:) char
    options.UseProjectDefault (1,1) logical = false
    options.Protocol (1,:) char = ''
end

subjectIds = cellstr(string(subjectIds));

report = struct('ok', false, ...
    'updated', struct('SubjectID', {}, 'Name', {}, 'From', {}, 'FromVersion', {}, ...
                      'To', {}, 'ToVersion', {}), ...
    'skipped', struct('Name', {}, 'reason', {}), ...
    'message', '');

if isempty(subjectIds)
    report.message = 'No subjects were selected.';
    return
end

if isempty(projectId)
    report.message = ['Select a project first: what a subject last ran is ' ...
        'recorded per project, so there is nothing to update in the All Subjects view.'];
    return
end

p = self.findProject(projectId);
if isempty(p)
    report.message = 'That project is no longer in the roster.';
    return
end

% The requested target, when it is the same for everyone.
forced = options.Protocol;
if isempty(forced) && options.UseProjectDefault
    forced = p.DefaultProtocol;
    if isempty(forced)
        report.message = sprintf('Project "%s" has no default protocol to apply.', p.Name);
        return
    end
end

for i = 1:numel(subjectIds)
    rec = self.findSubject(subjectIds{i});
    if isempty(rec)
        report.skipped(end+1) = struct('Name', subjectIds{i}, 'reason', 'not in the roster');
        continue
    end

    m = self.findMembership(rec.SubjectID, p.ProjectID);
    if isempty(m)
        report.skipped(end+1) = struct('Name', rec.Name, ...
            'reason', sprintf('not in project "%s"', p.Name));
        continue
    end

    target = forced;
    if isempty(target)
        target = m.LastProtocol;
        if isempty(target), target = p.DefaultProtocol; end
    end

    if isempty(target)
        report.skipped(end+1) = struct('Name', rec.Name, ...
            'reason', 'no protocol: none on record and the project has no default');
        continue
    end

    if ~isfile(target)
        report.skipped(end+1) = struct('Name', rec.Name, ...
            'reason', sprintf('protocol file not found: %s', target));
        continue
    end

    latest = epsych.Protocol.versionOnDisk(target);
    if strcmp(m.LastProtocol, target) && strcmp(m.LastProtocolVersion, latest)
        report.skipped(end+1) = struct('Name', rec.Name, 'reason', 'already current');
        continue
    end

    self.rememberProtocol(rec.SubjectID, p.ProjectID, target, NaN, Version = latest);

    report.updated(end+1) = struct('SubjectID', rec.SubjectID, 'Name', rec.Name, ...
        'From', m.LastProtocol, 'FromVersion', m.LastProtocolVersion, ...
        'To', target, 'ToVersion', latest);
end

report.ok = ~isempty(report.updated);

if isempty(report.updated)
    report.message = sprintf('Nothing to update; %d subject(s) were already current or could not be used.', ...
        numel(report.skipped));
else
    report.message = sprintf('Updated %d subject(s).', numel(report.updated));
    if ~isempty(report.skipped)
        report.message = sprintf('%s %d unchanged.', report.message, numel(report.skipped));
    end
    vprintf(1, 'Protocol updated for %d subject(s) in project "%s".', ...
        numel(report.updated), p.Name);
end
