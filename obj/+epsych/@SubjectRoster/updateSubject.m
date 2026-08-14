function updateSubject(self, id, S)
% updateSubject(self, id, S)
% Edit a subject record in place.
%
% Only the fields present in S are touched, so a caller can change a weight
% without restating the species. SubjectID, Created, and NameHistory are
% engine-owned and ignored if supplied.
%
% Renaming is refused once experiment data exists on disk under the old name —
% see renameBlocker_ for why nothing on disk is reconciled instead.
%
% Parameters:
%   id - SubjectID or current Name.
%   S  - struct or epsych.Subject carrying the fields to change.
%
% Throws:
%   epsych:SubjectRoster:NoSuchSubject
%   epsych:SubjectRoster:InvalidName
%   epsych:SubjectRoster:DuplicateName
%   epsych:SubjectRoster:RenameBlocked
%
% See also: epsych.SubjectRoster.addSubject, epsych.SubjectRoster.renameBlocker_
arguments
    self
    id (1,:) char
    S
end

if isa(S, 'epsych.Subject')
    S = S.toStruct();
end

[rec, idx] = self.findSubject(id);
if isempty(idx)
    error('epsych:SubjectRoster:NoSuchSubject', ...
        'No subject matches "%s".', id);
end

oldName = rec.Name;
newName = oldName;
if isfield(S, 'Name')
    newName = char(string(S.Name));
end

isRename = ~strcmp(newName, oldName);
if isRename
    [ok, why] = epsych.SubjectRoster.isNameSafe(newName);
    if ~ok
        error('epsych:SubjectRoster:InvalidName', '%s', why);
    end

    other = self.findSubject(newName);
    if ~isempty(other) && ~strcmp(other.SubjectID, rec.SubjectID)
        error('epsych:SubjectRoster:DuplicateName', ...
            'A subject named "%s" is already in the roster.', newName);
    end

    blocker = self.renameBlocker_(oldName);
    if ~isempty(blocker)
        error('epsych:SubjectRoster:RenameBlocked', ...
            ['"%s" cannot be renamed: experiment data is already saved under ' ...
             'that name in %s. Renaming here would leave that data orphaned, ' ...
             'and this tool does not move experiment data.'], oldName, blocker);
    end
end

subjectId = rec.SubjectID;
self.mutate_(@applyUpdate);

if isRename
    vprintf(1, 'Renamed subject "%s" to "%s".', oldName, newName);
else
    vprintf(2, 'Updated subject "%s".', newName);
end

    function applyUpdate(r)
        [cur, k] = r.findSubject(subjectId);
        if isempty(k)
            error('epsych:SubjectRoster:NoSuchSubject', ...
                'Subject "%s" was removed by another session.', subjectId);
        end

        % Another rig may have edited this record between our read and this
        % write. Last writer wins -- a rig must never be stuck -- but say so,
        % because this is the one case where a change really is lost.
        if ~isnat(cur.Modified) && ~isnat(rec.Modified) && cur.Modified > rec.Modified
            vprintf(0, 1, ['Subject "%s" was changed by another session at %s; ' ...
                'overwriting with this session''s edit from %s.'], cur.Name, ...
                char(cur.Modified), char(rec.Modified));
        end

        for f = ["Name" "Sex" "Species" "Weight" "Notes" "Retired"]
            if isfield(S, f)
                cur.(f) = S.(f);
            end
        end
        cur.Name = char(string(cur.Name));

        if isRename
            cur.NameHistory = [cur.NameHistory, string(oldName)];
        end
        cur.Modified = datetime('now');

        r.Subjects(k) = cur;
    end

end
