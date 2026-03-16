function onFigureKeyPress(self, evt)
% onFigureKeyPress — Handle RunExpt keyboard shortcuts.
% Behavior
%   Ctrl+0 through Ctrl+4 update the global verbosity level directly.

if isempty(evt)
    return
end

modifiers = string(evt.Modifier);
if any(modifiers == "alt")
    return
end

if ~any(modifiers == "control") && ~any(modifiers == "command")
    return
end

key = string(evt.Key);
switch key
    case {"0","1","2","3","4"}
        level = str2double(key);
    case {"numpad0","numpad1","numpad2","numpad3","numpad4"}
        level = str2double(extractAfter(key,"numpad"));
    otherwise
        return
end

self.verbosity(level);