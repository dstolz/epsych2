function tf = visenabled(verbose_level)
% tf = visenabled(verbose_level)
% True when a vprintf call at this level would produce output.
%
% Use it to guard log arguments that are expensive to build. vprintf already
% returns before doing any work when a level is suppressed, but it cannot
% prevent the CALLER from computing what it was about to pass:
%
%   if visenabled(4)
%       vprintf(4,'buffer: %s',mat2str(obj.readBuffer()));   % never read
%   end
%
% For an ordinary message with cheap arguments, call vprintf directly -- the
% guard costs more than it saves.
%
% It answers for BOTH destinations, matching vprintf: the error log takes every
% level by default (GLogVerbosity), so a guarded block now runs even when the
% console is quiet, and its message is written to the log. Guard on
% eplog.isEnabled(level,'console') instead only where the console is genuinely
% the sole consumer -- a guard that hides the argument also hides it from the
% log, which is the file that has to explain the failure afterwards.
%
% Parameters:
%   verbose_level - numeric verbosity level (see eplog.Level)
%
% Returns:
%   tf - logical scalar
%
% See also: vprintf, eplog.isEnabled, eplog.Level

tf = eplog.isEnabled(verbose_level,'any');
