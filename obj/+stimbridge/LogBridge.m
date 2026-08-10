classdef LogBridge < stimgen.LogSink
% stimbridge.LogBridge  Routes stimgen's log messages into the EPsych session log.
%
% stimgen ships its own logger so it can run standalone, which used to mean a
% StimPlayer or calibration failure was written to
% fullfile(tempdir,'stimgen_error_logs') and never reached .error_logs --
% diagnosing one session meant opening two files. Installing this bridge
% (epsych_startup does it) makes stimgen forward instead of writing, so every
% message goes through eplog: same format policy, same sinks, same daily file.
%
% The class is deliberately three lines of logic. stimgen.LogSink.emit was
% given the signature of eplog.Logger.emit precisely so this is a pass-through
% with nothing to translate and nothing to keep in sync.
%
% Methods:
%   emit      - forward one message to the session logger
%   isEnabled - defer the verbosity gate to eplog.isEnabled
%
% Example:
%   stimgen.util.logSink(stimbridge.LogBridge());   % done by epsych_startup
%   stimgen.util.logSink([]);                       % back to stimgen's own log
%
% See also: stimgen.LogSink, stimgen.util.logSink, eplog.Logger, vprintf

    methods
        function emit(~,level,red,msg,args)
            % emit(obj,level,red,msg,args)
            % Hand one stimgen message to the session logger.
            %
            % Three things this must NOT do, each of which has a failure mode:
            %
            %   * cache the logger in a property. eplog.Logger.instance('-reset')
            %     deletes the logger -- epsych_startup calls it on every run --
            %     and a cached handle then goes stale, so every stimgen message
            %     disappears into a caught error. instance() is a persistent
            %     read and costs nothing.
            %   * call the vprintf facade. It would re-run eplog.isEnabled,
            %     which stimgen has already run, and add a stack frame that
            %     eplog.callerFrame would then have to skip.
            %   * reformat, expand or stringify msg. An MException arrives
            %     unexpanded so that emit can make it ONE record with the
            %     identifier, stack and nested causes attributed to the catch
            %     site; flattening it here would throw that away.
            eplog.Logger.instance().emit(level,logical(red),msg,args);
        end

        function tf = isEnabled(~,level)
            % tf = isEnabled(obj,level)
            % Defer to EPsych's gate so eplog.isEnabled is the single reader of
            % GVerbosity across both code bases. stimgen then inherits its
            % repair of NaN/Inf/[]/non-scalar values for free, instead of two
            % gates that can disagree about the same global.
            tf = eplog.isEnabled(level);
        end
    end
end
