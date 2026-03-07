function verbosity(self)
% verbosity — Set the global verbosity level via dialog.
% Behavior
%   Presents a list dialog and updates GVerbosity accordingly.
arguments
    self
end
options = {'0. No extraneous text'
    '1. Additional info'
    '2. Detailed info'
    '3. Highly detailed info'
    '4. Ludicrously detailed info'};
[indx, tf] = listdlg('ListString', options, 'SelectionMode','single', ...
    'PromptString','Select the level of detail:', 'Name','Detail Level Selection', ...
    'InitialValue',self.GVerbosity+1, 'ListSize',[300,150]);
if ~tf, return, end
self.GVerbosity = indx-1;
vprintf(1,'Verbosity set to %s',options{self.GVerbosity+1})
