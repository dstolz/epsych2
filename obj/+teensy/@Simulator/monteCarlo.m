function [results, summary] = monteCarlo(program, responder, nTrials, options)
% [results, summary] = teensy.Simulator.monteCarlo(program, responder, nTrials)
% Run many simulated trials and summarize the outcomes.
%
% This is the check that catches a paradigm which is logically valid but
% behaviorally broken -- one where the response window closes before the
% subject can reach it, or where a "miss" is unreachable, or where every
% trial aborts. Validation cannot see any of that; a thousand simulated
% trials can.
%
% Each trial gets its own responder seed, so the run as a whole is
% reproducible from the Seed option while individual trials still differ.
%
% Parameters
%   program   - teensy.Program to run.
%   responder - function_handle from teensy.Simulator.Responder, a scripted
%       input accepted by runTrial, or [] for no input.
%   nTrials   - Number of trials to simulate.
%
% Name=Value
%   TimeStepMs (double)    - Passed to the simulator. Default 0.5, coarser
%       than the default because throughput matters more than sub-tick
%       precision when summarizing hundreds of trials.
%   MaxDurationMs (double) - Per-trial safety stop. Default 60000
%   Seed (double)          - Base seed. Default 0
%   Progress (function_handle) - Called as f(i, nTrials) after each trial, for
%       a progress dialog. Default [] (no callback).
%   ShouldStop (function_handle) - Queried as tf = f() after each trial;
%       returning true ends the run early. Default [] (never stops early).
%
% Returns:
%   results - Table with one row per trial: TrialNum, RespCode, RespLatency,
%       FinalState, DurationMs, Completed, plus one logical column per
%       response-outcome bit (Hit, Miss, CorrectReject, FalseAlarm, Abort,
%       Reward, Punish). A run stopped early returns only the trials that ran.
%   summary - Struct of rates: NTrials, CompleteRate, HitRate, FARate,
%       MissRate, CRRate, AbortRate, MedianLatencyMs and DPrime where it can
%       be computed. NTrials is the number actually simulated, so a caller can
%       tell a stopped run from a complete one.
%
% Example
%   r = teensy.Simulator.Responder("guessing");
%   [t, s] = teensy.Simulator.monteCarlo(program, r, 200);
%   fprintf('hit rate %.2f\n', s.HitRate);
%
% See also: teensy.Simulator.runTrial, teensy.Simulator.Responder

arguments
    program (1,1) teensy.Program
    responder = []
    nTrials (1,1) double {mustBePositive, mustBeInteger} = 100
    options.TimeStepMs (1,1) double {mustBePositive} = 0.5
    options.MaxDurationMs (1,1) double {mustBePositive} = 60000
    options.Seed (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    options.Progress = []
    options.ShouldStop = []
end

trialNum = (1:nTrials)';
respCode = zeros(nTrials, 1, 'uint32');
respLatency = nan(nTrials, 1);
finalState = strings(nTrials, 1);
durationMs = nan(nTrials, 1);
completed = false(nTrials, 1);

nRun = nTrials;

for i = 1:nTrials
    % A distinct seed per trial keeps probability branches varying while the
    % whole run stays reproducible from options.Seed.
    sim = teensy.Simulator(program, ...
        TimeStepMs = options.TimeStepMs, ...
        MaxDurationMs = options.MaxDurationMs, ...
        Seed = options.Seed + i, ...
        RecordTrace = false);

    sim.runTrial(responder);

    respCode(i) = sim.RespCode;
    respLatency(i) = sim.RespLatency;
    finalState(i) = sim.CurrentState;
    durationMs(i) = sim.TrialElapsedMs;
    completed(i) = sim.Completed;

    if ~isempty(options.Progress)
        options.Progress(i, nTrials);
    end

    % Checked after the trial rather than before, so a stopped run always
    % returns whole trials and never an empty table.
    if ~isempty(options.ShouldStop) && options.ShouldStop()
        nRun = i;
        break
    end
end

if nRun < nTrials
    keep = 1:nRun;
    trialNum = trialNum(keep);
    respCode = respCode(keep);
    respLatency = respLatency(keep);
    finalState = finalState(keep);
    durationMs = durationMs(keep);
    completed = completed(keep);
end

results = table(trialNum, respCode, respLatency, finalState, durationMs, completed, ...
    VariableNames = {'TrialNum', 'RespCode', 'RespLatency', 'FinalState', ...
        'DurationMs', 'Completed'});

% One logical column per outcome bit, so the table can be filtered directly
% and the designer can bar-chart it without decoding again.
decoded = epsych.BitMask.decode(respCode);
for bit = [epsych.BitMask.getResponses(), epsych.BitMask.getContingencies()]
    name = char(bit);
    results.(name) = decoded.(name)(:);
end

summary = localSummarize_(results, decoded, nRun);
end


function s = localSummarize_(results, decoded, nTrials)
% s = localSummarize_(results, decoded, nTrials)
% Outcome rates over a Monte Carlo run.
hit = decoded.Hit(:);
miss = decoded.Miss(:);
fa = decoded.FalseAlarm(:);
cr = decoded.CorrectReject(:);
abort = decoded.Abort(:);

s = struct();
s.NTrials = nTrials;
s.CompleteRate = mean(results.Completed);
s.HitRate = localRate_(sum(hit), sum(hit | miss));
s.MissRate = localRate_(sum(miss), sum(hit | miss));
s.FARate = localRate_(sum(fa), sum(fa | cr));
s.CRRate = localRate_(sum(cr), sum(fa | cr));
s.AbortRate = localRate_(sum(abort), nTrials);
s.MedianLatencyMs = median(results.RespLatency, 'omitnan');
s.DPrime = localDPrime_(s.HitRate, s.FARate, sum(hit | miss), sum(fa | cr));
end


function r = localRate_(numerator, denominator)
% r = localRate_(numerator, denominator)
% Proportion, or NaN when the denominator is zero.
if denominator == 0
    r = NaN;
else
    r = numerator / denominator;
end
end


function d = localDPrime_(hitRate, faRate, nSignal, nCatch)
% d = localDPrime_(hitRate, faRate, nSignal, nCatch)
% Sensitivity index, with the standard log-linear correction.
%
% A rate of exactly 0 or 1 sends norminv to infinity, so both are pulled in by
% half a trial -- the usual correction, and the reason nSignal and nCatch are
% needed here at all.
d = NaN;
if isnan(hitRate) || isnan(faRate) || nSignal == 0 || nCatch == 0
    return
end

hitRate = min(max(hitRate, 0.5 / nSignal), 1 - 0.5 / nSignal);
faRate = min(max(faRate, 0.5 / nCatch), 1 - 0.5 / nCatch);

d = localNormInv_(hitRate) - localNormInv_(faRate);
end


function z = localNormInv_(p)
% z = localNormInv_(p)
% Inverse standard normal CDF, without requiring the Statistics toolbox.
z = -sqrt(2) * erfcinv(2 * p);
end
