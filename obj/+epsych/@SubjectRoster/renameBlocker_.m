function blocker = renameBlocker_(self, oldName)
% blocker = renameBlocker_(self, oldName)
% First data folder found for oldName, or '' when renaming is safe.
%
% A subject's Name is a filesystem path component: ExptDispatch saves into
% <DataPath>/<Name>/, and the crash journal embeds it in filenames. Nothing
% downstream consults NameHistory, so once a folder exists, renaming the
% roster record would silently orphan that data. Renaming is therefore refused
% rather than reconciled — moving experiment data is out of this class's remit.
%
% Both roots are checked: the session-wide data path and every DefaultDataPath
% of a project the subject belongs to.
%
% Parameters:
%   oldName - the name currently on the record.
%
% Returns:
%   blocker - full path to the folder that blocks the rename, or ''.
%
% See also: epsych.SubjectRoster.updateSubject
arguments
    self
    oldName (1,:) char
end

blocker = '';
if isempty(oldName), return, end

roots = {};
if ispref('RunExpt', 'DataPath')
    roots{end+1} = char(getpref('RunExpt', 'DataPath'));
end

s = self.findSubject(oldName);
if ~isempty(s)
    projects = self.projectsForSubject(s.SubjectID);
    if ~isempty(projects)
        roots = [roots, {projects.DefaultDataPath}];
    end
end

for i = 1:numel(roots)
    if isempty(strtrim(roots{i})), continue, end
    candidate = fullfile(roots{i}, oldName);
    if isfolder(candidate)
        blocker = candidate;
        return
    end
end
