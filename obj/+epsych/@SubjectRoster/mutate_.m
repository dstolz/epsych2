function tf = mutate_(self, fcn)
% tf = mutate_(self, fcn)
% Apply a change to the roster and persist it, safely against other rigs.
%
% Every CRUD method's body is one call to this, so the reload-apply-write
% sequence exists in exactly one place:
%   1. take the advisory lock
%   2. re-read the file if another process changed it
%   3. run fcn(self), which mutates the in-memory model
%   4. write the whole model back atomically
%
% Parameters:
%   fcn - function handle taking the roster; may throw to abort the mutation.
%
% Returns:
%   tf - true when the change was applied AND written.
%
% Throws:
%   epsych:SubjectRoster:NoFile - no roster file is configured
%
% See also: epsych.SubjectRoster.reloadIfStale_, epsych.SubjectRoster.saveAtomic_
arguments
    self
    fcn (1,1) function_handle
end

tf = false;

% Throws rather than returning false, unlike the states below: the CRUD methods
% mint an ID and report success without consulting this return value, so a
% roster with nowhere to write has to stop the mutation dead. The operator-
% facing surfaces ask for a file before it gets this far; this is the backstop
% for a script, and its message is what their catch block shows.
if ~self.IsBound
    error('epsych:SubjectRoster:NoFile', ...
        ['No subject roster file has been chosen on this workstation. ' ...
         'Open Subjects & Projects and use File > Roster File..., or call ' ...
         'epsych.SubjectRoster.setConfiguredFile.']);
end

if self.IsReadOnly
    vprintf(0, 1, 'The subject roster is open read-only and was not changed: %s', ...
        self.LoadError);
    return
end

self.acquireLock_();
lockCleanup = onCleanup(@() self.releaseLock_());

self.reloadIfStale_();

% A file that could not be parsed leaves IsWritable false. Writing now would
% replace a corrupt-but-recoverable file with whatever little we managed to
% read, so refuse until an operator sorts it out.
if ~self.IsWritable
    vprintf(0, 1, 'The subject roster is not writable and was not changed: %s', ...
        self.FilePath);
    return
end

try
    fcn(self);
catch ME
    % The in-memory model may be half-changed, so re-read rather than leaving
    % it diverged from the file it was supposed to match.
    vprintf(0, 1, ME);
    self.reload();
    rethrow(ME)
end

tf = self.saveAtomic_();
