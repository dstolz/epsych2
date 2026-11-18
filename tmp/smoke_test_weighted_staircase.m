% smoke_test_weighted_staircase
% Standing proof for psychophysics.Staircase's weighted-staircase threshold
% (Hoover 2025): weightedThreshold, correctedReversalMean, and the
% ApplyWeightedCorrection route into Results.Threshold.
%
% Headless -- no figure and no hardware. Run it
% after any change to the weighted threshold:
%
%   run(fullfile(epsychRoot,'tmp','smoke_test_weighted_staircase.m'))
%
% The groups, and what each one is guarding:
%   1  the correction, exactly: x_R + (delta_- - delta_+)/4, and 0 when
%      the steps are symmetric
%   2  direction invariance: a mirrored track gives a mirrored threshold
%      and the same target, and StaircaseDirection changes nothing
%   3  psi and r against the paper's own step ratios
%   4  the balance rule: equal ascending and descending, most recent kept
%   5  every refusal, by its message; a refusal has the success fields;
%      a size mismatch throws
%   6  inconsistent steps are flagged, not refused -- inferred and field
%   7  ExpectedTarget is an assertion: a mismatch never moves the threshold
%   8  the three step sources, and a coarse-then-fine track reporting the
%      fine steps
%   9  ApplyWeightedCorrection: off changes nothing, on routes the threshold,
%      a refusal is NaN, and the pop-out copies the settings
%  10  the bias it exists to remove, by Monte Carlo against a Gaussian PF
%  11  no data and too little data: every short, empty, or malformed
%      session answers with a refusal naming its cause, through the method
%      and through the per-trial flag path, and never throws

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot);
if exist('epsych_startup','file') == 2
    epsych_startup;
end

nFail = 0;
nPass = 0;

fprintf('\n=== psychophysics.Staircase weighted threshold ===\n');

%% ---- 1. the correction, exactly -----------------------------------------
fprintf('\n-- 1. the correction --\n');
rv  = [-18 -22 -19 -23 -20 -24 -19 -23];
asc = logical([1 0 1 0 1 0 1 0]);
T = psychophysics.Staircase.correctedReversalMean(rv, asc, -2, 6);
[nPass,nFail] = check(nPass, nFail, T.Valid && T.ReversalMean == mean(rv), ...
    sprintf('ReversalMean is the plain mean of a balanced set (%.4f)', T.ReversalMean));
[nPass,nFail] = check(nPass, nFail, T.Correction == (2 - 6)/4 && T.Threshold == T.ReversalMean + (2 - 6)/4, ...
    sprintf('Threshold = x_R + (delta_- - delta_+)/4 exactly (%.4f)', T.Threshold));
[nPass,nFail] = check(nPass, nFail, T.StepDown == 2 && T.StepUp == 6, ...
    'StepDown and StepUp are the paper''s delta_- and delta_+');
[nPass,nFail] = check(nPass, nFail, T.ReversalStd == std(rv), ...
    'ReversalStd is the std of the reversals used');

Tsym = psychophysics.Staircase.correctedReversalMean(rv, asc, -2, 2);
[nPass,nFail] = check(nPass, nFail, Tsym.Correction == 0 && Tsym.Threshold == Tsym.ReversalMean ...
    && Tsym.TargetProbability == 0.5, ...
    'a symmetric staircase: no correction, psi = 0.5');

%% ---- 2. direction invariance ---------------------------------------------
fprintf('\n-- 2. direction invariance --\n');
Tm = psychophysics.Staircase.correctedReversalMean(-rv, ~asc, 2, -6);
[nPass,nFail] = check(nPass, nFail, Tm.Threshold == -T.Threshold, ...
    sprintf('mirrored track, mirrored threshold (%.4f vs %.4f)', Tm.Threshold, T.Threshold));
[nPass,nFail] = check(nPass, nFail, Tm.TargetProbability == T.TargetProbability && Tm.StepRatio == T.StepRatio, ...
    'and the same target and step ratio');

% Through a session: the same responses on a mirrored axis.
rng(20260911);
D  = simulateWeightedTrack(-18, 4.3, -2, 6, 160, Increasing=true, Start=-8);
Dm = D;
mir = num2cell(-[D.Depth]);
[Dm.Depth] = mir{:};
Sx = psychophysics.Staircase(D, 'Depth');
Su = psychophysics.Staircase(Dm, 'Depth');
Tx = Sx.weightedThreshold();
Tu = Su.weightedThreshold();
[nPass,nFail] = check(nPass, nFail, Tx.Valid && Tu.Valid && abs(Tu.Threshold + Tx.Threshold) < 1e-12, ...
    sprintf('a mirrored session mirrors the inferred-step threshold (%.4f vs %.4f)', Tu.Threshold, Tx.Threshold));
[nPass,nFail] = check(nPass, nFail, Tu.TargetProbability == Tx.TargetProbability ...
    && Tu.StepAfterYes == -Tx.StepAfterYes && Tu.StepAfterNo == -Tx.StepAfterNo, ...
    'with mirrored signed steps and the same target');

Sup = psychophysics.Staircase(D, 'Depth', StaircaseDirection="Up");
Tup = Sup.weightedThreshold();
[nPass,nFail] = check(nPass, nFail, Tup.Threshold == Tx.Threshold && isequal(Tup.ReversalUsed, Tx.ReversalUsed) ...
    && Tup.NumAscending == Tx.NumAscending, ...
    'StaircaseDirection="Up" changes the plot convention, not the threshold');
delete(Sx); delete(Su); delete(Sup);

%% ---- 3. psi and r ---------------------------------------------------------
fprintf('\n-- 3. target probability --\n');
ratios = [3 4 1/(1+3/4); 2 1 1/3; 1 40 40/41];
for k = 1:size(ratios,1)
    Tr = psychophysics.Staircase.correctedReversalMean(rv, asc, -ratios(k,1), ratios(k,2));
    [nPass,nFail] = check(nPass, nFail, abs(Tr.StepRatio - ratios(k,1)/ratios(k,2)) < 1e-12 ...
        && abs(Tr.TargetProbability - ratios(k,3)) < 1e-12, ...
        sprintf('r = %g/%g targets psi = %.3f', ratios(k,1), ratios(k,2), Tr.TargetProbability));
end

%% ---- 4. balance ------------------------------------------------------------
fprintf('\n-- 4. balance --\n');
Tb = psychophysics.Staircase.correctedReversalMean(1:7, logical([1 1 1 0 1 0 0]), -1, 3);
[nPass,nFail] = check(nPass, nFail, isequal(Tb.ReversalUsed, logical([0 1 1 1 1 1 1])) ...
    && Tb.NumAscending == 3 && Tb.NumDescending == 3, ...
    'four ascending, three descending: the oldest surplus ascending is dropped');
[nPass,nFail] = check(nPass, nFail, Tb.ReversalMean == mean(2:7), ...
    'and the mean is of the six kept');

To = psychophysics.Staircase.correctedReversalMean(1:8, logical([1 0 1 0 1 0 1 0]), -1, 3, NumReversals=5);
[nPass,nFail] = check(nPass, nFail, isequal(find(To.ReversalUsed), 5:8) && To.NumReversals == 4, ...
    'an odd NumReversals drops the oldest of the last N');

Tn = psychophysics.Staircase.correctedReversalMean([1 2 NaN 4 5 6], logical([1 0 1 0 1 0]), -1, 3);
[nPass,nFail] = check(nPass, nFail, Tn.NumUndefinedReversals == 1 && ~Tn.ReversalUsed(3) ...
    && Tn.NumAscending == Tn.NumDescending && isfinite(Tn.Threshold), ...
    sprintf('a NaN reversal is dropped and the rest rebalanced (%d+%d)', Tn.NumAscending, Tn.NumDescending));

%% ---- 5. refusals -----------------------------------------------------------
fprintf('\n-- 5. refusals --\n');
TRK = struct('Depth', num2cell([-4 -8 -12 -8 -12 -8 -4 -8]), 'TrialType', num2cell(zeros(1,8)));
Snc = psychophysics.Staircase(TRK, 'Depth');     % reversals, but no response codes
Sd  = psychophysics.Staircase(D, 'Depth');
refusals = { ...
    'zero',            psychophysics.Staircase.correctedReversalMean(rv, asc, 0, 6); ...
    'not finite',      psychophysics.Staircase.correctedReversalMean(rv, asc, -2, NaN); ...
    'same sign',       psychophysics.Staircase.correctedReversalMean(rv, asc, -2, -6); ...
    'no reversals',    psychophysics.Staircase.correctedReversalMean([], [], -2, 6); ...
    'one direction',   psychophysics.Staircase.correctedReversalMean([1 2 3], true(1,3), -2, 6); ...
    'no response code', Snc.weightedThreshold(); ...
    'has no field',    Sd.weightedThreshold(StepFieldYes='NoSuchField')};
for k = 1:size(refusals,1)
    Tf = refusals{k,2};
    ok = ~Tf.Valid && isnan(Tf.Threshold) && contains(Tf.Message, refusals{k,1});
    [nPass,nFail] = check(nPass, nFail, ok, sprintf('refused with "%s": %s', refusals{k,1}, Tf.Message));
end

[nPass,nFail] = check(nPass, nFail, isequal(fieldnames(refusals{1,2}), fieldnames(T)) ...
    && isequal(fieldnames(refusals{6,2}), fieldnames(T)), ...
    'a refusal has exactly the fields a threshold has, in the same order');

Tstated = Snc.weightedThreshold(StepAfterYes=-4, StepAfterNo=4);
[nPass,nFail] = check(nPass, nFail, Tstated.Valid && Tstated.StepSource == "stated", ...
    'with no response codes, stated steps still give a threshold');
delete(Snc); delete(Sd);

threw = false;
try
    psychophysics.Staircase.correctedReversalMean([1 2 3], [true false], -2, 6);
catch ME
    threw = strcmp(ME.identifier, 'psychophysics:Staircase:WeightedSizeMismatch');
end
[nPass,nFail] = check(nPass, nFail, threw, 'mismatched reversal vectors throw rather than refuse');

%% ---- 6. inconsistency is flagged, not refused -----------------------------
fprintf('\n-- 6. inconsistent steps --\n');
rng(7);
% The step after a yes changes from -2 to -1.5 half way through, and every
% reversal is used, so both values are well represented whatever the seed.
schedule = @(k) [-2 + 0.5*(k > 90), 6];
Dc = simulateWeightedTrack(-18, 4.3, -2, 6, 180, Increasing=true, Start=-8, Schedule=schedule);
Sc = psychophysics.Staircase(Dc, 'Depth');
Sc.ThresholdFromLastNReversals = 1000;   % the seam's NumReversals default follows it
Tc = Sc.weightedThreshold();
[nPass,nFail] = check(nPass, nFail, Tc.Valid && isfinite(Tc.Threshold) && ~Tc.StepsConsistent, ...
    'a step changed mid-window still gives a threshold, flagged inconsistent');
[nPass,nFail] = check(nPass, nFail, Tc.StepConsistency(1) < 0.9 && Tc.StepConsistency(2) == 1, ...
    sprintf('StepConsistency names the side that changed [%.2f %.2f]', Tc.StepConsistency));
[nPass,nFail] = check(nPass, nFail, contains(Tc.Message, '-2 (') && contains(Tc.Message, '-1.5 ('), ...
    sprintf('the message names the values seen: %s', Tc.Message));

Tcf = Sc.weightedThreshold(StepFieldYes='Depth_StepOnHit', StepFieldNo='Depth_StepOnMiss');
[nPass,nFail] = check(nPass, nFail, Tcf.Valid && ~Tcf.StepsConsistent && Tcf.StepSource == "field" ...
    && Tcf.StepConsistency(1) < 1, ...
    'an operator editing the step is visible through the DATA field too');
delete(Sc);

% A clamp at a parameter bound makes some steps short, but cannot drag the
% nominal step the way a mean would.
rng(11);
Dk = simulateWeightedTrack(-18, 4.3, -2, 6, 200, Increasing=true, Start=-8, Bounds=[-40 -10]);
Sk = psychophysics.Staircase(Dk, 'Depth');
Tk = Sk.weightedThreshold(NumReversals=Inf);
[nPass,nFail] = check(nPass, nFail, Tk.StepAfterYes == -2 && Tk.StepAfterNo == 6, ...
    sprintf('clamped steps do not move the nominal step (%g, %g; consistency [%.2f %.2f])', ...
    Tk.StepAfterYes, Tk.StepAfterNo, Tk.StepConsistency));
delete(Sk);

%% ---- 7. ExpectedTarget -----------------------------------------------------
fprintf('\n-- 7. ExpectedTarget --\n');
Te = psychophysics.Staircase.correctedReversalMean(rv, asc, -2, 6, ExpectedTarget=0.75);
Tw = psychophysics.Staircase.correctedReversalMean(rv, asc, -2, 6, ExpectedTarget=0.25);
[nPass,nFail] = check(nPass, nFail, Te.TargetMatchesExpected && Te.Message == "", ...
    'a matching target is silent');
[nPass,nFail] = check(nPass, nFail, ~Tw.TargetMatchesExpected && Tw.Valid && contains(Tw.Message, 'swapped'), ...
    sprintf('an inverted ratio is caught and named: %s', Tw.Message));
[nPass,nFail] = check(nPass, nFail, Tw.Threshold == Te.Threshold && Te.Threshold == T.Threshold, ...
    'and the threshold is the same either way');
Tnone = psychophysics.Staircase.correctedReversalMean(rv, asc, -2, 6);
[nPass,nFail] = check(nPass, nFail, isnan(Tnone.ExpectedTarget) && Tnone.TargetMatchesExpected, ...
    'no ExpectedTarget: nothing to contradict');

%% ---- 8. the three step sources --------------------------------------------
fprintf('\n-- 8. step sources --\n');
rng(20260912);
D8 = simulateWeightedTrack(-18, 4.3, -2, 6, 200, Increasing=true, Start=-8, CatchEvery=6, AbortRate=0.04);
S8 = psychophysics.Staircase(D8, 'Depth');

Ti = S8.weightedThreshold();
[nPass,nFail] = check(nPass, nFail, Ti.Valid && Ti.StepSource == "inferred" ...
    && Ti.StepAfterYes == -2 && Ti.StepAfterNo == 6 && Ti.StepsConsistent, ...
    sprintf('inference recovers the simulated steps through catch trials and aborts (%g, %g)', ...
    Ti.StepAfterYes, Ti.StepAfterNo));
[nPass,nFail] = check(nPass, nFail, abs(Ti.TargetProbability - 0.75) < 1e-12 && Ti.Correction == -1, ...
    'and so targets 0.75 with a -1 dB correction');
[nPass,nFail] = check(nPass, nFail, Ti.NumStepsYes > 0 && Ti.NumStepsNo > 0 ...
    && Ti.NumStepsYes + Ti.NumStepsNo <= numel(S8.Results.StimulusTrialIdx), ...
    sprintf('the samples examined are counted (%d yes, %d no)', Ti.NumStepsYes, Ti.NumStepsNo));

Tfd = S8.weightedThreshold(StepFieldYes='Depth_StepOnHit', StepFieldNo='Depth_StepOnMiss');
[nPass,nFail] = check(nPass, nFail, Tfd.Valid && Tfd.StepSource == "field" ...
    && Tfd.StepAfterYes == -2 && Tfd.StepAfterNo == 6 && Tfd.Threshold == Ti.Threshold, ...
    'the DATA fields give the same steps, read exactly');

Tst = S8.weightedThreshold(StepAfterYes=-3, StepAfterNo=5, StepFieldYes='Depth_StepOnHit');
[nPass,nFail] = check(nPass, nFail, Tst.StepSource == "stated" && Tst.StepAfterYes == -3 ...
    && Tst.StepAfterNo == 5 && isnan(Tst.StepConsistency(1)) && Tst.NumStepsYes == 0, ...
    'stated steps override a field and inference, and are not measured');

Tmix = S8.weightedThreshold(StepAfterYes=-2);
[nPass,nFail] = check(nPass, nFail, Tmix.StepSource == "stated/inferred" && Tmix.StepAfterNo == 6, ...
    sprintf('one side stated, the other found: StepSource "%s"', Tmix.StepSource));

[nPass,nFail] = check(nPass, nFail, Ti.ReversalMean == mean(S8.stimulusValues(Ti.ReversalIdx(Ti.ReversalUsed))) ...
    && Ti.NumReversals <= S8.ThresholdFromLastNReversals, ...
    'the reversals used are the staircase''s own, at most ThresholdFromLastNReversals');

resultsBefore = S8.Results;
S8.weightedThreshold();
[nPass,nFail] = check(nPass, nFail, isequaln(resultsBefore, S8.Results), ...
    'weightedThreshold stores nothing on the staircase');
delete(S8);

% Coarse steps to find the neighbourhood, then fine ones: the threshold
% comes from the final reversals, so the steps must too.
rng(99);
coarseFine = @(k) [-4 12]*(k <= 40) + [-1 3]*(k > 40);
Dcf = simulateWeightedTrack(-18, 4.3, -4, 12, 260, Increasing=true, Start=-4, Schedule=coarseFine);
Scf = psychophysics.Staircase(Dcf, 'Depth');
Tcf2 = Scf.weightedThreshold();
[nPass,nFail] = check(nPass, nFail, Tcf2.Valid && Tcf2.StepAfterYes == -1 && Tcf2.StepAfterNo == 3, ...
    sprintf('a coarse-then-fine track reports the fine steps (%g, %g)', Tcf2.StepAfterYes, Tcf2.StepAfterNo));
TcfAll = Scf.weightedThreshold(NumReversals=Inf);
[nPass,nFail] = check(nPass, nFail, ~TcfAll.StepsConsistent, ...
    'and says so when asked to use every reversal, coarse ones included');
delete(Scf);

%% ---- 9. ApplyWeightedCorrection -------------------------------------------
fprintf('\n-- 9. ApplyWeightedCorrection --\n');
rng(20260913);
D9 = simulateWeightedTrack(-18, 4.3, -2, 6, 200, Increasing=true, Start=-8);
S9 = psychophysics.Staircase(D9, 'Depth');

R = S9.Results;
lastN = max(1, R.ReversalCount - S9.ThresholdFromLastNReversals + 1):R.ReversalCount;
legacy = mean(S9.stimulusValues(R.ReversalIdx(lastN)));
[nPass,nFail] = check(nPass, nFail, ~S9.ApplyWeightedCorrection && R.Threshold == legacy && isempty(R.Weighted), ...
    'off by default: Results.Threshold is the plain mean of the last N, Weighted is empty');

S9.WeightedStepFieldYes = "Depth_StepOnHit";
S9.WeightedStepFieldNo  = "Depth_StepOnMiss";
S9.refresh_history();
[nPass,nFail] = check(nPass, nFail, S9.Results.Threshold == legacy, ...
    'naming the fields alone changes nothing while the flag is off');

S9.ApplyWeightedCorrection = true;
S9.refresh_history();
T9 = S9.weightedThreshold();
[nPass,nFail] = check(nPass, nFail, S9.Results.Threshold == T9.Threshold && T9.StepSource == "field" ...
    && S9.Results.ThresholdStd == T9.ReversalStd, ...
    sprintf('on: Results.Threshold is the corrected value (%.3f, was %.3f)', S9.Results.Threshold, legacy));
[nPass,nFail] = check(nPass, nFail, isequaln(S9.Results.Weighted, T9), ...
    'and Results.Weighted is what weightedThreshold() returns with no arguments');

% GeometricMean cannot quietly put the two on different scales.
S9.ThresholdFormula = "GeometricMean";
S9.refresh_history();
[nPass,nFail] = check(nPass, nFail, S9.Results.Threshold == T9.Threshold ...
    && contains(S9.Results.Weighted.Message, 'arithmetic mean'), ...
    'GeometricMean: still the arithmetic, corrected value, with an advisory');
S9.ThresholdFormula = "Mean";

% A correction that cannot be computed is NaN, never the uncorrected mean.
S9.WeightedStepFieldYes = "NoSuchField";
threw = false;
try
    S9.refresh_history();
catch
    threw = true;
end
[nPass,nFail] = check(nPass, nFail, ~threw && isnan(S9.Results.Threshold) && ~S9.Results.Weighted.Valid, ...
    'a refused correction is NaN under the flag, and does not throw from a refresh');

S9.ApplyWeightedCorrection = false;
S9.refresh_history();
[nPass,nFail] = check(nPass, nFail, S9.Results.Threshold == legacy && isempty(S9.Results.Weighted), ...
    'turning it off restores the plain threshold');

% Every trial, from the NewData path: an empty session and a growing one.
Sgrow = psychophysics.Staircase(D9(1:3), 'Depth');
Sgrow.ApplyWeightedCorrection = true;
threw = false;
try
    for n = [0 1 2 5 20 60]
        % update_data is the NewData listener's own entry point.
        Sgrow.update_data([], struct('Data', struct('DATA', D9(1:n), 'Subject', [], 'BoxID', 1)));
    end
catch ME
    threw = true;
    fprintf('    %s\n', ME.message);
end
[nPass,nFail] = check(nPass, nFail, ~threw && isfinite(Sgrow.Results.Threshold), ...
    'refreshing trial by trial from nothing never throws, and ends with a threshold');
delete(Sgrow);
delete(S9);

% createPopOut_ copies analysis settings onto a sibling Staircase by name.
% It needs a window, so this group reads the list rather than opening one.
src = fileread(fullfile(repoRoot,'obj','+psychophysics','@Staircase','Staircase.m'));
propsBlock = regexp(src, 'props = \{(.*?)\};', 'tokens', 'once');
needed = {'ApplyWeightedCorrection','WeightedStepAfterYes','WeightedStepAfterNo', ...
    'WeightedStepFieldYes','WeightedStepFieldNo'};
missing = needed(~cellfun(@(p) contains(propsBlock{1}, ['''' p '''']), needed));
[nPass,nFail] = check(nPass, nFail, isempty(missing), sprintf( ...
    'the pop-out copies every weighted setting%s', ternary(isempty(missing), '', [' -- missing: ' strjoin(missing, ', ')])));

%% ---- 10. the bias it exists to remove ------------------------------------
fprintf('\n-- 10. Monte Carlo --\n');
% Gaussian PF, 98% width 20 dB (Hoover's), so sigma = 20/(2*norminv(0.99)).
sigma = 20 / (2*norminv(0.99));
mu = 0;
cases = {0.75, -1, 3; 0.20, -4, 1};
nTracks = 400;
for c = 1:size(cases,1)
    psi = cases{c,1}; sYes = cases{c,2}; sNo = cases{c,3};
    thrU = nan(1, nTracks);
    thrC = nan(1, nTracks);
    rng(1000 + c);
    for t = 1:nTracks
        Dt = simulateWeightedTrack(mu, sigma, sYes, sNo, 120, Increasing=true, ...
            Start=mu + sigma*norminv(psi) + 8*(2*rand - 1), Fast=true);
        St = psychophysics.Staircase(Dt, 'Depth');
        Tt = St.weightedThreshold();
        delete(St);
        if Tt.Valid
            thrU(t) = Tt.ReversalMean;
            thrC(t) = Tt.Threshold;
        end
    end
    pU = normcdf((mean(thrU, 'omitnan') - mu)/sigma);
    pC = normcdf((mean(thrC, 'omitnan') - mu)/sigma);
    [nPass,nFail] = check(nPass, nFail, sum(isfinite(thrC)) > 0.95*nTracks, ...
        sprintf('psi = %.2f: %d of %d tracks gave a threshold', psi, sum(isfinite(thrC)), nTracks));
    [nPass,nFail] = check(nPass, nFail, abs(pC - psi) < 0.5*abs(pU - psi) && abs(pC - psi) < 0.015, ...
        sprintf('psi = %.2f: uncorrected lands at p = %.3f, corrected at p = %.3f', psi, pU, pC));
end

%% ---- 11. no data, and too little ----------------------------------------
fprintf('\n-- 11. no data and too little data --\n');
HIT  = double(bitset(uint32(0), uint32(epsych.BitMask.Hit)));
MISS = double(bitset(uint32(0), uint32(epsych.BitMask.Miss)));
ABRT = double(bitset(uint32(0), uint32(epsych.BitMask.Abort)));
CRJ  = double(bitset(uint32(0), uint32(epsych.BitMask.CorrectReject)));
BOTH = double(bitor(uint32(HIT), uint32(MISS)));
mk = @(lv, rc, tt) struct('Depth', num2cell(lv), 'RespCode', num2cell(rc), 'TrialType', num2cell(tt));

% Every one of these must answer -- through the method AND through a
% refresh with the flag on, which is the NewData listener's path -- with a
% refusal whose message names the cause, never an error.
short = { ...
    '0 trials',                 struct('Depth',{},'RespCode',{},'TrialType',{}),        'no trials'; ...
    '1 trial',                  mk(-10, HIT, 0),                                         'no reversals'; ...
    '2 trials, one step',       mk([-10 -12], [HIT HIT], [0 0]),                         'no reversals'; ...
    '3 trials, one reversal',   mk([-10 -12 -6], [HIT MISS HIT], [0 0 0]),               'one direction only (0 ascending, 1 descending)'; ...
    'no reversal (monotone)',   mk([-2 -4 -6 -8 -10], repmat(HIT,1,5), zeros(1,5)),      'no reversals'; ...
    'all catch trials',         mk([-10 -10 -10], [CRJ CRJ CRJ], [1 1 1]),               'No trial is a stimulus trial'; ...
    'all aborts',               mk([-10 -10 -10], [ABRT ABRT ABRT], [0 0 0]),            'no reversals'; ...
    'every level NaN',          mk(nan(1,6), [HIT MISS HIT MISS HIT MISS], zeros(1,6)),  'No stimulus trial recorded a level'; ...
    'Hit and Miss on every code', mk([-10 -12 -6 -8 -10 -4], repmat(BOTH,1,6), zeros(1,6)), 'No step after a yes'; ...
    'no TrialType, no RespCode', struct('Depth', num2cell([-10 -12 -6 -8])),             'No trial is a stimulus trial'};
for k = 1:size(short,1)
    [ok, detail] = answersWithRefusal(short{k,2}, short{k,3});
    [nPass,nFail] = check(nPass, nFail, ok, sprintf('%s: %s', short{k,1}, detail));
end

% The least that does work: four trials, one trough and one peak.
S4 = psychophysics.Staircase(mk([-10 -12 -6 -8], [HIT MISS HIT HIT], [0 0 0 0]), 'Depth');
T4 = S4.weightedThreshold();
[nPass,nFail] = check(nPass, nFail, T4.Valid && T4.Threshold == mean([-12 -6]) - 1 ...
    && T4.NumAscending == 1 && T4.NumDescending == 1, ...
    sprintf('four trials, one reversal each way, is enough (%.1f)', T4.Threshold));
delete(S4);

% A session growing from nothing, trial by trial, through the listener's
% own entry point: never a throw, Weighted always a struct under the flag,
% and no spread beside a missing threshold.
Dg = mk([-10 -12 -6 -8 -10 -4 -6 -8], [HIT MISS HIT HIT MISS HIT HIT HIT], zeros(1,8));
Sg = psychophysics.Staircase(Dg(1:0), 'Depth');
Sg.ApplyWeightedCorrection = true;
Sg.refresh_history();
grewOk = isstruct(Sg.Results.Weighted) && isnan(Sg.Results.Threshold) && isnan(Sg.Results.ThresholdStd);
firstValid = NaN;
try
    for n = 1:numel(Dg)
        Sg.update_data([], struct('Data', struct('DATA', Dg(1:n), 'Subject', [], 'BoxID', 1)));
        W = Sg.Results.Weighted;
        grewOk = grewOk && isstruct(W) && isequal(fieldnames(W), fieldnames(T));
        if W.Valid
            if isnan(firstValid), firstValid = n; end
            grewOk = grewOk && Sg.Results.Threshold == W.Threshold && Sg.Results.ThresholdStd == W.ReversalStd;
        else
            grewOk = grewOk && isnan(Sg.Results.Threshold) && isnan(Sg.Results.ThresholdStd);
        end
    end
catch ME
    grewOk = false;
    fprintf('    %s\n', ME.message);
end
[nPass,nFail] = check(nPass, nFail, grewOk && firstValid == 4, sprintf( ...
    'growing from 0 trials: a refusal struct and NaN until trial %d, then the threshold', firstValid));
delete(Sg);

% A trial that recorded no level used to shift every later level onto the
% wrong trial, and threw from the constructor. It reads as NaN now.
Dm1 = mk([-10 -12 -6 -8 -10 -4], [HIT MISS HIT HIT MISS HIT], zeros(1,6));
Dm1(5).Depth = [];
threw = false;
try
    Sm1 = psychophysics.Staircase(Dm1, 'Depth');
    Tm1 = Sm1.weightedThreshold();
catch ME
    threw = true;
    fprintf('    %s\n', ME.message);
end
[nPass,nFail] = check(nPass, nFail, ~threw && isnan(Sm1.stimulusValues(5)) ...
    && isequal(Sm1.stimulusValues([1:4 6]), [-10 -12 -6 -8 -4]) && Tm1.Valid && Tm1.Threshold == -10, ...
    'a trial with no recorded level reads as NaN, and later levels stay on their own trials');
if ~threw, delete(Sm1); end

% A response code missing from one trial used to pair every later code with
% the wrong trial ([DATA.RespCode] dropped it), so inference was refused.
% psychophysics.Psych.responseCodes now reads it as 0 -- an unscored trial
% -- and keeps every later code on its own trial, so the result must be
% exactly that of a trial scored 0 on purpose: its step is attributed to
% neither response, and nothing after it moves.
Drc = mk([-10 -12 -6 -8], [HIT MISS HIT HIT], [0 0 0 0]);
Drc(3).RespCode = [];
Src = psychophysics.Staircase(Drc, 'Depth');
Trc = Src.weightedThreshold();
Dz = mk([-10 -12 -6 -8], [HIT MISS 0 HIT], [0 0 0 0]);
Tz = psychophysics.Staircase(Dz, 'Depth').weightedThreshold();
[nPass,nFail] = check(nPass, nFail, isequaln(Trc, Tz) && Src.responseCodes(3) == 0 ...
    && Src.responseCodes(4) == HIT && ~contains(Trc.Message, 'no response code on every trial'), ...
    'a response code missing on one trial reads as unscored, and later codes stay on their own trials');
delete(Src);

% Step fields that are there but cannot be used.
base = mk([-10 -12 -6 -8 -10 -4 -6 -8], [HIT MISS HIT HIT MISS HIT HIT HIT], zeros(1,8));
fieldCases = {'empty on one trial', 'one number per trial'; 'all NaN', 'no defined value'; ...
    'text', 'one number per trial'; 'Value containers', ''};
for k = 1:size(fieldCases,1)
    Df = base;
    [Df.StepH] = deal(-2); [Df.StepM] = deal(6);
    switch fieldCases{k,1}
        case 'empty on one trial', Df(2).StepH = [];
        case 'all NaN',            [Df.StepH] = deal(NaN); [Df.StepM] = deal(NaN);
        case 'text',               [Df.StepH] = deal('x');
        case 'Value containers',   [Df.StepH] = deal(struct('Value',-2)); [Df.StepM] = deal(struct('Value',6));
    end
    Sf = psychophysics.Staircase(Df, 'Depth');
    Tf = Sf.weightedThreshold(StepFieldYes='StepH', StepFieldNo='StepM');
    if isempty(fieldCases{k,2})
        ok = Tf.Valid && Tf.StepAfterYes == -2 && Tf.StepAfterNo == 6;
    else
        ok = ~Tf.Valid && contains(Tf.Message, fieldCases{k,2});
    end
    [nPass,nFail] = check(nPass, nFail, ok, sprintf('step field %s: %s', fieldCases{k,1}, ...
        ternary(Tf.Valid, 'read', char(Tf.Message))));
    delete(Sf);
end

% Settings that leave too little.
Ss = psychophysics.Staircase(base, 'Depth');
T1 = Ss.weightedThreshold(NumReversals=1);
[nPass,nFail] = check(nPass, nFail, ~T1.Valid && contains(T1.Message, 'NumReversals = 1'), ...
    'NumReversals = 1 names itself as the cause, not "one direction"');
Tall = Ss.weightedThreshold();
Ss.StimulusTrialType = epsych.BitMask.TrialType_1;     % changed, no refresh_history()
Tstale = Ss.weightedThreshold();
[nPass,nFail] = check(nPass, nFail, Tstale.Threshold == Tall.Threshold, ...
    'a setting changed without refresh_history() still reads the trials its reversals came from');
Ss.StimulusTrialType = epsych.BitMask.TrialType_0;
Ss.ExcludedTrials = 1:numel(base);
Tx0 = Ss.weightedThreshold();
[nPass,nFail] = check(nPass, nFail, ~Tx0.Valid && contains(Tx0.Message, 'after ExcludedTrials'), ...
    'excluding every trial is a refusal that says so');
delete(Ss);

% The static, with the smallest and oddest inputs.
st = { ...
    '0x0',          psychophysics.Staircase.correctedReversalMean([], [], -2, 6),                          'no reversals'; ...
    '0x1 column',   psychophysics.Staircase.correctedReversalMean(zeros(0,1), false(0,1), -2, 6),          'no reversals'; ...
    'one NaN',      psychophysics.Staircase.correctedReversalMean(NaN, true, -2, 6),                       'no reversals with a defined value'; ...
    'one reversal', psychophysics.Staircase.correctedReversalMean(-10, true, -2, 6),                       'one direction only'};
for k = 1:size(st,1)
    Ts = st{k,2};
    [nPass,nFail] = check(nPass, nFail, ~Ts.Valid && isnan(Ts.Threshold) && contains(Ts.Message, st{k,3}) ...
        && isrow(Ts.ReversalUsed), sprintf('static, %s: %s', st{k,1}, Ts.Message));
end
Tcol = psychophysics.Staircase.correctedReversalMean([1;2;3;4], logical([1;0;1;0]), -2, 6);
Tinf = psychophysics.Staircase.correctedReversalMean([1 Inf 3 4], logical([1 0 1 0]), -2, 6);
[nPass,nFail] = check(nPass, nFail, Tcol.Valid && isrow(Tcol.ReversalValues) ...
    && Tinf.Valid && Tinf.NumUndefinedReversals == 1 && isequal(Tinf.ReversalUsed, logical([0 0 1 1])), ...
    'column inputs work, and an Inf reversal is dropped like a NaN');

for bad = {[1 NaN], [2 0]}
    threw = false;
    try
        psychophysics.Staircase.correctedReversalMean([1 2], bad{1}, -2, 6);
    catch ME
        threw = strcmp(ME.identifier, 'psychophysics:Staircase:WeightedInvalidAscending');
    end
    [nPass,nFail] = check(nPass, nFail, threw, sprintf( ...
        'reversalIsAscending = %s is a caller bug, and throws saying so', mat2str(bad{1})));
end

%% ---- summary -------------------------------------------------------------
fprintf('\n=== %d passed, %d failed ===\n\n', nPass, nFail);
if nFail > 0
    error('smoke_test_weighted_staircase:Failed','%d check(s) failed.', nFail);
end


%% =========================================================================
function [nPass, nFail] = check(nPass, nFail, condition, description)
% Report and tally one check.
if condition
    nPass = nPass + 1;
    fprintf('  PASS  %s\n', description);
else
    nFail = nFail + 1;
    fprintf('  FAIL  %s\n', description);
end
end

%% =========================================================================
function [ok, detail] = answersWithRefusal(D, expected)
% Too little data must come back as a refusal naming its cause -- from the
% method, and from a refresh with the flag on -- and never as an error.
ok = false;
try
    S = psychophysics.Staircase(D, 'Depth');
    T = S.weightedThreshold();
    S.ApplyWeightedCorrection = true;
    S.refresh_history();
    W = S.Results.Weighted;
    ok = ~T.Valid && isnan(T.Threshold) && contains(T.Message, expected) ...
        && isstruct(W) && ~W.Valid && isnan(S.Results.Threshold) && isnan(S.Results.ThresholdStd);
    detail = char(T.Message);
    delete(S);
catch ME
    detail = ['THREW: ' ME.message];
end
end

%% =========================================================================
function DATA = simulateWeightedTrack(mu, sigma, stepYes, stepNo, nTrials, options)
% A 1-up-1-down weighted staircase against a Gaussian PF, coded as a
% paradigm's saving function codes it. Steps are SIGNED changes in Depth
% after a yes (Hit) and a no (Miss), and are also recorded per trial as
% Depth_StepOnHit / Depth_StepOnMiss, the way cl_AppetitiveStimDetect's
% parameters land in DATA. A catch trial and an abort leave Depth alone,
% so a pending step survives them as it does in that selector.
arguments
    mu
    sigma
    stepYes
    stepNo
    nTrials
    options.Increasing (1,1) logical = true
    options.Start (1,1) double = mu
    options.CatchEvery (1,1) double = Inf
    options.AbortRate (1,1) double = 0
    options.Schedule = []        % @(k) [stepYes stepNo] for stimulus trial k
    options.Bounds (1,2) double = [-Inf Inf]
    options.Fast (1,1) logical = false   % omit the step fields
end
HIT   = double(bitset(uint32(0), uint32(epsych.BitMask.Hit)));
MISS  = double(bitset(uint32(0), uint32(epsych.BitMask.Miss)));
CR    = double(bitset(uint32(0), uint32(epsych.BitMask.CorrectReject)));
ABORT = double(bitset(uint32(0), uint32(epsych.BitMask.Abort)));

sgn = 1;
if ~options.Increasing, sgn = -1; end

depth = min(max(options.Start, options.Bounds(1)), options.Bounds(2));
level = nan(1, nTrials); rc = nan(1, nTrials); tt = zeros(1, nTrials);
onHit = nan(1, nTrials); onMiss = nan(1, nTrials);
kStim = 0;
for k = 1:nTrials
    if isempty(options.Schedule)
        steps = [stepYes stepNo];
    else
        steps = options.Schedule(kStim + 1);
    end
    onHit(k) = steps(1); onMiss(k) = steps(2);
    level(k) = depth;

    if mod(k, options.CatchEvery) == 0
        rc(k) = CR; tt(k) = 1;
        continue
    end
    kStim = kStim + 1;
    if rand < options.AbortRate
        rc(k) = ABORT;
        continue
    end
    if rand < normcdf(sgn*(depth - mu)/sigma)
        rc(k) = HIT;
        depth = depth + steps(1);
    else
        rc(k) = MISS;
        depth = depth + steps(2);
    end
    depth = min(max(depth, options.Bounds(1)), options.Bounds(2));
end

if options.Fast
    DATA = struct('Depth', num2cell(level), 'RespCode', num2cell(rc), 'TrialType', num2cell(tt));
else
    DATA = struct('Depth', num2cell(level), 'RespCode', num2cell(rc), 'TrialType', num2cell(tt), ...
        'Depth_StepOnHit', num2cell(onHit), 'Depth_StepOnMiss', num2cell(onMiss));
end
end

%% =========================================================================
function out = ternary(condition, a, b)
if condition, out = a; else, out = b; end
end
