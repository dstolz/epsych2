function id = addSubject(self, S)
% id = addSubject(self, S)
% Create a subject record and persist it.
%
% Parameters:
%   S - struct or epsych.Subject with at least a Name. A BoxID is accepted and
%       ignored: a box belongs to a session, not to an animal.
%
% Returns:
%   id - the minted SubjectID.
%
% Throws:
%   epsych:SubjectRoster:InvalidName    - name is empty or not filename-safe
%   epsych:SubjectRoster:DuplicateName  - a subject with that name exists
%
% See also: epsych.SubjectRoster.updateSubject, epsych.SubjectRoster.fromSubject
arguments
    self
    S
end

if isa(S, 'epsych.Subject')
    S = S.toStruct();
end

rec = epsych.SubjectRoster.blankSubject_();
for f = ["Name" "Sex" "Species" "Weight" "Notes"]
    if isfield(S, f)
        rec.(f) = S.(f);
    end
end
rec.Name = char(string(rec.Name));

[ok, why] = epsych.SubjectRoster.isNameSafe(rec.Name);
if ~ok
    error('epsych:SubjectRoster:InvalidName', '%s', why);
end

if ~isempty(self.findSubject(rec.Name))
    error('epsych:SubjectRoster:DuplicateName', ...
        'A subject named "%s" is already in the roster.', rec.Name);
end

rec.SubjectID = epsych.SubjectRoster.newId('S');
rec.Created   = datetime('now');
rec.Modified  = rec.Created;

self.mutate_(@applyAdd);

id = rec.SubjectID;
vprintf(1, 'Added subject "%s" to the roster.', rec.Name);

    % Nested rather than local so it keeps the method's access to the
    % private-set properties, and so the duplicate re-check below sees the
    % roster as mutate_ just re-read it.
    function applyAdd(r)
        if ~isempty(r.findSubject(rec.Name))
            error('epsych:SubjectRoster:DuplicateName', ...
                'A subject named "%s" was just added by another session.', rec.Name);
        end
        r.Subjects = [r.Subjects, rec];
    end

end
