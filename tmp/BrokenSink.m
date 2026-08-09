classdef BrokenSink < eplog.sink.Sink
% BrokenSink  A sink that always throws.
%
% Used by smoke_test_eplog to prove that a failing destination is contained by
% eplog.Logger and never propagates into the caller -- which matters because
% EPsych logs from inside catch blocks.

    methods
        function write(~,~)
            error('epsych:smoke:brokenSink','this sink always fails');
        end
    end
end
