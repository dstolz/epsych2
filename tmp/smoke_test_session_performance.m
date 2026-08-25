function smoke_test_session_performance()
% smoke_test_session_performance()
% Exercise psychophysics.TrialWindow, psychophysics.SessionMetrics, and
% gui.components.SessionPerformance: window parsing and resolution, metric arithmetic
% over every window mode, live updates from a NewData event, the
% programmatic and context-menu paths for changing the trial window and the
% metric selection, preference persistence, and teardown. Headless-safe:
% every figure is closed and every preference this test writes is restored
% on exit.
%
%   matlab -batch "run('tmp/smoke_test_session_performance.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

PREF_TAG = 'smoke_test_session_performance';
savedPrefs = snapshotPrefs(PREF_TAG);
cleanupObj = onCleanup(@() cleanupAll(PREF_TAG, savedPrefs));

% 1. TrialWindow: construction and shorthand parsing ----------------------
w = psychophysics.TrialWindow.allTrials();
assert(w.Mode == "All" && isequal(w.resolve(10), 1:10), 'all-trials window should select everything');

w = psychophysics.TrialWindow.lastN(20);
assert(isequal(w.resolve(47), 28:47), 'last-20 of 47 trials should be 28:47');
assert(isequal(w.resolve(5), 1:5), 'a window longer than the session should clamp');

w = psychophysics.TrialWindow.firstN(10);
assert(isequal(w.resolve(47), 1:10), 'first-10 should be 1:10');

w = psychophysics.TrialWindow.range(20,100);
assert(isequal(w.resolve(47), 20:47), 'a range past the end should clamp to the session');
assert(isempty(w.resolve(5)), 'a range starting past the end selects nothing');

assert(isequal(psychophysics.TrialWindow.range(20,Inf).resolve(30), 20:30), ...
    'an open-ended range should run to the last trial');
assert(isempty(psychophysics.TrialWindow.allTrials().resolve(0)), ...
    'no trials means no selection');

shorthand = {[], 'all', "all", 50, [20 100], "last 20", "first 10", "20-100", "20:100", "20+"};
expected = {"All","All","All","Last","Range","Last","First","Range","Range","Range"};
for i = 1:numel(shorthand)
    p = psychophysics.TrialWindow.parse(shorthand{i});
    assert(p.Mode == expected{i}, 'parse of input %d should give a %s window', i, expected{i});
end
assert(psychophysics.TrialWindow.parse(50).N == 50, 'a scalar should mean the last N trials');
assert(isequal(psychophysics.TrialWindow.parse([20 100]).Range, [20 100]), ...
    'a pair should mean a trial range');

assertThrows(@() psychophysics.TrialWindow.lastN(0), 'a zero trial count should be rejected');
assertThrows(@() psychophysics.TrialWindow.lastN(2.5), 'a fractional trial count should be rejected');
assertThrows(@() psychophysics.TrialWindow.range(100,20), 'a reversed range should be rejected');
assertThrows(@() psychophysics.TrialWindow.parse("sometimes"), 'unparseable text should be rejected');

assert(psychophysics.TrialWindow.lastN(20).label(47) == "Last 20 trials (28-47)", ...
    'label should state the window and the span it resolves to');
assert(contains(psychophysics.TrialWindow.range(60,80).label(47), 'no trials'), ...
    'a window selecting nothing should say so');

% toStruct/fromStruct round trip (how preferences are stored)
for w0 = {psychophysics.TrialWindow.allTrials(), psychophysics.TrialWindow.lastN(37), ...
        psychophysics.TrialWindow.firstN(4), psychophysics.TrialWindow.range(3,9)}
    assert(isequal(psychophysics.TrialWindow.fromStruct(w0{1}.toStruct()), w0{1}), ...
        'toStruct/fromStruct should round trip');
end
assert(psychophysics.TrialWindow.fromStruct(struct('junk',1)).Mode == "All", ...
    'an unrecognized saved window should fall back to all trials');
fprintf('PASS: psychophysics.TrialWindow\n');

% 2. SessionMetrics arithmetic (offline) ----------------------------------
% 20 trials: 12 stimulus (8 hit, 3 miss, 1 abort) and 8 catch (2 FA, 6 CR).
DATA = fakeData();
S = psychophysics.SessionMetrics(DATA);

assert(S.trialCount == 20, 'offline DATA should give 20 trials');
N = S.Results.N;
assert(N.Total == 20 && N.Stimulus == 12 && N.Catch == 8, 'trial-type counts');
assert(N.Hit == 8 && N.Miss == 3 && N.Abort == 1, 'stimulus outcome counts');
assert(N.FalseAlarm == 2 && N.CorrectReject == 6, 'catch outcome counts');
assert(abs(S.Results.Rate.Hit - 8/11) < 1e-12, 'hit rate is scored over hits and misses');
assert(abs(S.Results.Rate.FalseAlarm - 2/8) < 1e-12, 'FA rate is scored over catch trials');
assert(abs(S.Results.Rate.Abort - 1/20) < 1e-12, 'abort rate is scored over every included trial');
assert(abs(S.Results.Rate.Correct - 14/19) < 1e-12, 'percent correct pools hits and correct rejects');

expectedD = psychophysics.Detection.d_prime(8/11, 2/8, [0.05 0.95]);
assert(abs(S.Results.DPrime - expectedD) < 1e-12, 'd'' should match psychophysics.Detection');
fprintf('PASS: SessionMetrics computes session totals\n');

% 3. The trial window changes what is computed ----------------------------
S.TrialWindow = 10;                      % last 10 trials (11:20)
assert(isequal(S.Results.TrialIndex, 11:20), 'last-10 window should select trials 11:20');
assert(S.Results.N.Total == 10, 'only windowed trials should be counted');

S.TrialWindow = [1 10];
assert(isequal(S.Results.TrialIndex, 1:10), 'an explicit range should select trials 1:10');
firstHalf = S.Results.N.Hit;

S.TrialWindow = "last 10";
assert(S.Results.N.Hit + firstHalf == 8, 'the two halves should account for every hit');

S.TrialWindow = psychophysics.TrialWindow.range(50,60);
assert(S.Results.N.Total == 0 && isnan(S.Results.Rate.Hit) && isnan(S.Results.DPrime), ...
    'an empty window should report undefined rather than zero rates');
[~, txt] = S.metric("HitRate");
assert(txt == "--", 'an undefined metric should render as --');

% ExcludedTrials and the window intersect
S.TrialWindow = psychophysics.TrialWindow.allTrials();
S.ExcludedTrials = 1:10;
assert(isequal(S.Results.TrialIndex, 11:20), 'exclusions should drop trials from the window');
S.ExcludedTrials = [];
assert(S.Results.N.Total == 20, 'clearing exclusions should restore every trial');
fprintf('PASS: SessionMetrics honors the trial window and exclusions\n');

% 4. Metric catalogue and display strings ---------------------------------
T = S.summary();
assert(height(T) == numel(psychophysics.SessionMetrics.metricNames()), ...
    'summary should cover the whole catalogue');
assert(T.Text(T.Name == "HitRate") == "72.7%", 'hit rate should render as a percentage');
assert(T.Detail(T.Name == "HitRate") == "8/11", 'hit rate detail should show its denominator');
assert(T.Text(T.Name == "Trials") == "20", 'counts render as integers');
assert(contains(S.summaryText(), 'Hit Rate'), 'the text summary should label its metrics');
assertThrows(@() S.metric("NotAMetric"), 'an unknown metric name should be rejected');
fprintf('PASS: SessionMetrics summary formatting\n');

% 5. Single-trial-type paradigm (no trial types anywhere) -----------------
plain = untypedData(DATA);
Sp = psychophysics.SessionMetrics(plain);
assert(Sp.Results.N.Stimulus == 20 && Sp.Results.N.Catch == 20, ...
    'with no trial types every trial is scored for every outcome');
assert(Sp.Results.N.Hit == 8 && Sp.Results.N.FalseAlarm == 2, ...
    'a paradigm without trial types should still score every outcome');
delete(Sp);
fprintf('PASS: SessionMetrics falls back when trial types are absent\n');

% 6. gui.components.SessionPerformance over a live runtime ---------------------------
rt = fakeRuntime();
fig = uifigure('Visible','off','Tag',PREF_TAG,'Position',[100 100 380 320]);
panel = uipanel(fig,'Title','Session Performance','Units','normalized','Position',[0 0 1 1]);

P = gui.components.SessionPerformance(rt, panel, Metrics=["Trials","HitRate","FARate","DPrime"]);
assert(isa(P.Analysis,'psychophysics.SessionMetrics'), 'the panel should own a SessionMetrics');
assert(P.TrialWindow.Mode == "All", 'the default window is every trial');
assert(contains(P.HeaderH.Text,'All trials'), 'the header should name the active window');
assert(numel(P.GridH.RowHeight) == 1 + 4 + 1, 'header, four metric rows, and the filler');

% NewData drives both the analysis and the display
rt.EVENTS.notify('NewData', trialsEvent(DATA));
assert(P.Analysis.trialCount == 20, 'the analysis should follow the NewData event');
assert(valueText(P,"HitRate") == "72.7%", 'the panel should show the computed hit rate');
assert(contains(P.HeaderH.Text,'1-20'), 'the header should show the resolved span');
fprintf('PASS: gui.components.SessionPerformance builds and follows NewData\n');

% 7. Programmatic trial-window control ------------------------------------
P.TrialWindow = 10;
assert(P.Analysis.Results.N.Total == 10, 'setting the window should recompute');
assert(contains(P.HeaderH.Text,'Last 10 trials (11-20)'), ...
    'the header should track the window (got "%s")', P.HeaderH.Text);

P.setTrialWindow([1 10]);
assert(contains(P.HeaderH.Text,'Trials 1-10'), 'an explicit range should show in the header');

% a window changed on the analysis object directly still refreshes the panel
P.Analysis.TrialWindow = "all";
assert(contains(P.HeaderH.Text,'All trials'), ...
    'the panel should follow a window set on the analysis object');
fprintf('PASS: programmatic trial-window control\n');

% 8. Metric selection ------------------------------------------------------
P.setMetrics(["HitRate","MissRate","Aborts"]);
assert(isequal(P.Metrics, ["HitRate","MissRate","Aborts"]), 'metrics should be settable');
assert(numel(P.GridH.RowHeight) == 1 + 3 + 1, 'the rows should be rebuilt');

P.Metrics = ["DPrime","Trials","NotAMetric"];
assert(isequal(P.Metrics, ["DPrime","Trials"]), 'unknown metric names should be dropped');

P.setMetrics("NotAMetric");
assert(isequal(P.Metrics, psychophysics.SessionMetrics.defaultMetrics()), ...
    'an entirely unknown selection should fall back to the defaults');
fprintf('PASS: metric selection\n');

% 9. Context menu ----------------------------------------------------------
assert(~isempty(P.ContextMenu) && isvalid(P.ContextMenu), 'a context menu should exist');
assert(isequal(P.HeaderH.ContextMenu, P.ContextMenu), 'labels should carry the menu');
P.ContextMenu.ContextMenuOpeningFcn([],[]);   % builds the checkable entries

windowMenu = findobj(P.ContextMenu,'Text','Trials Included');
entries = string({windowMenu.Children.Text});
assert(any(entries == "All Trials") && any(entries == "Last 20 Trials") ...
    && any(entries == "Trial Range..."), 'the window menu should offer presets and a custom range');

allEntry = findobj(windowMenu,'Text','All Trials');
assert(allEntry.Checked == "on", 'the active window should be checked');

last20 = findobj(windowMenu,'Text','Last 20 Trials');
last20.MenuSelectedFcn([],[]);
assert(P.TrialWindow.Mode == "Last" && P.TrialWindow.N == 20, ...
    'choosing a preset should change the window');

metricMenu = findobj(P.ContextMenu,'Text','Show Metric');
hitEntry = findobj(metricMenu,'Text','Hit Rate');
assert(hitEntry.Checked == "on", 'a displayed metric should be checked');
hitEntry.MenuSelectedFcn([],[]);
assert(~ismember("HitRate", P.Metrics), 'toggling should remove the metric');
hitEntry = findobj(findobj(P.ContextMenu,'Text','Show Metric'),'Text','Hit Rate');
hitEntry.MenuSelectedFcn([],[]);
assert(ismember("HitRate", P.Metrics), 'toggling again should restore it');
assert(isequal(P.Metrics, orderedMetrics(P.Metrics)), 'metrics stay in catalogue order');
fprintf('PASS: context menu drives the window and the metric selection\n');

% 9b. Font size ------------------------------------------------------------
assert(P.FontSize == 12, 'the default caption size is 12pt');
assert(P.HeaderH.FontSize == 11, 'the header renders 1pt smaller than the captions');
assert(any(fontSizes(P) == 14), 'values render 2pt larger than the captions');

P.FontSize = 18;
assert(P.FontSize == 18, 'the font size should be settable as a property');
assert(P.HeaderH.FontSize == 17, 'the header should follow the caption size');
sizes = fontSizes(P);
assert(any(sizes == 18) && any(sizes == 20) && any(sizes == 16), ...
    'captions, values, and details should all scale');

P.setFontSize(200);
assert(P.FontSize == 72, 'an oversized value should clamp rather than throw');
P.setFontSize(1);
assert(P.FontSize == 6, 'an undersized value should clamp too');
P.setFontSize(14);

% the size survives a rebuild of the rows
P.setMetrics(["Trials","HitRate","FARate","DPrime"]);
assert(P.HeaderH.FontSize == 13, 'rebuilt rows should keep the chosen size');

P.ContextMenu.ContextMenuOpeningFcn([],[]);
fontMenu = findobj(P.ContextMenu,'Text','Font Size');
entries = string({fontMenu.Children.Text});
assert(any(entries == "14 pt") && any(entries == "Larger") && any(entries == "Custom..."), ...
    'the font menu should offer presets, steps, and a prompt');
assert(findobj(fontMenu,'Text','14 pt').Checked == "on", 'the active size should be checked');

findobj(fontMenu,'Text','20 pt').MenuSelectedFcn([],[]);
assert(P.FontSize == 20, 'choosing a preset should resize the panel');
P.ContextMenu.ContextMenuOpeningFcn([],[]);
findobj(findobj(P.ContextMenu,'Text','Font Size'),'Text','Smaller').MenuSelectedFcn([],[]);
assert(P.FontSize == 18, 'Smaller should step down 2pt');
fprintf('PASS: font size, programmatically and from the menu\n');

% 10. Persistence ----------------------------------------------------------
P.setMetrics(["Trials","DPrime"]);
P.setTrialWindow([5 15]);
P.setFontSize(15);
delete(P);

P2 = gui.components.SessionPerformance(rt, panel, Metrics="HitRate");
assert(isequal(P2.Metrics, ["Trials","DPrime"]), 'a saved selection should outrank the constructor default');
assert(P2.TrialWindow.Mode == "Range" && isequal(P2.TrialWindow.Range,[5 15]), ...
    'the saved trial window should be restored');
assert(P2.FontSize == 15 && P2.HeaderH.FontSize == 14, ...
    'the saved font size should be restored and applied to the rows');
fprintf('PASS: preferences persist across construction\n');

% 11. Pop-out window (gui.PopOut mixin) -----------------------------------
% The pop-out is a second, independent summary: its own analysis object, so
% narrowing its trial window leaves the embedded panel alone.
pop = P2.popOut();
assert(~isempty(pop) && isvalid(pop) && P2.hasPopOut(), 'popOut should open a sibling panel');
assert(pop.Analysis ~= P2.Analysis, 'the pop-out should compute through its own analysis');
assert(isequal(pop.Metrics, P2.Metrics), 'the pop-out should open showing what the host shows');

hostWindow = P2.TrialWindow;
pop.setTrialWindow(5);
assert(pop.TrialWindow.N == 5, 'the pop-out window should follow its own setting');
assert(isequal(P2.TrialWindow, hostWindow), 'the host window must not follow the pop-out');

popFig = P2.PopOutFigure;
P2.closePopOut();
assert(~P2.hasPopOut() && ~isvalid(pop) && ~isvalid(popFig), ...
    'closePopOut should delete the sibling and its window');
assert(isvalid(P2), 'the host panel should survive its pop-out');
fprintf('PASS: pop-out window\n');

% 12. Teardown -------------------------------------------------------------
analysis = P2.Analysis;
delete(P2);
assert(~isvalid(analysis), 'a panel-created analysis should be deleted with the panel');

% an analysis supplied by the caller is left alone
shared = psychophysics.SessionMetrics(DATA);
P3 = gui.components.SessionPerformance(shared, panel, PreferenceTag='smoke_shared');
delete(P3);
assert(isvalid(shared), 'a caller-supplied analysis should survive the panel');
delete(shared);

% deleting the graphics tears the component down too
P4 = gui.components.SessionPerformance(rt, panel, PreferenceTag='smoke_shared');
grid4 = P4.GridH;
delete(grid4);
assert(~isvalid(P4), 'destroying the layout should delete the component');

close(fig);
fprintf('PASS: teardown\n');

fprintf('smoke_test_session_performance: ALL PASS\n');
end


function s = valueText(P, name)
% Displayed value for one metric, read back out of the panel.
h = findobj(P.GridH,'Type','uilabel');
[~, text] = P.Analysis.metric(name);
s = string(text);
assert(any(strcmp({h.Text}, char(text))), 'metric "%s" should be displayed', name);
end


function sz = fontSizes(P)
% Font sizes in use across the panel's labels.
h = findobj(P.GridH,'Type','uilabel');
sz = [h.FontSize];
end


function names = orderedMetrics(names)
all_ = psychophysics.SessionMetrics.metricNames();
names = all_(ismember(all_, names));
end


function assertThrows(fcn, msg)
try
    fcn();
catch
    return
end
error('smoke_test_session_performance:expectedError', msg);
end


function DATA = fakeData()
% 20 trials: 12 stimulus (8 hit, 3 miss, 1 abort), 8 catch (2 FA, 6 CR).
stim  = epsych.BitMask.TrialType_0;
ctch  = epsych.BitMask.TrialType_1;
codes = [ ...
    repmat(bit(epsych.BitMask.Hit,  stim), 1, 8), ...
    repmat(bit(epsych.BitMask.Miss, stim), 1, 3), ...
    bit(epsych.BitMask.Abort, stim), ...
    repmat(bit(epsych.BitMask.FalseAlarm,    ctch), 1, 2), ...
    repmat(bit(epsych.BitMask.CorrectReject, ctch), 1, 6)];

% interleave so the windows exercised above straddle both trial types
order = reshape([1:10; 11:20], 1, []);
codes = codes(order);
types = [zeros(1,12) ones(1,8)];
types = types(order);

DATA = struct('RespCode', num2cell(codes), 'TrialType', num2cell(types), ...
    'TrialID', num2cell(1:20));
end


function DATA = untypedData(DATA)
% Same outcomes with every trace of the trial type removed: no TrialType
% field and no TrialType bits in RespCode.
DATA = rmfield(DATA,'TrialType');
for i = 1:numel(DATA)
    c = DATA(i).RespCode;
    c = bitset(c, double(epsych.BitMask.TrialType_0), 0);
    c = bitset(c, double(epsych.BitMask.TrialType_1), 0);
    DATA(i).RespCode = c;
end
end


function m = bit(varargin)
m = uint32(0);
for i = 1:nargin
    m = bitset(m, double(varargin{i}));
end
end


function evt = trialsEvent(DATA)
% Minimal stand-in for the RUNTIME.TRIALS payload of a NewData event.
T.Subject = 'TEST';
T.BoxID   = 1;
T.DATA    = DATA;
T.TrialIndex = numel(DATA);
evt = epsych.TrialsData(T);
end


function rt = fakeRuntime()
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
end


function s = snapshotPrefs(prefTag)
% Every preference key this test can touch: the panel's own (figure Tag),
% the explicit tag used for the shared-analysis panels, and the pop-out's
% derived key.
s = struct('tag', {{}}, 'value', {{}});
for name = {matlab.lang.makeValidName(prefTag), 'smoke_shared', popOutTag(prefTag)}
    s.tag{end+1} = name{1};
    if ispref('epsych2_gui_SessionPerformance', name{1})
        s.value{end+1} = getpref('epsych2_gui_SessionPerformance', name{1});
    else
        s.value{end+1} = [];
    end
end
end


function t = popOutTag(prefTag)
% Mirrors gui.PopOut.popOutPreferenceTag_ for this component.
t = matlab.lang.makeValidName([prefTag '_SessionPerformance_PopOut']);
end


function cleanupAll(prefTag, savedPrefs)
for i = 1:numel(savedPrefs.tag)
    name = savedPrefs.tag{i};
    if isempty(savedPrefs.value{i})
        if ispref('epsych2_gui_SessionPerformance', name)
            rmpref('epsych2_gui_SessionPerformance', name);
        end
    else
        setpref('epsych2_gui_SessionPerformance', name, savedPrefs.value{i});
    end
end
% gui.PopOut saves its window position under the pop-out tag's own group
if ispref(popOutTag(prefTag))
    rmpref(popOutTag(prefTag));
end
delete(findall(groot,'Type','figure','-and','Tag',prefTag));
delete(findall(groot,'Type','figure','-and','Tag',popOutTag(prefTag)));
end
