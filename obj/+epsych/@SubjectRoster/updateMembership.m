function updateMembership(self, subjectId, projectId, M)
% updateMembership(self, subjectId, projectId, M)
% Edit the session settings one membership carries.
%
% The membership is where a session's configuration lives: the project's
% template is stamped onto it when the subject joins, and this is how one
% subject deliberately diverges from it -- a longer timer period for a slow
% animal, a different saving function for a pilot. Only the fields present in
% M are touched, and only the SESSION_FIELDS are writable here: SubjectID,
% ProjectID, and the protocol memory are engine-owned and ignored if supplied.
%
% Empty ('' -- NaN for TimerPeriod) means "inherit the built-in default", the
% same reading everywhere in the roster.
%
% Parameters:
%   subjectId - SubjectID or Name.
%   projectId - ProjectID or Name.
%   M         - struct carrying the fields to change.
%
% Throws:
%   epsych:SubjectRoster:NoSuchSubject
%   epsych:SubjectRoster:NoSuchProject
%   epsych:SubjectRoster:NoSuchMembership
%   epsych:SubjectRoster:InvalidTimerPeriod
%
% See also: epsych.SubjectRoster.reapplyTemplate, epsych.SubjectRoster.updateProject,
%   epsych.SubjectRoster.assign
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
    M (1,1) struct
end

s = self.findSubject(subjectId);
if isempty(s)
    error('epsych:SubjectRoster:NoSuchSubject', 'No subject matches "%s".', subjectId);
end

p = self.findProject(projectId);
if isempty(p)
    error('epsych:SubjectRoster:NoSuchProject', 'No project matches "%s".', projectId);
end

% Validated before the file is touched, mirroring updateProject.
newPeriod = [];
if isfield(M, 'TimerPeriod')
    newPeriod = localToPeriod(M.TimerPeriod);
    if ~isnan(newPeriod) && (newPeriod < 0.001 || newPeriod > 1)
        error('epsych:SubjectRoster:InvalidTimerPeriod', ...
            'TimerPeriod must be between 0.001 and 1 s, or NaN to inherit the built-in period.');
    end
end

sid = s.SubjectID;
pid = p.ProjectID;

self.mutate_(@applyUpdate);

vprintf(2, 'Updated session settings for "%s" in project "%s".', s.Name, p.Name);

    function applyUpdate(r)
        [cur, k] = r.findMembership(sid, pid);
        if isempty(k)
            error('epsych:SubjectRoster:NoSuchMembership', ...
                'Subject "%s" is not a member of project "%s".', sid, pid);
        end

        for f = epsych.SubjectRoster.SESSION_FIELDS
            if strcmp(f{1}, 'TimerPeriod') || ~isfield(M, f{1})
                continue
            end
            cur.(f{1}) = char(string(M.(f{1})));
        end

        if isfield(M, 'TimerPeriod')
            cur.TimerPeriod = newPeriod;
        end

        cur.Modified = datetime('now');

        r.Memberships(k) = cur;
    end

end

% -----------------------------------------------------------------------
function p = localToPeriod(v)
% Accept what an edit field, a script, or a hand-edited struct is likely to
% hold. An empty value means "inherit", the same as NaN, so a caller clearing
% the field does not have to know which empty the record uses.
if ischar(v) || isstring(v)
    v = str2double(v);
end
if isempty(v)
    p = NaN;
else
    p = double(v(1));
end
end
