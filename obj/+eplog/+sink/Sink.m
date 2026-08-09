classdef (Abstract) Sink < handle
% eplog.sink.Sink  Destination for log records.
%
% A sink receives fully formatted log records (see eplog.record) and is
% responsible only for getting them somewhere. Filtering by verbosity has
% already happened in eplog.isEnabled; a sink filters only for reasons of its
% own (the console sink, for instance, drops log-only records).
%
% Subclasses implement write(). flush() and close() are optional.
%
% Methods:
%   write(rec) - (Abstract) emit one record
%   flush()    - make previously written records durable
%   close()    - release resources
%
% See also: eplog.sink.Console, eplog.sink.TextFile, eplog.sink.JsonLines

    properties
        Enabled (1,1) logical = true
    end

    methods (Abstract)
        write(obj,rec)
    end

    methods
        function flush(~)
        end

        function close(~)
        end
    end
end
