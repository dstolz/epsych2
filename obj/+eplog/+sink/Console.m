classdef Console < eplog.sink.Sink
% eplog.sink.Console  Writes log records to the MATLAB command window.
%
% Output is byte-for-byte what vprintf has always produced:
%
%   18:51:35.958: This is a level 2 message
%
% This sink is where GVerbosity is applied. The logger's own gate now asks
% only whether a record is wanted ANYWHERE, and the error log wants everything,
% so a record above the console level still arrives here and is dropped here.
%
% Records at a negative level are log-only and never reach the console; that
% is what makes vprintf(-1,...) the "record it but do not bother the operator"
% level the SelfTest relies on.
%
% Properties:
%   ShowTimestamp - prefix each line with HH:mm:ss.SSS (default true)
%   Stream        - 1 for stdout, 2 for stderr; Red records always use 2
%
% See also: eplog.sink.Sink, eplog.Logger, eplog.isEnabled

    properties
        ShowTimestamp (1,1) logical = true
        Stream        (1,1) double  = 1
    end

    methods
        function tf = accepts(obj,rec)
            tf = accepts@eplog.sink.Sink(obj,rec) ...
                && rec.Level >= 0 ...
                && eplog.isEnabled(rec.Level,'console');
        end

        function write(obj,rec)
            if ~obj.accepts(rec), return; end

            if rec.Red
                fid = 2;
            else
                fid = obj.Stream;
            end

            % '%s' throughout: rec.Text is finished text, never a format.
            if obj.ShowTimestamp
                fprintf(fid,'%s: %s\n',rec.Stamp,rec.Text);
            else
                fprintf(fid,'%s\n',rec.Text);
            end
        end
    end
end
