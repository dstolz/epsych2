function txt = format(msg,args)
% txt = eplog.format(msg,args)
% Render a log message to a single char row, applying EPsych's format policy.
%
%   no values  : the message is LITERAL text. Nothing is interpreted, so
%                '100% done' and 'C:\new\tmp\run.mat' survive intact.
%   with values: the message is a printf format string, exactly as documented.
%                '  [ERROR] %s\n' -> formatted, real newline.
%
% Keeping the no-values path literal is deliberate. About ten call sites pass
% a message built at runtime -- ME.message, ffmpeg output, a data path -- and
% those are precisely the strings that contain stray '%' and Windows
% backslashes. Interpreting them would corrupt the messages that matter most,
% turning 'C:\new\tmp' into a newline and a tab. The handful of literal
% messages that end in '\n' are fixed at the call site instead, where the
% intent is visible.
%
% Trailing newlines are stripped: the sinks add their own line ending, and
% many call sites append '\n' against convention. Stripping here makes that
% harmless rather than a source of blank log lines.
%
% Never throws. A bad format string yields the literal message plus a note,
% because logging routinely runs inside a catch block and must not replace
% the exception the caller was trying to report.
%
% Parameters:
%   msg  - char or string message text or format string
%   args - cell array of format values (may be empty)
%
% Returns:
%   txt  - char row vector, no trailing newline
%
% See also: vprintf, eplog.Logger, eplog.formatException

if nargin < 2, args = {}; end

m = localToChar(msg);

if isempty(args)
    txt = m;
else
    try
        txt = sprintf(m,args{:});
    catch fmtErr
        % '%s' below, so the offending text is an argument and cannot recurse.
        txt = sprintf('%s   [log format failed: %s]',m,fmtErr.message);
    end
end

% Strip trailing newlines and carriage returns only; leading and interior
% whitespace is the caller's business. Done by index rather than regexprep,
% which costs ~7 us against ~0.4 us and runs on every message.
LF = newline;
CR = char(13);
n = numel(txt);
while n > 0 && (txt(n) == LF || txt(n) == CR)
    n = n - 1;
end
if n < numel(txt)
    txt = txt(1:n);
end
end


function m = localToChar(msg)
% Coerce anything a caller might hand us into a char row, without throwing.
if ischar(msg)
    m = reshape(msg,1,[]);
    return
end

try
    if isstring(msg)
        msg(ismissing(msg)) = "<missing>";
        if isscalar(msg)
            m = char(msg);
        else
            m = char(strjoin(msg(:).',' '));
        end
    else
        % cellstr, numeric, logical, categorical, ... anything string() knows
        m = char(strjoin(string(msg(:)).',' '));
    end
catch
    m = sprintf('<unprintable %s>',class(msg));
end

if isempty(m)
    m = '';
else
    m = reshape(m,1,[]);
end
end
