classdef VideoConverter < handle
    % obj = util.VideoConverter(Name=Value,...)
    % Batch video format conversion using ffmpeg as tracked child processes.
    %
    % Recursively scans a folder for video files matching a regular
    % expression, then converts each with ffmpeg (H.264/AAC by default,
    % matching the vocabulary of the FFmpeg Toolbox's ffmpegtranscode).
    % Unlike ffmpegtranscode -- which shells out via a single blocking
    % system() call, so MATLAB (and its own progress timer) freezes for the
    % whole encode -- this class launches ffmpeg.exe itself as a tracked
    % System.Diagnostics.Process (the same pattern hw.VlcRecorder uses),
    % giving true per-file progress, instant cancellation, and optional
    % N-way parallelism.
    %
    % WORKFLOW
    %   c = util.VideoConverter(RootFolder="D:\data", MaxParallel=2);
    %   files = c.scan();             % populates c.Results
    %   c.convert();                  % asynchronous; returns immediately
    %   c.waitUntilDone();            % or: listen to the Progress event
    %
    % SAFETY
    %   Every job encodes to an extension-preserving ".part<token>.ext"
    %   sidecar next to the planned output and is committed by rename only
    %   after ffmpeg exits 0 and the sidecar is non-empty. This makes
    %   in-place conversion, cancellation, and re-scans all safe: a killed
    %   or failed job never leaves a truncated file at the final path, and
    %   DeleteSource only fires after the renamed output is verified.
    %
    % PROGRESS
    %   Set ProgressFcn = @(src,evt) ... for a callback, or
    %   listener(c,'Progress',@(src,evt) ...) for an event. evt is a
    %   util.ProgressEventData with Stage, JobIndex, Percent,
    %   OverallPercent, Fps, Speed, ElapsedSeconds, EtaSeconds, etc.
    %
    % Setup GUI
    %   obj.setupGUI() opens gui.VideoConverterSetup.
    %
    % See also: gui.VideoConverterSetup, hw.VlcRecorder, util.ProgressEventData

    properties (SetAccess = private)
        Results table              % one row per scanned file; see util.VideoConverter.emptyResults
        IsRunning (1,1) logical = false
    end

    % ---- discovery ----
    properties
        RootFolder      (1,1) string = ""
        FilePattern     (1,1) string = "(?i)\.(avi|mp4|mov|mkv|ts|mpg|mpeg|wmv|m4v)$"
        ExcludePattern  (1,1) string = "(?i)(_conv|\.part\w*)\.[^.\\/]+$"
        Recursive       (1,1) logical = true
    end

    % ---- output naming ----
    properties
        OutputFolder    (1,1) string = ""          % "" = alongside source
        MirrorTree      (1,1) logical = true        % only when OutputFolder ~= ""
        OutputExtension (1,1) string = ".mp4"
        NamePrefix      (1,1) string = ""
        NameSuffix      (1,1) string = "_conv"
        NameReplace     (1,2) string = ["",""]      % regexprep(stem, NameReplace(1), NameReplace(2))
    end

    % ---- safety / policy ----
    properties
        Overwrite (1,1) string {mustBeMember(Overwrite,["skip","overwrite","error"])} = "skip"
        DeleteSource       (1,1) logical = false
        VerifyBeforeDelete (1,1) logical = true
        DryRun             (1,1) logical = false
    end

    % ---- engine ----
    properties
        MaxParallel (1,1) double {mustBeInteger,mustBeInRange(MaxParallel,1,16)} = 2
        PollPeriod  (1,1) double {mustBeInRange(PollPeriod,0.1,5)} = 0.5
        ProgressFcn = []
        FfmpegExe   (1,1) string = ""
        ProbeOnScan (1,1) logical = false
    end

    % ---- ffmpegtranscode-style option vocabulary ----
    properties
        Range (1,:) double {mustBeNonnegative} = []          % scalar = total duration; 2-vec = [start end]
        Units (1,1) string {mustBeMember(Units,["seconds","frames","samples"])} = "seconds"
        FastSearch (1,1) string {mustBeMember(FastSearch,["off","on"])} = "off"
        InputFrameRate  (1,:) double {mustBeNonnegative} = []
        InputPixelFormat (1,1) string = ""
        InputFrameSize  (1,:) double {mustBeNonnegative} = [] % [width height]
        AudioCodec (1,1) string {mustBeMember(AudioCodec,["none","copy","wav","mp3","aac"])} = "aac"
        AacBitRate (1,:) double {mustBeNonnegative} = []
        Mp3Quality (1,:) double = []
        AudioSampleRate (1,:) double {mustBeNonnegative} = []
        VideoCodec (1,1) string {mustBeMember(VideoCodec,["none","copy","raw","mpeg4","x264","gif"])} = "x264"
        OutputFrameRate (1,:) double {mustBeNonnegative} = []
        PixelFormat (1,1) string = ""
        x264Preset (1,1) string = "medium"
        x264Tune   (1,1) string = ""
        x264Crf    (1,1) double {mustBeInteger,mustBeInRange(x264Crf,1,51)} = 18
        Mpeg4Quality (1,1) double {mustBeInteger,mustBeInRange(Mpeg4Quality,1,31)} = 1
        VideoScale (1,:) double {mustBePositive} = []         % scalar factor, or [num den]
        VideoCrop  (1,:) double = []                           % [left top right bottom]; negative = pad
        VideoFlip  (1,1) string {mustBeMember(VideoFlip,["","horizontal","vertical","both"])} = ""
        VideoFillColor (1,1) string = "black"
        ExtraArgs (1,:) string = string.empty(1,0)             % raw escape hatch, appended to output opts
    end

    events
        Progress   % fired on scan, batch start/finish/cancel, per-tick, and per-job completion
    end

    properties (Constant, Access = private)
        StatusCategories_ = ["pending","running","done","failed","skipped","cancelled","dryrun"]
    end

    properties (Access = private)
        jobs_ = struct([])           % struct array parallel to Results rows; see initJob_
        timer_ = []                  % scheduler timer
        queue_ (1,:) double = []     % pending row indices not yet launched
        cancelRequested_ (1,1) logical = false
        ffmpeg_  (1,1) string = ""
        ffprobe_ (1,1) string = ""
        token_   (1,1) string = ""   % unique tag for this instance's temp/sidecar filenames
        tStart_  = []                % tic() at convert() start, for batch elapsed/ETA
    end

    methods
        files = scan(obj)                          % Recursively find + populate Results
        convert(obj)                                % Start converting pending rows (asynchronous)
        cancel(obj)                                 % Kill owned processes, discard partials, stop
        ok = waitUntilDone(obj, timeoutSec)         % Cooperatively block until the batch finishes
        g = setupGUI(obj, varargin)                 % Open gui.VideoConverterSetup

        function obj = VideoConverter(options)
            % obj = util.VideoConverter(Name=Value,...)
            % Any public property may be set as a name-value pair.
            arguments
                options.?util.VideoConverter
            end
            fn = fieldnames(options);
            for i = 1:numel(fn)
                obj.(fn{i}) = options.(fn{i});
            end

            obj.token_ = extractBefore(string(char(java.util.UUID.randomUUID)), 9);
            obj.Results = util.VideoConverter.emptyResults();

            [ok, exe, probe, msg] = util.VideoConverter.ensureDependencies(obj.FfmpegExe);
            if ~ok
                vprintf(0, 1, 'util.VideoConverter: %s', msg);
            end
            obj.ffmpeg_  = exe;
            obj.ffprobe_ = probe;
        end

        function delete(obj)
            % Ensure owned ffmpeg processes and temp files do not outlive the object.
            try
                obj.cancel();
                obj.stopTimer_();
                obj.cleanupTempFiles_();
            catch
                % object teardown must not throw
            end
        end
    end

    methods (Access = private)
        function buildQueue_(obj)
            % (Re)build the job array from the current Results table and
            % queue every row still marked 'pending'.
            T = obj.Results;
            n = height(T);
            jobs = repmat(obj.initJob_("", ""), max(n,1), 1);
            for k = 1:n
                jobs(k) = obj.initJob_(T.SourceFile(k), T.OutputFile(k));
            end
            if n == 0
                jobs = jobs([]);
            end
            obj.jobs_ = jobs;
            obj.queue_ = find(T.Status == 'pending')';
        end

        function job = initJob_(~, src, dst)
            job = struct( ...
                'src', string(src), 'dst', string(dst), 'part', "", 'args', "", ...
                'durationSec', NaN, 'progFile', "", 'progPos', 0, ...
                'outTimeSec', 0, 'percent', 0, 'fps', NaN, 'speed', NaN, 'eta', NaN, ...
                'proc', [], 'outTask', [], 'errTask', [], ...
                'tStart', [], 'startTime', NaT, 'tEnd', NaT, 'exitCode', NaN, 'message', "");
        end

        function startTimer_(obj)
            obj.stopTimer_();
            obj.timer_ = timer( ...
                'Name', 'util_VideoConverter_scheduler', ...
                'Tag', 'util_VideoConverter', ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', obj.PollPeriod, ...
                'BusyMode', 'drop', ...
                'TimerFcn', @(~,~) obj.onTick_(), ...
                'ErrorFcn', @(~,~) obj.abort_());
            start(obj.timer_);
        end

        function stopTimer_(obj)
            if ~isempty(obj.timer_) && isvalid(obj.timer_)
                try
                    stop(obj.timer_);
                catch
                end
                delete(obj.timer_);
            end
            obj.timer_ = [];
        end

        function onTick_(obj)
            % Scheduler tick: reap/update running jobs, fill free slots up
            % to MaxParallel, report progress, and detect batch completion.
            try
                if obj.cancelRequested_
                    obj.killAll_();
                    obj.finishBatch_('cancelled');
                    return
                end

                for k = obj.runningIdx_()
                    obj.readProgress_(k);
                    obj.syncRow_(k);
                    if obj.jobs_(k).proc.HasExited
                        obj.finalizeJob_(k);
                    end
                end

                while numel(obj.runningIdx_()) < obj.MaxParallel && ~isempty(obj.queue_)
                    k = obj.queue_(1);
                    obj.queue_(1) = [];
                    obj.launchJob_(k);
                end

                obj.emitProgress_('progress', NaN);

                if isempty(obj.queue_) && isempty(obj.runningIdx_())
                    obj.finishBatch_('finished');
                end
            catch ME
                vprintf(0, 1, ME);
                obj.killAll_();
                obj.finishBatch_('finished');
            end
        end

        function abort_(obj)
            vprintf(0, 1, 'util.VideoConverter: scheduler timer error; stopping.');
            try
                obj.killAll_();
            catch
            end
            obj.finishBatch_('finished');
        end

        function finishBatch_(obj, stage)
            obj.stopTimer_();
            obj.IsRunning = false;
            obj.cancelRequested_ = false;
            obj.emitProgress_(stage, NaN);
        end

        function idx = runningIdx_(obj)
            idx = find(obj.Results.Status == 'running')';
        end

        function launchJob_(obj, k)
            job = obj.jobs_(k);

            same = strcmpi(obj.canonicalPath_(job.src), obj.canonicalPath_(job.dst));
            if same && ~obj.DeleteSource
                job.message = "Output would overwrite source; set DeleteSource=true to convert in place, or change NameSuffix/OutputFolder.";
                obj.jobs_(k) = job;
                T = obj.Results; T.Message(k) = job.message; obj.Results = T;
                obj.markStatus_(k, 'failed');
                obj.emitProgress_('jobdone', k);
                return
            end

            job.durationSec = obj.probeDuration_(job.src);
            job.progFile = fullfile(tempdir, sprintf('epsych_vc_%s_%03d.progress', obj.token_, k));
            if isfile(job.progFile)
                delete(job.progFile);
            end

            [d, b, e] = fileparts(job.dst);
            job.part = string(fullfile(d, sprintf('%s.part%s%s', b, obj.token_, e)));
            if isfile(job.part)
                delete(job.part);
            end

            job.args = util.VideoConverter.buildArgs(job.src, job.part, obj.optionStruct_(), ...
                ProgressFile = job.progFile);

            T = obj.Results;
            T.Args(k) = job.args;
            obj.Results = T;

            if obj.DryRun
                obj.jobs_(k) = job;
                obj.markStatus_(k, 'dryrun');
                obj.emitProgress_('jobdone', k);
                return
            end

            if obj.ffmpeg_ == "" || ~isfile(obj.ffmpeg_)
                job.message = "ffmpeg.exe not available.";
                obj.jobs_(k) = job;
                T = obj.Results; T.Message(k) = job.message; obj.Results = T;
                obj.markStatus_(k, 'failed');
                obj.emitProgress_('jobdone', k);
                return
            end

            try
                psi = System.Diagnostics.ProcessStartInfo(char(obj.ffmpeg_), char(job.args));
                psi.UseShellExecute        = false;   % required for redirection
                psi.CreateNoWindow         = true;    % no console flash per job
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError  = true;
                psi.WorkingDirectory       = char(tempdir);  % never depend on / lock pwd
                job.proc = System.Diagnostics.Process.Start(psi);
            catch ME
                vprintf(0, 1, ME);
                job.message = string(ME.message);
                obj.jobs_(k) = job;
                T = obj.Results; T.Message(k) = job.message; obj.Results = T;
                obj.markStatus_(k, 'failed');
                obj.emitProgress_('jobdone', k);
                return
            end

            % Drain both pipes immediately so neither can fill and block
            % ffmpeg forever; HasExited would then never go true.
            job.outTask = job.proc.StandardOutput.ReadToEndAsync();
            job.errTask = job.proc.StandardError.ReadToEndAsync();

            job.tStart = tic;
            job.progPos = 0;
            job.percent = 0;
            job.speed = NaN;
            job.fps = NaN;
            obj.jobs_(k) = job;
            obj.markStatus_(k, 'running');
            vprintf(2, 'util.VideoConverter: launched job %d (PID %d): %s', k, double(job.proc.Id), job.src);
        end

        function readProgress_(obj, k)
            % Tail-read this job's -progress file and update its live
            % percent/fps/speed/eta. out_time_us (and out_time_ms) are
            % BOTH microseconds -- a long-standing ffmpeg misnomer.
            job = obj.jobs_(k);
            if job.progFile == ""
                return
            end
            fid = fopen(job.progFile, 'r');
            if fid < 0
                return   % ffmpeg has not created it yet
            end
            fseek(fid, job.progPos, 'bof');
            txt = fread(fid, inf, '*char')';
            job.progPos = ftell(fid);
            fclose(fid);
            if isempty(txt)
                obj.jobs_(k) = job;
                return
            end

            t = regexp(txt, 'out_time_us=(\d+)', 'tokens');
            if ~isempty(t)
                job.outTimeSec = str2double(t{end}{1}) / 1e6;
            end
            s = regexp(txt, 'speed=\s*([\d.]+)x', 'tokens');
            if ~isempty(s)
                job.speed = str2double(s{end}{1});
            end
            f = regexp(txt, 'fps=\s*([\d.]+)', 'tokens');
            if ~isempty(f)
                job.fps = str2double(f{end}{1});
            end

            if isfinite(job.durationSec) && job.durationSec > 0
                pct = 100 * job.outTimeSec / job.durationSec;
                pct = min(100, max(0, pct));
                job.percent = max(job.percent, pct);   % force monotonic; -ss can momentarily rewind out_time
                if job.speed > 0
                    job.eta = max(0, (job.durationSec - job.outTimeSec) / job.speed);
                end
            else
                job.percent = NaN;   % indeterminate duration: report honestly, do not lie with 0
            end

            obj.jobs_(k) = job;
        end

        function syncRow_(obj, k)
            job = obj.jobs_(k);
            T = obj.Results;
            T.Percent(k) = job.percent;
            if isfinite(job.durationSec)
                T.DurationSec(k) = job.durationSec;
            end
            if ~isempty(job.tStart)
                T.ElapsedSec(k) = toc(job.tStart);
            end
            if ~isnan(job.fps)
                T.Fps(k) = job.fps;
            end
            if ~isnan(job.speed)
                T.Speed(k) = job.speed;
            end
            obj.Results = T;
        end

        function finalizeJob_(obj, k)
            job = obj.jobs_(k);
            code = double(job.proc.ExitCode);   % only safe to read after HasExited
            errTxt = "";
            try
                if ~isempty(job.errTask) && job.errTask.Wait(2000)
                    errTxt = string(char(job.errTask.Result));
                end
            catch
            end
            try
                job.proc.Close();
            catch
            end
            if job.progFile ~= "" && isfile(job.progFile)
                delete(job.progFile);
            end

            ok = (code == 0) && isfile(job.part) && dir(char(job.part)).bytes > 0;
            if ok
                status = obj.commitOutput_(k);   % may re-check overwrite policy -> "skipped"/"failed"
            else
                if isfile(job.part)
                    delete(job.part);
                end
                job.message = obj.firstLines_(errTxt, 3);
                obj.jobs_(k) = job;
                status = "failed";
            end

            job = obj.jobs_(k);   % commitOutput_ may have updated message/BytesOut
            job.exitCode = code;
            job.tEnd = datetime('now');
            if status == "done"
                job.percent = 100;
            end
            obj.jobs_(k) = job;

            T = obj.Results;
            T.ExitCode(k) = code;
            T.EndTime(k) = job.tEnd;
            if job.message ~= ""
                T.Message(k) = job.message;
            end
            obj.Results = T;
            obj.syncRow_(k);
            obj.markStatus_(k, char(status));

            if status == "done" && obj.DeleteSource
                obj.maybeDeleteSource_(k);
            end
            if status == "failed"
                vprintf(0, 1, 'util.VideoConverter: job %d failed (exit %d): %s', k, code, job.message);
            end

            obj.emitProgress_('jobdone', k);
        end

        function status = commitOutput_(obj, k)
            % Rename the verified .part sidecar onto the planned output.
            % Re-checks the overwrite policy here (not just at scan time):
            % a long encode leaves plenty of time for the destination to
            % appear from elsewhere.
            job = obj.jobs_(k);
            dst = job.dst;

            if isfile(dst)
                switch obj.Overwrite
                    case "skip"
                        if isfile(job.part), delete(job.part); end
                        status = "skipped";
                        return
                    case "error"
                        if isfile(job.part), delete(job.part); end
                        job.message = "Output file already exists.";
                        obj.jobs_(k) = job;
                        status = "failed";
                        return
                    case "overwrite"
                        % fall through to forced rename
                end
            end

            [d,~,~] = fileparts(dst);
            if ~isempty(d) && ~isfolder(d)
                mkdir(d);
            end
            try
                movefile(char(job.part), char(dst), 'f');
            catch ME
                vprintf(0, 1, ME);
                job.message = string(ME.message);
                obj.jobs_(k) = job;
                if isfile(job.part), delete(job.part); end
                status = "failed";
                return
            end

            if obj.VerifyBeforeDelete
                durOut = obj.probeDuration_(dst);
                durExp = job.durationSec;
                if isfinite(durOut) && isfinite(durExp) && durExp > 0
                    tol = max(0.5, 0.02 * durExp);
                    if abs(durOut - durExp) > tol
                        vprintf(1, 'util.VideoConverter: job %d output duration %.2fs differs from expected %.2fs (tol %.2fs).', ...
                            k, durOut, durExp, tol);
                    end
                end
            end

            T = obj.Results;
            if isfile(dst)
                info = dir(char(dst));
                T.BytesOut(k) = info.bytes;
            end
            obj.Results = T;
            status = "done";
        end

        function maybeDeleteSource_(obj, k)
            job = obj.jobs_(k);
            if ~isfile(job.dst)
                return   % never delete the source unless the output is confirmed on disk
            end
            try
                delete(job.src);
                vprintf(1, 'util.VideoConverter: deleted source "%s" after successful conversion.', job.src);
            catch ME
                vprintf(0, 1, ME);
            end
        end

        function killAll_(obj)
            for k = obj.runningIdx_()
                job = obj.jobs_(k);
                try
                    if ~isempty(job.proc) && ~job.proc.HasExited
                        job.proc.Kill();
                        job.proc.WaitForExit(3000);
                    end
                catch ME
                    vprintf(2, 'util.VideoConverter: kill job %d: %s', k, ME.message);
                end
                % A killed ffmpeg leaves a truncated, unfinalized file; it
                % must not survive, or Overwrite="skip" on a rerun would
                % mistake it for a completed conversion.
                if job.part ~= "" && isfile(job.part)
                    delete(job.part);
                end
                if job.progFile ~= "" && isfile(job.progFile)
                    delete(job.progFile);
                end
                obj.jobs_(k) = job;
                obj.markStatus_(k, 'cancelled');
            end
            for k = obj.queue_
                obj.markStatus_(k, 'cancelled');
            end
            obj.queue_ = [];
        end

        function emitProgress_(obj, stage, jobIndex)
            T = obj.Results;
            numJobs = height(T);
            if numJobs == 0
                numDone = 0; numFailed = 0; numRunning = 0; overallPct = NaN;
            else
                numDone = nnz(ismember(T.Status, {'done','skipped','dryrun'}));
                numFailed = nnz(T.Status == 'failed');
                numRunning = nnz(T.Status == 'running');
                pcts = double(T.Percent);
                finishedMask = ismember(T.Status, {'done','skipped','dryrun','cancelled'});
                pcts(finishedMask) = 100;
                pcts(isnan(pcts)) = 0;
                w = double(T.DurationSec);
                w(~isfinite(w) | w <= 0) = 1;
                overallPct = sum(w .* min(max(pcts,0),100)) / sum(w);
            end

            elapsed = NaN;
            if ~isempty(obj.tStart_)
                elapsed = toc(obj.tStart_);
            end
            etaSec = NaN;
            if isfinite(overallPct) && overallPct > 0.5 && isfinite(elapsed)
                etaSec = max(0, elapsed / overallPct * 100 - elapsed);
            end

            s = struct('Stage', string(stage), 'JobIndex', NaN, 'NumJobs', numJobs, ...
                'NumDone', numDone, 'NumFailed', numFailed, 'NumRunning', numRunning, ...
                'SourceFile', "", 'OutputFile', "", 'Percent', NaN, 'OverallPercent', overallPct, ...
                'Fps', NaN, 'Speed', NaN, 'ElapsedSeconds', elapsed, 'EtaSeconds', etaSec, ...
                'Status', "", 'Message', "");

            if isfinite(jobIndex) && jobIndex >= 1 && jobIndex <= numJobs
                k = jobIndex;
                s.JobIndex = k;
                s.SourceFile = T.SourceFile(k);
                s.OutputFile = T.OutputFile(k);
                s.Percent = double(T.Percent(k));
                s.Fps = double(T.Fps(k));
                s.Speed = double(T.Speed(k));
                s.Status = string(T.Status(k));
                s.Message = T.Message(k);
            end

            evt = util.ProgressEventData(s);
            try
                notify(obj, 'Progress', evt);
            catch ME
                vprintf(0, 1, ME);
            end
            if ~isempty(obj.ProgressFcn)
                try
                    obj.ProgressFcn(obj, evt);
                catch ME
                    vprintf(0, 1, ME);
                end
            end
        end

        function s = optionStruct_(obj)
            fn = ["Range","Units","FastSearch","InputFrameRate","InputPixelFormat","InputFrameSize", ...
                  "AudioCodec","AacBitRate","Mp3Quality","AudioSampleRate", ...
                  "VideoCodec","OutputFrameRate","PixelFormat","x264Preset","x264Tune","x264Crf","Mpeg4Quality", ...
                  "VideoScale","VideoCrop","VideoFlip","VideoFillColor","ExtraArgs"];
            s = struct();
            for i = 1:numel(fn)
                s.(fn(i)) = obj.(fn(i));
            end
        end

        function d = probeDuration_(obj, f)
            % Lazy duration probe (called at launch, not at scan, so
            % scanning hundreds of files never blocks MATLAB). Cascades
            % ffprobe -> ffmpeginfo (toolbox, if present) -> `ffmpeg -i`
            % stderr parsing, so the class works even if the FFmpeg
            % Toolbox Add-On is entirely absent from the path.
            d = NaN;
            if obj.ffprobe_ ~= ""
                cmd = sprintf('"%s" -v error -show_entries format=duration -of default=nw=1:nk=1 "%s"', obj.ffprobe_, f);
                [st, out] = system(cmd);
                if st == 0
                    v = str2double(strtrim(out));
                    if isfinite(v)
                        d = v;
                    end
                end
            end
            if isnan(d) && exist('ffmpeginfo', 'file') == 2
                try
                    info = ffmpeginfo(char(f));
                    if isfield(info, 'duration') && isfinite(info.duration)
                        d = info.duration;
                    end
                catch ME
                    vprintf(3, ME.message);
                end
            end
            if isnan(d) && obj.ffmpeg_ ~= ""
                [~, out] = system(sprintf('"%s" -hide_banner -i "%s"', obj.ffmpeg_, f));
                t = regexp(out, 'Duration:\s*(\d+):(\d\d):(\d\d\.\d+)', 'tokens', 'once');
                if ~isempty(t)
                    v = str2double(t);
                    d = v(1)*3600 + v(2)*60 + v(3);
                end
            end
        end

        function s = firstLines_(~, txt, n)
            txt = string(txt);
            if strtrim(txt) == ""
                s = "";
                return
            end
            lines = splitlines(strtrim(txt));
            lines = lines(strlength(strtrim(lines)) > 0);
            if isempty(lines)
                s = "";
                return
            end
            n = min(n, numel(lines));
            s = strjoin(lines(1:n), " | ");
        end

        function markStatus_(obj, k, status)
            T = obj.Results;
            T.Status(k) = categorical(string(status), util.VideoConverter.StatusCategories_);
            if strcmp(status, 'running') && isnat(T.StartTime(k))
                T.StartTime(k) = datetime('now');
            end
            obj.Results = T;
        end

        function c = canonicalPath_(~, p)
            try
                c = string(char(java.io.File(char(p)).getCanonicalPath()));
            catch
                c = string(p);
            end
        end

        function cleanupTempFiles_(obj)
            if isempty(obj.jobs_)
                return
            end
            for k = 1:numel(obj.jobs_)
                job = obj.jobs_(k);
                try
                    if isfield(job,'part') && job.part ~= "" && isfile(job.part)
                        delete(job.part);
                    end
                catch
                end
                try
                    if isfield(job,'progFile') && job.progFile ~= "" && isfile(job.progFile)
                        delete(job.progFile);
                    end
                catch
                end
            end
        end
    end

    methods (Static)
        args = buildArgs(src, dst, opts, extra)                     % Compose the ffmpeg command line (pure)
        [ok, exePath, probePath, msg] = ensureDependencies(preferredExe)  % Locate ffmpeg/ffprobe; degrade, do not throw
        exePath = findFfmpegExe(preferredExe)                        % Locate ffmpeg.exe only; "" when not found
        dst = planOutput(src, obj)                                   % Compute the planned output path for src (pure)
        T = emptyResults()                                           % Empty Results table with correct schema
    end

end
