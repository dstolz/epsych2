function smoke_test_popout()
% smoke_test_popout()
% Exercise the gui.PopOut mixin across every component that adopts it:
% gui.ParameterScatter, gui.History, gui.SessionPerformance, gui.NextTrial,
% gui.Parameter_Monitor, gui.PsychPlot, and psychophysics.Staircase, plus
% gui.BehaviorGUI.addPopOutButton.
%
% The claims under test, for each component:
%   - popOut builds a SECOND instance in a window of its own, leaving the
%     embedded component and its graphics untouched
%   - the pop-out's settings are its own: changing them (or closing the
%     window) does not reach back into the embedded component
%   - the pop-out saves preferences under a different key than its host
%   - popOut called again raises the same window rather than opening another
%   - closePopOut removes only the pop-out
%   - destroying the host takes its pop-out window with it
%
% Headless-safe: every GUI is closed and every timer deleted before returning.
%
%   matlab -batch "run('tmp/smoke_test_popout.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % FakeScatterRuntime, PopOutBehaviorGUI, +psychophysics/FakeHistoryPsych

TAGS = {'smokePO_scatter','smokePO_hist','smokePO_perf','smokePO_next', ...
    'smokePO_mon','smokePO_stair','smokePopOutScatter'};
cleanupObj = onCleanup(@() cleanupAll(TAGS));
cleanupPrefs();

% 1. gui.ParameterScatter: a second, independent scatter ------------------
D  = makeData(20);
f1 = uifigure('Visible','off','Tag','SmokePO_Scatter');
S  = gui.ParameterScatter(D, f1, PreferenceTag='smokePO_scatter', ...
    XParameter='FreqHz', YParameter='LevelDB');

assert(isa(S,'gui.PopOut'), 'gui.ParameterScatter should adopt the gui.PopOut mixin');
assert(~S.hasPopOut(), 'no pop-out should exist before popOut is called');
assertMenuItem(f1, 'gui.ParameterScatter');

P = S.popOut();
assert(isvalid(P) && isa(P,'gui.ParameterScatter'), 'popOut should return a ParameterScatter');
assert(P ~= S, 'the pop-out must be a separate instance, not the host');
assert(S.hasPopOut() && isvalid(S.PopOutFigure), 'the pop-out figure should be open');
assert(P.AxesH ~= S.AxesH, 'the pop-out must own separate axes');
assert(endsWith(S.PopOutFigure.Tag,'_PopOut'), ...
    'pop-out figure Tag should be the pop-out preference key (got %s)', S.PopOutFigure.Tag);
assert(~strcmp(S.PopOutFigure.Tag,'smokePO_scatter'), ...
    'the pop-out must not save preferences under the host key');
assert(strcmp(P.XParameter,'FreqHz') && strcmp(P.YParameter,'LevelDB'), ...
    'a first-time pop-out should open on what the host is showing');
assert(numel(P.ScatterH.XData) == 20, 'the pop-out should plot the same trials');
fprintf('PASS: scatter pop-out is a separate instance seeded from the host\n');

% Changing the pop-out leaves the embedded scatter alone.
P.XParameter = 'Trial Number';
P.MarkerSize = 96;
assert(strcmp(S.XParameter,'FreqHz'), 'host X selection changed with the pop-out');
assert(S.MarkerSize ~= 96, 'host marker size changed with the pop-out');
assert(isvalid(S.AxesH) && isequal(S.ScatterH.XData,[D.FreqHz]), ...
    'host plot should still be drawn from its own selection');
fprintf('PASS: pop-out edits do not reach the embedded scatter\n');

% A second popOut raises the same window rather than opening another.
before = numel(findall(groot,'Type','figure'));
P2 = S.popOut();
assert(P2 == P, 'popOut should raise the existing pop-out, not build a new one');
assert(numel(findall(groot,'Type','figure')) == before, 'popOut opened a second window');
fprintf('PASS: popOut raises an already-open window\n');

% Closing the pop-out removes only the pop-out.
popFig = S.PopOutFigure;
S.closePopOut();
assert(~isvalid(P) && ~isvalid(popFig), 'closePopOut should delete the pop-out and its window');
assert(isvalid(S) && isvalid(S.AxesH), 'the host must survive its pop-out closing');
assert(~S.hasPopOut(), 'hasPopOut should be false after closePopOut');
S.update; % the host still redraws normally
fprintf('PASS: closing the pop-out leaves the host intact\n');

% Destroying the host takes the pop-out window with it.
P = S.popOut();
popFig = S.PopOutFigure;
delete(S);
assert(~isvalid(P) && ~isvalid(popFig), 'deleting the host should close its pop-out');
delete(f1);
fprintf('PASS: destroying the host closes the pop-out window\n');

% 2. gui.History ----------------------------------------------------------
HP = psychophysics.FakeHistoryPsych('FreqHz');
HP.setData(makeData(12));
f2 = uifigure('Visible','off','Tag','SmokePO_Hist');
H = gui.History(HP, f2, PreferenceTag='smokePO_hist');
H.ParametersOfInterest = {'FreqHz','LevelDB'};
H.update;
assertMenuItem(f2, 'gui.History');

HPop = H.popOut();
assert(isvalid(HPop) && HPop ~= H, 'History popOut should return a separate instance');
assert(HPop.TableH ~= H.TableH, 'the pop-out must own a separate uitable');
assert(isequal(HPop.ParametersOfInterest, H.ParametersOfInterest), ...
    'a first-time pop-out should mirror the host columns');
assert(size(HPop.TableH.Data,1) > 0, 'the pop-out table should be populated at once');

HPop.ParametersOfInterest = {'FreqHz'};
HPop.update;
assert(numel(H.ParametersOfInterest) == 2, 'host columns changed with the pop-out');
assert(size(H.TableH.Data,2) == numel(H.ParametersOfInterest) + 3, ...
    'the host table should still render Trial, Time, Response and its own columns');
H.closePopOut();
assert(isvalid(H) && isvalid(H.TableH), 'History host should survive its pop-out');
delete(f2);
fprintf('PASS: history pop-out is independent of the embedded table\n');

% 3. gui.SessionPerformance ----------------------------------------------
f3 = uifigure('Visible','off','Tag','SmokePO_Perf');
SP = gui.SessionPerformance(makeData(30), f3, PreferenceTag='smokePO_perf', ...
    Metrics=["Trials","HitRate"]);
assertMenuItem(f3, 'gui.SessionPerformance');

SPop = SP.popOut();
assert(isvalid(SPop) && SPop ~= SP, 'SessionPerformance popOut should return a separate instance');
assert(SPop.Analysis ~= SP.Analysis, ...
    'the pop-out must compute through an analysis object of its own');
assert(isequal(SPop.Metrics, SP.Metrics), 'a first-time pop-out should mirror the host metrics');

SPop.TrialWindow = 5;
assert(SP.TrialWindow.Mode == "All", ...
    'host trial window changed with the pop-out (now %s)', SP.TrialWindow.describe());
SPop.setMetrics("DPrime");
assert(numel(SP.Metrics) == 2, 'host metric selection changed with the pop-out');
SP.closePopOut();
assert(isvalid(SP.Analysis), 'the host analysis must survive the pop-out closing');
delete(f3);
fprintf('PASS: performance pop-out summarizes its own trial window\n');

% 4. gui.NextTrial --------------------------------------------------------
rt  = FakeScatterRuntime();
f4  = uifigure('Visible','off','Tag','SmokePO_Next');
NT  = gui.NextTrial(rt, f4, Fields=["FreqHz","LevelDB"], PreferenceTag='smokePO_next');
assertMenuItem(f4, 'gui.NextTrial');

NPop = NT.popOut();
assert(isvalid(NPop) && NPop ~= NT, 'NextTrial popOut should return a separate instance');
assert(isequal(NPop.SelectedFields, NT.SelectedFields), ...
    'a first-time pop-out should mirror the host field selection');
NPop.setFields("FreqHz");
assert(numel(NT.SelectedFields) == 2, 'host field selection changed with the pop-out');
NT.closePopOut();
assert(isvalid(NT.TableH), 'NextTrial host should survive its pop-out');
delete(f4);
fprintf('PASS: next-trial pop-out keeps its own field selection\n');

% 5. gui.Parameter_Monitor ------------------------------------------------
sw   = hw.Software();
pIn  = hw.Parameter(sw, Name='InTrial', Type='Boolean'); pIn.Value = 0;
pLvl = hw.Parameter(sw, Name='Level', Type='Float', Min=0, Max=100); pLvl.Value = 40;

f5 = uifigure('Visible','off','Tag','SmokePO_Mon');
M  = gui.Parameter_Monitor(f5, [pIn pLvl], pollPeriod=5, type="graphical", ...
    PreferenceTag="smokePO_mon");
M.stop();
assertMenuItem(f5, 'gui.Parameter_Monitor');

MPop = M.popOut();
MPop.stop();
assert(isvalid(MPop) && MPop ~= M, 'Parameter_Monitor popOut should return a separate instance');
assert(MPop.Timer ~= M.Timer, 'the pop-out must own its own polling timer');
assert(numel(MPop.VisibleParameters) == 2, 'the pop-out should show the host parameters');

MPop.set_parameter_visible("Level", false);
assert(numel(M.VisibleParameters) == 2, 'host visibility changed with the pop-out');
assert(isscalar(MPop.VisibleParameters), 'the pop-out should have hidden its own parameter');
M.closePopOut();
assert(~isvalid(MPop), 'closePopOut should delete the pop-out monitor and its timer');
assert(isvalid(M) && numel(M.VisibleParameters) == 2, 'the host monitor should be untouched');
delete(f5);
fprintf('PASS: monitor pop-out polls and hides independently\n');

% 6. psychophysics.Staircase ---------------------------------------------
SC = psychophysics.Staircase(makeStaircaseData(40), 'Depth');
f6 = uifigure('Visible','off','Tag','SmokePO_Stair');
ax = uiaxes(uigridlayout(f6,[1 1]));
SC.Plot(ax);
assertMenuItem(f6, 'psychophysics.Staircase');

CPop = SC.popOut();
assert(isvalid(CPop) && isa(CPop,'psychophysics.Staircase'), ...
    'Staircase popOut should return a Staircase');
assert(CPop ~= SC, 'the pop-out must be a separate analysis object');
assert(CPop.trialCount == SC.trialCount, 'the pop-out should open on the same trials');
assert(isequal(CPop.Results.Threshold, SC.Results.Threshold), ...
    'the pop-out should compute the same threshold as the host');

CPop.ConvertToDecibels = ~SC.ConvertToDecibels;
CPop.refresh_history();
assert(SC.ConvertToDecibels == false, 'host dB setting changed with the pop-out');
assert(isvalid(ax), 'the host axes must survive the pop-out');

popFig = SC.PopOutFigure;
SC.closePopOut();
assert(~isvalid(CPop) && ~isvalid(popFig), 'closePopOut should delete the pop-out staircase');
assert(isvalid(ax) && ~isempty(SC.Results.Threshold), 'the host plot should still be live');
delete(SC);
delete(f6);
fprintf('PASS: staircase pop-out analyses the same trials independently\n');

% 7. gui.PsychPlot --------------------------------------------------------
PP_psych = psychophysics.FakeHistoryPsych(pLvl);
PP_psych.setData(makeData(10));
f7  = uifigure('Visible','off','Tag','SmokePO_Psych');
pax = axes(uipanel(f7,'Units','normalized','Position',[0 0 1 1]));
PP  = gui.PsychPlot(PP_psych, pax);
assertMenuItem(f7, 'gui.PsychPlot');

PPop = PP.popOut();
assert(isvalid(PPop) && PPop ~= PP, 'PsychPlot popOut should return a separate instance');
assert(PPop.ax ~= PP.ax, 'the pop-out must own separate axes');
PPop.PlotType = 'Hit_Rate';
assert(strcmp(PP.PlotType,'DPrime'), 'host plot type changed with the pop-out');
PP.closePopOut();
assert(isvalid(PP.ax), 'PsychPlot host should survive its pop-out');
delete(f7);
fprintf('PASS: psychometric plot pop-out keeps its own plot type\n');

% 8. gui.BehaviorGUI.addPopOutButton ------------------------------------------
g = PopOutBehaviorGUI(makeRuntime());
assert(isvalid(g.PopButton), 'addPopOutButton should create a button');
assert(~g.Scatter.hasPopOut(), 'no pop-out before the button is pressed');

g.PopButton.ButtonPushedFcn([], []); % simulate the operator's click
assert(g.Scatter.hasPopOut(), 'the button should open the component pop-out');
popFig = g.Scatter.PopOutFigure;
assert(isvalid(g.Scatter.AxesH), 'the embedded scatter must be left in place');

g.closeGUI(g.h_figure, []); % the normal close path
assert(~isvalid(popFig), 'closing the BehaviorGUI should close its components pop-outs');
fprintf('PASS: BehaviorGUI pop-out button opens and closes with the GUI\n');

fprintf('\nsmoke_test_popout: all checks passed\n');
end


% -- helpers ---------------------------------------------------------------

function assertMenuItem(fig, componentName)
% The whole feature is reached from a right-click, so assert the item is
% actually on the menu: addPopOutMenu_ logs and continues on failure.
m = findall(fig, 'Type', 'uimenu', 'Tag', gui.PopOut.POPOUT_MENU_TAG);
assert(~isempty(m), '%s should add a pop-out item to its context menu', componentName);
assert(contains(m(1).Text, 'Separate Window'), ...
    '%s pop-out menu item reads "%s"', componentName, m(1).Text);
end


function D = makeData(n)
% Per-trial DATA struct array shaped like RUNTIME.TRIALS.DATA.
resp = [epsych.BitMask.Hit epsych.BitMask.Miss ...
    epsych.BitMask.CorrectReject epsych.BitMask.FalseAlarm];
D = struct([]);
for k = 1:n
    D(k).TrialID = mod(k-1,4)+1;
    D(k).RespCode = bitset(uint32(0), uint32(resp(mod(k-1,4)+1)));
    D(k).computerTimestamp = datetime('now') + seconds(k);
    D(k).TrialType = double(mod(k,4) == 0);
    D(k).FreqHz = 1000*2^mod(k,5);
    D(k).LevelDB = 30 + 5*mod(k,7);
    D(k).RespLatency = 100 + 3*mod(k,11);
end
end


function D = makeStaircaseData(n)
% Descending staircase with reversals, enough for a threshold estimate.
HIT  = bitset(uint32(0), uint32(epsych.BitMask.Hit));
MISS = bitset(uint32(0), uint32(epsych.BitMask.Miss));
depth = 40;
D = struct('Depth',{},'RespCode',{},'TrialType',{});
for k = 1:n
    if mod(floor((k-1)/3),2) == 0
        D(end+1) = struct('Depth',depth,'RespCode',HIT,'TrialType',0); %#ok<AGROW>
        depth = max(5, depth - 5);
    else
        D(end+1) = struct('Depth',depth,'RespCode',MISS,'TrialType',0); %#ok<AGROW>
        depth = min(60, depth + 5);
    end
end
end


function rt = makeRuntime()
% Runtime with a connected software interface, enough for a BehaviorGUI to open.
rt = epsych.Runtime;
rt.isTest = true;
rt.HELPER = epsych.Helper;

sw = hw.Software;
p = sw.add_parameter('SmokeFreq', 1000, Unit='Hz'); p.Value = 1000;
p = sw.add_parameter('SmokeLevel', 60);             p.Value = 60;
rt.Interfaces = sw;
end


function cleanupPrefs()
% Remove every preference this test can create. A pop-out's key is derived
% from its hosting figure's Tag, and it saves its window position in a
% preference GROUP of that name, so both are matched by the shared 'smokepo'
% marker in the tags this test uses rather than spelled out one by one.
% Leftovers matter: a pop-out with saved preferences restores them instead
% of mirroring its host, which is exactly what section 1 asserts about.
S = getpref;
groups = fieldnames(S);
for gi = 1:numel(groups)
    g = groups{gi};
    if contains(lower(g),'smokepo')
        rmpref(g);
        continue
    end
    if ~startsWith(g,'epsych2_gui_'), continue; end
    names = fieldnames(S.(g));
    hit = names(contains(lower(names),'smokepo'));
    for k = 1:numel(hit)
        rmpref(g, hit{k});
    end
end
end


function cleanupAll(tags)
cleanupPrefs();

for k = 1:numel(tags)
    delete(findall(groot,'Type','figure','-and','Tag',tags{k}));
end
figs = findall(groot,'Type','figure');
for k = 1:numel(figs)
    if contains(lower(figs(k).Tag),'smokepo')
        delete(figs(k));
    end
end

try
    T = timerfindall;
    if ~isempty(T)
        T = T(startsWith({T.Name},'Parameter_Monitor_Timer_'));
        if ~isempty(T)
            stop(T);
            delete(T);
        end
    end
catch
end
end
