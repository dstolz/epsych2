classdef (Abstract) Sink < handle
% eplog.sink.Sink  Destination for log records.
%
% A sink receives fully formatted log records (see eplog.record) and is
% responsible only for getting them somewhere.
%
% The verbosity gate in eplog.isEnabled answers for the session as a whole --
% "would this reach ANY destination" -- so it can no longer decide for an
% individual sink now that the console and the error log have separate levels.
% Each sink therefore filters again in accepts(), against the global gate for
% its own destination plus its own MaxLevel.
%
% Subclasses implement write(), which must start by consulting accepts().
% flush() and close() are optional.
%
% Properties:
%   Enabled  - master switch for this sink (default true)
%   MaxLevel - sink-local ceiling, applied on top of the global gate
%              (default Inf: no ceiling of its own)
%
% Methods:
%   write(rec)   - (Abstract) emit one record
%   accepts(rec) - should this sink write this record
%   flush()      - make previously written records durable
%   close()      - release resources
%
% See also: eplog.sink.Console, eplog.sink.TextFile, eplog.sink.JsonLines

    properties
        Enabled  (1,1) logical = true
        MaxLevel (1,1) double  = Inf
    end

    methods (Abstract)
        write(obj,rec)
    end

    methods
        function tf = accepts(obj,rec)
            % tf = accepts(obj,rec)
            % Subclasses extend this with the gate for their destination.
            % rec.Level is a scalar double -- eplog.record guarantees it -- so
            % these tests stay scalar even for a malformed call site.
            tf = obj.Enabled && rec.Level <= obj.MaxLevel;
        end

        function flush(~)
        end

        function close(~)
        end
    end
end
