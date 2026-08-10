function vprintf(verbose_level,varargin)
% vprintf(verbose_level,msg)
% vprintf(verbose_level,red,msg)
% vprintf(verbose_level,msg,value1,value2,...)
% vprintf(verbose_level,red,msg,value1,value2,...)
% vprintf(verbose_level,[red],exception)
%
% Verbosity-gated console and log printing. This is the front door to the
% +eplog package: it parses the historical calling convention and hands the
% result to eplog.Logger, which formats the record once and dispatches it to
% every configured sink (console, daily text file, optional JSON Lines).
%
% Messages are filtered against the global GVerbosity, an integer normally
% between -1 and 4:
%  -1 log message, but do not print to screen
%   0 critical; suppresses nearly all other text
%   1 low, information that may be generally useful to the user
%   2 medium, information that can be helpful for debugging
%   3 high, lots of information about nearly all processes (debugging)
%   4 trace, per-trial detail
% See eplog.Level for the named form.
%
% Format policy (eplog.format):
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
%      vprintf(3,'Not printed because GVerbosity = %d',GVerbosity)
%
%      vprintf(1,1,'This is a red level %d message: %s',1,'low verbosity')
%      18:51:35.958: This is a red level 1 message: low verbosity
%
% See documentation/eplog/eplog_Logging.md for the package overview and
% documentation/helpers/helpers_vprintf.md for a usage guide.
%
% See also: visenabled, eplog.Logger, eplog.isEnabled, eplog.Level, eplog.format
%
% Daniel.Stolzberg@gmail.com 2015

% Copyright (C) 2016  Daniel Stolzberg, PhD

% The gate comes first and is the only cost a suppressed message pays: no
% timestamp, no dbstack, no formatting. At a 100 Hz trial timer that is the
% difference between level-4 traces being free and being a timing hazard.
if ~eplog.isEnabled(verbose_level), return; end

if isempty(varargin)
    % Nothing to say. Historically this errored on an undefined variable
    % inside the logger, which is the worst possible place to raise.
    return
end

% Calling convention: an optional red flag sits between the level and the
% message. It is only a flag when something follows it, and only when it is
% numeric or logical -- the old test was ~ischar, which read a string scalar
% message as the flag and then failed on it.
if numel(varargin) >= 2 && (isnumeric(varargin{1}) || islogical(varargin{1})) ...
        && isscalar(varargin{1})
    red    = logical(varargin{1});
    msg    = varargin{2};
    values = varargin(3:end);
else
    red    = false;
    msg    = varargin{1};
    values = varargin(2:end);
end

eplog.Logger.instance().emit(verbose_level,red,msg,values);
