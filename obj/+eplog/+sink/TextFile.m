classdef TextFile < eplog.sink.FileSink
% eplog.sink.TextFile  Daily human-readable log file.
%
% Writes the line shape EPsych has always written, so existing logs and the
% new ones read the same:
%
%   09:14:26.435,epsych_startup,80: EPsych Toolbox version 2
%
% Multi-line records -- an exception with its stack -- keep the header line in
% that shape and indent their continuation lines, so one event stays visually
% one event instead of repeating the timestamp per stack frame.
%
% The path and filename are deliberately unchanged: RunExpt's "Open Current
% Error Log", the SelfTest window's "Open Log" button and SelfTest check A4
% all look for .error_logs/error_log_<ddmmmyyyy>.txt.
%
% See also: eplog.sink.FileSink, eplog.sink.JsonLines

    methods
        function obj = TextFile(logDir)
            if nargin < 1, logDir = ''; end
            obj@eplog.sink.FileSink(logDir);
        end
    end

    methods (Access = protected)
        function s = formatLine(~,rec)
            % Concatenation rather than sprintf: this runs on every message
            % and sprintf costs roughly 18 us here against 13 us for a concat.
            head = [rec.Stamp ',' rec.Caller ',' localInt(rec.Line) ': '];

            if contains(rec.Text,newline)
                parts = strsplit(rec.Text,newline);
                body  = strjoin([parts(1) strcat({'    '},parts(2:end))],newline);
                s = [head body newline];
            else
                s = [head rec.Text newline];
            end
        end

        function e = extension(~)
            e = '.txt';
        end
    end
end


function s = localInt(v)
% Line numbers are almost always small; skip sprintf for the common case.
if v >= 0 && v < 10
    s = char(48+v);
else
    s = sprintf('%d',v);
end
end
