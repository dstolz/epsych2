function results = checkEnvironment(self)
% results = checkEnvironment(self)
% Verify the installation itself: repository metadata, MATLAB path, the
% stimgen submodule, working log output, and the absence of stale figures or
% timers left behind by a previous session.
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
    "vprintf", "epsych_path", "epsych_startup", ...
    "ep_TimerFcn_Start", "ep_TimerFcn_RunTime", "ep_TimerFcn_Stop", "ep_TimerFcn_Error", ...
    "ep_SaveDataFcn", "ep_GenericGUI", ...
    "epsych.RunExpt", "epsych.Protocol", "epsych.Runtime", "epsych.TrialSelector", ...
    "hw.Interface", "hw.DeviceState", "PRGMSTATE"];

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

if hasDir && hasClass
    r = epsych.SelfTest.result("A3_Stimgen", GROUP, "stimgen submodule", "pass", ...
        'stimgen is present and its classes resolve.', ...
        Detail = string(stimgenDir));
elseif ~hasDir
    r = epsych.SelfTest.result("A3_Stimgen", GROUP, "stimgen submodule", "fail", ...
        'The stimgen submodule is not checked out.', ...
        Detail = "Expected: " + string(stimgenDir), ...
        Remedy = "Run: git submodule update --init --recursive");
else
    r = epsych.SelfTest.result("A3_Stimgen", GROUP, "stimgen submodule", "fail", ...
        'stimgen is checked out but its classes do not resolve.', ...
        Detail = "Found: " + string(stimgenDir), ...
        Remedy = "Run epsych_startup so obj/stimgen is added to the path.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- A4: logging actually reaches disk --------------------------------
% vprintf is how every other check reports itself, so a broken logger would
% silently hollow out this entire report.
t = tic;
logPath = fullfile(epsych_path, '.error_logs', sprintf('error_log_%s.txt', datestr(now,'ddmmmyyyy')));
before = localFileBytes(logPath);
marker = sprintf('selftest-log-probe-%s', char(datetime('now', Format='yyMMdd''T''HHmmss.SSS')));
vprintf(-1, '%s', marker);
after = localFileBytes(logPath);

if after > before
    r = epsych.SelfTest.result("A4_Logging", GROUP, "Log file writable", "pass", ...
        sprintf('Log grew by %d bytes: %s', after - before, logPath));
else
    r = epsych.SelfTest.result("A4_Logging", GROUP, "Log file writable", "fail", ...
        sprintf('Writing to the log did not change its size: %s', logPath), ...
        Detail = sprintf("Bytes before: %d, after: %d", before, after), ...
        Remedy = "Check write permission on the .error_logs directory under the repository root.");
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
