function vprintf(verbose_level,varargin)
% vprintf(verbose_level,msg)
% vprintf(verbose_level,red,msg)
% vprintf(verbose_level,msg,value1,value2,...)
% vprintf(verbose_level,red,msg,value1,value2,...)
% vprintf(verbose_level,[red],exception)
%
% Verbosity-gated console and log printing, and EPsych's front door to the
% granary logging package. This function is a thin forward to granary.printf,
% which parses the calling convention and hands the result to granary.Logger.
%
% It exists rather than having every call site say granary.printf for two
% reasons: EPsych has over a thousand vprintf calls, and a library has no
% business claiming an unqualified name on the Matlab path. epsych_startup
% registers this file with granary.config's FacadeFiles, so a log record is
% attributed to the code that called vprintf rather than to vprintf itself --
% without that registration the caller column of every line in the log would
% read "vprintf" at one fixed line number.
%
% Levels are integers normally between -1 and 4:
%  -1 log message, but do not print to screen
%   0 critical; suppresses nearly all other text
%   1 low, information that may be generally useful to the user
%   2 medium, information that can be helpful for debugging
%   3 high, lots of information about nearly all processes (debugging)
%   4 trace, per-trial detail
% See granary.Level for the named form.
%
% The two destinations are filtered separately:
%   GVerbosity    - command window. Default 1, unchanged.
%   GLogVerbosity - error log. Default Inf, so EVERY message is written to
%                   .error_logs no matter how quiet the console is.
% Lowering GVerbosity therefore hides output; it no longer discards it. Set
% GLogVerbosity to a finite level on a rig where per-trial level-4 traces are
% too expensive to write.
%
% Format policy (granary.format):
%   With values, msg is a printf format string, exactly as documented.
%   With no values, msg is LITERAL text -- nothing is interpreted -- so a
%   runtime-built message such as ME.message or 'C:\new\data.mat' survives
%   intact instead of being mangled by '\n' and '%' conversions.
% A trailing newline is never needed and is stripped if present; the sinks
% add their own line ending.
%
% The msg input may also be an MException, or any struct carrying .message
% (a lasterror-style struct or a timer ErrorFcn event). The identifier,
% message, stack and any nested causes are written as a SINGLE log record,
% attributed to the catch site rather than to the logger.
%
% Nothing here throws. EPsych logs from inside catch blocks, and an exception
% raised while reporting an exception destroys the report.
%
% ex:
%      global GVerbosity
%      GVerbosity = 2;
%      vprintf(2,'This is a level %d message: %s',2,'medium verbosity')
%      18:51:35.958: This is a level 2 message: medium verbosity
%
%      vprintf(3,'Not printed because GVerbosity = %d, but still logged',GVerbosity)
%
%      vprintf(1,1,'This is a red level %d message: %s',1,'low verbosity')
%      18:51:35.958: This is a red level 1 message: low verbosity
%
% See documentation/helpers/helpers_vprintf.md for a usage guide, and the
% granary repository for the package itself.
%
% See also: visenabled, granary.printf, granary.Logger, granary.isEnabled
%
% Daniel.Stolzberg@gmail.com 2015

% Copyright (C) 2016  Daniel Stolzberg, PhD

granary.printf(verbose_level,varargin{:});
