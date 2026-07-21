function vprintf(verbose_level,varargin)
% stimgen.util.vprintf(verbose_level,[red],msg,[moreinputs])
%
% Prints timestamp and text to the command window based on the current
% value of the global variable GVerbosity.  GVerbosity is a scalar
% integer value between -1 and 3:
%  -1 log message, but do not print to screen
%   0 suppresses nearly all non-critcal messages
%   1 low, information that may be generally useful to user
%   2 medium, information that can be helpful for debugging
%   3 high, lots of information about nearly all processes (debugging)
%
% Uses fprintf to print text. Additonal values must correspond to the
% escape characters defined as if calling fprintf directly.
%
% This function always prints a '\n' character at the end of the line,
% skipping a line.
%
% Messages at verbose_level <= GVerbosity are also written to a daily log
% file under fullfile(tempdir,'stimgen_error_logs'). Each log entry records
% the calling function and line number.  The log file handle is managed
% internally by this function.
%
% This is the stimgen package's self-contained logger. It deliberately has
% no dependency on the host application so that stimgen can be used
% standalone; GVerbosity is shared with any host that uses the same global,
% so verbosity set by the host still applies here.
%
% ex:
%      global GVerbosity
%      GVerbosity = 2;
%      stimgen.util.vprintf(2,'This is a level %d message: %s',2,'medium verbosity')
%      18:51:35.958: This is a level 2 message: medium verbosity
%
%      stimgen.util.vprintf(1,1,'This is a red level %d message',1)
%      18:51:35.958: This is a red level 1 message
%
% The msg input can also be an MException object and the entire error
% message and stack will be printed to the log.
%
% Daniel.Stolzberg@gmail.com 2015

% Copyright (C) 2016  Daniel Stolzberg, PhD
global GVerbosity

if isempty(GVerbosity) || ~isnumeric(GVerbosity), GVerbosity = 1; end

if verbose_level > GVerbosity, return; end

curTimeStr = datestr(now,'HH:MM:SS.FFF');

moreinputs = [];
red = 0;

if nargin == 2
    msg = varargin{1};

elseif nargin > 2 && ~ischar(varargin{1})
    red = varargin{1};
    msg = varargin{2};
    if nargin > 2
        moreinputs = varargin(3:end);
    end

elseif nargin > 2
    msg = varargin{1};
    moreinputs = varargin(2:end);

end

% log error
if isa(msg,'MException')
    stimgen.util.vprintf(verbose_level,red,msg.identifier);
    stimgen.util.vprintf(verbose_level,red,msg.message);
    for i = 1:length(msg.stack)
        stimgen.util.vprintf(verbose_level,red,'Stack %d\n\tfile:\t%s\n\tname:\t%s\n\tline:\t%d', ...
            i,msg.stack(i).file,msg.stack(i).name,msg.stack(i).line);
    end
    return
end


% log message
logmessage(msg,curTimeStr,moreinputs);

% don't want to display message, just log and return
if verbose_level == -1, return; end


% Print to command window
if isempty(moreinputs)
    msgText = char(string(msg));
    if red
        fprintf(2,'%s: %s\n',curTimeStr,msgText)
    else
        fprintf('%s: %s\n',curTimeStr,msgText)
    end
else
    if red
        fprintf(2,['%s: ' msg '\n'],curTimeStr,moreinputs{:})
    else
        fprintf(['%s: ' msg '\n'],curTimeStr,moreinputs{:})
    end
end




function logmessage(msg,curTimeStr,moreinputs)
% Print to log file
persistent logFid logDate

currentLogDate = datestr(now,'ddmmmyyyy');

needNewLog = isempty(logFid) || ~isnumeric(logFid) || logFid <= 2;

if ~needNewLog
    try
        ftell(logFid);
        needNewLog = ~strcmp(logDate,currentLogDate);
    catch
        needNewLog = true;
    end
end

if needNewLog
    if ~isempty(logFid) && logFid > 2
        fclose(logFid);
    end
    errlogs = fullfile(tempdir,'stimgen_error_logs');
    if ~isfolder(errlogs), mkdir(errlogs); end
    logFid = fopen(fullfile(errlogs,['error_log_' currentLogDate '.txt']),'at');
    logDate = currentLogDate;

end

if isnumeric(logFid) && logFid > 2
    st = dbstack;
    if length(st)>=3
        st = st(3);
    else
        st = st(end);
    end
    if isempty(moreinputs)
        msgText = char(string(msg));
        fprintf(logFid,'%s,%s,%d: %s\n',curTimeStr,st.name,st.line,msgText);
    else
        fprintf(logFid,['%s,%s,%d: ' msg '\n'],curTimeStr,st.name,st.line,moreinputs{:});
    end
end
