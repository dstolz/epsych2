function tf = ensureRoster_(self, action)
% tf = ensureRoster_(self, action)
% Make sure a roster file has been chosen, demanding one if it has not.
%
% EPsych keeps no default roster location. Where a lab's animal records live --
% one shared file on a network drive, or a private file per workstation -- is a
% decision with no safe guess, and the old guess put the only copy under
% prefdir, where a MATLAB upgrade lost it. So the first action that would write
% to the roster asks, and keeps asking: the only ways out are naming a file or
% closing the window. "Carry on without one" is not offered, because it would
% mean silently discarding the project the operator is in the middle of
% creating.
%
% Two states fail the check: no file chosen at all, and a file whose folder has
% gone (a share that moved, a drive not mounted, a temp path that was cleaned
% up). Both are demanded here rather than at window-open, because both are
% harmless until something needs saving.
%
% Every read-only path is left alone -- browsing shows an empty window and an
% explanation, no dialog -- so this is called only from the actions that create
% something.
%
% Parameters:
%   action - what the operator was trying to do, named in the prompt, e.g.
%            'creating a project'.
%
% Returns:
%   tf - true when a roster file is configured and the caller may proceed.
%        False means the operator closed the manager rather than choosing.
%
% See also: gui.SubjectManager.chooseRosterFile_, epsych.SubjectRoster.configuredFile
arguments
    self
    action (1,:) char = 'saving anything'
end

bound = ~isempty(self.Roster) && isvalid(self.Roster) && self.Roster.IsBound;

% A pointer at a folder that no longer exists has to be caught here too, and
% for a sharper reason than tidiness: saveAtomic_ creates a missing folder, so
% a rig whose share moved -- or whose path came from somewhere temporary --
% would silently RE-CREATE that folder and save the operator's new project
% into it, where nothing will ever look for it again.
stale = bound && self.rosterFolderMissing_();

tf = bound && ~stale;
if tf, return, end

if stale
    msg = sprintf(['This rig is pointed at a roster whose folder no longer exists:' ...
        newline '%s' newline newline ...
        'Choose the right file before %s -- otherwise that folder would be ' ...
        'created again and the record saved somewhere nothing will look for it.'], ...
        self.Roster.FilePath, action);
else
    msg = sprintf(['EPsych has no default place to keep subjects and projects, so ' ...
        'choose where this roster file lives before %s.' newline newline ...
        'Put it on a shared drive and point every rig at the same file to share ' ...
        'one roster across the lab, or keep it beside your own data to make it ' ...
        'private to this workstation. The file is created when you save the ' ...
        'first record.'], action);
end

while true
    answer = uiconfirm(self.H.figure, msg, 'Choose a Subject Roster', ...
        'Options', {'Choose File...', 'Close Manager'}, ...
        'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'question');

    if strcmp(answer, 'Close Manager')
        delete(self);
        return
    end

    if self.chooseRosterFile_()
        tf = true;
        return
    end

    % Cancelled the file dialog. Round again rather than falling through: the
    % caller is about to write, and there is still nowhere to put it.
    msg = sprintf(['A roster file is still needed before %s.' newline newline ...
        'Choose or name a .esub file, or close the Subjects & Projects window.'], ...
        action);
end
