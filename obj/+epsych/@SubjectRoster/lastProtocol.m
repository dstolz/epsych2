function pfn = lastProtocol(self, subjectId, projectId)
% pfn = lastProtocol(self, subjectId, projectId)
% The protocol to propose for this subject, or '' when there is nothing to go on.
%
% Resolution order, most specific first:
%   1. what this subject last ran in this project
%   2. the project's default protocol
%   3. '' — the caller browses, seeded from ep_RunExpt_Setup/PDir
%
% Pass an empty projectId to consider only rule 1, across every project the
% subject belongs to, most recently modified first. That is what the
% All Subjects view uses, where there is no project context to fall back on.
%
% Parameters:
%   subjectId - SubjectID or subject Name.
%   projectId - ProjectID or project Name; '' to search across projects.
%
% Returns:
%   pfn - full path to a .eprot, or ''.
%
% See also: epsych.SubjectRoster.rememberProtocol, epsych.SubjectRoster.assignToSession
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char = ''
end

pfn = '';

s = self.findSubject(subjectId);
if isempty(s), return, end

if ~isempty(projectId)
    rec = self.findMembership(s.SubjectID, projectId);
    if ~isempty(rec) && ~isempty(rec.LastProtocol)
        pfn = rec.LastProtocol;
        return
    end

    p = self.findProject(projectId);
    if ~isempty(p) && ~isempty(p.DefaultProtocol)
        pfn = p.DefaultProtocol;
    end
    return
end

% No project context: fall back to whatever this subject most recently ran
% anywhere, then to the default of any project it belongs to.
if isempty(self.Memberships), return, end

mine = self.Memberships(strcmp({self.Memberships.SubjectID}, s.SubjectID));
if isempty(mine), return, end

[~, order] = sort([mine.Modified], 'descend', 'MissingPlacement', 'last');
mine = mine(order);

for i = 1:numel(mine)
    if ~isempty(mine(i).LastProtocol)
        pfn = mine(i).LastProtocol;
        return
    end
end

for i = 1:numel(mine)
    p = self.findProject(mine(i).ProjectID);
    if ~isempty(p) && ~isempty(p.DefaultProtocol)
        pfn = p.DefaultProtocol;
        return
    end
end
