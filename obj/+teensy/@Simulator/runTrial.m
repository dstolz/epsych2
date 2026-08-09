function T = runTrial(obj, inputScript)
% T = runTrial(obj, inputScript)
% Run one trial from start to completion against a scripted input.
%
% Parameters
%   inputScript - One of:
%       []                 no input at all; the trial runs on its timers
%       Nx3 double         rows of [timeMs, channelIndex, value]
%       struct array       fields TimeMs, Channel (name or index), Value
%       function_handle    f(sim) called every step, for closed-loop responding
%
% Returns:
%   T - The trace struct; see teensy.Simulator.trace.
%
% Example
%   T = sim.runTrial([500 1 1; 600 1 0]);          % a 100 ms poke at 500 ms
%   T = sim.runTrial(teensy.Simulator.Responder("perfect"));
%
% See also: teensy.Simulator.trace, teensy.Simulator.Responder

arguments
    obj (1,1) teensy.Simulator
    inputScript = []
end

obj.start();

if ~obj.Running
    T = obj.trace();
    return
end

isClosedLoop = isa(inputScript, 'function_handle');
events = localNormalizeScript_(obj, inputScript, isClosedLoop);
nextEvent = 1;

maxSteps = ceil(obj.MaxDurationMs / obj.TimeStepMs);

for k = 1:maxSteps
    if ~obj.Running || obj.Completed
        break
    end

    % Scripted inputs are applied before the step that would sample them, so
    % an event scheduled for time t is visible to the machine at time t.
    while nextEvent <= numel(events) && events(nextEvent).TimeMs <= obj.TrialElapsedMs
        obj.setInput(events(nextEvent).Channel, events(nextEvent).Value);
        nextEvent = nextEvent + 1;
    end

    if isClosedLoop
        inputScript(obj);
    end

    obj.step();
end

if ~obj.Completed
    vprintf(2, 'teensy.Simulator: trial did not complete within %g ms', obj.MaxDurationMs);
end

T = obj.trace();
end


function events = localNormalizeScript_(obj, inputScript, isClosedLoop)
% events = localNormalizeScript_(obj, inputScript, isClosedLoop)
% Turn any accepted script form into a time-sorted event struct array.
events = struct('TimeMs', {}, 'Channel', {}, 'Value', {});

if isClosedLoop || isempty(inputScript)
    return
end

inputNames = localInputNames_(obj);

if isnumeric(inputScript)
    if size(inputScript, 2) ~= 3
        vprintf(0, 1, 'teensy.Simulator: a numeric input script needs 3 columns [timeMs channel value]');
        return
    end
    for i = 1:size(inputScript, 1)
        events(end+1) = struct( ...
            'TimeMs', inputScript(i, 1), ...
            'Channel', localChannelName_(inputNames, inputScript(i, 2)), ...
            'Value', inputScript(i, 3));
    end
elseif isstruct(inputScript)
    for i = 1:numel(inputScript)
        events(end+1) = struct( ...
            'TimeMs', double(inputScript(i).TimeMs), ...
            'Channel', localChannelName_(inputNames, inputScript(i).Channel), ...
            'Value', double(inputScript(i).Value));
    end
else
    vprintf(0, 1, 'teensy.Simulator: unsupported input script of class "%s"', class(inputScript));
    return
end

if ~isempty(events)
    [~, order] = sort([events.TimeMs]);
    events = events(order);
end
end


function names = localInputNames_(obj)
% names = localInputNames_(obj)
% Input channel names in program order, for index-based scripts.
names = strings(1, 0);
for i = 1:numel(obj.Program.Channels)
    if obj.Program.Channels(i).Direction == "Input"
        names(end+1) = obj.Program.Channels(i).Name;
    end
end
end


function name = localChannelName_(inputNames, spec)
% name = localChannelName_(inputNames, spec)
% Resolve a channel given either its name or its index among the inputs.
if isnumeric(spec)
    idx = round(spec);
    if idx >= 1 && idx <= numel(inputNames)
        name = inputNames(idx);
    else
        name = "";
    end
else
    name = string(spec);
end
end
