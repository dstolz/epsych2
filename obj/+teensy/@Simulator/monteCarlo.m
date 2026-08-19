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

% psychophysics.Metrics owns the arithmetic. "halfcell" is the correction
% this function used to implement by hand: a rate of exactly 0 or 1 sends the
% z-transform to infinity, so both are pulled in by half a trial, which is why
% the counts rather than the rates are what get passed.
M = psychophysics.Metrics.fromCounts(sum(hit), sum(miss), sum(fa), sum(cr), ...
    Correction="halfcell");

s = struct();
s.NTrials = nTrials;
s.CompleteRate = mean(results.Completed);
s.HitRate = M.Rate.Hit;
s.MissRate = M.Rate.Miss;
s.FARate = M.Rate.FalseAlarm;
s.CRRate = M.Rate.CorrectReject;
s.AbortRate = psychophysics.Metrics.rate(sum(abort), nTrials);
s.MedianLatencyMs = median(results.RespLatency, 'omitnan');
s.DPrime = M.DPrime;
end
