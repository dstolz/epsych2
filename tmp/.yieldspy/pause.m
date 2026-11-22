function varargout = pause(varargin)
% Test spy for the built-in pause: counts the call, then does what pause does.
% Only on the path while a harness puts tmp/.yieldspy there (see yieldspy_count).
yieldspy_count('bump');
[varargout{1:nargout}] = builtin('pause', varargin{:});
end
