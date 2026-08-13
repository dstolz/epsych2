function onSimulate(obj, verb, varargin)
% onSimulate(obj, verb, varargin)
% Handle every Test Bench action.
%
% The simulation advances off a MATLAB timer rather than a loop, so the
% window stays responsive and the virtual inputs can be clicked mid-trial --
% which is the whole point of the test bench.
%
% Parameters
%   verb - 'start', 'pause', 'step', 'reset', 'speed', 'input', 'tick',
%       'montecarlo'.
%   varargin - Verb-specific arguments.
%
% See also: teensy.Simulator, teensy.Simulator.monteCarlo

arguments
    obj (1,1) teensy.TrialDesigner
    verb (1,:) char
end
arguments (Repeating)
    varargin
end

switch verb

    case 'start'
        report = obj.Program.validate();
        if teensy.Compiler.hasError(report)
            obj.setStatus('The program has errors and cannot be simulated.', ...
                'Open the Compile tab to see what needs fixing.');
            return
        end

        obj.Simulator = teensy.Simulator(obj.Program, TimeStepMs = 0.5);
        obj.Simulator.start();

        obj.stopTimer_('SimTimer');
        obj.SimTimer = timer( ...
            Name = 'TeensyDesignerSim', ...
            ExecutionMode = 'fixedSpacing', ...
            Period = 0.03, ...
            BusyMode = 'drop', ...
            TimerFcn = @(~, ~) obj.onSimulate('tick'));
        start(obj.SimTimer);

        obj.setStatus(sprintf('Simulating from %s.', obj.Program.StartState), ...
            'Click the input buttons to respond while the trial runs.');

    case 'pause'
        obj.stopTimer_('SimTimer');
        obj.setStatus('Paused. Press Start to run a new trial, or Step to advance by hand.');

    case 'step'
        if isempty(obj.Simulator)
            obj.onSimulate('start');
            obj.stopTimer_('SimTimer');
            return
        end
        obj.Simulator.runFor(10);
        localRefreshSim_(obj);
        obj.setStatus(sprintf('t = %.0f ms, in %s.', ...
            obj.Simulator.TrialElapsedMs, obj.Simulator.CurrentState));

    case 'reset'
        obj.stopTimer_('SimTimer');
        obj.Simulator = [];
        cla(obj.HSim.Axes);
        obj.HSim.Result.Value = {'No trial has been run yet.'};
        obj.HSim.Clock.Text = 't = 0 ms';
        obj.HSim.StateLabel.Text = '';
        obj.setStatus('Reset the test bench.');

    case 'speed'
        switch varargin{1}
            case '1x',  obj.SimSpeed = 1;
            case '5x',  obj.SimSpeed = 5;
            case '20x', obj.SimSpeed = 20;
            otherwise,  obj.SimSpeed = 200;
        end
        obj.setStatus(sprintf('Simulated time now advances at %gx.', obj.SimSpeed));

    case 'input'
        if isempty(obj.Simulator)
            obj.setStatus('Press Start before driving the inputs.');
            return
        end
        obj.Simulator.setInput(varargin{1}, varargin{2});

    case 'tick'
        localTick_(obj);

    case 'montecarlo'
        localMonteCarlo_(obj);

end
end


% =========================================================================
function localTick_(obj)
% localTick_(obj)
% Advance simulated time by the elapsed wall time, scaled by the speed.
if isempty(obj.Figure) || ~isvalid(obj.Figure) || isempty(obj.Simulator)
    obj.stopTimer_('SimTimer');
    return
end

sim = obj.Simulator;

if sim.Completed || ~sim.Running
    obj.stopTimer_('SimTimer');
    localRefreshSim_(obj);
    localShowOutcome_(obj);
    return
end

% The timer period is 30 ms; advancing by period*speed keeps simulated time
% proportional to wall time without depending on how long the redraw took.
sim.runFor(30 * obj.SimSpeed);
localRefreshSim_(obj);

if sim.Completed
    obj.stopTimer_('SimTimer');
    localShowOutcome_(obj);
end
end


function localRefreshSim_(obj)
% localRefreshSim_(obj)
% Update the clock, the output lamps and the timeline.
sim = obj.Simulator;
if isempty(sim)
    return
end

obj.HSim.Clock.Text = sprintf('t = %.0f ms', sim.TrialElapsedMs);
obj.HSim.StateLabel.Text = char(sim.CurrentState);

names = fieldnames(obj.HSim.OutputLamps);
for i = 1:numel(names)
    lamp = obj.HSim.OutputLamps.(names{i});
    if ~isvalid(lamp)
        continue
    end
    value = sim.Outputs.(names{i});
    if value > 0
        lamp.Text = '  ON  ';
        lamp.BackgroundColor = [0.30 0.85 0.35];
    else
        lamp.Text = '  OFF  ';
        lamp.BackgroundColor = [0.85 0.85 0.85];
    end
end

localDrawTimeline_(obj, sim.trace());
end


function localDrawTimeline_(obj, T)
% localDrawTimeline_(obj, T)
% Draw the state band, the input and output traces, and the event markers.
ax = obj.HSim.Axes;
if isempty(ax) || ~isvalid(ax)
    return
end

cla(ax);

if isempty(T.t)
    return
end

inNames = fieldnames(T.Inputs);
outNames = fieldnames(T.Outputs);
nRows = numel(inNames) + numel(outNames);

rowH = 1;
gap = 0.35;
yTop = (nRows + 1) * (rowH + gap);

% --- State occupancy band -------------------------------------------------
% Drawn as contiguous blocks rather than a step trace: what matters is which
% state was active, and a block with a name in it reads at a glance.
changes = [1, find(diff(T.StateIndex) ~= 0) + 1, numel(T.t) + 1];
for k = 1:numel(changes) - 1
    a = changes(k);
    b = changes(k + 1) - 1;
    idx = T.StateIndex(a);
    if idx < 1 || idx > numel(obj.Program.States)
        continue
    end

    x0 = T.t(a);
    x1 = T.t(min(b + 1, numel(T.t)));
    if x1 <= x0
        x1 = x0 + 1;
    end

    rectangle(ax, Position = [x0, yTop, x1 - x0, rowH * 1.4], ...
        FaceColor = obj.Program.States(idx).Color, EdgeColor = [1 1 1], LineWidth = 0.5);

    if x1 - x0 > (max(T.t) - min(T.t)) * 0.05
        text(ax, (x0 + x1) / 2, yTop + rowH * 0.7, char(obj.Program.States(idx).Name), ...
            HorizontalAlignment = 'center', VerticalAlignment = 'middle', ...
            FontSize = 8, Interpreter = 'none');
    end
end

labels = strings(1, 0);
yTicks = [];

% --- Inputs ---------------------------------------------------------------
row = nRows;
for i = 1:numel(inNames)
    y = row * (rowH + gap);
    v = T.Inputs.(inNames{i});
    scaled = localScale_(v);
    plot(ax, T.t, y + scaled * rowH * 0.85, LineWidth = 1.4, Color = [0.20 0.45 0.80]);
    labels(end+1) = string(inNames{i});
    yTicks(end+1) = y + rowH * 0.4;
    row = row - 1;
end

% --- Outputs --------------------------------------------------------------
for i = 1:numel(outNames)
    y = row * (rowH + gap);
    v = T.Outputs.(outNames{i});
    scaled = localScale_(v);
    plot(ax, T.t, y + scaled * rowH * 0.85, LineWidth = 1.4, Color = [0.85 0.40 0.10]);
    labels(end+1) = string(outNames{i});
    yTicks(end+1) = y + rowH * 0.4;
    row = row - 1;
end

% --- Event markers --------------------------------------------------------
for i = 1:numel(T.Events)
    e = T.Events(i);
    if ~ismember(e.Kind, ["latency", "respcode", "user"])
        continue
    end
    plot(ax, [e.TimeMs e.TimeMs], [0 yTop + rowH * 1.4], ':', ...
        Color = [0.55 0.15 0.55], LineWidth = 1);
end

[yTicks, order] = sort(yTicks);
labels = labels(order);
ax.YTick = yTicks;
ax.YTickLabel = cellstr(labels);
ax.YLim = [-0.3, yTop + rowH * 1.8];
ax.XLim = [0, max(T.t(end), 1)];
ax.XLabel.String = 'time (ms)';
end


function s = localScale_(v)
% s = localScale_(v)
% Normalize a trace to 0..1 so channels of different units share an axis.
lo = min(v);
hi = max(v);
if hi - lo < eps
    s = zeros(size(v));
else
    s = (v - lo) / (hi - lo);
end
end


function localShowOutcome_(obj)
% localShowOutcome_(obj)
% Report the decoded outcome of a completed trial.
sim = obj.Simulator;
if isempty(sim)
    return
end

lines = {};
if sim.Completed
    lines{end+1} = sprintf('Completed in state : %s', sim.CurrentState);
else
    lines{end+1} = 'Trial did not complete.';
end

lines{end+1} = sprintf('Duration           : %.1f ms', sim.TrialElapsedMs);
lines{end+1} = sprintf('RespCode           : %d', sim.RespCode);

if isnan(sim.RespLatency)
    lines{end+1} = 'RespLatency        : not marked';
else
    lines{end+1} = sprintf('RespLatency        : %.1f ms', sim.RespLatency);
end

decoded = epsych.BitMask.decode(sim.RespCode);
active = string(fieldnames(decoded));
set = active(structfun(@(x) any(x), decoded));
if isempty(set)
    lines{end+1} = 'Outcome bits       : (none)';
else
    lines{end+1} = sprintf('Outcome bits       : %s', strjoin(set, ', '));
end

obj.HSim.Result.Value = lines;

if sim.Completed
    obj.setStatus(sprintf('Trial completed in %s after %.0f ms.', ...
        sim.CurrentState, sim.TrialElapsedMs));
end
end


function localMonteCarlo_(obj)
% localMonteCarlo_(obj)
% Run many trials against a stochastic subject and summarize the outcomes.
report = obj.Program.validate();
if teensy.Compiler.hasError(report)
    obj.setStatus('The program has errors and cannot be simulated.', ...
        'Open the Compile tab to see what needs fixing.');
    return
end

n = obj.HSim.NTrials.Value;
kind = string(obj.HSim.Responder.Value);

dlg = localProgressDialog_(obj.Figure, 'Monte Carlo', ...
    sprintf('Simulating %d trials...', n));
closeDialog = onCleanup(@() localCloseDialog_(dlg));

responder = teensy.Simulator.Responder(kind);

try
    [~, summary] = teensy.Simulator.monteCarlo(obj.Program, responder, n, ...
        TimeStepMs = 1, ...
        Progress = @(i, total) localProgress_(dlg, i, total), ...
        ShouldStop = @() localStopRequested_(dlg));
catch ME
    vprintf(0, 1, ME);
    obj.setStatus(sprintf('Monte Carlo failed: %s', ME.message));
    return
end

fields = fieldnames(summary);
data = cell(numel(fields), 2);
for i = 1:numel(fields)
    value = summary.(fields{i});
    if isnan(value)
        text = 'n/a';
    elseif fields{i} == "NTrials"
        text = sprintf('%d', value);
    elseif endsWith(fields{i}, 'Ms')
        text = sprintf('%.0f ms', value);
    elseif endsWith(fields{i}, 'Rate')
        text = sprintf('%.1f %%', value * 100);
    else
        text = sprintf('%.3f', value);
    end
    data(i, :) = {fields{i}, text};
end

obj.HSim.MCTable.Data = data;

% The summary counts only the trials that ran, so a short count means Stop was
% pressed; the partial result is still worth showing.
if summary.NTrials < n
    obj.setStatus(sprintf('Stopped after %d of %d trials with a "%s" subject.', ...
        summary.NTrials, n, kind), ...
        'The rates below cover only the trials that ran.');
else
    obj.setStatus(sprintf('Simulated %d trials with a "%s" subject.', n, kind), ...
        'Check that every outcome the paradigm defines actually occurs.');
end
end


function dlg = localProgressDialog_(fig, title, message)
% dlg = localProgressDialog_(fig, title, message)
% A progress dialog with a Stop button, or [] when the window is hidden.
%
% uiprogressdlg refuses to attach to an invisible figure, which would
% otherwise make the whole Monte Carlo path unrunnable in a headless test.
% The dialog is modal, so its own Stop button is the only control the user can
% reach while the run holds the thread -- hence Cancelable rather than a button
% on the Test Bench panel.
dlg = [];
if isempty(fig) || ~isvalid(fig) || fig.Visible ~= "on"
    return
end
dlg = uiprogressdlg(fig, Title = title, Message = message, Value = 0, ...
    Cancelable = 'on', CancelText = 'Stop');
end


function localProgress_(dlg, i, total)
% localProgress_(dlg, i, total)
% Update the Monte Carlo progress dialog, if there is one.
%
% The Stop click only reaches CancelRequested when the callback queue is
% flushed, and a Monte Carlo run never returns to idle until it finishes --
% so the flush has to happen here. limitrate keeps it from costing a redraw
% per trial.
if isempty(dlg) || ~isvalid(dlg)
    return
end
dlg.Value = i / total;
dlg.Message = sprintf('Simulating trial %d of %d...', i, total);
drawnow limitrate
end


function tf = localStopRequested_(dlg)
% tf = localStopRequested_(dlg)
% True once the user has pressed Stop on the progress dialog.
tf = ~isempty(dlg) && isvalid(dlg) && dlg.CancelRequested;
end


function localCloseDialog_(dlg)
% localCloseDialog_(dlg)
% Close a progress dialog if it is still open.
if ~isempty(dlg) && isvalid(dlg)
    close(dlg);
end
end
