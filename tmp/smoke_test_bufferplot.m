function smoke_test_bufferplot()
% smoke_test_bufferplot()
% Exercise gui.components.BufferPlot headlessly: auto-selection, capture from the trial
% record, the hardware-read fallback for a buffer the record does not carry,
% envelope decimation, the sample-rate x axis, trial history, the operator
% menu path (which is also what persists preferences), an offline DATA
% source, pop-out, and teardown. Every figure is closed before returning.
%
%   matlab -batch "run('tmp/smoke_test_bufferplot.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

PREF_TAG = 'smokeBufferPlotTest';
PREF_GROUP = 'epsych2_gui_BufferPlot';
cleanupObj = onCleanup(@() cleanupAll(PREF_TAG, PREF_GROUP));
cleanupAll(PREF_TAG, PREF_GROUP); % start from no saved arrangement

rt = makeRuntime();
wave = sin(2*pi*(0:9999)'/500) * 3;
wave(5000) = 12;          % the transient a stride would drop
lick = double(mod(0:999,100) < 10)';

% 1. Construction and auto-selection ---------------------------------------
fig = uifigure('Visible','off','Tag',PREF_TAG);
bp = gui.components.BufferPlot(rt, fig);
assert(isvalid(bp), 'construction should succeed');
assert(isequal(bp.bufferNames, {'SmokeWave','SmokeLick'}), ...
    'auto-selection should take the visible Buffer parameters in order (got %s)', ...
    strjoin(bp.bufferNames,', '));
assert(strcmp(bp.XAxisUnits,'samples'), 'the default x axis is buffer samples');
assert(isempty(findobj(bp.AxesH,'Type','line')), 'nothing is drawn before the first trial');
assert(~any(strcmp(bp.availableBuffers,'SmokeCoef')), ...
    'a Coefficient Buffer is session-static and must not be offered');
fprintf('PASS: construction, auto-selection, samples by default\n');

% 2. Capture from the trial record ----------------------------------------
notifyTrial(rt, makeTrial(1, wave, lick));
L = findobj(bp.AxesH,'Type','line');
assert(numel(L) == 2, 'one line per buffer after a trial (got %d)', numel(L));
assert(~any(strcmp(bp.availableBuffers,'SmokeCoef')), ...
    'a coefficient buffer must stay out of the list even once a record carries it');
fprintf('PASS: NewData draws both buffers out of the trial record\n');

% 3. Envelope decimation keeps the extremes -------------------------------
bp.MaxPoints = 200;
L = findobj(bp.AxesH,'Type','line');
np = arrayfun(@(h) numel(h.XData), L);
assert(all(np <= 200), 'traces should be decimated to MaxPoints (got %d)', max(np));
yAll = [L.YData];
assert(abs(max(yAll) - max(wave)) < 1e-9, ...
    'the envelope must keep the peak sample (%g vs %g)', max(yAll), max(wave));
assert(abs(min(yAll) - min([wave;lick])) < 1e-9, 'the envelope must keep the trough');
bp.MaxPoints = Inf;
L = findobj(bp.AxesH,'Type','line');
assert(max(arrayfun(@(h) numel(h.XData), L)) == numel(wave), ...
    'MaxPoints = Inf should draw every sample');
fprintf('PASS: envelope decimation, and Inf draws every sample\n');

% 4. Sample rate turns the axis into time ---------------------------------
bp.MaxPoints = 10000;
bp.SampleRate = 1000;
bp.XAxisUnits = 'milliseconds';
L = findobj(bp.AxesH,'Type','line');
xmax = max([L.XData]);
assert(abs(xmax - (numel(wave)-1)) < 1e-6, ...
    'at 1 kHz in ms the last sample is at %g ms, got %g', numel(wave)-1, xmax);
bp.XAxisUnits = 'seconds';
assert(abs(max([findobj(bp.AxesH,'Type','line').XData]) - (numel(wave)-1)/1000) < 1e-9, ...
    'seconds should be milliseconds over 1000');
fprintf('PASS: SampleRate and XAxisUnits move the x axis\n');

% 5. Trial history --------------------------------------------------------
bp.NumTrialsShown = 3;
for k = 2:4
    notifyTrial(rt, makeTrial(k, wave*k/4, lick));
end
L = findobj(bp.AxesH,'Type','line');
assert(numel(L) == 6, '2 buffers x 3 trials of history = 6 lines (got %d)', numel(L));
bp.NumTrialsShown = 1;
assert(numel(findobj(bp.AxesH,'Type','line')) == 2, 'back to one trial each');
fprintf('PASS: history depth\n');

% 6. The operator menu path, which is also what saves preferences ---------
assert(~bp.hasSavedConfiguration, 'nothing should be saved before the menu is used');
clickMenu(fig, 'tgl|ShowGrid');
assert(~bp.ShowGrid, 'the Grid item should have toggled ShowGrid');
assert(bp.hasSavedConfiguration, 'an operator change should persist');
clickMenu(fig, 'aes|Layout|stacked');
assert(strcmp(bp.Layout,'stacked'), 'the Layout item should have applied');
delete(bp);

bp = gui.components.BufferPlot(rt, fig);
assert(~bp.ShowGrid && strcmp(bp.Layout,'stacked'), ...
    'a saved arrangement should be restored');
assert(isequal(bp.bufferNames, {'SmokeWave','SmokeLick'}), ...
    'a selection the operator never made must not be restored over the auto one');

% ...but a selection the operator DID make outranks auto-selection. The
% constructor must decide "the caller stated buffers" from its options,
% BEFORE auto-selection fills a list in -- deciding it after made every
% auto-selected session look explicit, so the remembered selection was never
% restored anywhere a session had buffers to auto-select.
s = getpref(PREF_GROUP, PREF_TAG);       % preference key = the figure Tag
s.SelectionByOperator = true;
s.Buffers = {'SmokeLick'};
setpref(PREF_GROUP, PREF_TAG, s);
delete(bp);
bp = gui.components.BufferPlot(rt, fig);
assert(isequal(bp.bufferNames, {'SmokeLick'}), ...
    'the operator''s remembered selection must be restored over the auto one');
delete(bp);
bp = gui.components.BufferPlot(rt, fig, Buffers={'SmokeWave','SmokeLick'});
assert(isequal(bp.bufferNames, {'SmokeWave','SmokeLick'}), ...
    'a list the caller states still outranks the remembered selection');
s.SelectionByOperator = false;
s.Buffers = {};
setpref(PREF_GROUP, PREF_TAG, s);        % back to the auto pair below
delete(bp);
bp = gui.components.BufferPlot(rt, fig);
fprintf('PASS: menu changes apply, persist, and restore\n');

% 7. Programmatic changes do NOT persist ----------------------------------
bp.LineWidth = 3;
delete(bp);
bp = gui.components.BufferPlot(rt, fig);
assert(bp.LineWidth == 1, 'a programmatic change must not overwrite the saved arrangement');
fprintf('PASS: programmatic changes are not persisted\n');

% 8. Colours ---------------------------------------------------------------
bp.setTraceColor('SmokeLick', [1 0 0]);
c = bp.LineColors;
assert(isequal(c(2,:), [1 0 0]), 'setTraceColor should colour that trace');
bp.setBuffers({'SmokeLick','SmokeWave'});
c = bp.LineColors;
assert(isequal(c(1,:), [1 0 0]), 'a hand-picked colour follows its buffer through a reselection');
fprintf('PASS: per-trace colour, matched by name\n');

% 9. Pop-out ---------------------------------------------------------------
po = bp.popOut();
assert(~isempty(po) && isvalid(po) && bp.hasPopOut, 'pop-out should open');
assert(isequal(po.bufferNames, bp.bufferNames), 'the pop-out opens on what the host shows');
bp.closePopOut();
assert(~bp.hasPopOut, 'pop-out should close');
delete(bp); delete(fig);
fprintf('PASS: pop-out opens over the same buffers and closes cleanly\n');

% 10. The buffer the trial record does not carry --------------------------
fig2 = uifigure('Visible','off','Tag',[PREF_TAG '2']);
bpH = gui.components.BufferPlot(rt, fig2, Buffers="~SmokeHidden");
assert(isequal(bpH.bufferNames, {'~SmokeHidden'}), 'an invisible buffer can be named explicitly');
notifyTrial(rt, makeTrial(5, wave, lick)); % record has no ~SmokeHidden field
L = findobj(bpH.AxesH,'Type','line');
assert(isscalar(L), 'the fallback read should have drawn the hidden buffer');
assert(abs(max(L.YData) - 7) < 1e-9, 'it should hold the parameter value (max 7)');
delete(bpH); delete(fig2);
fprintf('PASS: hardware fallback for a buffer absent from the trial record\n');

% 11. Offline, over a saved DATA struct array -----------------------------
fig3 = uifigure('Visible','off','Tag',[PREF_TAG '3']);
D = [makeTrial(1, wave, lick), makeTrial(2, wave/2, lick)];
bpO = gui.components.BufferPlot(D, fig3, Buffers="SmokeWave", NumTrialsShown=2);
L = findobj(bpO.AxesH,'Type','line');
assert(numel(L) == 2, 'two trials of one buffer should draw offline (got %d)', numel(L));
s = bpO.exportToWorkspace('smokeBufferExport');
assert(numel(s.SmokeWave) == numel(wave), 'export should be full resolution');
evalin('base','clear smokeBufferExport');
delete(bpO); delete(fig3);
fprintf('PASS: offline source and workspace export\n');

fprintf('smoke_test_bufferplot: ALL PASS\n');
end


function rt = makeRuntime()
% Runtime with a software interface carrying two visible buffers, one
% invisible buffer, a coefficient buffer, and a scalar -- the last two must
% not be selected, or offered.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;

sw = hw.Software;
sw.add_parameter('SmokeWave', 0, Type='Buffer', isArray=true);
sw.add_parameter('SmokeLick', 0, Type='Buffer', isArray=true);
p = sw.add_parameter('~SmokeHidden', 0, Type='Buffer', isArray=true, Visible=false);
p.Value = linspace(0,7,4096)';
sw.add_parameter('SmokeCoef', 0, Type='Coefficient Buffer', isArray=true);
sw.add_parameter('SmokeLevel', 60);
rt.Interfaces = sw;
end


function t = makeTrial(idx, wave, lick)
% One DATA record, as ep_TimerFcn_RunTime writes it.
t = struct('SmokeWave',wave, 'SmokeLick',lick, 'SmokeCoef',(1:64)', ...
    'SmokeLevel',60, 'TrialID',1, 'TrialIndex',idx);
end


function notifyTrial(rt, record)
% Fire NewData with a DATA array ending in `record`, the way the runtime does.
persistent DATA
if isempty(DATA) || record.TrialIndex == 1
    DATA = record;
else
    DATA(end+1) = record;
end
trials = struct('DATA',DATA, 'Subject',1, 'BoxID',1);
rt.EVENTS.notify('NewData', epsych.TrialsData(trials));
end


function clickMenu(fig, tag)
% Invoke a context-menu item the way the operator does.
m = findall(fig,'Type','uimenu','-and','Tag',tag);
assert(~isempty(m), 'menu item "%s" should exist', tag);
feval(m(1).MenuSelectedFcn, m(1), []);
end


function cleanupAll(prefTag, prefGroup)
% Remove this test's preferences -- including the pop-out's, whose key is
% derived from the host tag -- and any stray test figures. Never the whole
% group: a rig running this has real gui.components.BufferPlot arrangements in it.
for t = {prefTag, [prefTag '2'], [prefTag '3']}
    delete(findall(groot,'Type','figure','-and','Tag',t{1}));
end
if ispref(prefGroup)
    stem = matlab.lang.makeValidName(prefTag);
    keys = fieldnames(getpref(prefGroup));
    mine = keys(startsWith(keys, stem));
    if ~isempty(mine), rmpref(prefGroup, mine); end
end
if ispref(prefTag), rmpref(prefTag); end
end
