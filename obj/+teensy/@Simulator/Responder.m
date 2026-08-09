function fcn = Responder(kind, options)
% fcn = teensy.Simulator.Responder(kind, Name=Value)
% Build a stochastic simulated subject for the test bench.
%
% The returned handle is a closed-loop input script: teensy.Simulator.runTrial
% calls it every step with the simulator, and it drives inputs in response to
% what the machine is doing. That is what makes a Monte Carlo run informative
% -- an open-loop script cannot show you that a paradigm is, say, impossible
% to abort out of.
%
% Parameters
%   kind - "perfect", "guessing", "impulsive", "sluggish", "biased" or
%       "psychometric".
%
% Name=Value
%   Channel (string)     - Input the subject drives. Default: first digital input.
%   AltChannel (string)  - Second input, for two-choice paradigms.
%   PRespond (double)    - Probability of responding at all. Default by kind.
%   LatencyMs (double)   - Mean response latency from trial start. Default 400.
%   LatencyJitterMs (double) - Standard deviation of the latency. Default 100.
%   HoldMs (double)      - How long a response is held. Default 60.
%   Bias (double)        - Share of responses going to Channel rather than
%       AltChannel, 0..1. Default 0.5.
%   Variable (string)    - For "psychometric": the variable the response
%       probability depends on.
%   Midpoint, Slope (double) - Logistic parameters for "psychometric".
%   Seed (double)        - RandStream seed. Default 1.
%
% Returns:
%   fcn - function_handle f(sim) usable as runTrial's inputScript.
%
% Example
%   r = teensy.Simulator.Responder("guessing", PRespond=0.5);
%   T = sim.runTrial(r);
%
% See also: teensy.Simulator.runTrial, teensy.Simulator.monteCarlo

arguments
    kind (1,1) string {mustBeMember(kind, ["perfect","guessing","impulsive", ...
        "sluggish","biased","psychometric"])} = "perfect"
    options.Channel (1,1) string = ""
    options.AltChannel (1,1) string = ""
    options.PRespond (1,1) double = NaN
    options.LatencyMs (1,1) double = NaN
    options.LatencyJitterMs (1,1) double = 100
    options.HoldMs (1,1) double = 60
    options.Bias (1,1) double {mustBeInRange(options.Bias, 0, 1)} = 0.5
    options.Variable (1,1) string = ""
    options.Midpoint (1,1) double = 0
    options.Slope (1,1) double = 1
    options.Seed (1,1) double {mustBeNonnegative, mustBeInteger} = 1
end

% Per-kind defaults. Latency and response probability are what actually
% distinguish these subjects; everything else is shared.
switch kind
    case "perfect"
        defaults = struct('PRespond', 1.00, 'LatencyMs', 300);
    case "guessing"
        defaults = struct('PRespond', 0.50, 'LatencyMs', 500);
    case "impulsive"
        defaults = struct('PRespond', 0.95, 'LatencyMs', 60);
    case "sluggish"
        defaults = struct('PRespond', 0.70, 'LatencyMs', 1500);
    case "biased"
        defaults = struct('PRespond', 0.90, 'LatencyMs', 400);
    otherwise
        defaults = struct('PRespond', NaN, 'LatencyMs', 400);
end

pRespond = options.PRespond;
if isnan(pRespond)
    pRespond = defaults.PRespond;
end

latencyMs = options.LatencyMs;
if isnan(latencyMs)
    latencyMs = defaults.LatencyMs;
end

% The responder owns its own stream so it stays reproducible independently of
% the probability branches inside the program.
stream = RandStream('twister', Seed = options.Seed);
state = struct('Planned', false, 'RespondAt', Inf, 'ReleaseAt', Inf, ...
    'Channel', "", 'LastTrialElapsed', Inf);

fcn = @respond;

    function respond(sim)
        % respond(sim)
        % One step of the simulated subject.

        % runTrial calls start() before the first step, so a backwards jump in
        % trial time means a new trial and the plan must be redrawn.
        if sim.TrialElapsedMs < state.LastTrialElapsed
            state.Planned = false;
        end
        state.LastTrialElapsed = sim.TrialElapsedMs;

        if ~state.Planned
            state = localPlan_(sim, state, stream, kind, pRespond, latencyMs, options);
        end

        if isinf(state.RespondAt) || strlength(state.Channel) == 0
            return
        end

        if sim.TrialElapsedMs >= state.RespondAt && sim.TrialElapsedMs < state.ReleaseAt
            sim.setInput(state.Channel, 1);
        elseif sim.TrialElapsedMs >= state.ReleaseAt
            sim.setInput(state.Channel, 0);
        end
    end
end


function state = localPlan_(sim, state, stream, kind, pRespond, latencyMs, options)
% state = localPlan_(...)
% Decide once per trial whether, when and where this subject responds.
state.Planned = true;
state.RespondAt = Inf;
state.ReleaseAt = Inf;
state.Channel = "";

channel = options.Channel;
if strlength(channel) == 0
    channel = localFirstDigitalInput_(sim.Program);
end
if strlength(channel) == 0
    return
end

p = pRespond;
if kind == "psychometric" && strlength(options.Variable) > 0
    idx = sim.Program.variableIndex(options.Variable);
    if idx > 0
        x = sim.Program.Variables(idx).Value;
        p = 1 / (1 + exp(-options.Slope * (x - options.Midpoint)));
    else
        p = 0.5;
    end
end

if rand(stream) >= p
    return
end

if kind == "biased" && strlength(options.AltChannel) > 0 && rand(stream) >= options.Bias
    channel = options.AltChannel;
end

latency = latencyMs + options.LatencyJitterMs * randn(stream);
state.RespondAt = max(0, latency);
state.ReleaseAt = state.RespondAt + max(1, options.HoldMs);
state.Channel = channel;
end


function name = localFirstDigitalInput_(program)
% name = localFirstDigitalInput_(program)
% Name of the first digital input, or "" when the program has none.
name = "";
for i = 1:numel(program.Channels)
    c = program.Channels(i);
    if c.Direction == "Input" && c.Kind == "Digital"
        name = c.Name;
        return
    end
end
end
