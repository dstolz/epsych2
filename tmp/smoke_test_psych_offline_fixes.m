% smoke_test_psych_offline_fixes
% Standing proof of the offline contract of psychophysics.Psych and
% psychophysics.Staircase (2026-10-07), headless:
%   1. A plot call never changes an OFFLINE staircase's analysis settings from
%      remembered right-click choices; an online staircase still restores them.
%   2. Analysis settings recompute when set; refresh_history is not needed.
%   3. Subject / BoxID / Unit label an offline plot, and follow a later change.
%   4. Offline refresh and ExcludedTrials changes broadcast Events.NewData.
%   5. setData replaces an offline analysis's trials and is refused online.
%   6. The base-class changes hold for SessionMetrics too.
%
%   run('tmp/smoke_test_psych_offline_fixes.m')

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if exist('epsych.BitMask', 'class') ~= 8
    run(fullfile(repoRoot, 'epsych_startup.m'));
end

PREF_GROUP = 'epsych2_psychophysics_Staircase';
FIG_TAG = 'SmokeOfflineFixes';
prefName = matlab.lang.makeValidName(sprintf('%s_%s', FIG_TAG, 'Depth'));
hadPref = ispref(PREF_GROUP, prefName);
if hadPref
    oldPref = getpref(PREF_GROUP, prefName);
else
    oldPref = [];
end
cleanup = onCleanup(@() localCleanup(PREF_GROUP, prefName, hadPref, oldPref, FIG_TAG));

results = cell(0, 2);
DATA = localStaircaseData(90, 11);
Son = [];

%% 1. Remembered menu choices: analysis settings restored online only
try
    setpref(PREF_GROUP, prefName, struct('ThresholdFromLastNReversals', 4, ...
        'ThresholdFormula', 'GeometricMean', 'ApplyWeightedCorrection', false, ...
        'ShowSteps', false));

    Soff = psychophysics.Staircase(DATA, 'Depth');
    fOff = uifigure('Visible', 'off', 'Tag', FIG_TAG);
    axOff = uiaxes(uigridlayout(fOff, [1 1]));
    Soff.Plot(axOff);
    results(end+1,:) = check('offline: ThresholdFromLastNReversals untouched by Plot', ...
        Soff.ThresholdFromLastNReversals == 12);
    results(end+1,:) = check('offline: ThresholdFormula untouched by Plot', ...
        Soff.ThresholdFormula == "Mean");
    results(end+1,:) = check('offline: display flag still restored', ~Soff.ShowSteps);

    [rt, P, T] = localStubRuntime(DATA);
    Son = psychophysics.Staircase(rt, P);
    Son.update_data([], epsych.TrialsData(T));
    fOn = uifigure('Visible', 'off', 'Tag', FIG_TAG);
    axOn = uiaxes(uigridlayout(fOn, [1 1]));
    Son.Plot(axOn);
    results(end+1,:) = check('online: remembered reversal count restored', ...
        Son.ThresholdFromLastNReversals == 4);
    results(end+1,:) = check('online: remembered formula restored', ...
        Son.ThresholdFormula == "GeometricMean");
    results(end+1,:) = check('online: restored setting was recomputed', ...
        isfinite(Son.Results.Threshold) && ~isequal(Son.Results.Threshold, Soff.Results.Threshold));
    results(end+1,:) = check('online: title names the runtime subject', ...
        startsWith(string(axOn.Title.String), "smoke [1]"));

    rmpref(PREF_GROUP, prefName);
    delete(Soff); delete(fOff); delete(fOn);
catch ME
    results(end+1,:) = check(['group 1: ' ME.message], false);
end

%% 2. Analysis settings recompute when set
try
    S = psychophysics.Staircase(DATA, 'Depth');
    t0 = S.Results.Threshold;
    S.ThresholdFormula = "GeometricMean";
    t1 = S.Results.Threshold;
    results(end+1,:) = check('ThresholdFormula set alone changes Results.Threshold', ...
        isfinite(t0) && isfinite(t1) && abs(t1 - t0) > 1e-9);

    S.ThresholdFromLastNReversals = 4;
    S.StaircaseDirection = "Up";
    S2 = psychophysics.Staircase(DATA, 'Depth', StaircaseDirection="Up");
    S2.ThresholdFormula = "GeometricMean";
    S2.ThresholdFromLastNReversals = 4;
    S2.refresh_history();
    results(end+1,:) = check('setter path equals the explicit refresh_history path', ...
        isequaln(S.Results, S2.Results));

    store = containers.Map('KeyType', 'char', 'ValueType', 'any');
    store('count') = 0; store('last') = [];
    L = addlistener(S.Events, 'NewData', @(~,evt) localRecord(store, evt));
    S.ThresholdFormula = "GeometricMean";   % the value already held
    results(end+1,:) = check('assigning the value already held is not a change', store('count') == 0);
    S.ThresholdFromLastNReversals = 6;
    results(end+1,:) = check('a changed setting broadcasts NewData once', store('count') == 1);
    S.ApplyWeightedCorrection = true;
    results(end+1,:) = check('ApplyWeightedCorrection set alone fills Results.Weighted', ...
        ~isempty(S.Results.Weighted));
    delete(L); delete(S); delete(S2);
catch ME
    results(end+1,:) = check(['group 2: ' ME.message], false);
end

%% 3. Subject, BoxID and Unit label an offline plot
try
    S = psychophysics.Staircase(DATA, 'Depth');
    f = uifigure('Visible', 'off', 'Tag', FIG_TAG);
    ax = uiaxes(uigridlayout(f, [1 1]));
    S.Plot(ax);
    results(end+1,:) = check('offline title carries no subject by default', ...
        ~contains(string(ax.Title.String), "M01"));
    results(end+1,:) = check('offline y label is the field name alone', ...
        strcmp(char(string(ax.YLabel.String)), 'Depth'));
    S.Subject = "M01";
    S.BoxID = 2;
    S.Unit = "dB";
    results(end+1,:) = check('title starts "M01 [2]" once Subject and BoxID are set', ...
        startsWith(string(ax.Title.String), "M01 [2]"));
    results(end+1,:) = check('y label carries the unit once Unit is set', ...
        strcmp(char(string(ax.YLabel.String)), 'Depth (dB)'));
    S.Unit = "";
    results(end+1,:) = check('clearing Unit drops it from the label', ...
        strcmp(char(string(ax.YLabel.String)), 'Depth'));
    delete(S); delete(f);
catch ME
    results(end+1,:) = check(['group 3: ' ME.message], false);
end

%% 4. Offline refresh and ExcludedTrials changes broadcast NewData
try
    S = psychophysics.Staircase(DATA, 'Depth');
    store = containers.Map('KeyType', 'char', 'ValueType', 'any');
    store('count') = 0; store('last') = [];
    L = addlistener(S.Events, 'NewData', @(~,evt) localRecord(store, evt));
    S.ExcludedTrials = [1 2 3];
    results(end+1,:) = check('ExcludedTrials change broadcasts NewData offline', store('count') == 1);
    evt = store('last');
    results(end+1,:) = check('payload carries the whole DATA array', ...
        isa(evt, 'epsych.TrialsData') && numel(evt.Data.DATA) == numel(DATA));
    results(end+1,:) = check('payload Subject is empty offline', isempty(evt.Subject));
    S.refresh_history();
    results(end+1,:) = check('refresh_history broadcasts NewData offline', store('count') == 2);
    S.ExcludedTrials = [1 2 3];
    results(end+1,:) = check('an unchanged ExcludedTrials does not broadcast', store('count') == 2);
    delete(L); delete(S);
catch ME
    results(end+1,:) = check(['group 4: ' ME.message], false);
end

%% 5. setData replaces an offline analysis's trials; refused online
try
    S = psychophysics.Staircase(DATA, 'Depth');
    S.setData(DATA(1:30));
    S30 = psychophysics.Staircase(DATA(1:30), 'Depth');
    results(end+1,:) = check('setData replaces the trials', S.trialCount == 30);
    results(end+1,:) = check('setData recomputes (equals a fresh object over the same trials)', ...
        isequaln(S.Results, S30.Results));
    results(end+1,:) = check('setData refuses a non-struct', localThrows(@() S.setData(42), ''));
    results(end+1,:) = check('setData is refused on an online staircase', ...
        ~isempty(Son) && localThrows(@() Son.setData(DATA), 'psychophysics:Staircase:OnlineSetData'));
    delete(S); delete(S30);
    if ~isempty(Son), delete(Son); end
catch ME
    results(end+1,:) = check(['group 5: ' ME.message], false);
end

%% 6. The base-class changes hold for SessionMetrics
try
    M = psychophysics.SessionMetrics(DATA);
    store = containers.Map('KeyType', 'char', 'ValueType', 'any');
    store('count') = 0; store('last') = [];
    L = addlistener(M.Events, 'NewData', @(~,evt) localRecord(store, evt));
    M.ExcludedTrials = 1;
    results(end+1,:) = check('SessionMetrics: offline ExcludedTrials change broadcasts', store('count') == 1);
    M.setData(DATA(1:20));
    results(end+1,:) = check('SessionMetrics: setData replaces the trials and recomputes', ...
        M.trialCount == 20 && M.Results.N.Total <= 20 && store('count') == 2);
    delete(L); delete(M);
catch ME
    results(end+1,:) = check(['group 6: ' ME.message], false);
end

%% Summary
fprintf('\n');
nFail = 0;
for k = 1:size(results, 1)
    if results{k,2}
        tag = 'PASS';
    else
        tag = 'FAIL';
        nFail = nFail + 1;
    end
    fprintf('  %s  %s\n', tag, results{k,1});
end
fprintf('smoke_test_psych_offline_fixes: %d checks, %d failed\n', size(results, 1), nFail);
if nFail > 0
    error('smoke_test_psych_offline_fixes:Failed', '%d check(s) failed', nFail);
end

%% ------------------------------------------------------------------------
function row = check(label, tf)
row = {char(label), logical(tf)};
end

function DATA = localStaircaseData(nTrials, seed)
% A 1-up/1-down track on a positive-dB Depth with catch trials and the odd
% abort, shaped like RUNTIME.TRIALS.DATA (TrialType both as a field and as
% the bit the runtime sets in RespCode).
rng(seed);
HIT   = bitset(uint32(0), uint32(epsych.BitMask.Hit));
MISS  = bitset(uint32(0), uint32(epsych.BitMask.Miss));
CR    = bitset(uint32(0), uint32(epsych.BitMask.CorrectReject));
FA    = bitset(uint32(0), uint32(epsych.BitMask.FalseAlarm));
ABORT = bitset(uint32(0), uint32(epsych.BitMask.Abort));
ttBit = uint32(epsych.BitMask.TrialType_0);

depth = 40; trueThr = 20; stepDown = 2; stepUp = 4;
t0 = datetime(2026, 10, 7, 9, 0, 0);
DATA = struct('Depth', cell(1, nTrials), 'RespCode', [], 'TrialType', [], ...
    'TrialIndex', [], 'TrialID', [], 'computerTimestamp', [], 'isTest', []);
for k = 1:nTrials
    if mod(k, 6) == 0
        rc = CR;
        if rand < 0.2, rc = FA; end
        tt = 1;
    elseif rand < 0.04
        rc = ABORT;
        tt = 0;
    else
        tt = 0;
        pHit = 1 / (1 + exp(-0.55 * (depth - trueThr)));
        rc = MISS;
        if rand() < pHit
            rc = HIT;
        end
    end
    DATA(k) = struct('Depth', depth, 'RespCode', bitset(rc, ttBit + tt), 'TrialType', tt, ...
        'TrialIndex', k, 'TrialID', tt + 1, 'computerTimestamp', t0 + seconds(8 * k), ...
        'isTest', false);
    if tt == 0 && rc == HIT
        depth = max(2, depth - stepDown);
    elseif tt == 0 && rc == MISS
        depth = min(60, depth + stepUp);
    end
end
end

function [rt, P, T] = localStubRuntime(DATA)
% The smallest runtime an online Staircase accepts (tmp/smoke_test_detection_respcode.m).
rt = epsych.Runtime;
rt.isTest = true;
rt.ReviewMode = true;      % suppress the one-shot dispatch in set.TRIALS
rt.EVENTS = epsych.EventHub;
iface = hw.Software();
P = iface.Module.add_parameter('Depth', 1);
T = struct('DATA', DATA, 'TrialIndex', numel(DATA), 'Subject', struct('Name', 'smoke'), ...
    'BoxID', 1, 'NextTrialID', 1);
rt.TRIALS = T;
end

function store = localRecord(store, evt)
% The Map is a handle, so the caller's copy sees the change; it is returned
% as well only so the Code Analyzer does not read the assignment as unused.
store('count') = store('count') + 1;
store('last') = evt;
end

function tf = localThrows(fcn, id)
tf = false;
try
    fcn();
catch ME
    tf = isempty(id) || strcmp(ME.identifier, id);
end
end

function localCleanup(group, name, hadPref, oldPref, figTag)
try
    if hadPref
        setpref(group, name, oldPref);
    elseif ispref(group, name)
        rmpref(group, name);
    end
catch
end
try
    delete(findall(groot, 'Type', 'figure', 'Tag', figTag));
catch
end
end
