function verbosity()
% verbosity — Set the global verbosity level via dialog.
% Behavior
%   Presents a list dialog and updates GVerbosity accordingly.

global GVerbosity

if isempty(GVerbosity) || ~isnumeric(GVerbosity)
    GVerbosity = 1;
end

options = {'0. No extraneous text'
    '1. Additional info'
    '2. Detailed info'
    '3. Highly detailed info'
    '4. Ludicrously detailed info'};
[indx, tf] = listdlg('ListString', options, 'SelectionMode','single', ...
    'PromptString','Select the level of detail:', 'Name','Detail Level Selection', ...
    'InitialValue',min(GVerbosity+1,length(options)), 'ListSize',[300,150]);
if ~tf, return, end
GVerbosity = indx-1;
vprintf(1,'Verbosity set to %s',options{GVerbosity+1})
