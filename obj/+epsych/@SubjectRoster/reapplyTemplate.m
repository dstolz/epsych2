function report = reapplyTemplate(self, subjectIds, projectId)
% report = reapplyTemplate(self, subjectIds, projectId)
% Stamp the project's current session-defaults template onto memberships again.
%
% A template is stamped once, when a subject joins, and project edits never
% propagate on their own. This is the deliberate push: after editing the
% template, or for memberships written before the roster carried session
% settings (which read as all-inherit), it copies the project's SESSION_FIELDS
% onto each named membership verbatim -- including any per-subject edits, which
% is the point: everyone back onto one agreed configuration.
%
% Parameters:
%   subjectIds - SubjectID or Name; char for one, cellstr/string for many.
%   projectId  - project whose template is applied. Required: the settings are
%                per-membership, so there is nothing to stamp without one.
%
% Returns:
%   report - struct with fields:
%     ok       - true when at least one membership was updated
%     updated  - (1,:) struct: SubjectID, Name
%     skipped  - (1,:) struct: Name, reason
%     message  - one-line summary suitable for a status bar
%
% See also: epsych.SubjectRoster.updateMembership, epsych.SubjectRoster.updateProject,
%   epsych.SubjectRoster.assign
arguments
    self
    subjectIds
    projectId (1,:) char
end

subjectIds = cellstr(string(subjectIds));

report = struct('ok', false, ...
    'updated', struct('SubjectID', {}, 'Name', {}), ...
    'skipped', struct('Name', {}, 'reason', {}), ...
    'message', '');

if isempty(subjectIds)
    report.message = 'No subjects were selected.';
    return
end

if isempty(projectId)
    report.message = ['Select a project first: session settings are recorded ' ...
        'per project, so there is nothing to re-apply in the All Subjects view.'];
    return
end

p = self.findProject(projectId);
if isempty(p)
    report.message = 'That project is no longer in the roster.';
    return
end

pid = p.ProjectID;
self.mutate_(@applyStamp);

report.ok = ~isempty(report.updated);
report.message = sprintf('Re-applied the "%s" template to %d subject(s).', ...
    p.Name, numel(report.updated));
if ~isempty(report.skipped)
    report.message = sprintf('%s %d skipped.', report.message, numel(report.skipped));
end
vprintf(1, report.message);

    function applyStamp(r)
        % Resolve inside the mutation, so the template stamped is the one the
        % file holds now, not the one this session last saw.
        [tpl, kp] = r.findProject(pid);
        if isempty(kp)
            error('epsych:SubjectRoster:NoSuchProject', ...
                'Project "%s" was removed by another session.', pid);
        end

        for i = 1:numel(subjectIds)
            s = r.findSubject(subjectIds{i});
            if isempty(s)
                report.skipped(end+1) = struct('Name', subjectIds{i}, ...
                    'reason', 'not in the roster');
                continue
            end

            [cur, k] = r.findMembership(s.SubjectID, pid);
            if isempty(k)
                report.skipped(end+1) = struct('Name', s.Name, ...
                    'reason', 'not a member of this project');
                continue
            end

            for f = epsych.SubjectRoster.SESSION_FIELDS
                cur.(f{1}) = tpl.(f{1});
            end
            cur.Modified = datetime('now');
            r.Memberships(k) = cur;

            report.updated(end+1) = struct('SubjectID', s.SubjectID, 'Name', s.Name);
        end
    end

end
