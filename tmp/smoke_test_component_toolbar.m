function smoke_test_component_toolbar()
% smoke_test_component_toolbar()
% Exercise gui.components.ComponentToolbar and gui.BehaviorGUI.addComponentToolbar.
%
% The claims under test:
%   - a gui.PopOut component registered anywhere in build gets a tool, even
%     though the toolbar was asked for before that component existed
%   - a tool is labelled by its register name, else by its class name split
%     into words
%   - clicking an automatic tool opens the component's pop-out; clicking
%     again raises that window rather than opening a second one
%   - a lazy component is not constructed until its tool is first clicked,
%     its window position is remembered under its own key, closing it
%     deletes the component, and clicking again builds a fresh one
%   - in toggle style a tool shows whether its window is open, and follows
%     the window being closed behind its back
%   - Exclude and AutoDiscover leave entries off
%   - a component with no glyph of its own still gets a tool
%   - closing the GUI closes every window the toolbar opened
%
% Headless-safe: every GUI is closed and every timer deleted before returning.
%
%   matlab -batch "run('tmp/smoke_test_component_toolbar.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % ComponentToolbarBehaviorGUI, FakeScatterRuntime

cleanupObj = onCleanup(@() cleanupAll());
cleanupPrefs();

% 1. Deferred discovery, labelling and ordering ---------------------------
g  = ComponentToolbarBehaviorGUI(makeRuntime());
tb = g.Toolbar;

assert(isa(tb,'gui.components.ComponentToolbar'), 'addComponentToolbar should return a gui.components.ComponentToolbar');
assert(isvalid(tb.ToolbarH) && strcmp(tb.ToolbarH.Type,'uitoolbar'), ...
    'the toolbar should be a uitoolbar on the GUI figure');
assert(ancestor(tb.ToolbarH,'figure') == g.h_figure, 'the toolbar belongs on the GUI figure');

names = tb.Names;
assert(isequal(names, ["Performance" "Mystery" "Parameter Scatter" "Upcoming" "Staircase"]), ...
    'expected lazy entries then discovered ones, got: %s', strjoin(names, ', '));
fprintf('PASS: components registered after the toolbar was made are still listed\n');

assert(any(names == "Staircase"), ...
    'a poppable psych object should be listed even though build never registers it');
fprintf('PASS: the psych object is discovered alongside registered components\n');

assert(any(names == "Parameter Scatter"), ...
    'a component registered with no name should be labelled from its class');
assert(any(names == "Upcoming"), ...
    'a component registered under a name should be labelled with it');
fprintf('PASS: entries are labelled by register name, else by class\n');

scatterTool = findTool(g.h_figure, 'Parameter Scatter');
assert(strcmp(scatterTool.Type,'uipushtool'), 'push is the default style');
assert(contains(scatterTool.Tooltip,'Parameter Scatter') && ...
    contains(scatterTool.Tooltip,'separate window'), ...
    'tooltip should name the component and what clicking does (got "%s")', scatterTool.Tooltip);
assert(isequal(size(scatterTool.Icon),[16 16 3]), 'tools should carry a 16x16 truecolor icon');
fprintf('PASS: tools carry an icon and a tooltip naming the component\n');

% 2. Push style: an automatic tool opens, then raises ---------------------
assert(~g.Scatter.hasPopOut(), 'nothing should be open before the first click');
scatterTool.ClickedCallback([],[]);
assert(g.Scatter.hasPopOut(), 'clicking should open the component pop-out');
popFig = g.Scatter.PopOutFigure;
assert(isvalid(g.Scatter.AxesH), 'the embedded component must be left in place');

before = numel(findall(groot,'Type','figure'));
scatterTool.ClickedCallback([],[]);
assert(numel(findall(groot,'Type','figure')) == before, ...
    'a second click opened another window instead of raising the first');
assert(g.Scatter.PopOutFigure == popFig, 'the same pop-out window should be raised');
fprintf('PASS: an automatic tool opens the pop-out, then raises it\n');

% 3. Lazy entries are built on first click, not before --------------------
perfTool = findTool(g.h_figure, 'Performance');
assert(g.LazyCalls == 0, 'a lazy component must not be constructed during build');
assert(isempty(findall(groot,'Type','figure','Tag','smokeCT_GUI_Performance_Tool')), ...
    'no lazy window should exist before the tool is clicked');

perfTool.ClickedCallback([],[]);
assert(g.LazyCalls == 1, 'clicking should run the factory exactly once');
lazyFig = findall(groot,'Type','figure','Tag','smokeCT_GUI_Performance_Tool');
assert(isscalar(lazyFig) && isvalid(lazyFig), ...
    'the lazy window should be tagged with its own preference key');
assert(contains(lazyFig.Name,'Performance') && contains(lazyFig.Name, g.h_figure.Name), ...
    'the lazy window title should name the GUI and the component (got "%s")', lazyFig.Name);
perfComp = findall(lazyFig,'Type','uitable');
assert(~isempty(perfComp) || ~isempty(findall(lazyFig,'Type','uilabel')), ...
    'the factory should have built something into the window');
fprintf('PASS: a lazy component is built on first click, into its own window\n');

% Its position is remembered under its own key, and closing deletes it.
lazyFig.Position = [140 160 430 270];
lazyFig.CloseRequestFcn([],[]); % the operator's close box
assert(~isvalid(lazyFig), 'closing should delete the lazy window');
assert(ispref('smokeCT_GUI_Performance_Tool','FigurePosition'), ...
    'the lazy window should save its position under its own key');
saved = getpref('smokeCT_GUI_Performance_Tool','FigurePosition');
assert(isequal(saved(3:4),[430 270]), 'the saved position should be the one it was closed at');
fprintf('PASS: closing a lazy window saves its position and deletes the component\n');

% Clicking again rebuilds, restoring that position.
perfTool.ClickedCallback([],[]);
assert(g.LazyCalls == 2, 'reopening should build a fresh component');
lazyFig = findall(groot,'Type','figure','Tag','smokeCT_GUI_Performance_Tool');
assert(isscalar(lazyFig) && isequal(lazyFig.Position(3:4),[430 270]), ...
    'the rebuilt window should reopen where it was closed');
fprintf('PASS: reopening builds a fresh component at the remembered position\n');

% 4. A component with no glyph of its own still gets a tool ---------------
mysteryTool = findTool(g.h_figure, 'Mystery');
assert(isequal(size(mysteryTool.Icon),[16 16 3]), ...
    'an unknown icon name should fall back to the generic glyph, not fail');
assert(isequaln(mysteryTool.Icon, gui.toolbarIcon("component")), ...
    'the fallback should be the generic two-window glyph');
fprintf('PASS: an unknown icon name falls back to the generic glyph\n');

% 5. Closing the GUI closes everything the toolbar opened -----------------
popFig  = g.Scatter.PopOutFigure;
g.closeGUI(g.h_figure, []);
assert(~isvalid(popFig), 'closing the GUI should close its component pop-outs');
assert(~isvalid(lazyFig), 'closing the GUI should close the windows its toolbar owns');
fprintf('PASS: closing the GUI closes every window the toolbar opened\n');

% 6. Toggle style tracks what is open -------------------------------------
cleanupPrefs();
g2 = ComponentToolbarBehaviorGUI(makeRuntime(), Style="toggle", ...
    PreferenceTag='smokeCT_GUI2');
scatterTool = findTool(g2.h_figure, 'Parameter Scatter');
assert(strcmp(scatterTool.Type,'uitoggletool'), 'Style="toggle" should make toggle tools');
assert(~logical(scatterTool.State), 'a toggle starts released');

scatterTool.ClickedCallback([],[]);
assert(g2.Scatter.hasPopOut(), 'the toggle should open the pop-out');
assert(logical(scatterTool.State), 'the toggle should show the window is open');

% Closed behind the toolbar's back: the tool must notice.
g2.Scatter.closePopOut();
assert(~logical(scatterTool.State), ...
    'the toggle should release when the window closes without it');

scatterTool.ClickedCallback([],[]);
assert(g2.Scatter.hasPopOut() && logical(scatterTool.State), 'reopening should re-press it');
scatterTool.ClickedCallback([],[]);
assert(~g2.Scatter.hasPopOut(), 'clicking a pressed toggle should close the window');
assert(~logical(scatterTool.State), 'and release the tool');
fprintf('PASS: a toggle tool tracks its window, however the window is closed\n');

% The same for a lazy entry, whose window the toolbar owns itself.
perfTool = findTool(g2.h_figure, 'Performance');
perfTool.ClickedCallback([],[]);
lazyFig = findall(groot,'Type','figure','Tag','smokeCT_GUI2_Performance_Tool');
assert(isscalar(lazyFig) && logical(perfTool.State), 'the lazy toggle should press on open');
delete(lazyFig); % deleted outright, bypassing the close request
assert(~logical(perfTool.State), 'the lazy toggle should release when its window is deleted');
perfTool.ClickedCallback([],[]);
assert(logical(perfTool.State), 'the lazy toggle should reopen after its window was deleted');
perfTool.ClickedCallback([],[]);
assert(~logical(perfTool.State) && ...
    isempty(findall(groot,'Type','figure','Tag','smokeCT_GUI2_Performance_Tool')), ...
    'clicking a pressed lazy toggle should close its window');
fprintf('PASS: a lazy toggle tracks the window the toolbar owns\n');

g2.closeGUI(g2.h_figure, []);

% 7. Exclude and AutoDiscover --------------------------------------------
cleanupPrefs();
g3 = ComponentToolbarBehaviorGUI(makeRuntime(), Exclude="ParameterScatter", ...
    PreferenceTag='smokeCT_GUI3');
assert(~any(g3.Toolbar.Names == "Parameter Scatter"), 'Exclude should drop the entry by class');
assert(any(g3.Toolbar.Names == "Upcoming"), 'Exclude should leave other entries alone');
g3.closeGUI(g3.h_figure, []);

g4 = ComponentToolbarBehaviorGUI(makeRuntime(), AutoDiscover=false, ...
    PreferenceTag='smokeCT_GUI4');
assert(isequal(g4.Toolbar.Names, ["Performance" "Mystery"]), ...
    'AutoDiscover=false should list only what was declared, got: %s', ...
    strjoin(g4.Toolbar.Names, ', '));
fprintf('PASS: Exclude drops one entry and AutoDiscover=false drops discovery\n');

% 8. Asking twice returns the toolbar already made ------------------------
again = g4.addComponentToolbar(g4.h_figure);
assert(again == g4.Toolbar, 'a second addComponentToolbar should return the existing toolbar');
assert(isscalar(findall(g4.h_figure,'Type','uitoolbar')), 'only one toolbar should exist');
g4.closeGUI(g4.h_figure, []);
fprintf('PASS: asking for a second toolbar returns the first\n');

% 9. Name derivation for every adopter ------------------------------------
expect = { ...
    'gui.components.ParameterScatter',    "Parameter Scatter",   "parameterscatter"; ...
    'gui.components.History',             "History",             "history"; ...
    'gui.components.SessionPerformance',  "Session Performance", "sessionperformance"; ...
    'gui.components.NextTrial',           "Next Trial",          "nexttrial"; ...
    'gui.components.Parameter_Monitor',   "Parameter Monitor",   "parametermonitor"; ...
    'gui.components.PsychPlot',           "Psych Plot",          "psychplot"; ...
    'gui.components.SyringePump',         "Syringe Pump",        "syringepump"; ...
    'psychophysics.Staircase', "Staircase",           "staircase"};
for k = 1:size(expect,1)
    cls = expect{k,1};
    assert(gui.components.ComponentToolbar.entryLabel(cls) == expect{k,2}, ...
        '%s should be labelled "%s", got "%s"', cls, expect{k,2}, ...
        gui.components.ComponentToolbar.entryLabel(cls));
    assert(gui.components.ComponentToolbar.iconNameForClass(cls) == expect{k,3}, ...
        '%s should use icon "%s", got "%s"', cls, expect{k,3}, ...
        gui.components.ComponentToolbar.iconNameForClass(cls));
    gui.toolbarIcon(expect{k,3}); % every adopter has a glyph of its own
end
assert(gui.components.ComponentToolbar.entryLabel('gui.components.ParameterScatter','Left Box') == "Left Box", ...
    'a register name should win over the class name');
fprintf('PASS: every gui.PopOut adopter has a label and a glyph of its own\n');

fprintf('\nsmoke_test_component_toolbar: all checks passed\n');
end


% -- helpers ---------------------------------------------------------------

function t = findTool(fig, entryName)
% Tools are tagged with the entry name, exactly as gui.components.ComponentToolbar builds it.
tag = matlab.lang.makeValidName(sprintf('ctb_%s', entryName));
t = findall(fig, 'Tag', tag);
assert(isscalar(t), 'expected one tool tagged %s, found %d', tag, numel(t));
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
% Remove every preference this test can create. Window positions are saved
% in a preference GROUP named for the window's key, and components save
% their own settings under that key inside their epsych2_gui_* group, so
% both are matched by the shared 'smokect' marker rather than spelled out.
% Leftovers matter: section 3 asserts on a position saved during the run.
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
cleanupPrefs();

figs = findall(groot,'Type','figure');
for k = 1:numel(figs)
    if contains(lower(figs(k).Tag),'smokect')
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
