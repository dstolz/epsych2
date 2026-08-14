function rememberProtocol(self, subjectId, projectId, protocolFile, boxID)
% rememberProtocol(self, subjectId, projectId, protocolFile)
% rememberProtocol(self, subjectId, projectId, protocolFile, boxID)
% Record what a subject just ran, so next session proposes the same thing.
%
% Called by assignToSession after a successful commit. Silently does nothing
% when the subject is not in the project — assigning to a session does not
% require membership, and a stray call must not create one.
%
% Parameters:
%   subjectId    - SubjectID or subject Name.
%   projectId    - ProjectID or project Name.
%   protocolFile - full path to the .eprot that was used.
%   boxID        - (optional) box it ran in; NaN leaves the stored value alone.
%
% See also: epsych.SubjectRoster.lastProtocol, epsych.SubjectRoster.assignToSession
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
    protocolFile (1,:) char
    boxID (1,1) double = NaN
end

[rec, idx] = self.findMembership(subjectId, projectId);
if isempty(idx)
    vprintf(3, 'rememberProtocol: "%s" is not in "%s"; nothing recorded.', ...
        subjectId, projectId);
    return
end

sid = rec.SubjectID;
pid = rec.ProjectID;

self.mutate_(@applyRemember);

vprintf(3, 'Remembered protocol for "%s" in "%s": %s', subjectId, projectId, protocolFile);

    function applyRemember(r)
        [~, k] = r.findMembership(sid, pid);
        if isempty(k), return, end

        r.Memberships(k).LastProtocol = protocolFile;
        if ~isnan(boxID)
            r.Memberships(k).LastBoxID = boxID;
        end
        r.Memberships(k).Modified = datetime('now');
    end

end
