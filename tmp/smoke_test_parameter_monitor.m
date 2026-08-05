function smoke_test_parameter_monitor()
% smoke_test_parameter_monitor()
% Exercise the refactored gui.Parameter_Monitor: graphical display type
% (auto/forced widget styles, lamp state colors, gauge tracking, value-label
% change highlight lifecycle), runtime add/remove with rebuild, layout
% variants, table-mode render skipping when values are unchanged, unique
% per-instance timers, self-deletion when the display is destroyed, runtime
% poll-period changes, and legacy-figure text mode.
% Headless-safe: every GUI is closed and every timer deleted before returning.
%
%   matlab -batch "run('tmp/smoke_test_parameter_monitor.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

cleanupObj = onCleanup(@cleanup_all);

% Software-backed parameters (no hardware I/O)
sw = hw.Software();
pIn  = hw.Parameter(sw, Name='InTrial', Type='Boolean');            pIn.Value  = 0;
pLat = hw.Parameter(sw, Name='RespLatency', Unit='ms');             pLat.Value = 12.5;
pLvl = hw.Parameter(sw, Name='Level', Type='Float', Min=0, Max=100); pLvl.Value = 40;
pPlt = hw.Parameter(sw, Name='Platform');                           pPlt.Value = 1;

% 1. Graphical: style resolution and initial render -----------------------
f1 = uifigure('Visible','off','Tag','SmokePM_Graphical');
M = gui.Parameter_Monitor(f1, [pIn pLat pLvl pPlt], pollPeriod=5, ...
    type="graphical", Styles=struct(Level="gauge", Platform="lamp"));
M.stop();

styles = [M.Widgets.Style];
assert(isequal(styles, ["lamp","label","gauge","lamp"]), ...
    'style resolution wrong: %s', strjoin(styles,','));
assert(isequal(M.Widgets(1).ValueHandle.Color, M.LampOffColor), 'InTrial=0 lamp should be off');
assert(isequal(M.Widgets(4).ValueHandle.Color, M.LampOnColor), 'Platform=1 lamp should be on');
assert(strcmp(M.Widgets(2).ValueHandle.Text, pLat.ValueStr), 'label should show ValueStr');
assert(M.Widgets(3).ValueHandle.Value == 40, 'gauge should track parameter value');
assert(~isequal(M.Widgets(2).ValueHandle.BackgroundColor, M.HighlightColor), ...
    'initial fill must not flash the change highlight');
fprintf('PASS: graphical construction, style resolution, initial render\n');

% 2. Change detection, lamp toggling, highlight lifecycle -----------------
pIn.Value = 1;
pLat.Value = 99.9;
pLvl.Value = 75;
M.poll_parameters();
assert(isequal(M.Widgets(1).ValueHandle.Color, M.LampOnColor), 'lamp should turn on');
assert(strcmp(M.Widgets(2).ValueHandle.Text, pLat.ValueStr), 'label should update on change');
assert(isequal(M.Widgets(2).ValueHandle.BackgroundColor, M.HighlightColor), ...
    'changed value label should flash HighlightColor');
assert(M.Widgets(3).ValueHandle.Value == 75, 'gauge should follow value');
M.poll_parameters(); % values now stable
assert(strcmp(M.Widgets(2).ValueHandle.BackgroundColor,'none'), ...
    'highlight should clear once the value is stable');
assert(M.ParameterValues(1) == "1", 'lamp state should report into ParameterValues');
assert(M.ParameterValues(2) == string(pLat.ValueStr), 'label value should report into ParameterValues');
fprintf('PASS: change detection, lamp toggling, highlight lifecycle\n');

% 3. Runtime add/remove rebuilds the widget grid --------------------------
pNew = hw.Parameter(sw, Name='PelletTotal', Type='Integer'); pNew.Value = 3;
M.add_parameter(pNew);
assert(numel(M.Widgets) == 5, 'add_parameter should rebuild with 5 widgets');
assert(strcmp(M.Widgets(5).ValueHandle.Text, pNew.ValueStr), 'new widget should render immediately');
M.add_parameter(pNew); % duplicate is ignored
assert(numel(M.Widgets) == 5, 'duplicate add should be ignored');
M.remove_parameter("RespLatency");
names = arrayfun(@(w) string(w.Parameter.Name), M.Widgets);
assert(numel(M.Widgets) == 4 && ~ismember("RespLatency",names), 'remove_parameter by name failed');
fprintf('PASS: runtime add/remove with rebuild\n');

% 4. Layout variants ------------------------------------------------------
f2 = uifigure('Visible','off','Tag','SmokePM_Layout');
M2 = gui.Parameter_Monitor(f2, [pIn pLat pLvl pPlt], pollPeriod=5, ...
    type="graphical", LayoutColumns=2, LabelPosition="above", FontSize=14);
M2.stop();
assert(numel(M2.handle.ColumnWidth) == 2, 'LayoutColumns=2 should yield 2 grid columns');
assert(numel(M2.handle.RowHeight) == 4, 'LabelPosition="above" should yield 2 rows per parameter row');
assert(M2.Widgets(1).LabelHandle.FontSize == 14, 'FontSize option should reach the labels');
fprintf('PASS: layout variants (columns, label-above, font size)\n');

% 5. Table mode skips re-render when values are unchanged -----------------
f3 = uifigure('Visible','off','Tag','SmokePM_Table');
M3 = gui.Parameter_Monitor(f3, [pIn pLat], pollPeriod=5, type="table", ...
    PreferenceTag='smokePM_table');
M3.stop();
M3.handle.Data{1,2} = '__sentinel__';
M3.poll_parameters();
assert(strcmp(M3.handle.Data{1,2},'__sentinel__'), ...
    'unchanged values must not reassign uitable Data');
pIn.Value = 0;
M3.poll_parameters();
assert(~strcmp(M3.handle.Data{1,2},'__sentinel__'), 'changed values must re-render the table');
fprintf('PASS: table render skipped when idle, refreshed on change\n');

% 6. Poll period is adjustable at runtime ---------------------------------
M3.setPollPeriod(0.5);
assert(M3.Timer.Period == 0.5, 'setPollPeriod should retune the timer');
fprintf('PASS: setPollPeriod\n');

% 7. Unique timers; monitor deletes itself with its display ---------------
assert(~strcmp(M.Timer.Name, M3.Timer.Name), 'each monitor must own a uniquely-named timer');
tname = M.Timer.Name;
delete(f1);
assert(~isvalid(M), 'monitor should delete itself when its display is destroyed');
assert(isempty(timerfindall('Name',tname)), 'timer should be deleted with the monitor');
assert(isvalid(M3), 'other monitors must be unaffected');
fprintf('PASS: unique timers and self-cleanup on figure close\n');

% 8. Legacy-figure text mode ----------------------------------------------
f4 = figure('Visible','off');
M4 = gui.Parameter_Monitor(f4, [pIn pLat], pollPeriod=5, type="text");
M4.stop();
assert(~isempty(M4.handle.String), 'text display should render');
assert(ismember("InTrial", M4.ParameterNames), 'text mode should poll parameter names');
delete(f4);
assert(~isvalid(M4), 'text monitor should also self-delete with its figure');
fprintf('PASS: legacy-figure text mode\n');

% 9. Appetitive-detection integration shape -------------------------------
% Mirrors cl_AppetitiveDetection_GUI_B/create_gui.m: a titled uipanel host,
% 10 parameters with the 5 lamps listed first, and the onModeChange
% stop/start lifecycle.
f5 = uifigure('Visible','off','Tag','SmokePM_Appetitive');
gl = uigridlayout(f5,[1 1]);
panelMonitor = uipanel(gl,'Title','Trial State');
mkp = @(n,t) make_param(sw,n,t);
pset = [mkp('Platform','Boolean'), mkp('Trough','Boolean'), ...
        mkp('InTrial','Boolean'), mkp('DelayPeriod','Boolean'), ...
        mkp('RespWindow','Boolean'), mkp('PelletTotal','Integer'), ...
        mkp('StimDelay','Float'), mkp('RespWinDelay','Float'), ...
        mkp('RespLatency','Float'), mkp('RespCode','Integer')];

M5 = gui.Parameter_Monitor(panelMonitor, pset, pollPeriod=0.1, ...
    type="graphical", FontSize=14, ...
    Styles=struct(Platform="lamp", Trough="lamp", InTrial="lamp", ...
        DelayPeriod="lamp", RespWindow="lamp"));

styles5 = [M5.Widgets.Style];
assert(all(styles5(1:5) == "lamp"), 'first five widgets should be lamps');
assert(all(styles5(6:10) == "label"), 'remaining widgets should be value labels');
assert(M5.Timer.Running == "on", 'monitor should be polling after construction');

M5.stop();  % hw.DeviceState.Stop path
assert(M5.Timer.Running == "off", 'Stop mode should pause polling');
assert(isvalid(M5) && isvalid(M5.handle), 'stopped monitor must stay on screen');
M5.start(); % Preview/Record path
assert(M5.Timer.Running == "on", 'Preview/Record should resume polling');

% figure teardown must release the monitor and its timer
tname5 = M5.Timer.Name;
delete(f5);
assert(~isvalid(M5), 'monitor should self-delete with the hosting figure');
assert(isempty(timerfindall('Name',tname5)), 'timer should not outlive the GUI');
fprintf('PASS: appetitive-detection integration shape and mode lifecycle\n');

delete(f2); delete(f3);
fprintf('\nAll gui.Parameter_Monitor smoke tests passed.\n');

end


function p = make_param(sw,name,type)
p = hw.Parameter(sw, Name=name, Type=type);
if isequal(type,'Boolean')
    p.Value = 0;
else
    p.Value = 1;
end
end


function cleanup_all()
try
    t = timerfindall;
    if ~isempty(t)
        t = t(startsWith({t.Name},'Parameter_Monitor_Timer_'));
        if ~isempty(t)
            stop(t);
            delete(t);
        end
    end
catch
end
try
    close all force
catch
end
end
