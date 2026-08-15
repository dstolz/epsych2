function results = checkFunctions(self)
% results = checkFunctions(self)
% Verify every callback name in FUNCS resolves and has the signature the
% runtime will call it with. RunExpt fevals these names without checking, so
% a typo surfaces as a mid-session error.
%
% Returns:
%	results	- Result struct array; see epsych.SelfTest.result.
%
% See also: epsych.SelfTest.run, epsych.RunExpt.OpenCustomizeDialog
arguments
    self
end

GROUP = "Functions";
results = epsych.SelfTest.result();

if isempty(self.RunExpt) || ~isvalid(self.RunExpt)
    results = epsych.SelfTest.result("B0_NoSession", GROUP, "Callback functions", "skip", ...
        'No RunExpt session is open.');
    return
end

F = self.RunExpt.FUNCS;

% --- B1: saving function ----------------------------------------------
% Same contract the project dialog enforces: SaveFcn(RUNTIME), no outputs.
t = tic;
r = localCheckCallable("B1_SavingFcn", GROUP, "Saving function", ...
    localField(F, 'SavingFcn', ''), ...
    ExpectedNargin = 1, ExpectedNargout = 0, ...
    Remedy = "Set a valid saving function on the project (Subjects & Projects > Edit Project > Session Defaults; default: ep_SaveDataFcn), then add its subjects again.");
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- B2: add-subject function -----------------------------------------
% The built-in default is a static method, which `which` cannot resolve
% directly; RunExpt.GetDefaultFuncs special-cases it the same way.
t = tic;
addSubj = string(localField(F, 'AddSubjectFcn', ''));
if addSubj == "epsych.DefaultSubject.open"
    if isempty(which('epsych.DefaultSubject'))
        r = epsych.SelfTest.result("B2_AddSubjectFcn", GROUP, "Add-subject function", "fail", ...
            'The built-in epsych.DefaultSubject class does not resolve.', ...
            Remedy = "Run epsych_startup.");
    else
        r = epsych.SelfTest.result("B2_AddSubjectFcn", GROUP, "Add-subject function", "pass", ...
            'Using the built-in epsych.DefaultSubject.open dialog.');
    end
else
    r = localCheckCallable("B2_AddSubjectFcn", GROUP, "Add-subject function", addSubj, ...
        Remedy = "Set a valid add-subject function in Customize > Customize... (Functions tab).");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- B3: behavior GUI function ---------------------------------------------
t = tic;
behaviorGUI = string(localField(F, 'BehaviorGUI', ''));
if strlength(strtrim(behaviorGUI)) == 0
    r = epsych.SelfTest.result("B3_BehaviorGUI", GROUP, "Behavior GUI function", "info", ...
        'No behavior GUI configured; none will be launched.');
else
    r = localCheckCallable("B3_BehaviorGUI", GROUP, "Behavior GUI function", behaviorGUI, ...
        Remedy = "Set a valid behavior GUI on the project (Subjects & Projects > Edit Project > Session Defaults; default: ep_GenericGUI), or choose (none) to disable.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- B4: timer functions ----------------------------------------------
t = tic;
timerSpecs = { ...
    'Start',   1, 2, 1; ...   % ep_TimerFcn_Start(RUNTIME, CONFIG) -> RUNTIME
    'RunTime', 2, 1, 1; ...
    'Stop',    3, 1, 1; ...
    'Error',   4, 1, 1};

if ~isfield(F, 'TIMERfcn')
    r = epsych.SelfTest.result("B4_TimerFcns", GROUP, "Timer functions", "fail", ...
        'FUNCS has no TIMERfcn struct.', ...
        Remedy = "Reload the configuration, or run rmpref('ep_RunExpt_TIMER') to restore the ep_TimerFcn_* defaults.");
else
    rows = epsych.SelfTest.result();
    for i = 1:size(timerSpecs, 1)
        nm = timerSpecs{i,1};
        rows(end+1) = localCheckCallable("B4_Timer" + nm, GROUP, "Timer function: " + nm, ...
            localField(F.TIMERfcn, nm, ''), ...
            ExpectedNargin = timerSpecs{i,3}, ExpectedNargout = timerSpecs{i,4}, ...
            Remedy = "Reset the timer-function preferences: rmpref('ep_RunExpt_TIMER') restores the ep_TimerFcn_* defaults.");
    end

    % status is a string scalar inside a cell, which strcmp against a char
    % row vector never matches; compare as strings.
    bad = rows(string({rows.status}) ~= "pass");
    if isempty(bad)
        r = epsych.SelfTest.result("B4_TimerFcns", GROUP, "Timer functions", "pass", ...
            'All four timer callbacks resolve with the expected signatures.', ...
            Detail = string({rows.summary}));
    else
        r = epsych.SelfTest.result("B4_TimerFcns", GROUP, "Timer functions", "fail", ...
            sprintf('%d of 4 timer callbacks are unusable.', numel(bad)), ...
            Detail = string({bad.summary}), ...
            Remedy = "Reset the timer-function preferences: rmpref('ep_RunExpt_TIMER') restores the ep_TimerFcn_* defaults.");
    end
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- B5: timer period --------------------------------------------------
t = tic;
period = localField(F, 'TimerPeriod', []);
if isempty(period) || ~isnumeric(period) || ~isscalar(period)
    r = epsych.SelfTest.result("B5_TimerPeriod", GROUP, "Timer period", "fail", ...
        'TimerPeriod is unset or not a numeric scalar.', ...
        Remedy = "Set a period between 0.001 and 1 s on the project (Subjects & Projects > Edit Project > Session Defaults).");
elseif period < 0.001 || period > 1
    r = epsych.SelfTest.result("B5_TimerPeriod", GROUP, "Timer period", "fail", ...
        sprintf('TimerPeriod %.4g s is outside the supported range [0.001, 1].', period), ...
        Remedy = "Set a period between 0.001 and 1 s on the project (Subjects & Projects > Edit Project > Session Defaults).");
elseif period < 0.005
    r = epsych.SelfTest.result("B5_TimerPeriod", GROUP, "Timer period", "warn", ...
        sprintf('TimerPeriod %.4g s is very short and will load the CPU heavily.', period), ...
        Remedy = "Consider 0.01 s unless the paradigm genuinely needs finer resolution.");
else
    r = epsych.SelfTest.result("B5_TimerPeriod", GROUP, "Timer period", "pass", ...
        sprintf('TimerPeriod is %.4g s.', period));
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- B6: in-memory vs persisted preferences ---------------------------
% Drift is informational and now usually expected: a project applies its own
% saving function and behavior GUI to the session without touching the machine's
% preferences. It still explains why a rig behaves differently after loading a
% colleague's configuration.
t = tic;
drift = strings(1,0);
prefSpecs = { ...
    'SavingFcn',     getpref('ep_RunExpt_FUNCS','SavingFcn','ep_SaveDataFcn'); ...
    'AddSubjectFcn', getpref('ep_RunExpt_FUNCS','AddSubjectFcn','epsych.DefaultSubject.open'); ...
    'BehaviorGUI',        getpref('ep_RunExpt_FUNCS','BehaviorGUI','ep_GenericGUI')};

for i = 1:size(prefSpecs, 1)
    inMemory = string(localField(F, prefSpecs{i,1}, ''));
    stored   = string(prefSpecs{i,2});
    if inMemory ~= stored
        drift(end+1) = sprintf("%s: session uses '%s', preference holds '%s'", ...
            prefSpecs{i,1}, inMemory, stored);
    end
end

if isempty(drift)
    r = epsych.SelfTest.result("B6_PrefDrift", GROUP, "Preference consistency", "pass", ...
        'Session callbacks match the stored preferences.');
else
    r = epsych.SelfTest.result("B6_PrefDrift", GROUP, "Preference consistency", "info", ...
        sprintf('%d callback(s) differ from the stored preferences.', numel(drift)), ...
        Detail = drift, ...
        Remedy = "Expected when a project applied its session defaults, or after loading a configuration that carries its own functions.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

end

% -----------------------------------------------------------------------
function r = localCheckCallable(id, group, name, fcnName, opts)
% Resolve a function name and, when requested, verify its arity.
arguments
    id (1,1) string
    group (1,1) string
    name (1,1) string
    fcnName
    opts.ExpectedNargin double = []
    opts.ExpectedNargout double = []
    opts.Remedy (1,1) string = ""
end

fcnName = string(fcnName);
if strlength(strtrim(fcnName)) == 0
    r = epsych.SelfTest.result(id, group, name, "fail", 'No function name is set.', ...
        Remedy = opts.Remedy);
    return
end

located = which(fcnName);
if isempty(located)
    r = epsych.SelfTest.result(id, group, name, "fail", ...
        sprintf('"%s" was not found on the MATLAB path.', fcnName), ...
        Remedy = opts.Remedy);
    return
end

detail = "Resolves to: " + string(located);

% nargin/nargout throw for classes and some builtins; an unverifiable arity
% is not a failure, just unverified.
if ~isempty(opts.ExpectedNargin) || ~isempty(opts.ExpectedNargout)
    try
        nIn  = nargin(fcnName);
        nOut = nargout(fcnName);
    catch
        r = epsych.SelfTest.result(id, group, name, "pass", ...
            sprintf('"%s" resolves; signature could not be inspected.', fcnName), ...
            Detail = detail);
        return
    end

    problems = strings(1,0);
    if ~isempty(opts.ExpectedNargin) && nIn ~= opts.ExpectedNargin
        problems(end+1) = sprintf("expects %d input(s), found %d", opts.ExpectedNargin, nIn);
    end
    if ~isempty(opts.ExpectedNargout) && nOut ~= opts.ExpectedNargout
        problems(end+1) = sprintf("expects %d output(s), found %d", opts.ExpectedNargout, nOut);
    end

    if ~isempty(problems)
        r = epsych.SelfTest.result(id, group, name, "fail", ...
            sprintf('"%s" has the wrong signature: %s.', fcnName, strjoin(problems, '; ')), ...
            Detail = detail, Remedy = opts.Remedy);
        return
    end
end

r = epsych.SelfTest.result(id, group, name, "pass", ...
    sprintf('"%s" resolves with the expected signature.', fcnName), ...
    Detail = detail);
end

% -----------------------------------------------------------------------
function v = localField(s, name, dflt)
% Return s.(name) when present and non-empty, otherwise dflt.
v = dflt;
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end
