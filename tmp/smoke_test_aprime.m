function smoke_test_aprime()
% smoke_test_aprime()
% Exercise the nonparametric sensitivity index A' (Grier 1971) everywhere it
% is now available: the psychophysics.Detection.a_prime arithmetic, the
% per-stimulus-value Detection.APrime property, and the SessionMetrics
% catalogue entry. Headless-safe: no figures are created.
%
%   matlab -batch "run('tmp/smoke_test_aprime.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

A = @psychophysics.Detection.a_prime;
tol = 1e-12;

% 1. Arithmetic ------------------------------------------------------------
assert(abs(A(1,0) - 1) < tol, 'perfect performance should be A'' = 1');
assert(abs(A(0,1) - 0) < tol, 'perfectly reversed performance should be A'' = 0');
assert(abs(A(0.8,0.2) - 0.875) < tol, 'A''(0.8,0.2) should be 0.875');
assert(abs(A(0.2,0.8) - 0.125) < tol, 'A''(0.2,0.8) should be 0.125');

% H == FA is chance whatever the rates are, including where the denominator
% of Grier's formula also vanishes
for r = [0 0.25 0.5 0.75 1]
    assert(abs(A(r,r) - 0.5) < tol, 'A''(%g,%g) should be chance', r, r);
end

% Symmetry about chance: swapping the rates reflects A' through 0.5
grid = 0:0.1:1;
for h = grid
    for f = grid
        a = A(h,f);
        assert(a >= -tol && a <= 1+tol, 'A''(%g,%g) = %g is outside [0 1]', h, f, a);
        assert(abs(a - (1 - A(f,h))) < 1e-12, 'A'' should reflect through 0.5 when rates swap');
        if h > f
            assert(a > 0.5, 'A'' should exceed chance when H > FA');
        elseif h < f
            assert(a < 0.5, 'A'' should fall below chance when H < FA');
        end
    end
end

% Monotone in the hit rate at a fixed false alarm rate
a = A(0:0.05:1, 0.2);
assert(all(diff(a) > 0), 'A'' should increase with the hit rate');

% Rates broadcast, and NaN propagates rather than being invented
assert(isequal(A([0.3 0.6 0.9], 0.2), [A(0.3,0.2) A(0.6,0.2) A(0.9,0.2)]), ...
    'a vector of hit rates should pair with a scalar FA rate');
assert(isequal(A([0.5 0.8],[0.5 0.2]), [0.5 0.875]), ...
    'the H == FA case should be handled element-wise');
assert(isnan(A(NaN,0.2)) && isnan(A(0.8,NaN)), 'an undefined rate should give NaN');
assert(isempty(A([], [])), 'empty rates should give an empty result');

% Independent check: A' estimates the area under the ROC curve, which for
% equal-variance Gaussian evidence is normcdf(d'/sqrt(2))
for d = [0.5 1 2 3]
    h = normcdf(d/2); f = normcdf(-d/2);
    assert(abs(A(h,f) - normcdf(d/sqrt(2))) < 0.03, ...
        'A'' should track the Gaussian ROC area at d'' = %g', d);
end
fprintf('PASS: psychophysics.Detection.a_prime\n');

% 2. SessionMetrics --------------------------------------------------------
% 20 trials: 12 stimulus (8 hit, 3 miss, 1 abort), 8 catch (2 FA, 6 CR)
S = psychophysics.SessionMetrics(fakeData());
assert(abs(S.Results.Rate.Hit - 8/11) < tol && abs(S.Results.Rate.FalseAlarm - 2/8) < tol, ...
    'the fixture should give the expected rates');
assert(abs(S.Results.APrime - A(8/11, 2/8)) < tol, ...
    'Results.APrime should be A'' of the session hit and false alarm rates');

[v, txt] = S.metric("APrime");
assert(abs(v - S.Results.APrime) < tol, 'metric("APrime") should return the computed value');
assert(txt == string(sprintf('%.3f', S.Results.APrime)), 'A'' should display to three decimals');

T = S.summary();
assert(any(T.Name == "APrime"), 'A'' should appear in the summary table');
assert(T.Group(T.Name == "APrime") == "Sensitivity", 'A'' belongs to the Sensitivity group');
assert(ismember("APrime", psychophysics.SessionMetrics.metricNames()), ...
    'A'' should be a named metric');

% A' takes the rates uncorrected, so infCorrection moves d' but not A'
d0 = S.Results.DPrime; a0 = S.Results.APrime;
S.infCorrection = [0.4 0.6];
assert(abs(S.Results.DPrime - d0) > 1e-6, 'infCorrection should change d''');
assert(abs(S.Results.APrime - a0) < tol, 'infCorrection should not touch A''');
S.infCorrection = [0.05 0.95];

% An empty window leaves it undefined rather than at chance
S.TrialWindow = psychophysics.TrialWindow.range(50,60);
assert(isnan(S.Results.APrime), 'an empty window should give an undefined A''');
[~, txt] = S.metric("APrime");
assert(txt == "--", 'an undefined A'' should render as --');
fprintf('PASS: psychophysics.SessionMetrics reports A''\n');

% 3. Detection: A' per unique stimulus value -------------------------------
D = fakeDetection();
assert(isequal(D.uniqueValues, [10 20 30]), 'the fixture should give three stimulus values');
assert(max(abs(D.Hit_Rate - [0.3 0.6 0.9])) < tol, 'hit rates per value');
assert(max(abs(D.FA_Rate - 0.2)) < tol, 'the catch-trial false alarm rate');

expected = A([0.3 0.6 0.9], 0.2);
assert(isequal(size(D.APrime), size(expected)), 'APrime should be a row, one per stimulus value');
assert(max(abs(D.APrime - expected)) < tol, 'APrime should be A'' of each hit rate against the FA rate');
assert(all(diff(D.APrime) > 0), 'A'' should rise with stimulus level in the fixture');
fprintf('PASS: psychophysics.Detection.APrime\n');

% 4. Plot components offer it ----------------------------------------------
assert(ismember('APrime', gui.PsychPlot.ValidPlotTypes), ...
    'gui.PsychPlot should offer APrime as a plot type');
mc = ?gui.SlidingWindowPerformancePlot;
assert(ismember("aPrime", string({mc.PropertyList.Name})), ...
    'gui.SlidingWindowPerformancePlot should accumulate aPrime');
fprintf('PASS: plot components expose A''\n');

fprintf('\nALL PASS: smoke_test_aprime\n');
end


function DATA = fakeData()
% 20 trials: 12 stimulus (8 hit, 3 miss, 1 abort), 8 catch (2 FA, 6 CR).
stim = epsych.BitMask.TrialType_0;
ctch = epsych.BitMask.TrialType_1;
codes = [ ...
    repmat(bit(epsych.BitMask.Hit,  stim), 1, 8), ...
    repmat(bit(epsych.BitMask.Miss, stim), 1, 3), ...
    bit(epsych.BitMask.Abort, stim), ...
    repmat(bit(epsych.BitMask.FalseAlarm,    ctch), 1, 2), ...
    repmat(bit(epsych.BitMask.CorrectReject, ctch), 1, 6)];
types = [zeros(1,12) ones(1,8)];

DATA = struct('RespCode', num2cell(codes), 'TrialType', num2cell(types), ...
    'TrialID', num2cell(1:20));
end


function D = fakeDetection()
% A finished session with three stimulus levels (10 trials each, 3/6/9 hits)
% and 20 catch trials (4 false alarms), fed through the NewData path so the
% decoded bitmasks are populated the way a live session populates them.
stim = epsych.BitMask.TrialType_0;
ctch = epsych.BitMask.TrialType_1;

levels = [10 20 30];
nHit   = [3 6 9];

codes = uint32([]);
vals  = [];
types = [];
for i = 1:numel(levels)
    c = [repmat(bit(epsych.BitMask.Hit, stim), 1, nHit(i)), ...
         repmat(bit(epsych.BitMask.Miss, stim), 1, 10-nHit(i))];
    codes = [codes c];
    vals  = [vals repmat(levels(i), 1, 10)];
    types = [types zeros(1,10)];
end
codes = [codes, repmat(bit(epsych.BitMask.FalseAlarm, ctch), 1, 4), ...
                repmat(bit(epsych.BitMask.CorrectReject, ctch), 1, 16)];
vals  = [vals zeros(1,20)];
types = [types ones(1,20)];

TRIALS.DATA = struct('RespCode', num2cell(codes), 'TrialType', num2cell(types), ...
    'Level', num2cell(vals));
TRIALS.TrialIndex  = numel(codes);
TRIALS.Subject     = struct('Name','TEST');
TRIALS.BoxID       = 1;
TRIALS.writeparams = {'Level'};

RUNTIME.EVENTS = epsych.EventHub;

% Parameter only has to name the DATA field; a struct keeps the fixture free
% of hardware objects
P = struct('Name','Level','validName','Level');

D = psychophysics.Detection(RUNTIME, P, epsych.BitMask.TrialType_0);
D.update_data([], epsych.TrialsData(TRIALS));
end


function m = bit(varargin)
m = uint32(0);
for i = 1:nargin
    m = bitset(m, double(varargin{i}));
end
end
