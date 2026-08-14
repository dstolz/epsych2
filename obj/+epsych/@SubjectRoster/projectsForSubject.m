function recs = projectsForSubject(self, subjectId)
% recs = projectsForSubject(self, subjectId)
% Project records this subject belongs to, retired memberships included.
%
% Retired ones are kept because the callers that need this — the delete
% confirmation and the data-path search in renameBlocker_ — must see every
% project the subject touches, not just the ones it is currently running in.
%
% Parameters:
%   subjectId - SubjectID or subject Name.
%
% Returns:
%   recs - (1,:) project records, ordered by Name.
%
% See also: epsych.SubjectRoster.subjectsInProject
arguments
    self
    subjectId (1,:) char
end

recs = epsych.SubjectRoster.emptyProject();

s = self.findSubject(subjectId);
if isempty(s) || isempty(self.Memberships), return, end

ids = {self.Memberships(strcmp({self.Memberships.SubjectID}, s.SubjectID)).ProjectID};
idx = zeros(1, numel(ids));
for i = 1:numel(ids)
    [~, k] = self.findProject(ids{i});
    if ~isempty(k)
        idx(i) = k;
    end
end

idx = idx(idx > 0);
recs = self.Projects(idx);

if ~isempty(recs)
    [~, order] = sort(lower(string({recs.Name})));
    recs = recs(order);
end
