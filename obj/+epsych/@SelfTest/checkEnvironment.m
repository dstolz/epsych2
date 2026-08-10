function results = checkEnvironment(self)
% results = checkEnvironment(self)
% Verify the installation itself: repository metadata, MATLAB path, the
% stimgen submodule and the stimbridge contract over it, working log output,
% and the absence of stale figures or timers left behind by a previous session.
%
% Returns:
%	results	- Result struct array; see epsych.SelfTest.result.
%
% See also: epsych.SelfTest.run
arguments
    self
end

GROUP = "Environment";
results = epsych.SelfTest.result();

% --- A1: repository metadata ------------------------------------------
t = tic;
try
    E = EPsychInfo;
    detail = [ ...
        sprintf("Root: %s", string(E.root)), ...
        sprintf("Tag: %s", string(E.latestTag)), ...
        sprintf("Data format: %s", string(E.DataVersion))];

    if ~isfolder(E.root)
        r = epsych.SelfTest.result("A1_Metadata", GROUP, "Repository metadata", "fail", ...
            sprintf('EPsychInfo reports a root that does not exist: %s', E.root), ...
            Detail = detail, ...
            Remedy = "Re-clone the repository or fix the MATLAB path, then run epsych_startup.");
    elseif isempty(E.latestTag) || strlength(string(E.latestTag)) == 0
        r = epsych.SelfTest.result("A1_Metadata", GROUP, "Repository metadata", "warn", ...
            'Git metadata is unavailable; version reporting will be incomplete.', ...
            Detail = detail, ...
            Remedy = "Ensure git is installed and this is a git working copy, not a downloaded zip.");
    else
        r = epsych.SelfTest.result("A1_Metadata", GROUP, "Repository metadata", "pass", ...
            sprintf('EPsych %s at %s', string(E.latestTag), string(E.root)), ...
            Detail = detail);
    end
catch ME
    r = epsych.SelfTest.result("A1_Metadata", GROUP, "Repository metadata", "fail", ...
        sprintf('EPsychInfo could not be constructed: %s', ME.message), ...
        Remedy = "Run epsych_startup and confirm helpers/@EPsychInfo is on the path.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- A2: path integrity -----------------------------------------------
t = tic;
required = [ ...
    "vprintf", "visenabled", "epsych_path", "epsych_startup", ...
    "eplog.isEnabled", "eplog.Logger", "eplog.sink.TextFile", ...
    "ep_TimerFcn_Start", "ep_TimerFcn_RunTime", "ep_TimerFcn_Stop", "ep_TimerFcn_Error", ...
    "ep_SaveDataFcn", "ep_GenericGUI", ...
    "epsych.RunExpt", "epsych.Protocol", "epsych.Runtime", "epsych.TrialSelector", ...
    "hw.Interface", "hw.DeviceState", "PRGMSTATE", ...
    "stimbridge.RuntimeHost", "stimbridge.InterfaceAdapter", "stimbridge.LogBridge"];

missing = required(arrayfun(@(n) isempty(which(n)), required));
if isempty(missing)
    r = epsych.SelfTest.result("A2_Path", GROUP, "MATLAB path", "pass", ...
        sprintf('All %d required functions and classes resolve.', numel(required)));
else
    r = epsych.SelfTest.result("A2_Path", GROUP, "MATLAB path", "fail", ...
        sprintf('%d of %d required names do not resolve.', numel(missing), numel(required)), ...
        Detail = "Missing: " + missing, ...
        Remedy = "Run epsych_startup from the repository root.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- A3: stimgen submodule --------------------------------------------
t = tic;
stimgenDir = fullfile(epsych_path, 'obj', 'stimgen', '+stimgen');
hasDir   = isfolder(stimgenDir);
hasClass = exist('stimgen.StimType', 'class') == 8;

if ~hasDir
    r = epsych.SelfTest.result("A3_Stimgen", GROUP, "stimgen submodule", "fail", ...
        'The stimgen submodule is not checked out.', ...
        Detail = "Expected: " + string(stimgenDir), ...
        Remedy = "Run: git submodule update --init --recursive");
elseif ~hasClass
    r = epsych.SelfTest.result("A3_Stimgen", GROUP, "stimgen submodule", "fail", ...
        'stimgen is checked out but its classes do not resolve.', ...
        Detail = "Found: " + string(stimgenDir), ...
        Remedy = "Run epsych_startup so obj/stimgen is added to the path.");
else
    % stimgen versions independently, so a contract change there turns the
    % stimbridge classes abstract and every construction fails at runtime
    % with an opaque message. Catch it here instead.
    hasLogSeam = ~isempty(which('stimgen.LogSink'));
    if hasLogSeam
        seamNote = "Log seam: available";
    else
        seamNote = "Log seam: absent from the pinned stimgen";
    end
    detail = [string(stimgenDir), "Commit: " + string(EPsychInfo().stimgenChksum), seamNote];

    unimplemented = [ ...
        localAbstractMethods("stimbridge.RuntimeHost"), ...
        localAbstractMethods("stimbridge.InterfaceAdapter")];
    if hasLogSeam
        % Only reachable when stimgen defines LogSink: naming LogBridge under an
        % older pin would fail to resolve its superclass and raise here.
        unimplemented = [unimplemented, localAbstractMethods("stimbridge.LogBridge")];
    end

    if isempty(unimplemented)
        r = epsych.SelfTest.result("A3_Stimgen", GROUP, "stimgen submodule", "pass", ...
            'stimgen resolves and stimbridge implements its contract.', ...
            Detail = detail);
    else
        r = epsych.SelfTest.result("A3_Stimgen", GROUP, "stimgen submodule", "fail", ...
            'stimgen''s abstract contract changed; stimbridge no longer implements it.', ...
            Detail = [detail, "Unimplemented: " + unimplemented], ...
            Remedy = "Implement the new stimgen.HardwareHost / stimgen.calibration.HwAdapter / " + ...
                "stimgen.LogSink methods in obj/+stimbridge, or pin an earlier stimgen commit.");
    end
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- A4: logging actually reaches disk --------------------------------
% vprintf is how every other check reports itself, so a broken logger would
% silently hollow out this entire report. The probe goes through vprintf
% rather than the sink directly, so it exercises the whole path: gate,
% format, record, sink.
t = tic;
L = eplog.Logger.instance();
fileSink = L.sinkOfType('eplog.sink.FileSink');
logPath = L.LogFile;

sinkNames = string(cellfun(@class, L.Sinks, UniformOutput = false));

if isempty(fileSink)
    r = epsych.SelfTest.result("A4_Logging", GROUP, "Log file writable", "fail", ...
        'The session logger has no file sink, so nothing is written to disk.', ...
        Detail = "Active sinks: " + strjoin(sinkNames, ", "), ...
        Remedy = "Restore the default logger: eplog.Logger.instance('-reset').");
else
    before = localFileBytes(logPath);
    marker = sprintf('selftest-log-probe-%s', char(datetime('now', Format='yyMMdd''T''HHmmss.SSS')));
    vprintf(-1, '%s', marker);
    L.flush();   % the sink buffers; without this the bytes are not on disk yet
    after = localFileBytes(logPath);

    detail = "Active sinks: " + strjoin(sinkNames, ", ");

    if after > before
        r = epsych.SelfTest.result("A4_Logging", GROUP, "Log file writable", "pass", ...
            sprintf('Log grew by %d bytes: %s', after - before, logPath), ...
            Detail = detail);
    elseif fileSink.Failed
        r = epsych.SelfTest.result("A4_Logging", GROUP, "Log file writable", "fail", ...
            sprintf('The file sink latched a failure and disabled itself: %s', logPath), ...
            Detail = detail, ...
            Remedy = "Fix write access to the log directory, then clear the latch " + ...
                "with eplog.Logger.instance().sinkOfType('eplog.sink.FileSink').reset().");
    else
        r = epsych.SelfTest.result("A4_Logging", GROUP, "Log file writable", "fail", ...
            sprintf('Writing to the log did not change its size: %s', logPath), ...
            Detail = [sprintf("Bytes before: %d, after: %d", before, after), detail], ...
            Remedy = "Check write permission on " + string(fileSink.Dir) + ...
                " (set by Customize > Paths > Error Log Path).");
    end
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- A5: stale figures and timers -------------------------------------
t = tic;
figs = findall(groot, 'Type', 'figure', '-and', 'Tag', 'RunExpt');
psychTimers = timerfindall('Name', 'PsychTimer');
boxTimers   = timerfindall('Name', 'BoxTimer');
isRunning = ~isempty(self.RunExpt) && isvalid(self.RunExpt) && self.RunExpt.STATE >= PRGMSTATE.RUNNING;

problems = strings(1,0);
if numel(figs) > 1
    problems(end+1) = sprintf("%d RunExpt windows are open; only one should be.", numel(figs));
end
if ~isRunning && ~isempty(psychTimers)
    problems(end+1) = sprintf("%d PsychTimer object(s) exist outside a run.", numel(psychTimers));
end
if ~isRunning && ~isempty(boxTimers)
    problems(end+1) = sprintf("%d BoxTimer object(s) exist outside a run.", numel(boxTimers));
end

if isempty(problems)
    r = epsych.SelfTest.result("A5_Stale", GROUP, "No stale figures or timers", "pass", ...
        sprintf('%d RunExpt window(s), no orphaned timers.', numel(figs)));
else
    r = epsych.SelfTest.result("A5_Stale", GROUP, "No stale figures or timers", "warn", ...
        'Leftover objects from a previous session were found.', ...
        Detail = problems, ...
        Remedy = "Close the extra windows and run: delete(timerfindall)");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- A6: stimgen logging reaches the session log ----------------------
% A3 proves the seam exists and A4 proves the log file is writable. Neither
% proves a message raised inside stimgen actually arrives, which is the only
% thing that stops an operator having to open a second log after a StimPlayer
% or calibration failure. Probe it end to end, through stimgen's own front door.
t = tic;
stimgenLogDir = fullfile(tempdir, 'stimgen_error_logs');
NAME6 = "stimgen logging";

if isempty(which('stimgen.util.logSink'))
    % A supported configuration: pinning a stimgen from before the log seam.
    % It costs a unified log, not a working session, so warn rather than fail.
    r = epsych.SelfTest.result("A6_StimgenLogging", GROUP, NAME6, "warn", ...
        'The pinned stimgen predates the logging seam, so it logs separately.', ...
        Detail = "stimgen logs to: " + string(stimgenLogDir), ...
        Remedy = "Update the submodule for unified logging: " + ...
            "git submodule update --remote obj/stimgen");
else
    bridge = stimgen.util.logSink();
    if isempty(bridge) || ~isa(bridge, 'stimbridge.LogBridge')
        r = epsych.SelfTest.result("A6_StimgenLogging", GROUP, NAME6, "warn", ...
            'No EPsych log bridge is installed, so stimgen logs separately.', ...
            Detail = "stimgen logs to: " + string(stimgenLogDir), ...
            Remedy = "Run epsych_startup, or install it directly: " + ...
                "stimgen.util.logSink(stimbridge.LogBridge())");
    else
        logPath6 = eplog.Logger.instance().LogFile;
        before6 = localFileBytes(logPath6);
        marker6 = sprintf('selftest-stimgen-probe-%s', ...
            char(datetime('now', Format='yyMMdd''T''HHmmss.SSS')));
        stimgen.util.vprintf(-1, '%s', marker6);
        eplog.Logger.instance().flush();
        after6 = localFileBytes(logPath6);

        if after6 > before6
            r = epsych.SelfTest.result("A6_StimgenLogging", GROUP, NAME6, "pass", ...
                sprintf('stimgen logs into the session log: %s', logPath6), ...
                Detail = "Bridge: " + string(class(bridge)));
        else
            r = epsych.SelfTest.result("A6_StimgenLogging", GROUP, NAME6, "fail", ...
                'A bridge is installed but a stimgen message did not reach the log.', ...
                Detail = [sprintf("Bytes before: %d, after: %d", before6, after6), ...
                          "Log file: " + string(logPath6)], ...
                Remedy = "Reinstall the bridge: " + ...
                    "stimgen.util.logSink(stimbridge.LogBridge())");
        end
    end
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

end

% -----------------------------------------------------------------------
function names = localAbstractMethods(className)
% Abstract methods of className that are still unimplemented, qualified for
% display. A stimbridge class only reports any once stimgen adds a method to
% HardwareHost or HwAdapter that the bridge has not caught up with.
names = strings(1,0);

mc = meta.class.fromName(className);
if isempty(mc) || isempty(mc.MethodList), return; end

isAbstract = [mc.MethodList.Abstract];
if ~any(isAbstract), return; end

names = reshape(className + "." + string({mc.MethodList(isAbstract).Name}), 1, []);
end

% -----------------------------------------------------------------------
function n = localFileBytes(ffn)
% Size of ffn in bytes; 0 when it does not exist.
n = 0;
d = dir(ffn);
if ~isempty(d)
    n = d(1).bytes;
end
end
