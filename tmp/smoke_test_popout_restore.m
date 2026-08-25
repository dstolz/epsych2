function smoke_test_popout_restore()
% smoke_test_popout_restore()
% Exercise gui.BehaviorGUI's RestorePopOuts memory: the display windows an
% operator had open are reopened, as they were, the next time the GUI runs.
%
% The claims under test:
%   - with nothing remembered, a GUI opens no display windows and writes no
%     preference
%   - a window opening or closing is recorded AS IT HAPPENS, not at teardown,
%     so a MATLAB that never closed cleanly still remembers
%   - both kinds of window are remembered: a component's own pop-out and one
%     gui.components.ComponentToolbar opened for a lazy entry
%   - relaunching reopens them at the size they were left, still pinned if
%     they were pinned, with the lazy factory run once
%   - closing one window updates the memory, so it stays shut next time
%   - a remembered display this GUI does not have is skipped, is LEFT in the
%     list rather than erased, and does not stop the rest reopening
%   - RestorePopOuts=false reopens nothing and records nothing
%   - forgetPopOutLayout clears the list without touching what each window
%     remembers about its own appearance
%
% Headless-safe: every GUI is closed, every window unpinned, and every
% preference removed before returning.
%
%   matlab -batch "run('tmp/smoke_test_popout_restore.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % ComponentToolbarBehaviorGUI

cleanupObj = onCleanup(@() cleanupAll());
cleanupPrefs();

PREF = 'smokeCT_GUI';
KEY  = 'OpenPopOuts';

% 1. Nothing remembered, nothing opened -----------------------------------
g = ComponentToolbarBehaviorGUI(makeRuntime(), RestorePopOuts=true);

assert(g.RestorePopOuts, 'the constructor option should reach the property');
assert(~g.Scatter.hasPopOut(), 'a GUI with nothing remembered should open no pop-out');
assert(isempty(openWindows()), 'a GUI with nothing remembered should open no windows');
assert(~ispref(PREF,KEY), ...
    'a GUI that opened nothing should not write a layout preference');
fprintf('PASS: with nothing remembered the GUI opens no display windows\n');

% 2. Opening is recorded as it happens ------------------------------------
g.Scatter.popOut();
assert(isequal(saved(PREF,KEY), "Component:Parameter Scatter"), ...
    'popping out should record the component at once, got: %s', ...
    strjoin(saved(PREF,KEY), ', '));

perfTool = findTool(g.h_figure, 'Performance');
perfTool.ClickedCallback([],[]);
assert(g.LazyCalls == 1, 'the lazy factory should have run once');
ids = saved(PREF,KEY);
assert(numel(ids) == 2 && all(ismember( ...
    ["Component:Parameter Scatter" "Toolbar:Performance"], ids)), ...
    'both kinds of window should be recorded, got: %s', strjoin(ids, ', '));
fprintf('PASS: a window is recorded the moment it opens, not at teardown\n');

% 3. Leave each window in a distinctive state -----------------------------
popFig = g.Scatter.PopOutFigure;
popFig.Position = [220 180 640 420];
pin(popFig, true);
assert(gui.PopOut.isAlwaysOnTop(popFig), 'the pop-out should be pinned for the next section');

lazyFig = lazyWindow('Performance');
lazyFig.Position = [150 140 430 260];

% 4. Closing the GUI keeps the record -------------------------------------
g.closeGUI(g.h_figure, []);
assert(~isvalid(popFig) && ~isvalid(lazyFig), 'closing the GUI should close its windows');
ids = saved(PREF,KEY);
assert(numel(ids) == 2, ...
    'closing the GUI must not erase what was open, got: %s', strjoin(ids, ', '));
fprintf('PASS: closing the GUI leaves the remembered list intact\n');

% 5. Relaunching brings them back, as they were ---------------------------
g = ComponentToolbarBehaviorGUI(makeRuntime(), RestorePopOuts=true);

assert(g.Scatter.hasPopOut(), 'the pop-out that was open should reopen');
popFig = g.Scatter.PopOutFigure;
assert(isequal(popFig.Position(3:4), [640 420]), ...
    'the pop-out should reopen at the size it was left, got [%s]', num2str(popFig.Position(3:4)));
assert(gui.PopOut.isAlwaysOnTop(popFig), 'a pinned pop-out should reopen pinned');
assert(isscalar(aotItem(popFig)) && ...
    aotItem(popFig).Checked == matlab.lang.OnOffSwitchState.on, ...
    'the reopened window should show itself as pinned');

lazyFig = lazyWindow('Performance');
assert(g.LazyCalls == 1, 'the lazy factory should have run once during the restore');
assert(isequal(lazyFig.Position(3:4), [430 260]), ...
    'the lazy window should reopen at the size it was left, got [%s]', ...
    num2str(lazyFig.Position(3:4)));
fprintf('PASS: both windows reopen, sized and pinned as they were left\n');

assert(isvalid(g.h_figure), 'reopening windows must leave the GUI itself alive');

% 6. Closing one window is remembered too ---------------------------------
pin(popFig, false); % so nothing is left pinned to the desktop below
g.Scatter.closePopOut();
assert(isequal(saved(PREF,KEY), "Toolbar:Performance"), ...
    'closing a window should drop it from the list, got: %s', strjoin(saved(PREF,KEY), ', '));

g.closeGUI(g.h_figure, []);
g = ComponentToolbarBehaviorGUI(makeRuntime(), RestorePopOuts=true);
assert(~g.Scatter.hasPopOut(), 'a window closed last session should stay closed');
assert(isscalar(lazyWindow('Performance')), 'the window left open should still reopen');
fprintf('PASS: a window closed by the operator stays closed next session\n');

% 7. A remembered display this GUI does not have --------------------------
g.closeGUI(g.h_figure, []);
setpref(PREF, KEY, {'Component:No Such Display', 'Toolbar:Gone', ...
    'Component:Parameter Scatter'});

g = ComponentToolbarBehaviorGUI(makeRuntime(), RestorePopOuts=true);
assert(g.Scatter.hasPopOut(), 'an unknown entry must not stop the known ones opening');
assert(isempty(lazyWindow('Performance')), 'only the recorded windows should open');

% Still remembered, so a session run against a smaller protocol cannot
% erase the layout a fuller one had -- even after a later rewrite.
g.Scatter.closePopOut();
ids = saved(PREF,KEY);
assert(all(ismember(["Component:No Such Display" "Toolbar:Gone"], ids)), ...
    'entries this GUI cannot show should stay remembered, got: %s', strjoin(ids, ', '));
assert(~any(ids == "Component:Parameter Scatter"), ...
    'the window actually closed should still be dropped, got: %s', strjoin(ids, ', '));
fprintf('PASS: a display this GUI cannot show is skipped but stays remembered\n');

% 8. Off by default: nothing reopens, nothing is recorded ------------------
g.closeGUI(g.h_figure, []);
cleanupPrefs();
setpref(PREF, KEY, {'Component:Parameter Scatter'});

g = ComponentToolbarBehaviorGUI(makeRuntime());
assert(~g.RestorePopOuts, 'RestorePopOuts should be off unless asked for');
assert(~g.Scatter.hasPopOut(), 'a GUI that did not ask should reopen nothing');

g.Scatter.popOut();
assert(isequal(saved(PREF,KEY), "Component:Parameter Scatter"), ...
    'a GUI that did not ask should not rewrite the list');
g.Scatter.closePopOut();
assert(isequal(saved(PREF,KEY), "Component:Parameter Scatter"), ...
    'a GUI that did not ask should not rewrite the list on close either');
fprintf('PASS: RestorePopOuts=false reopens nothing and records nothing\n');

% 9. Turning it on mid-session, and forgetting the layout -----------------
g.RestorePopOuts = true;
g.Scatter.popOut();
assert(isequal(saved(PREF,KEY), "Component:Parameter Scatter"), ...
    'turning the memory on should make the next change record');

g.Scatter.closePopOut(); % writes the window's own position preference
assert(isempty(saved(PREF,KEY)), 'closing the only window should empty the list');
g.Scatter.popOut();

g.forgetPopOutLayout();
assert(~ispref(PREF,KEY), 'forgetPopOutLayout should clear the list');
assert(ispref('smokeCT_GUI_ParameterScatter_PopOut','FigurePosition'), ...
    'forgetting the list must not forget what the window itself remembers');

g.closeGUI(g.h_figure, []);
assert(isequal(saved(PREF,KEY), "Component:Parameter Scatter"), ...
    'the teardown snapshot should record what was open when the GUI closed');
fprintf('PASS: the memory can be turned on mid-session, and forgotten\n');

fprintf('\nALL PASS: smoke_test_popout_restore\n');
end


% -- helpers ---------------------------------------------------------------

function ids = saved(prefGroup, key)
% The remembered list as a string row, empty when nothing is saved.
ids = string.empty(1,0);
if ispref(prefGroup, key)
    ids = reshape(string(getpref(prefGroup, key)), 1, []);
end
end


function t = findTool(fig, entryName)
tag = matlab.lang.makeValidName(sprintf('ctb_%s', entryName));
t = findall(fig, 'Tag', tag);
assert(isscalar(t), 'expected one tool tagged %s, found %d', tag, numel(t));
end


function f = lazyWindow(entryName)
% The window gui.components.ComponentToolbar owns for a lazy entry, by its preference tag.
f = findall(groot, 'Type', 'figure', '-and', 'Tag', ...
    matlab.lang.makeValidName(sprintf('smokeCT_GUI_%s_Tool', entryName)));
end


function f = openWindows()
% Every smokeCT window except the GUIs themselves.
figs = findall(groot,'Type','figure');
keep = false(size(figs));
for k = 1:numel(figs)
    keep(k) = contains(lower(figs(k).Tag),'smokect') && ~strcmp(figs(k).Tag,'smokeCT_GUI');
end
f = figs(keep);
end


function m = aotItem(fig)
m = findall(fig, 'Type', 'uimenu', 'Tag', gui.PopOut.ALWAYSONTOP_MENU_TAG);
end


function pin(fig, tf)
% Pin through the menu item, the way the operator does, so the saved flag
% is written by the same path the feature uses.
m = aotItem(fig);
assert(isscalar(m), 'expected one always-on-top item on the window');
if gui.PopOut.isAlwaysOnTop(fig) ~= tf
    m.MenuSelectedFcn(m,[]);
end
end


function rt = makeRuntime()
% Runtime with a connected software interface, enough for a BehaviorGUI to open.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;

sw = hw.Software;
p = sw.add_parameter('SmokeFreq', 1000, Unit='Hz'); p.Value = 1000;
p = sw.add_parameter('SmokeLevel', 60);             p.Value = 60;
rt.Interfaces = sw;
end


function cleanupPrefs()
% Remove every preference this test can create: the layout list, the window
% positions, the pinned flags, and each component's own saved settings.
S = getpref;
groups = fieldnames(S);
for gi = 1:numel(groups)
    g = groups{gi};
    if contains(lower(g),'smokect')
        rmpref(g);
        continue
    end
    if ~startsWith(g,'epsych2_gui_'), continue; end
    names = fieldnames(S.(g));
    hit = names(contains(lower(names),'smokect'));
    for k = 1:numel(hit)
        rmpref(g, hit{k});
    end
end
end


function cleanupAll()
figs = findall(groot,'Type','figure');
for k = 1:numel(figs)
    if contains(lower(figs(k).Tag),'smokect')
        try
            figs(k).WindowStyle = 'normal'; % never leave one pinned over the desktop
        catch
        end
        delete(figs(k));
    end
end
cleanupPrefs();

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
