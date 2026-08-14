function recs = subjectsInProject(self, projectId, options)
% recs = subjectsInProject(self, projectId)
% recs = subjectsInProject(self, projectId, IncludeRetired=true)
% Subject records enrolled in one project.
%
% Retired members are excluded by default: the common case is picking animals
% to run today, and a finished animal should not be in that list.
%
% Parameters:
%   projectId - ProjectID or project Name.
%
% Options:
%   IncludeRetired - include memberships whose Active flag is false (default false)
%
% Returns:
%   recs - (1,:) subject records, ordered by Name.
%
% See also: epsych.SubjectRoster.projectsForSubject, epsych.SubjectRoster.setActive
arguments
    self
    projectId (1,:) char
    options.IncludeRetired (1,1) logical = false
end

recs = epsych.SubjectRoster.emptySubject();

p = self.findProject(projectId);
if isempty(p) || isempty(self.Memberships), return, end

keep = strcmp({self.Memberships.ProjectID}, p.ProjectID);
if ~options.IncludeRetired
    keep = keep & [self.Memberships.Active];
end

ids = {self.Memberships(keep).SubjectID};
idx = zeros(1, numel(ids));
for i = 1:numel(ids)
    [~, k] = self.findSubject(ids{i});
    if ~isempty(k)
        idx(i) = k;
    end
end

% A membership can outlive its subject only if a file was hand-edited, but
% indexing with a 0 would throw, so drop the misses rather than trusting it.
idx = idx(idx > 0);
recs = self.Subjects(idx);

if ~isempty(recs)
    [~, order] = sort(lower(string({recs.Name})));
    recs = recs(order);
end
