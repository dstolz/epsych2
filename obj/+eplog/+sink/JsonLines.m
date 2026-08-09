classdef JsonLines < eplog.sink.FileSink
% eplog.sink.JsonLines  Structured daily log, one JSON object per line.
%
% Off by default. Add it to the logger when a session's log needs to be
% queried rather than read:
%
%   L = eplog.Logger.instance();
%   L.addSink(eplog.sink.JsonLines());
%
% Each line carries the full record -- level, level name, red flag, caller,
% line, file, error identifier, message and, for exceptions, the stack -- so a
% session can be filtered by level or grouped by call site without parsing the
% human-readable log, which nothing currently parses and which is therefore
% free to keep changing shape.
%
% See also: eplog.sink.FileSink, eplog.sink.TextFile, eplog.record

    methods
        function obj = JsonLines(logDir)
            if nargin < 1, logDir = ''; end
            obj@eplog.sink.FileSink(logDir);
        end
    end

    methods (Access = protected)
        function s = formatLine(~,rec)
            try
                c = rec.Clock;
                out = struct( ...
                    'time',       sprintf('%04d-%02d-%02dT%s', ...
                                      c(1),c(2),c(3),rec.Stamp), ...
                    'level',      double(rec.Level), ...
                    'levelName',  char(eplog.Level.label(rec.Level)), ...
                    'red',        logical(rec.Red), ...
                    'caller',     rec.Caller, ...
                    'line',       double(rec.Line), ...
                    'file',       rec.File, ...
                    'identifier', rec.Identifier, ...
                    'message',    rec.Text);

                if ~isempty(rec.Stack)
                    st = rec.Stack;
                    frames = cell(1,numel(st));
                    for k = 1:numel(st)
                        frames{k} = struct('name',st(k).name, ...
                            'line',double(st(k).line),'file',st(k).file);
                    end
                    out.stack = frames;
                end

                s = [jsonencode(out) newline];
            catch encodeErr
                % A record must never be able to take the logger down.
                s = [jsonencode(struct( ...
                    'time',   rec.Stamp, ...
                    'level',  double(rec.Level), ...
                    'error',  ['unencodable record: ' encodeErr.message])) newline];
            end
        end

        function e = extension(~)
            e = '.jsonl';
        end
    end
end
