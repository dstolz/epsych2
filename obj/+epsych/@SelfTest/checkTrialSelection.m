function results = checkTrialSelection(self)
% results = checkTrialSelection(self)
% Resolve each protocol's trial selector and actually drive it: hundreds of
% selections against a compiled trial table, checking that every returned ID
% is in range, that the selection is balanced, and that it is fast enough for
% the trial loop.
%
% A custom selector that throws or returns an out-of-range index otherwise
% only fails once trials are running.
%
% Returns:
%	results	- Result struct array; see epsych.SelfTest.result.
%
% See also: epsych.SelfTest.run, epsych.TrialSelector, ep_TimerFcn_RunTime
arguments
    self
end

GROUP = "TrialSelection";
results = epsych.SelfTest.result();

% ep_TimerFcn_RunTime warns above this; a selector slower than the timer
% period starves the trial loop.
SLOW_SELECT_SEC = 0.25;
MAX_DRAWS = 500;

if isempty(self.RunExpt) || ~isvalid(self.RunExpt)
    results = epsych.SelfTest.result("F0_NoSession", GROUP, "Trial selection", "skip", ...
        'No RunExpt session is open.');
    return
end

CONFIG = self.RunExpt.CONFIG;
nSubjects = numel(CONFIG);
if nSubjects == 0 || ~isfield(CONFIG,'PROTOCOL') || isempty(CONFIG(1).PROTOCOL)
    results = epsych.SelfTest.result("F0_NoConfig", GROUP, "Trial selection", "skip", ...
        'No configuration is loaded.');
    return
end

% --- F1: selector resolves ---------------------------------------------
t = tic;
selectors = cell(1, nSubjects);
snapshots = cell(1, nSubjects);
failures  = strings(1,0);
detail    = strings(1,0);

for i = 1:nSubjects
    nm = localSubjectName(CONFIG(i), i);
    P  = CONFIG(i).PROTOCOL;
    if ~isa(P,'epsych.Protocol') || ~isvalid(P)
        failures(end+1) = nm + ": no valid protocol";
        continue
    end

    trialFunc = P.Options.trialFunc;
    try
        sel = epsych.TrialSelector.create(struct('trialFunc', trialFunc));
    catch ME
        failures(end+1) = sprintf("%s: %s", nm, ME.message);
        continue
    end

    selectors{i} = sel;
    detail(end+1) = sprintf("%s: %s", nm, class(sel));
end

if isempty(failures)
    r = epsych.SelfTest.result("F1_Resolve", GROUP, "Selector resolves", "pass", ...
        sprintf('All %d selector(s) resolve.', nSubjects), ...
        Detail = detail);
else
    r = epsych.SelfTest.result("F1_Resolve", GROUP, "Selector resolves", "fail", ...
        sprintf('%d selector(s) could not be created.', numel(failures)), ...
        Detail = [failures detail], ...
        Remedy = "Set Options.trialFunc to the name of an epsych.TrialSelector subclass on the path, or clear it to use the default.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- F2: dry run --------------------------------------------------------
t = tic;
problems = strings(1,0);
detail   = strings(1,0);
tested   = 0;

for i = 1:nSubjects
    if isempty(selectors{i}), continue, end
    nm = localSubjectName(CONFIG(i), i);

    [snapshot, snapErr] = localBuildSnapshot(CONFIG(i), i);
    if ~isempty(snapErr)
        problems(end+1) = nm + ": " + snapErr;
        continue
    end
    snapshots{i} = snapshot;

    sel = selectors{i};
    nTrials = size(snapshot.trials, 1);

    try
        sel.initialize(snapshot);
    catch ME
        problems(end+1) = sprintf("%s: initialize() threw - %s", nm, ME.message);
        continue
    end

    nDraws = min(MAX_DRAWS, max(nTrials, 5 * nTrials));
    picks = nan(1, nDraws);
    times = nan(1, nDraws);
    threw = '';

    for k = 1:nDraws
        tk = tic;
        try
            picks(k) = sel.selectNext(snapshot);
        catch ME
            threw = ME.message;
            break
        end
        times(k) = toc(tk);
    end

    if ~isempty(threw)
        problems(end+1) = sprintf("%s: selectNext() threw after %d draw(s) - %s", nm, k-1, threw);
        continue
    end

    tested = tested + 1;

    outOfRange = picks(picks < 1 | picks > nTrials | mod(picks,1) ~= 0);
    if ~isempty(outOfRange)
        problems(end+1) = sprintf("%s: %d selection(s) outside 1..%d (e.g. %g)", ...
            nm, numel(outOfRange), nTrials, outOfRange(1));
        continue
    end

    counts   = histcounts(picks, 0.5:1:(nTrials+0.5));
    coverage = 100 * nnz(counts) / nTrials;
    meanSec  = mean(times, 'omitnan');
    maxSec   = max(times, [], 'omitnan');

    detail(end+1) = sprintf("%s (%s): %d draws over %d trials, %.0f%% coverage, counts %d-%d, mean %.4f s, max %.4f s", ...
        nm, class(sel), nDraws, nTrials, coverage, min(counts), max(counts), meanSec, maxSec);

    if maxSec > SLOW_SELECT_SEC
        problems(end+1) = sprintf("%s: a selection took %.3f s (the trial loop warns above %.2f s)", ...
            nm, maxSec, SLOW_SELECT_SEC);
    end
end

if tested == 0 && isempty(problems)
    r = epsych.SelfTest.result("F2_DryRun", GROUP, "Selector dry run", "skip", ...
        'No selector could be exercised.');
elseif isempty(problems)
    r = epsych.SelfTest.result("F2_DryRun", GROUP, "Selector dry run", "pass", ...
        sprintf('%d selector(s) produced only in-range selections.', tested), ...
        Detail = detail);
else
    r = epsych.SelfTest.result("F2_DryRun", GROUP, "Selector dry run", "fail", ...
        sprintf('%d problem(s) while exercising the selector(s).', numel(problems)), ...
        Detail = [problems detail], ...
        Remedy = "Fix selectNext so it always returns an integer row index into TRIALS.trials and returns promptly.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- F3: lifecycle callbacks -------------------------------------------
% onComplete and onRecompile are no-ops on the base class, so a custom
% selector that overrides them is the usual place this breaks.
t = tic;
problems = strings(1,0);
tested   = 0;

for i = 1:nSubjects
    if isempty(selectors{i}) || isempty(snapshots{i}), continue, end
    nm  = localSubjectName(CONFIG(i), i);
    sel = selectors{i};
    snapshot = snapshots{i};
    tested = tested + 1;

    syntheticData = struct( ...
        'TrialIndex', 1, ...
        'TrialID', 1, ...
        'computerTimestamp', datetime('now'), ...
        'isTest', true);

    try
        sel.onComplete(1, syntheticData);
    catch ME
        problems(end+1) = sprintf("%s: onComplete() threw - %s", nm, ME.message);
    end

    try
        sel.setRuntime(epsych.Runtime, i);
    catch ME
        problems(end+1) = sprintf("%s: setRuntime() threw - %s", nm, ME.message);
    end

    try
        sel.onRecompile(snapshot);
    catch ME
        problems(end+1) = sprintf("%s: onRecompile() threw - %s", nm, ME.message);
    end
end

if tested == 0
    r = epsych.SelfTest.result("F3_Lifecycle", GROUP, "Selector lifecycle", "skip", ...
        'No selector could be exercised.');
elseif isempty(problems)
    r = epsych.SelfTest.result("F3_Lifecycle", GROUP, "Selector lifecycle", "pass", ...
        sprintf('onComplete, setRuntime, and onRecompile ran cleanly on %d selector(s).', tested));
else
    r = epsych.SelfTest.result("F3_Lifecycle", GROUP, "Selector lifecycle", "fail", ...
        sprintf('%d lifecycle callback(s) raised an error.', numel(problems)), ...
        Detail = problems, ...
        Remedy = "The runtime calls these after every trial and after an operator recompile; they must not throw.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

end

% -----------------------------------------------------------------------
function nm = localSubjectName(cfg, idx)
% Best available label for one CONFIG entry.
nm = "subject " + idx;
if isfield(cfg,'SUBJECT') && isa(cfg.SUBJECT, 'epsych.Subject') && strlength(string(cfg.SUBJECT.Name)) > 0
    nm = string(cfg.SUBJECT.Name);
end
end

% -----------------------------------------------------------------------
function [snapshot, errMsg] = localBuildSnapshot(cfg, idx)
% Build the TRIALS struct a selector is contractually handed, mirroring
% ep_TimerFcn_Start. Compiles an isolated copy so the live protocol is
% untouched.
snapshot = struct();
errMsg = '';

pfn = string(cfg.protocol_fn);
P = [];
warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
try
    if strlength(pfn) > 0 && isfile(pfn)
        P = epsych.Protocol.load(pfn);
    else
        P = epsych.Protocol();
        P.fromStruct(cfg.PROTOCOL.toStruct());
    end
    P.compile();
catch ME
    errMsg = ME.message;
end
warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

if ~isempty(errMsg), return, end

C = P.COMPILED;
if C.ntrials == 0
    errMsg = 'protocol compiled 0 trials';
    return
end

snapshot.parameters    = C.parameters;
snapshot.trials        = C.trials;
snapshot.writeparams   = C.writeparams;
snapshot.writeParamIdx = struct();
for w = 1:numel(C.writeparams)
    name = char(string(C.writeparams{w}));
    if isvarname(name)
        snapshot.writeParamIdx.(name) = w;
    end
end

snapshot.Subject   = cfg.SUBJECT;
snapshot.BoxID     = 1;
if isa(cfg.SUBJECT, 'epsych.Subject')
    snapshot.BoxID = cfg.SUBJECT.BoxID;
end
snapshot.protocol            = P;
snapshot.DataFilename        = '';
snapshot.FORCE_TRIAL         = false;
snapshot.RECOMPILE_REQUESTED = false;
snapshot.TrialIndex          = 1;
snapshot.NextTrialID         = 1;
end
