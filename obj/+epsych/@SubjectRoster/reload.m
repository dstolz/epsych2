function reload(self)
% reload(self)
% Re-read the roster from disk, replacing everything held in memory.
%
% Never throws. A roster that cannot be read must not stop a session from
% running, so every failure mode degrades to a readable state and a message in
% LoadError:
%   * missing file     -> empty roster, writable (it appears on first mutation)
%   * unparseable file -> empty roster, NOT writable, so a corrupt file is
%                         never overwritten with the empty state we invented
%   * newer file       -> loaded, but IsReadOnly, so this build cannot drop
%                         fields a newer one wrote
%
% See also: epsych.SubjectRoster.save, epsych.SubjectRoster.reloadIfStale_
arguments
    self
end

self.Subjects    = epsych.SubjectRoster.emptySubject();
self.Projects    = epsych.SubjectRoster.emptyProject();
self.Memberships = epsych.SubjectRoster.emptyMembership();
self.LoadError   = '';
self.IsReadOnly  = false;

% A path that names an existing folder has to be caught here: movefile onto a
% directory moves the temp file INTO it and reports success, so the write would
% appear to work while silently going nowhere.
if isfolder(self.FilePath)
    self.LoadError  = sprintf('The roster path is a folder, not a file: %s', self.FilePath);
    self.IsWritable = false;
    self.FileStamp_ = [];
    vprintf(0, 1, 'Subject roster path is a folder, not a file: %s', self.FilePath);
    return
end

if ~isfile(self.FilePath)
    self.IsWritable = true;
    self.FileStamp_ = [];
    self.LastRead   = datetime('now');
    vprintf(2, 'Subject roster does not exist yet: %s', self.FilePath);
    return
end

try
    S = load(self.FilePath, '-mat');
catch ME
    self.LoadError  = ME.message;
    self.IsWritable = false;
    self.FileStamp_ = [];
    vprintf(0, 1, ME);
    vprintf(0, 1, 'Subject roster could not be read; it will not be overwritten: %s', ...
        self.FilePath);
    return
end

if ~isfield(S, 'formatVersion') || ~isfield(S, 'subjects')
    self.LoadError  = 'The file is not a subject roster.';
    self.IsWritable = false;
    self.FileStamp_ = [];
    vprintf(0, 1, 'Not a subject roster file; it will not be overwritten: %s', ...
        self.FilePath);
    return
end

if S.formatVersion > epsych.SubjectRoster.FORMAT_VERSION
    self.IsReadOnly = true;
    self.LoadError  = sprintf(['This roster was written by a newer version of EPsych ' ...
        '(format %g; this build understands %g). It is open read-only so fields ' ...
        'this build does not know about are not discarded.'], ...
        S.formatVersion, epsych.SubjectRoster.FORMAT_VERSION);
    vprintf(0, 1, 'Subject roster format %g is newer than %g; opening read-only.', ...
        S.formatVersion, epsych.SubjectRoster.FORMAT_VERSION);
end

self.Subjects    = epsych.SubjectRoster.normalize_(S.subjects, ...
    epsych.SubjectRoster.blankSubject_());
self.Projects    = epsych.SubjectRoster.normalize_(localField(S, 'projects'), ...
    epsych.SubjectRoster.blankProject_());
self.Memberships = epsych.SubjectRoster.normalize_(localField(S, 'memberships'), ...
    epsych.SubjectRoster.blankMembership_());

% normalize_ shapes the outer record only, so a project's nested Links array
% gets its own pass. Not validated here: a link one operator typo'd must not
% make the shared roster unreadable for the lab. openLink is the backstop.
for i = 1:numel(self.Projects)
    self.Projects(i).Links = epsych.SubjectRoster.normalizeLinks_(self.Projects(i).Links);
end

self.IsWritable = ~self.IsReadOnly;
self.FileStamp_ = epsych.SubjectRoster.stamp_(self.FilePath);
self.LastRead   = datetime('now');

vprintf(3, 'Subject roster read: %d subject(s), %d project(s), %d membership(s) from %s', ...
    numel(self.Subjects), numel(self.Projects), numel(self.Memberships), self.FilePath);

end

% -----------------------------------------------------------------------
function v = localField(S, name)
% Tolerate a file missing an optional array entirely.
v = [];
if isfield(S, name)
    v = S.(name);
end
end
