classdef Logger < handle
% eplog.Logger  Session-wide log dispatcher.
%
% Owns the list of sinks and turns a call into a log record (see eplog.record).
% There is one logger per MATLAB session, reached through
% eplog.Logger.instance().
%
% Verbosity filtering is NOT done here -- eplog.isEnabled gates before a
% logger is even fetched, so a suppressed message costs a global read and a
% comparison and nothing else.
%
% Nothing in this class is allowed to throw. Logging runs inside catch blocks
% throughout EPsych, and an exception raised while reporting an exception
% replaces the failure the operator actually needed to see.
%
% Properties:
%   Enabled - master switch (default true)
%   Sinks   - cell array of eplog.sink.Sink
%   LogFile - path of the first file sink's current file (read-only)
%
% Methods:
%   instance()                 - (Static) the session logger
%   emit(level,red,msg,args)   - format and dispatch one message
%   log(rec)                   - dispatch an already-built record
%   flush() / close()          - durability and teardown
%   addSink(s) / removeSink(s) - reconfigure destinations
%   sinkOfType(cls)            - first sink of a given class, or empty
%
% Example:
%   L = eplog.Logger.instance();
%   L.addSink(eplog.sink.JsonLines());   % structured log alongside the text one
%   disp(L.LogFile)
%
% See also: vprintf, eplog.isEnabled, eplog.sink.Sink, eplog.record

    properties
        Enabled (1,1) logical = true
    end

    properties (SetAccess = protected)
        Sinks (1,:) cell = {}
    end

    properties (Dependent, SetAccess = private)
        LogFile
    end

    methods (Static)
        function L = instance(cmd)
            % L = eplog.Logger.instance()
            % L = eplog.Logger.instance('-reset')   discard and rebuild
            persistent theLogger

            if nargin > 0 && (ischar(cmd) || isstring(cmd)) && strcmp(cmd,'-reset')
                if ~isempty(theLogger) && isvalid(theLogger)
                    theLogger.close();
                    delete(theLogger);
                end
                theLogger = [];
            end

            if isempty(theLogger) || ~isvalid(theLogger)
                theLogger = eplog.Logger();
            end

            L = theLogger;
        end
    end

    methods
        function obj = Logger(sinks)
            % obj = eplog.Logger()        console + daily text file
            % obj = eplog.Logger(sinks)   cell array of eplog.sink.Sink
            if nargin < 1 || isempty(sinks)
                sinks = {eplog.sink.Console(), eplog.sink.TextFile()};
            end
            obj.Sinks = sinks;
        end

        function emit(obj,level,red,msg,args)
            % emit(obj,level,red,msg,args)
            % Build one record from a vprintf-style call and dispatch it.
            if ~obj.Enabled, return; end
            if nargin < 5, args = {}; end

            try
                % clock, not datetime('now'): the Code Analyzer prefers
                % datetime, but rendering one to 'HH:mm:ss.SSS' costs ~275 us
                % against ~1 us for eplog.stamp on a clock vector, and this
                % runs on every emitted message. See eplog.stamp.
                c = clock;

                if isa(msg,'MException') || (isstruct(msg) && isfield(msg,'message'))
                    [txt,ident,stk] = eplog.formatException(msg);
                else
                    txt   = eplog.format(msg,args);
                    ident = '';
                    stk   = struct('file',{},'name',{},'line',{});
                end

                [nm,ln,fl] = eplog.callerFrame();

                rec = eplog.record(c,eplog.stamp(c),level,red,txt,nm,ln,fl);
                rec.Identifier = ident;
                rec.Stack      = stk;

                obj.log(rec);
            catch emitErr
                % Last resort: say so on stderr and carry on.
                fprintf(2,'eplog: dropped a log message (%s)\n',emitErr.message);
            end
        end

        function log(obj,rec)
            % log(obj,rec)  Dispatch a record to every sink.
            for k = 1:numel(obj.Sinks)
                try
                    obj.Sinks{k}.write(rec);
                catch sinkErr
                    % One broken sink must not stop the others, and must not
                    % propagate into the caller's catch block.
                    fprintf(2,'eplog: sink %s failed: %s\n', ...
                        class(obj.Sinks{k}),sinkErr.message);
                end
            end
        end

        function flush(obj)
            for k = 1:numel(obj.Sinks)
                try
                    obj.Sinks{k}.flush();
                catch
                    % nothing useful to do while flushing
                end
            end
        end

        function close(obj)
            for k = 1:numel(obj.Sinks)
                try
                    obj.Sinks{k}.close();
                catch
                    % nothing useful to do while closing
                end
            end
        end

        function addSink(obj,s)
            arguments
                obj
                s (1,1) eplog.sink.Sink
            end
            obj.Sinks{end+1} = s;
        end

        function removeSink(obj,s)
            keep = true(1,numel(obj.Sinks));
            for k = 1:numel(obj.Sinks)
                keep(k) = obj.Sinks{k} ~= s;
            end
            dropped = obj.Sinks(~keep);
            for k = 1:numel(dropped)
                try
                    dropped{k}.close();
                catch
                    % already closed
                end
            end
            obj.Sinks = obj.Sinks(keep);
        end

        function s = sinkOfType(obj,cls)
            % s = sinkOfType(obj,'eplog.sink.TextFile')
            s = [];
            for k = 1:numel(obj.Sinks)
                if isa(obj.Sinks{k},cls)
                    s = obj.Sinks{k};
                    return
                end
            end
        end

        function p = get.LogFile(obj)
            p = '';
            fs = obj.sinkOfType('eplog.sink.FileSink');
            if ~isempty(fs)
                p = fs.Path;
                if isempty(p)
                    % Nothing logged yet, so no file is open. Report where the
                    % next record will land rather than an empty string.
                    p = fullfile(fs.Dir,'');
                end
            end
        end

        function delete(obj)
            obj.close();
        end
    end
end
