function drawnow(varargin)
% Test spy for the built-in drawnow: counts the call, then does what drawnow
% does. Only on the path while a harness puts tmp/.yieldspy there (see
% yieldspy_count).
yieldspy_count('bump');
builtin('drawnow', varargin{:});
end
