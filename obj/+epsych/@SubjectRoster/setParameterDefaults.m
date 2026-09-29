function setParameterDefaults(self, subjectId, projectId, D)
% setParameterDefaults(self, subjectId, projectId, D)
% Replace the parameter defaults one membership carries.
%
% The whole set is replaced rather than merged, because that is what the
% editor holds: every row the operator left filled in. An empty D clears them.
% Records are checked for shape here (epsych.ParameterDefaults.validate) --
% a name, something to apply, sane bounds, no parameter twice -- but not
% against a protocol: which parameters exist is a question for the moment the
% subject runs, and a default for a parameter the current protocol lacks is
% kept (and skipped at Run) so a protocol reverted to an older version finds it
% again.
%
% Parameters:
%   subjectId - SubjectID or Name.
%   projectId - ProjectID or Name.
%   D         - record array (epsych.ParameterDefaults.blank shape), or empty.
%
% Throws:
%   epsych:SubjectRoster:NoSuchSubject
%   epsych:SubjectRoster:NoSuchProject
%   epsych:SubjectRoster:NoSuchMembership
%   epsych:SubjectRoster:InvalidParameterDefaults
%
% See also: epsych.SubjectRoster.parameterDefaults, epsych.ParameterDefaults,
%   gui.ParameterDefaultsEditor
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
    D = epsych.ParameterDefaults.empty()
end

s = self.findSubject(subjectId);
if isempty(s)
    error('epsych:SubjectRoster:NoSuchSubject', 'No subject matches "%s".', subjectId);
end

p = self.findProject(projectId);
if isempty(p)
    error('epsych:SubjectRoster:NoSuchProject', 'No project matches "%s".', projectId);
end

if isempty(D)
    D = epsych.ParameterDefaults.empty();
end
if ~isstruct(D)
    error('epsych:SubjectRoster:InvalidParameterDefaults', ...
        'Parameter defaults must be a struct array.');
end

% Validated before the file is touched, mirroring updateMembership. normalize
% first, so a caller's missing or extra fields are shaped the way the file
% stores them and validation sees what will be written.
D = epsych.ParameterDefaults.normalize(D);
[ok, msg] = epsych.ParameterDefaults.validate(D);
if ~ok
    error('epsych:SubjectRoster:InvalidParameterDefaults', '%s', msg);
end

sid = s.SubjectID;
pid = p.ProjectID;

self.mutate_(@applyUpdate);

if isempty(D)
    vprintf(2, 'Cleared the parameter defaults of "%s" in project "%s".', s.Name, p.Name);
else
    vprintf(2, 'Set %d parameter default(s) for "%s" in project "%s": %s', numel(D), ...
        s.Name, p.Name, epsych.ParameterDefaults.summary(D));
end

    function applyUpdate(r)
        [cur, k] = r.findMembership(sid, pid);
        if isempty(k)
            error('epsych:SubjectRoster:NoSuchMembership', ...
                'Subject "%s" is not a member of project "%s".', sid, pid);
        end
        cur.ParameterDefaults = D;
        cur.Modified = datetime('now');
        r.Memberships(k) = cur;
    end

end
