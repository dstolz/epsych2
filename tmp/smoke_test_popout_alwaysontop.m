function smoke_test_popout_alwaysontop()
% smoke_test_popout_alwaysontop()
% Exercise the "Keep Window on Top" context menu item gui.PopOut adds to a
% component that has a window to itself.
%
% The claims under test:
%   - an EMBEDDED component gets no such item: its window belongs to the
%     behavior GUI, not to it
%   - a POP-OUT gets one, unticked, over a window of the ordinary style
%   - choosing it pins the window (WindowStyle 'alwaysontop') and ticks the
%     item; choosing it again unpins and unticks
%   - the choice is remembered with the window's other preferences, so a
%     pinned pop-out reopens pinned and already ticked, under the pop-out's
%     own preference key rather than its host's
%   - a window gui.components.ComponentToolbar opens for a lazy component gets the item
%     too, since that window also holds one component
%
% Headless-safe: every GUI is closed and every preference removed before
% returning.
%
%   matlab -batch "run('tmp/smoke_test_popout_alwaysontop.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % ComponentToolbarBehaviorGUI, FakeScatterRuntime

cleanupObj = onCleanup(@() cleanupAll());
cleanupPrefs();

% 1. The embedded component is not offered the item ------------------------
D  = makeData(12);
f1 = uifigure('Visible','off','Tag','smokeAOT_host');
S  = gui.components.ParameterScatter(D, f1, PreferenceTag='smokeAOT_scatter', ...
    XParameter='FreqHz', YParameter='LevelDB');

assert(isempty(aotItem(f1)), ...
    'an embedded component must not offer to pin the GUI window it shares');
fprintf('PASS: no always-on-top item on the embedded component\n');

% 2. The pop-out is, and starts unpinned -----------------------------------
P      = S.popOut();
popFig = S.PopOutFigure;
m      = aotItem(popFig);

assert(isscalar(m), 'the pop-out should offer exactly one always-on-top item');
assert(strcmp(m.Text,'Keep Window on Top'), 'item reads "%s"', m.Text);
assert(strcmpi(char(popFig.WindowStyle),'normal'), ...
    'a first-time pop-out should open as an ordinary window');
assert(m.Checked == matlab.lang.OnOffSwitchState.off, 'the item should start unticked');
assert(~gui.PopOut.isAlwaysOnTop(popFig), 'isAlwaysOnTop should agree with the window');
fprintf('PASS: the pop-out offers the item, unticked, over a normal window\n');

% 3. Choosing it pins the window; choosing it again unpins ----------------
m.MenuSelectedFcn(m,[]);
assert(strcmpi(char(popFig.WindowStyle),'alwaysontop'), ...
    'choosing the item should pin the window (WindowStyle is "%s")', popFig.WindowStyle);
assert(m.Checked == matlab.lang.OnOffSwitchState.on, 'the item should tick when pinned');
assert(gui.PopOut.isAlwaysOnTop(popFig), 'isAlwaysOnTop should report the pinned window');
assert(isvalid(f1) && strcmpi(char(f1.WindowStyle),'normal'), ...
    'pinning the pop-out must leave the host window alone');

m.MenuSelectedFcn(m,[]);
assert(strcmpi(char(popFig.WindowStyle),'normal'), 'choosing it again should unpin');
assert(m.Checked == matlab.lang.OnOffSwitchState.off, 'the item should untick when unpinned');
fprintf('PASS: the item toggles the window between pinned and normal\n');

% 4. The choice survives the window ---------------------------------------
m.MenuSelectedFcn(m,[]);   % leave it pinned
popTag = popFig.Tag;
assert(getpref(popTag,'AlwaysOnTop',false), ...
    'the choice should be saved under the pop-out key %s', popTag);
assert(~ispref('smokeAOT_scatter','AlwaysOnTop'), ...
    'the pop-out must not write the host component''s preferences');

S.closePopOut();
P2 = S.popOut();
popFig2 = S.PopOutFigure;
m2 = aotItem(popFig2);

assert(P2 ~= P, 'closePopOut then popOut should build a fresh instance');
assert(strcmpi(char(popFig2.WindowStyle),'alwaysontop'), ...
    'a pop-out left pinned should reopen pinned');
assert(m2.Checked == matlab.lang.OnOffSwitchState.on, ...
    'the reopened item should show the window as pinned');
fprintf('PASS: a pinned pop-out reopens pinned, under its own key\n');

% Unpin before closing so the window is not left on top of the desktop.
m2.MenuSelectedFcn(m2,[]);
S.closePopOut();
delete(f1);

% 5. A toolbar-owned window is a one-component window too ------------------
g  = ComponentToolbarBehaviorGUI(makeRuntime());
tb = g.Toolbar;
assert(isvalid(tb), 'expected a component toolbar');

tool = findTool(g.h_figure, 'Mystery');   % a lazy gui.components.NextTrial
tool.ClickedCallback([],[]);
lazyFig = findall(groot,'Type','figure','-and','Tag','smokeCT_GUI_Mystery');
if isempty(lazyFig)
    lazyFig = lazyWindow_(g.h_figure);
end
assert(isscalar(lazyFig) && isvalid(lazyFig), 'the tool should have opened one window');

mL = aotItem(lazyFig);
assert(isscalar(mL), 'a toolbar-owned window should offer the always-on-top item');
mL.MenuSelectedFcn(mL,[]);
assert(strcmpi(char(lazyFig.WindowStyle),'alwaysontop'), ...
    'the item should pin a toolbar-owned window');
mL.MenuSelectedFcn(mL,[]);
assert(strcmpi(char(lazyFig.WindowStyle),'normal'), 'and unpin it');
fprintf('PASS: a window the component toolbar owns offers the item as well\n');

delete(g);

fprintf('\nALL PASS: smoke_test_popout_alwaysontop\n');
end


function m = aotItem(fig)
% Every menu item this feature creates carries the mixin's tag.
m = findall(fig, 'Type', 'uimenu', 'Tag', gui.PopOut.ALWAYSONTOP_MENU_TAG);
end


function f = lazyWindow_(guiFig)
% The toolbar's window, found by exclusion: any smokeCT figure that is not
% the GUI itself.
figs = findall(groot,'Type','figure');
keep = false(size(figs));
for k = 1:numel(figs)
    keep(k) = contains(lower(figs(k).Tag),'smokect') && figs(k) ~= guiFig;
end
f = figs(keep);
end


function t = findTool(fig, entryName)
tag = matlab.lang.makeValidName(sprintf('ctb_%s', entryName));
t = findall(fig, 'Tag', tag);
assert(isscalar(t), 'expected one tool tagged %s, found %d', tag, numel(t));
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
% Remove every preference this test can create -- the saved AlwaysOnTop
% flag above all, since a leftover would make section 2 open pinned and the
% first assertion fail for the wrong reason.
S = getpref;
groups = fieldnames(S);
for gi = 1:numel(groups)
    g = groups{gi};
    if contains(lower(g),'smokeaot') || contains(lower(g),'smokect')
        rmpref(g);
        continue
    end
    if ~startsWith(g,'epsych2_gui_'), continue; end
    names = fieldnames(S.(g));
    hit = names(contains(lower(names),'smokeaot') | contains(lower(names),'smokect'));
    for k = 1:numel(hit)
        rmpref(g, hit{k});
    end
end
end


function cleanupAll()
figs = findall(groot,'Type','figure');
for k = 1:numel(figs)
    if contains(lower(figs(k).Tag),'smokeaot') || contains(lower(figs(k).Tag),'smokect')
        try
            figs(k).WindowStyle = 'normal';
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
