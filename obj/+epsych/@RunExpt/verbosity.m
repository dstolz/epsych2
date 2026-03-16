function verbosity(self, varargin)
% verbosity — Set the global verbosity level via dialog or shortcut.
% Behavior
%   Presents a list dialog and updates GVerbosity accordingly.
%   When called with a numeric scalar, sets that level directly.

global GVerbosity

if isempty(GVerbosity) || ~isnumeric(GVerbosity)
    GVerbosity = 1;
end

options = {'0. No extraneous text'
    '1. Additional info'
    '2. Detailed info'
    '3. Highly detailed info'
    '4. Ludicrously detailed info'};
if nargin >= 2 && ~isempty(varargin{1})
    level = double(varargin{1});
    if ~isscalar(level) || ~isfinite(level) || level ~= fix(level)
        return
    end
    if level < 0 || level > (length(options) - 1)
        return
    end
else
    [indx, tf] = listdlg('ListString', options, 'SelectionMode','single', ...
        'PromptString','Select the level of detail:', 'Name','Detail Level Selection', ...
        'InitialValue',min(GVerbosity+1,length(options)), 'ListSize',[300,150]);
    if ~tf, return, end
    level = indx-1;
end

GVerbosity = level;
if GVerbosity == 0
    disp(sprintf('Verbosity set to %s', options{GVerbosity+1}))
else
    vprintf(1,'Verbosity set to %s',options{GVerbosity+1})
end
