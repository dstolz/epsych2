function smoke_test_detection
% smoke_test_detection
% Standing proof for psychophysics.Detection after its re-base on
% psychophysics.Psych, and for the displays built over it. Headless; opens
% figures for the component group only.
%
% Verifies:
%   1) per-value counts, rates and indices match a hand count and
%      psychophysics.Metrics.fromCounts; the false-alarm rate pools EVERY
%      catch trial, whatever value it recorded
%   2) reading results changes nothing, in any order
%   3) one stimulus value agrees exactly with psychophysics.SessionMetrics
%   4) every analysis setting recomputes and broadcasts NewData once
%   5) every analysis object has its own Events hub
%   6) an empty value or response code keeps later trials aligned
%   7) trial types from TrialType bits equal trial types from the field; an
%      unlabeled paradigm is analysed as all stimulus trials
%   8) online: BoxID filtering, seeding from the runtime, a field name as
%      Parameter, refresh over a multi-box runtime
%   9) windowed() equals a brute-force recomputation for every trial
%  10) candidateParameters, summary, and the empty / degenerate cases
%  11) the other Psych subclasses still construct and agree
%  12) PsychPlot, SlidingWindowPerformancePlot, Performance and History over
%      a Detection: consistent X/Y for every plot type, before and after the
%      first stimulus trial, and the abscissa switch
%
% Run headless: matlab -batch "run('tmp/smoke_test_detection.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
cleanup = onCleanup(@() close(findall(groot, 'Type', 'figure')));
tol = 1e-12;

% 1. Counts, rates and indices --------------------------------------------
% Three levels, 10 stimulus trials each: hits 3/6/9, aborts 2/1/0, the rest
% misses. 20 catch trials split across TWO recorded values (0 and 5): 4 false
% alarms (3 at value 0, 1 at value 5), 14 correct rejects, 2 aborts.
[D0, truth] = fixture();
D = psychophysics.Detection(D0, "Level");
R = D.Results;
assert(isequal(R.Values, [10 20 30]), 'Values should be the three stimulus levels')
assert(isequal(R.N.Trials, [10 10 10]) && isequal(R.N.Hit, [3 6 9]) ...
    && isequal(R.N.Abort, [2 1 0]) && isequal(R.N.Miss, [5 3 1]), 'per-value counts')
assert(isequal(R.N.Scored, [8 9 10]), 'Scored leaves the aborts out by default')
assert(R.Catch.Trials == 20 && R.Catch.FalseAlarm == 4 && R.Catch.CorrectReject == 14 ...
    && R.Catch.Abort == 2 && R.Catch.Scored == 18, 'pooled catch counts')
assert(abs(R.Rate.FalseAlarm - 4/18) < tol, ...
    'the false-alarm rate must pool every catch trial, not the first catch value')
S = psychophysics.Metrics.fromCounts([3 6 9], [5 3 1], 4, 14, ...
    AbortSignal=[2 1 0], AbortNoise=2, Bounds=[0.05 0.95]);
assert(max(abs(R.Rate.Hit - [3/8 6/9 9/10])) < tol, 'hit rate is over answered trials')
for f = ["DPrime","APrime","Criterion","BPrimePrime"]
    assert(max(abs(R.(f) - S.(f))) < tol, '%s should be psychophysics.Metrics.fromCounts', f)
end
assert(R.NumNoValue == 0 && R.Message == "", 'a clean fixture leaves nothing out')
assert(isequal(R.TrialIndex, 1:truth.n), 'every trial is in the default window')
fprintf('PASS: per-value counts, pooled catch trials, Metrics agreement\n');

% 2. Reading is side-effect free ------------------------------------------
before = D.Results;
names = psychophysics.Detection.metricNames();
for k = numel(names):-1:1
    y = D.metric(names(k));
    assert(numel(y) == numel(D.Results.Values), '%s must line up with Values', names(k))
end
D.summary(); D.windowed(5); D.candidateParameters();
assert(isequaln(D.Results, before), 'reading results must not change them')
assert(D.StimulusTrialType == epsych.BitMask.TrialType_0, 'reading must not move the trial type')
fprintf('PASS: reads change nothing\n');

% 3. One stimulus value equals SessionMetrics ------------------------------
one = D0([D0.Level] ~= 20 & [D0.Level] ~= 30);  % level 10 plus every catch trial
D1 = psychophysics.Detection(one, "Level");
SM = psychophysics.SessionMetrics(one);
assert(isequal(D1.Results.Values, 10), 'the subset should hold one stimulus value')
assert(abs(D1.Results.Rate.Hit - SM.Results.Rate.Hit) < tol ...
    && abs(D1.Results.Rate.FalseAlarm - SM.Results.Rate.FalseAlarm) < tol ...
    && abs(D1.Results.DPrime - SM.Results.DPrime) < tol ...
    && abs(D1.Results.APrime - SM.Results.APrime) < tol ...
    && abs(D1.Results.Criterion - SM.Results.Criterion) < tol, ...
    'one stimulus value must agree with SessionMetrics')
fprintf('PASS: agrees with SessionMetrics on one value\n');

% 4. Settings recompute and broadcast -------------------------------------
D = psychophysics.Detection(D0, "Level");
hits = 0;
L = listener(D.Events, 'NewData', @(~,~) bump());
expectOne = @(label) assert(takeHits() == 1, '%s should broadcast NewData once', label);

D.IncludeAborts = true;   expectOne('IncludeAborts');
assert(isequal(D.Results.N.Scored, [10 10 10]) && abs(D.Results.Rate.FalseAlarm - 4/20) < tol, ...
    'IncludeAborts puts aborts in both denominators')
D.IncludeAborts = false;  expectOne('IncludeAborts back');
d0 = D.Results.DPrime;
D.CorrectionMode = "loglinear"; expectOne('CorrectionMode');
S2 = psychophysics.Metrics.fromCounts([3 6 9], [5 3 1], 4, 14, AbortSignal=[2 1 0], ...
    AbortNoise=2, Correction="loglinear");
assert(max(abs(D.Results.DPrime - S2.DPrime)) < tol && ~isequal(D.Results.DPrime, d0), ...
    'CorrectionMode reaches d''')
D.CorrectionMode = "clamp";     expectOne('CorrectionMode back');
D.infCorrection = [0.01 0.99];  expectOne('infCorrection');
D.infCorrection = [0.05 0.95];  expectOne('infCorrection back');
D.TrialWindow = "last 20";      expectOne('TrialWindow');
assert(isequal(D.Results.TrialIndex, truth.n-19:truth.n) && isempty(D.Results.Values), ...
    'the last 20 trials are all catch trials')
D.TrialWindow = "all";          expectOne('TrialWindow back');
D.ExcludedTrials = 1:10;        expectOne('ExcludedTrials');
assert(isequal(D.Results.Values, [20 30]), 'excluding level 10''s trials removes it')
D.ExcludedTrials = [];          expectOne('ExcludedTrials back');
D.Parameter = "Other";          expectOne('Parameter');
assert(isequal(D.Results.Values, unique([D0([D0.TrialType] == 0).Other])) ...
    && D.Results.Parameter == "Other", 'Parameter regroups by the new field')
D.Parameter = "Level";          expectOne('Parameter back');
D.StimulusTrialType = epsych.BitMask.TrialType_1;
D.CatchTrialType = epsych.BitMask.TrialType_0;
assert(takeHits() == 2, 'swapping the trial types broadcasts once per setting')
assert(isequal(D.Results.Values, [0 5]), 'catch trials grouped by value once they are the stimulus')
delete(L)
fprintf('PASS: every setting recomputes and broadcasts once\n');

% 5. One Events hub per object ---------------------------------------------
Da = psychophysics.Detection(D0, "Level");
Db = psychophysics.Detection(D0, "Level");
Sm = psychophysics.SessionMetrics(D0);
assert(Da.Events ~= Db.Events && Da.Events ~= Sm.Events, ...
    'each analysis object must own its Events hub')
hits = 0;
L = listener(Da.Events, 'NewData', @(~,~) bump());
Db.refresh(); Sm.refresh();
assert(takeHits() == 0, 'another analysis''s refresh must not reach this one''s listeners')
Da.refresh();
assert(takeHits() == 1, 'its own refresh does')
delete(L)
fprintf('PASS: one Events hub per analysis object\n');

% 6. Alignment through empty values and codes ------------------------------
Dg = D0;
Dg(3).Level = [];          % a stimulus trial with no value
Dg(12).RespCode = [];      % a stimulus trial with no response code
Dx = psychophysics.Detection(Dg, "Level");
assert(Dx.Results.NumNoValue == 1, 'the trial with no value is counted as such')
assert(numel(Dx.responseCodes) == truth.n && Dx.responseCodes(12) == 0 ...
    && Dx.responseCodes(13) == D0(13).RespCode, 'an empty code reads 0 and keeps later codes in place')
want = [3 6 9];
want(1) = want(1) - double(bitget(uint32(D0(3).RespCode), uint32(epsych.BitMask.Hit)));
want(2) = want(2) - double(bitget(uint32(D0(12).RespCode), uint32(epsych.BitMask.Hit)));
assert(isequal(Dx.Results.N.Hit, want), 'hits stay on their own trials around the gaps')
fprintf('PASS: empty values and codes keep trials aligned\n');

% 7. Trial types from bits; unlabeled paradigms ----------------------------
Dbits = rmfield(D0, 'TrialType');
Rb = psychophysics.Detection(Dbits, "Level").Results;
assert(isequaln(rmfield(Rb, 'Window'), rmfield(psychophysics.Detection(D0, "Level").Results, 'Window')), ...
    'TrialType bits must give what the TrialType field gives')
Dn = Dbits;
for k = 1:numel(Dn)
    Dn(k).RespCode = bitset(bitset(uint32(Dn(k).RespCode), uint32(epsych.BitMask.TrialType_0), 0), ...
        uint32(epsych.BitMask.TrialType_1), 0);
end
Ru = psychophysics.Detection(Dn, "Level").Results;
assert(isequal(Ru.Values, [0 5 10 20 30]) && Ru.Catch.FalseAlarm == 4, ...
    'an unlabeled paradigm: every trial a stimulus trial, false alarms counted where scored')
fprintf('PASS: trial types from bits; unlabeled paradigms\n');

% 8. Online ---------------------------------------------------------------
rt = epsych.Runtime;
rt.ReviewMode = true;   % keep set.TRIALS from dispatching
rt.EVENTS = epsych.EventHub;
T1 = struct('DATA', D0(1:20), 'TrialIndex', 20, 'Subject', struct('Name', 'M1'), 'BoxID', 1);
T2 = struct('DATA', D0(21:end), 'TrialIndex', truth.n-20, 'Subject', struct('Name', 'M2'), 'BoxID', 2);
rt.TRIALS = [T1 T2];
Don = psychophysics.Detection(rt, "Level", BoxID = 1);  % a field name online
assert(numel(Don.DATA) == 20 && Don.sourceLabel() == "M1 [1]", 'seeded from box 1 at construction')
Dall = psychophysics.Detection(rt, "Level");
assert(isempty(Dall.DATA), 'with two boxes and no BoxID nothing is seeded (ambiguous)')
rt.EVENTS.notify('NewData', epsych.TrialsData(T2));
assert(numel(Don.DATA) == 20, 'box 1''s analysis ignores box 2''s trials')
assert(numel(Dall.DATA) == truth.n-20 && Dall.sourceLabel() == "M2 [2]", ...
    'an analysis with no BoxID follows every box')
Don.BoxID = 2;
assert(numel(Don.DATA) == truth.n-20, 'changing BoxID takes that box''s trials from the runtime')
Dall.refresh();   % a multi-box runtime must not break the broadcast payload
rt1 = epsych.Runtime; rt1.ReviewMode = true; rt1.EVENTS = epsych.EventHub; rt1.TRIALS = T1;
Dp = psychophysics.Detection(rt1, struct('Name', 'Level', 'validName', 'Level'));
assert(numel(Dp.DATA) == 20, 'a single-box runtime seeds with no BoxID')
delete([Don Dall Dp])
fprintf('PASS: online BoxID, seeding, field-name parameter, multi-box refresh\n');

% 9. windowed() equals brute force -----------------------------------------
rs = RandStream('mt19937ar', Seed = 3);   % stimulus and catch trials interleaved
D = psychophysics.Detection(D0(randperm(rs, truth.n)), "Level");
for w = [0 7]
    W = D.windowed(w);
    for t = 1:truth.n
        lo = 1;
        if w > 0, lo = max(1, t - w + 1); end
        B = psychophysics.Detection(D.DATA(lo:t), "Level").Results;
        [isIn, col] = ismember(B.Values, W.Values);
        assert(all(isIn), 'window %d trial %d: a value missing from the curve', w, t)
        assert(max([0 abs(W.HitRate(t, col) - B.Rate.Hit)]) < tol ...
            && max([0 abs(W.DPrime(t, col) - B.DPrime)]) < tol, ...
            'window %d trial %d: curve disagrees with a recomputation', w, t)
        absent = setdiff(1:numel(W.Values), col);
        assert(all(isnan(W.HitRate(t, absent))), 'a value absent from the window has no rate')
        assert(isequaln(W.FARate(t), B.Rate.FalseAlarm), 'window %d trial %d: FA rate', w, t)
    end
end
fprintf('PASS: windowed() equals brute force, cumulative and sliding\n');

% 10. Candidate parameters, summary, degenerate cases ----------------------
D = psychophysics.Detection(D0, "Level");
assert(isequal(sort(D.candidateParameters()), sort(["Level","Other"])), ...
    'candidates are the numeric fields, bookkeeping and text left out')
T = D.summary();
assert(height(T) == 3 && isequal(T.Hits.', [3 6 9]), 'summary has one row per value')
noCatch = psychophysics.Detection(D0([D0.TrialType] == 0), "Level").Results;
assert(isnan(noCatch.Rate.FalseAlarm) && all(isnan(noCatch.DPrime)) && ~any(isnan(noCatch.Rate.Hit)), ...
    'no catch trials: hit rates defined, false-alarm rate and d'' undefined')
noStim = psychophysics.Detection(D0([D0.TrialType] == 1), "Level").Results;
assert(isempty(noStim.Values) && noStim.Message ~= "" && abs(noStim.Rate.FalseAlarm - 4/18) < tol, ...
    'no stimulus trials: no values, a message, the false-alarm rate still defined')
assert(psychophysics.Detection(struct('RespCode', {}, 'TrialType', {}, 'Level', {}), "Level").Results.Message ...
    == "No trials yet.", 'empty DATA says so')
assert(contains(psychophysics.Detection(D0, "Missing").Results.Message, 'no field'), 'a missing field says so')
assert(contains(psychophysics.Detection(D0, []).Results.Message, 'No Parameter'), 'no Parameter says so')
fprintf('PASS: candidates, summary, degenerate cases\n');

% 11. The other Psych subclasses ------------------------------------------
Sx = psychophysics.SessionMetrics(Dg);
assert(Sx.Results.N.Total == truth.n && Sx.Results.N.Hit == nnz(arrayfun(@(d) ...
    ~isempty(d.RespCode) && bitget(uint32(d.RespCode), uint32(epsych.BitMask.Hit)), Dg)), ...
    'SessionMetrics counts stay aligned around an empty response code')
st = psychophysics.Staircase(D0, "Level");
assert(isa(st, 'psychophysics.Psych') && st.Events ~= Sx.Events, 'Staircase constructs with its own hub')
fprintf('PASS: other Psych subclasses unaffected\n');

% 12. Displays over a Detection --------------------------------------------
fig = figure('Visible', 'off');
early = D0([D0.TrialType] == 1);                       % catch trials only: no value yet
Dd = psychophysics.Detection(early(1:5), "Level");
pp = gui.components.PsychPlot(Dd, axes(fig));
for pt = string(gui.components.PsychPlot.ValidPlotTypes)
    pp.PlotType = char(pt);
    pp.update_plot();
    assert(all(isnan(pp.LineH.XData)) || isempty(pp.LineH.XData), 'no stimulus value yet: nothing drawn (%s)', pt)
end
Dd.setData(D0);
for pt = string(gui.components.PsychPlot.ValidPlotTypes)
    pp.PlotType = char(pt);
    pp.update_plot();
    assert(numel(pp.LineH.XData) == 3 && numel(pp.LineH.YData) == 3, '%s: X and Y must match', pt)
    assert(isequaln(pp.LineH.YData, Dd.metric(pt)), '%s: the plot must show the analysis', pt)
end
pp.PlotType = 'APrime';
ref = findall(pp.ax, 'Tag', 'reference');   % findall sees HandleVisibility 'off'
assert(isscalar(ref) && isequal(ref.YData, [0.5 0.5]), ...
    'the reference line moves to chance (0.5) for A''')
Dd.Parameter = "Other";
assert(strcmp(pp.ax.XLabel.String, 'Other'), 'the x label follows the analysed field')
Dd.Parameter = "Level";

clf(fig);
sw = gui.components.SlidingWindowPerformancePlot(Dd, axes(fig));
for pt = ["HitRate","FARate","DPrime","APrime","Criterion"]
    sw.plotType = pt;
    ln = findobj(sw.hAxes, 'Type', 'line', '-not', 'Tag', 'reference');
    assert(~isempty(ln) && all(arrayfun(@(h) numel(h.XData) == numel(Dd.DATA), ln)), ...
        '%s: one point per trial on every line', pt)
    assert(any(arrayfun(@(h) any(isfinite(h.YData)), ln)), '%s: something finite is drawn', pt)
end
for k = 1:30, Dd.refresh(); end   % many redraws
assert(isscalar(findall(sw.hAxes, 'Tag', 'reference')), ...
    'redraws must move one reference line, not add another each time')
sw.windowSize = 10;
W = Dd.windowed(10);
ln = findobj(sw.hAxes, 'Type', 'line', '-not', 'Tag', 'reference');
assert(any(arrayfun(@(h) isequaln(h.YData(:), W.Criterion(:, 1)), ln)), ...
    'changing windowSize redraws from the windowed curve')

clf(fig);
pf = gui.components.Performance(Dd, uipanel(fig));
assert(size(pf.TableH.Data, 1) == 3, 'Performance shows one row per stimulus value')

uf = uifigure('Visible', 'off');
h = gui.components.History(Dd, uf);
Dd.refresh();
drawnow
assert(numel(h.Info.ResponseBit) == numel(Dd.DATA), 'History labels every trial of a Detection')
delete(uf)

% On a hidden tab the plots defer their redraws until the tab is shown.
uf = uifigure('Visible', 'off');
tg = uitabgroup(uf);
uitab(tg, 'Title', 'shown');
hiddenTab = uitab(tg, 'Title', 'hidden');
Dh = psychophysics.Detection(early(1:5), "Level");
ph = gui.components.PsychPlot(Dh, axes(hiddenTab));
sh = gui.components.SlidingWindowPerformancePlot(Dh, axes(hiddenTab));
Dh.setData(D0);
assert(isempty(ph.LineH) || all(isnan(ph.LineH.XData)), 'a PsychPlot on a hidden tab defers its redraw')
assert(isempty(sh.Curves), 'a sliding-window plot on a hidden tab defers its update')
tg.SelectedTab = hiddenTab;
drawnow
assert(numel(ph.LineH.XData) == 3 && numel(sh.Curves.TrialIndex) == numel(D0), ...
    'showing the tab draws what was deferred')
delete(uf)
fprintf('PASS: PsychPlot, SlidingWindowPerformancePlot, Performance, History over a Detection\n');

fprintf('\nsmoke_test_detection: ALL PASS\n');

    function bump()
        hits = hits + 1;
    end

    function n = takeHits()
        n = hits;
        hits = 0;
    end
end


function [DATA, truth] = fixture()
% 30 stimulus trials over levels 10/20/30 (hits 3/6/9, aborts 2/1/0), then 20
% catch trials, 10 recording Level 0 and 10 recording Level 5 (false alarms
% 3 and 1, aborts 1 and 1). Other is a second numeric field; Note is text.
stim = epsych.BitMask.TrialType_0;
ctch = epsych.BitMask.TrialType_1;
nHit = [3 6 9]; nAbort = [2 1 0];
lv = [10 20 30];
catchVal = [0 5]; nFA = [3 1];
blocks = cell(1, 5);          % one block of 10 trials per level / catch value
for i = 1:3
    nMiss = 10 - nHit(i) - nAbort(i);
    blocks{i} = [repmat(bit(epsych.BitMask.Hit, stim), 1, nHit(i)), ...
        repmat(bit(epsych.BitMask.Miss, stim), 1, nMiss), ...
        repmat(bit(epsych.BitMask.Abort, stim), 1, nAbort(i))];
end
for i = 1:2
    blocks{3+i} = [repmat(bit(epsych.BitMask.FalseAlarm, ctch), 1, nFA(i)), ...
        repmat(bit(epsych.BitMask.CorrectReject, ctch), 1, 9 - nFA(i)), ...
        bit(epsych.BitMask.Abort, ctch)];
end
codes  = [blocks{:}];
levels = repelem([lv catchVal], 10);
types  = repelem([0 0 0 1 1], 10);
n = numel(codes);
other = mod(levels, 7) + 100;
DATA = struct('RespCode', num2cell(double(codes)), 'TrialType', num2cell(types), ...
    'Level', num2cell(levels), 'Other', num2cell(other), 'Note', {'x'}, ...
    'TrialIndex', num2cell(1:n), 'TrialID', num2cell(1 + types), ...
    'computerTimestamp', num2cell(datetime(2026,1,1) + seconds(1:n)));
truth.n = n;
end


function m = bit(varargin)
m = uint32(0);
for i = 1:nargin
    m = bitset(m, double(varargin{i}));
end
end
