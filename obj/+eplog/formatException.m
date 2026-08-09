function [txt,identifier,stack] = formatException(err)
% [txt,identifier,stack] = eplog.formatException(err)
% Render an exception into one multi-line message.
%
% Accepts an MException or any struct carrying message/identifier/stack --
% notably the lasterror-style struct that RUNTIME.ERROR holds, which the old
% logger could not print at all (it threw inside the error handler).
%
% The whole exception becomes a SINGLE log record. The previous implementation
% recursed into vprintf once per identifier, message and stack frame, which
% made dbstack report vprintf itself as the caller -- so every
% "catch ME; vprintf(0,1,ME); end" site lost the location that mattered.
%
% Exception text is returned as literal text, never as a format string, so an
% error message containing '%' or a Windows path survives intact.
%
% Parameters:
%   err - MException, or struct with .message and optionally
%         .identifier / .stack
%
% Returns:
%   txt        - char row, possibly multi-line, no trailing newline
%   identifier - error identifier ('' when absent)
%   stack      - stack struct array ('file','name','line'), possibly empty
%
% See also: eplog.format, vprintf

identifier = '';
stack = struct('file',{},'name',{},'line',{});
msgText = '';

if isa(err,'MException') || isstruct(err)
    if localHas(err,'identifier')
        identifier = localChar(err.identifier);
    elseif localHas(err,'messageID')
        % A MATLAB timer's ErrorFcn event data names the field messageID
        % rather than identifier; RUNTIME.ERROR may hold either shape.
        identifier = localChar(err.messageID);
    end
    if localHas(err,'message'),    msgText    = localChar(err.message);    end
    if localHas(err,'stack') && ~isempty(err.stack)
        stack = localNormalizeStack(err.stack);
    end
else
    msgText = localChar(err);
end

nStack = numel(stack);
lines = cell(1,1+nStack);

if isempty(identifier)
    lines{1} = msgText;
else
    lines{1} = [identifier ': ' msgText];
end

for k = 1:nStack
    lines{1+k} = sprintf('    at %s (line %d) %s', ...
        stack(k).name, stack(k).line, stack(k).file);
end

% MException.cause carries the underlying failure for wrapped errors;
% dropping it discards the actual reason.
if localHas(err,'cause') && ~isempty(err.cause)
    causes = err.cause;
    nCause = numel(causes);
    causeLines = cell(1,2*nCause);
    for k = 1:nCause
        causeTxt = eplog.formatException(causes{k});
        causeLines{2*k-1} = '  caused by:';
        causeLines{2*k}   = regexprep(causeTxt,'^','    ','lineanchors');
    end
    lines = [lines causeLines];
end

txt = strjoin(lines,newline);
end


function tf = localHas(x,name)
if isstruct(x)
    tf = isfield(x,name);
else
    tf = isprop(x,name);
end
end


function s = localNormalizeStack(st)
% lasterror stacks and MException stacks agree on name/line/file, but a
% hand-built struct may carry only some of them.
n = numel(st);
s = repmat(struct('file','','name','','line',0),1,n);
for k = 1:n
    if localHas(st(k),'file'), s(k).file = localChar(st(k).file); end
    if localHas(st(k),'name'), s(k).name = localChar(st(k).name); end
    if localHas(st(k),'line'), s(k).line = double(st(k).line);    end
end
end


function c = localChar(v)
if ischar(v)
    c = reshape(v,1,[]);
elseif isstring(v) && isscalar(v) && ~ismissing(v)
    c = char(v);
else
    try
        c = char(string(v));
    catch
        c = '';
    end
end
end
