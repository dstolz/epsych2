function revealSubject(self, name)
% revealSubject(self, name)
% Select a subject in the table, switching project and clearing the filter.
%
% Called by the session window's "Show in Subject Manager" action, so the two
% windows are navigable in both directions. A subject that is not in the roster
% is not an error: the window lands on All Projects and the status line says so,
% which is the answer the operator was looking for anyway.
%
% Parameters:
%   name - subject Name or SubjectID.
%
% See also: epsych.RunExpt.ShowSubjectInManager
arguments
    self
    name (1,:) char
end

if isempty(self.Roster) || ~isvalid(self.Roster), return, end

rec = self.Roster.findSubject(name);
if isempty(rec)
    self.PendingProject_ = '';
    self.setFilterText_('');
    self.refresh();
    self.setStatus_(sprintf('"%s" is not in the roster. Use New Subject... to add it.', name));
    return
end

% A filter left over from earlier could hide the very row being revealed,
% including one the operator has typed but not yet committed.
self.setFilterText_('');

% Prefer a project the subject is actually in, so the row is visible without
% falling back to All Projects.
projects = self.Roster.projectsForSubject(rec.SubjectID);
if isempty(projects)
    self.PendingProject_ = '';
else
    self.PendingProject_ = projects(1).ProjectID;
end

% Retired subjects would otherwise be filtered out of their own project.
self.H.showRetired.Value = true;

self.refresh();

row = find(strcmp({self.Rows_.SubjectID}, rec.SubjectID), 1);
if isempty(row)
    self.setStatus_(sprintf('"%s" is in the roster but not visible here.', rec.Name));
    return
end

self.H.table.Selection = row;
self.H.table.scroll('row', row);
self.updateEnableStates_();

if isempty(projects)
    self.setStatus_(sprintf('"%s" is in the roster but not in any project.', rec.Name));
else
    self.setStatus_(sprintf('%s \x2014 in %s.', rec.Name, strjoin({projects.Name}, ', ')));
end
