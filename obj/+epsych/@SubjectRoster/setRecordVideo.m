function report = setRecordVideo(self, subjectIds, projectId, value, options)
% report = setRecordVideo(self, subjectIds, projectId, value)
% report = setRecordVideo(self, [], projectId, value, AllMembers = true)
% Turn automatic webcam recording on or off for memberships in one project.
%
% The setting is per-membership, like the parameter defaults: whether an
% animal is filmed is a fact about that animal in that study, and an operator
% should not have to remember to press the session window's Record Video
% toggle for the ones that need it. assignToSession reads it when the subject
% is added to a session and puts the result on the toggle.
%
% AllMembers covers every member of the project, retired ones included, and is
% resolved INSIDE the mutation, so a subject another rig enrolled a moment ago
% is covered too. Retired members are included because the setting is the
% animal's, and one restored later should come back filmed the way it was.
%
% Parameters:
%   subjectIds - SubjectID or Name; char for one, cellstr/string for many.
%                Ignored under AllMembers.
%   projectId  - ProjectID or Name. Required: the setting lives on the membership.
%   value      - true/"on" to record, false/"off" not to, NaN/"rig" to follow
%                the rig's Record Video toggle. See recordVideoSetting.
%
% Options:
%   AllMembers - apply to every member of the project (default false).
%
% Returns:
%   report - struct with fields:
%     ok        - true when the call was carried out (even if nothing changed)
%     updated   - (1,:) struct: SubjectID, Name -- memberships whose value changed
%     unchanged - number of memberships already at the value
%     skipped   - (1,:) struct: Name, reason
%     message   - one-line summary suitable for a status bar
%
% Throws:
%   epsych:SubjectRoster:NoSuchProject
%   epsych:SubjectRoster:InvalidRecordVideo
%
% Example:
%   R.setRecordVideo({'M001','M002'}, 'Tone Detection', true);
%   R.setRecordVideo([], 'Tone Detection', "rig", AllMembers = true);
%
% See also: epsych.SubjectRoster.recordVideoSetting, epsych.SubjectRoster.assignToSession,
%   gui.SubjectManager
arguments
    self
    subjectIds
    projectId (1,:) char
    value
    options.AllMembers (1,1) logical = false
end

[v, ok] = epsych.SubjectRoster.recordVideoSetting(value);
if ~ok
    error('epsych:SubjectRoster:InvalidRecordVideo', ...
        'RecordVideo must be true, false, or NaN (follow the rig toggle).');
end

p = self.findProject(projectId);
if isempty(p)
    error('epsych:SubjectRoster:NoSuchProject', 'No project matches "%s".', projectId);
end

if options.AllMembers
    subjectIds = {};
else
    subjectIds = cellstr(string(subjectIds));
end

report = struct('ok', false, ...
    'updated', struct('SubjectID', {}, 'Name', {}), ...
    'unchanged', 0, ...
    'skipped', struct('Name', {}, 'reason', {}), ...
    'message', '');

if ~options.AllMembers && isempty(subjectIds)
    report.message = 'No subjects were selected.';
    return
end

pid = p.ProjectID;

% mutate_ declines a read-only or unwritable roster by returning false rather
% than throwing; the report must not then claim a change it did not make.
if ~self.mutate_(@applySet)
    report.updated = report.updated([]);
    report.unchanged = 0;
    report.message = 'The roster could not be written, so webcam recording was not changed.';
    return
end

report.ok = true;
report.message = sprintf('Webcam recording set to "%s" for %d subject(s) in "%s".', ...
    localDescribe(v), numel(report.updated), p.Name);
if report.unchanged > 0
    report.message = sprintf('%s %d already were.', report.message, report.unchanged);
end
if ~isempty(report.skipped)
    report.message = sprintf('%s %d skipped.', report.message, numel(report.skipped));
end
vprintf(1, report.message);

    function applySet(r)
        if isempty(r.findProject(pid))
            error('epsych:SubjectRoster:NoSuchProject', ...
                'Project "%s" was removed by another session.', pid);
        end

        if options.AllMembers
            if isempty(r.Memberships)
                ks = [];
            else
                ks = find(strcmp({r.Memberships.ProjectID}, pid));
            end
        else
            ks = zeros(1, 0);
            for i = 1:numel(subjectIds)
                s = r.findSubject(subjectIds{i});
                if isempty(s)
                    report.skipped(end+1) = struct('Name', subjectIds{i}, ...
                        'reason', 'not in the roster');
                    continue
                end
                [~, k] = r.findMembership(s.SubjectID, pid);
                if isempty(k)
                    report.skipped(end+1) = struct('Name', s.Name, ...
                        'reason', 'not a member of this project');
                    continue
                end
                ks(end+1) = k;
            end
        end

        now_ = datetime('now');
        for k = ks
            cur = r.Memberships(k);
            % isequaln so NaN == NaN: re-applying "follow the rig" to a
            % membership already following it is not an edit, and must not
            % move its Modified stamp.
            if isequaln(epsych.SubjectRoster.recordVideoSetting(cur.RecordVideo), v)
                report.unchanged = report.unchanged + 1;
                continue
            end
            cur.RecordVideo = v;
            cur.Modified = now_;
            r.Memberships(k) = cur;

            s = r.findSubject(cur.SubjectID);
            name = cur.SubjectID;
            if ~isempty(s), name = s.Name; end
            report.updated(end+1) = struct('SubjectID', cur.SubjectID, 'Name', name);
        end
    end

end

% -----------------------------------------------------------------------
function s = localDescribe(v)
% The value as the manager's Video column words it.
if isnan(v)
    s = 'rig toggle';
elseif v == 1
    s = 'record';
else
    s = 'off';
end
end
