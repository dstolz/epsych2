function rec = record(c,stamp,level,red,text,caller,line,file)
% rec = eplog.record(c,stamp,level,red,text,caller,line,file)
% Build one log event.
%
% A plain struct, not a class. Sinks read six or seven fields per record, and
% classdef property access costs roughly 5-10 us per read against ~0.1 us for
% a struct field -- enough, across the console and file sinks, to dominate the
% whole logging path. epsych.SelfTest.result sets the same precedent for
% struct-shaped result records.
%
% Fields:
%   Clock      - clock vector [y mo d h mi s] the event was raised
%   Stamp      - 'HH:mm:ss.SSS' rendering of Clock, formatted once and shared
%                by every sink
%   Level      - numeric verbosity level (see eplog.Level)
%   Red        - true to route console output to stderr
%   Text       - fully formatted message, no trailing newline
%   Caller     - name of the function that called vprintf
%   Line       - line number within that function
%   File       - full path of that function's file
%   Identifier - error identifier when the event came from an exception
%   Stack      - exception stack, empty struct otherwise
%
% See also: eplog.Logger, eplog.sink.Sink, eplog.stamp

rec.Clock      = c;
rec.Stamp      = stamp;
rec.Level      = level;
rec.Red        = red;
rec.Text       = text;
rec.Caller     = caller;
rec.Line       = line;
rec.File       = file;
rec.Identifier = '';
rec.Stack      = struct('file',{},'name',{},'line',{});
end
