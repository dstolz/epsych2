classdef (Abstract) FileSink < eplog.sink.Sink
% eplog.sink.FileSink  Shared lifecycle for sinks that write a daily file.
%
% Owns everything the old logmessage subfunction did, with the parts that were
% costing time or hiding failures fixed:
%
%   * Rotation is a single datetime comparison against a cached midnight
%     boundary. The old code formatted the date to text on EVERY message just
%     to strcmp it against the previous day.
%   * No per-message ftell probe. The handle is trusted until a write actually
%     fails, and only then re-opened.
%   * fopen failure latches. The old code left the fid at -1, so needNewLog
%     stayed true and every later message retried epsych_path + isfolder +
%     mkdir + fopen, silently, forever.
%   * flush() closes and reopens in append mode. MATLAB exposes no fflush, and
%     a buffered tail is exactly what gets lost in the crash the log exists to
%     explain. Records at or below FlushLevel flush automatically.
%   * PerProcess adds the process id to the filename, so several MATLAB
%     instances sharing one repo stop interleaving into one file.
%
% Subclasses supply formatLine() and extension().
%
% Properties:
%   Dir        - directory holding the log files
%   BaseName   - filename stem before the date
%   PerProcess - include the process id in the filename (default false)
%   FlushLevel - flush after any record at or below this level (default 0)
%   Path       - full path currently open (read-only)
%   Failed     - true once opening failed and logging was disabled (read-only)
%
% See also: eplog.sink.TextFile, eplog.sink.JsonLines, eplog.Logger

    properties
        Dir        (1,:) char    = ''
        BaseName   (1,:) char    = 'error_log'
        PerProcess (1,1) logical = false
        FlushLevel (1,1) double  = 0
    end

    properties (SetAccess = protected)
        Path   (1,:) char    = ''
        Fid    (1,1) double  = -1
        Failed (1,1) logical = false
    end

    properties (Access = private)
        openDate_ = [0 0 0]   % [year month day] the current file belongs to
    end

    methods (Abstract, Access = protected)
        s = formatLine(obj,rec)   % returns char, including its line ending
        e = extension(obj)        % e.g. '.txt'
    end

    methods
        function obj = FileSink(logDir)
            % obj = FileSink([logDir])
            if nargin < 1 || isempty(logDir)
                logDir = eplog.defaultLogDir();
            end
            obj.Dir = char(logDir);
        end

        function write(obj,rec)
            if ~obj.Enabled || obj.Failed, return; end

            if ~obj.ensureOpen_(rec.Clock), return; end

            line = obj.formatLine(rec);

            % '%s': the record text is finished, never a format string.
            written = false;
            try
                written = fprintf(obj.Fid,'%s',line) > 0;
            catch
                % fprintf raises on an invalid fid rather than returning 0.
            end

            if ~written
                % Re-open once and retry before giving up, so a transient
                % failure costs one line rather than the rest of the session.
                obj.closeHandle_();
                if obj.ensureOpen_(rec.Clock)
                    try
                        fprintf(obj.Fid,'%s',line);
                    catch
                        obj.fail_('log handle could not be re-established');
                    end
                end
            end

            if rec.Level <= obj.FlushLevel
                obj.flush();
            end
        end

        function flush(obj)
            % Close and reopen in append mode: MATLAB has no fflush, so this
            % is the only way to guarantee the bytes reached disk.
            if obj.Fid <= 2, return; end
            p = obj.Path;
            obj.closeHandle_();
            fid = fopen(p,'at');
            if fid > 2
                obj.Fid = fid;
            else
                obj.Fid = -1;
                obj.openDate_ = [0 0 0];
            end
        end

        function close(obj)
            obj.closeHandle_();
            obj.openDate_ = [0 0 0];
        end

        function reset(obj)
            % Clear a latched open failure and try again on the next record.
            obj.close();
            obj.Failed = false;
        end

        function delete(obj)
            obj.closeHandle_();
        end
    end

    methods (Access = private)
        function ok = ensureOpen_(obj,c)
            % Rotation is three numeric comparisons. The old logger formatted
            % the date to text on every message purely to strcmp it.
            d = obj.openDate_;
            if obj.Fid > 2 && d(1) == c(1) && d(2) == c(2) && d(3) == c(3)
                % Confirm the handle still refers to OUR file. fopen(fid)
                % costs ~1 us and returns '' for a dead fid, so it subsumes
                % the old ftell probe -- and unlike ftell it also catches a
                % fid that was closed and reused for a different file, which
                % would otherwise send log lines into someone else's output.
                if strcmp(fopen(obj.Fid),obj.Path)
                    ok = true;
                    return
                end
            end

            obj.closeHandle_();

            if ~isfolder(obj.Dir)
                [made,msg] = mkdir(obj.Dir);
                if ~made
                    obj.fail_(sprintf('cannot create "%s": %s',obj.Dir,msg));
                    ok = false;
                    return
                end
            end

            obj.Path = fullfile(obj.Dir,obj.fileName_(c));

            fid = fopen(obj.Path,'at');
            if fid <= 2
                obj.fail_(sprintf('cannot open "%s" for append',obj.Path));
                ok = false;
                return
            end

            obj.Fid = fid;
            obj.openDate_ = [c(1) c(2) c(3)];
            ok = true;
        end

        function n = fileName_(obj,c)
            datePart = eplog.dateTag(c);
            if obj.PerProcess
                n = sprintf('%s_%s_pid%d%s',obj.BaseName,datePart,localPid(),obj.extension());
            else
                n = sprintf('%s_%s%s',obj.BaseName,datePart,obj.extension());
            end
        end

        function closeHandle_(obj)
            if obj.Fid > 2
                try
                    fclose(obj.Fid);
                catch
                    % already closed by clear/fclose('all'); nothing to do
                end
            end
            obj.Fid = -1;
        end

        function fail_(obj,why)
            obj.Failed = true;
            obj.Fid = -1;
            % Reported once, on stderr, because the log itself is unavailable.
            fprintf(2,'eplog: file logging disabled -- %s\n',why);
        end
    end
end


function p = localPid()
persistent thePid
if isempty(thePid)
    try
        thePid = feature('getpid');
    catch
        thePid = 0;
    end
end
p = thePid;
end
