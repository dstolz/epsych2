classdef CountingLogSink < granary.sink.Sink
    % Log sink that counts the records it is handed, by level, and writes
    % nothing. For tmp/bench_trial_boundary.m: a record that reaches a sink was
    % BUILT (timestamp, dbstack, formatting), which is the cost being counted.
    %
    % s = CountingLogSink();
    % granary.Logger.instance().addSink(s);
    % ... ; n = s.Total; byLevel = s.ByLevel;   % ByLevel(k) counts level k-2 (-1..4)
    % granary.Logger.instance().removeSink(s);

    properties (SetAccess = private)
        Total   (1,1) double = 0
        ByLevel (1,6) double = zeros(1,6)   % levels -1, 0, 1, 2, 3, 4
    end

    methods
        function write(obj, rec)
            if ~obj.accepts(rec), return; end
            obj.Total = obj.Total + 1;
            k = round(rec.Level) + 2;
            if k >= 1 && k <= 6
                obj.ByLevel(k) = obj.ByLevel(k) + 1;
            end
        end

        function reset(obj)
            obj.Total = 0;
            obj.ByLevel = zeros(1,6);
        end
    end
end
