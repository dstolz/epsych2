function [filePath, mode] = chooseRosterFile(parent, options)
% [filePath, mode] = gui.chooseRosterFile(parent)
% [filePath, mode] = gui.chooseRosterFile(parent, Mode="open"|"create", ...)
% Ask the operator for a subject roster file, OPENING an existing one or
% CREATING a new one -- never both in one dialog.
%
% One Save dialog used to serve both: picking an existing roster then drew the
% operating system's "already exists -- do you want to replace it?", which
% reads as a threat to the lab's animal records when the operator only meant
% to open them (nothing was ever replaced). So the two are separate: "open"
% is an Open dialog, which lists and accepts only existing files, and
% "create" is a Save dialog seeded with a name that does not exist yet. A
% name typed in "create" that turns out to exist is NOT replaced -- the
% operator is told so and offered to open it instead or pick another name.
%
% Nothing is written here; the caller passes the answer to
% epsych.SubjectRoster.setConfiguredFile. A new roster's file is created on
% the first record saved.
%
% Parameters:
%   parent      - uifigure the confirmation dialogs belong to.
%   Mode        - "ask" (default: put the open/create question first),
%                 "open", or "create".
%   Current     - the roster configured now, '' if none; seeds the folder and
%                 is named in the question.
%   StartFolder - folder to start in when Current is empty or unreachable.
%
% Returns:
%   filePath - absolute path chosen, '' when the operator cancelled.
%   mode     - 'open' or 'create' (what the operator chose), '' on cancel.
%
% See also: epsych.SubjectRoster.setConfiguredFile,
%   gui.SubjectManager, epsych.RunExpt.DefineRosterFile
arguments
    parent
    options.Mode (1,1) string {mustBeMember(options.Mode, ["ask","open","create"])} = "ask"
    options.Current (1,:) char = ''
    options.StartFolder (1,:) char = ''
end

filePath = '';

ext = epsych.SubjectRoster.FILE_EXTENSION;
filter = {['*' ext], ['Subject Roster (*' ext ')']; '*.*', 'All Files (*.*)'};

% A configured roster on a share that is unreachable now would open the
% dialog somewhere that hangs or fails, so only a folder that exists counts.
startDir = '';
if ~isempty(options.Current)
    startDir = fileparts(options.Current);
end
if isempty(startDir) || ~isfolder(startDir)
    startDir = options.StartFolder;
end
if isempty(startDir) || ~isfolder(startDir)
    startDir = pwd;
end

mode = char(options.Mode);
if strcmp(mode, 'ask')
    if isempty(options.Current)
        current = 'No roster file is chosen yet.';
    else
        current = sprintf('Current roster:\n%s', options.Current);
    end
    answer = uiconfirm(parent, sprintf(['%s\n\nOpen a roster file that already ' ...
        'exists, or create a new, empty one?'], current), 'Subject Roster', ...
        'Options', {'Open Existing...', 'Create New...', 'Cancel'}, ...
        'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');
    switch answer
        case 'Open Existing...', mode = 'open';
        case 'Create New...',    mode = 'create';
        otherwise,               mode = ''; return
    end
end

while true
    if strcmp(mode, 'open')
        seed = startDir;
        if ~isempty(options.Current) && isfile(options.Current)
            seed = options.Current;
        elseif ~endsWith(seed, filesep)
            seed = [seed filesep];
        end
        [fn, pn] = uigetfile(filter, 'Open an Existing Subject Roster', seed);
        figure(parent);
        if isequal(fn, 0), mode = ''; return, end
        filePath = fullfile(pn, fn);
        return
    end

    [fn, pn] = uiputfile(filter, 'Create a New Subject Roster', ...
        fullfile(startDir, unusedName_(startDir, ext)));
    figure(parent);
    if isequal(fn, 0), mode = ''; return, end
    filePath = fullfile(pn, fn);
    [~, ~, e] = fileparts(filePath);
    if isempty(e), filePath = [filePath ext]; end

    if ~isfile(filePath), return, end

    % Windows has just asked "replace it?" and the operator said yes. Say
    % plainly that nothing will be replaced, and let them choose what they meant.
    answer = uiconfirm(parent, sprintf(['A roster named "%s" already exists in\n%s\n\n' ...
        'EPsych never replaces a roster file, so it cannot create a new one ' ...
        'there. Open the existing roster instead, or choose another name?'], ...
        fn, pn), 'Roster Already Exists', ...
        'Options', {'Open Existing', 'Choose Another Name', 'Cancel'}, ...
        'DefaultOption', 2, 'CancelOption', 3, 'Icon', 'warning');
    switch answer
        case 'Open Existing'
            mode = 'open';
            return
        case 'Choose Another Name'
            startDir = pn;
        otherwise
            filePath = '';
            mode = '';
            return
    end
end
end

function name = unusedName_(folder, ext)
% A suggested name that does not exist, so accepting the default never
% triggers the replace prompt.
name = ['subjects' ext];
k = 1;
while isfile(fullfile(folder, name))
    k = k + 1;
    name = sprintf('subjects_%d%s', k, ext);
end
end
