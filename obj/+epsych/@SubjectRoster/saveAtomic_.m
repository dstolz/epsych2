function tf = saveAtomic_(self)
% tf = saveAtomic_(self)
% Write the roster so a reader never observes a half-written file.
%
% Saves to a temp file in the SAME directory — same volume is what makes the
% movefile a rename rather than a copy — then moves it over the target. A
% crash or a full disk leaves the previous good file untouched. Same idiom as
% obj/+util/@VideoConverter/VideoConverter.m:508.
%
% Returns:
%   tf - true on success. On failure IsWritable latches false and the existing
%        file is left exactly as it was.
%
% See also: epsych.SubjectRoster.save, epsych.SubjectRoster.mutate_
arguments
    self
end

tf = false;

% movefile onto an existing directory succeeds by moving the file inside it, so
% a folder target would look like a successful write that saved nothing.
if isfolder(self.FilePath)
    self.IsWritable = false;
    vprintf(0, 1, 'Subject roster path is a folder, not a file: %s', self.FilePath);
    return
end

formatVersion = epsych.SubjectRoster.FORMAT_VERSION;
subjects      = self.Subjects;
projects      = self.Projects;
memberships   = self.Memberships;

meta = localMeta();

folder = fileparts(self.FilePath);
if ~isempty(folder) && ~isfolder(folder)
    try
        mkdir(folder);
    catch ME
        self.IsWritable = false;
        vprintf(0, 1, ME);
        return
    end
end

tmp = sprintf('%s.%d-%s.tmp', self.FilePath, feature('getpid'), ...
    lower(dec2hex(randi([0, 16^4 - 1]), 4)));

try
    save(tmp, 'formatVersion', 'subjects', 'projects', 'memberships', 'meta', '-mat');
    movefile(tmp, self.FilePath, 'f');
catch ME
    % Never leave a stray temp file behind, and never touch the good file.
    if isfile(tmp)
        try
            delete(tmp);
        catch
        end
    end
    self.IsWritable = false;
    vprintf(0, 1, ME);
    vprintf(0, 1, 'Subject roster could not be written: %s', self.FilePath);
    return
end

self.FileStamp_ = epsych.SubjectRoster.stamp_(self.FilePath);
self.IsWritable = true;
tf = true;

vprintf(3, 'Subject roster written: %s', self.FilePath);

end

% -----------------------------------------------------------------------
function meta = localMeta()
% Provenance for the file. Purely informational, so a failure to collect it
% must never be the reason a roster cannot be saved.
meta = struct();
try
    E = EPsychInfo;
    meta = E.meta;
catch ME
    vprintf(3, ME);
end
meta.writtenBy   = localUser();
meta.writtenOn   = char(datetime('now', Format='yyyy-MM-dd HH:mm:ss'));
meta.writtenHost = localHost();
end

% -----------------------------------------------------------------------
function u = localUser()
u = getenv('USERNAME');
if isempty(u), u = getenv('USER'); end
if isempty(u), u = 'unknown'; end
end

% -----------------------------------------------------------------------
function h = localHost()
h = getenv('COMPUTERNAME');
if isempty(h), h = getenv('HOSTNAME'); end
if isempty(h), h = 'unknown'; end
end
