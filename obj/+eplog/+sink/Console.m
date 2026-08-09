classdef Console < eplog.sink.Sink
% eplog.sink.Console  Writes log records to the MATLAB command window.
%
% Output is byte-for-byte what vprintf has always produced:
%
%   18:51:35.958: This is a level 2 message
%
% Records at a negative level are log-only and never reach the console; that
% is what makes vprintf(-1,...) the "record it but do not bother the operator"
% level the SelfTest relies on.
%
% Properties:
%   ShowTimestamp - prefix each line with HH:mm:ss.SSS (default true)
%   Stream        - 1 for stdout, 2 for stderr; Red records always use 2
%
% See also: eplog.sink.Sink, eplog.Logger

    properties
        ShowTimestamp (1,1) logical = true
        Stream        (1,1) double  = 1
    end

    methods
        function write(obj,rec)
            if ~obj.Enabled, return; end
            if rec.Level < 0, return; end   % log-only

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
