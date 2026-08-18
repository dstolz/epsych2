% smoke_test_calgui_display_toolbar
% Exercise CalibrationGui's display toolbar offline. Every control that mirrors
% the display state -- toolbar tool, View menu item, Display checkbox -- must
% agree with the monitor that owns it after a change made through any of them,
% and every toggle must redraw without a render error.
%
% The toolbar carries overlays only. Which measurement is on screen is the
% plots panel's tab strip, which owns no mirrored state -- it is checked here
% only for being the selector it claims to be.
%
% Run:  run('C:\src\epsych2\tmp\smoke_test_calgui_display_toolbar.m')

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..'));
addpath(fullfile(here, '..', 'obj', 'stimgen'));

fails = 0;
gui = stimgen.calibration.CalibrationGui();
h = @(name) private_(gui, name);

% --- Initial state ---------------------------------------------------------
fails = fails + sync_(gui, 'initial');
fails = fails + expect_(private_(gui, 'TransferView_') == "calibration", ...
    'transfer curves are the tab up first');
fails = fails + expect_(numel(findall(private_(gui, 'Figure'), ...
    'Type', 'uitoggletool')) == 3, 'toolbar carries three overlay toggles');

% --- Log X, toolbar -> monitor -> checkbox ---------------------------------
fails = fails + click_(h('ToolLogX'), false);
fails = fails + expect_(~gui.Monitor.LogX, 'toolbar off -> Monitor.LogX false');
fails = fails + expect_(~h('TransferLogXCheck').Value, 'checkbox followed toolbar');
fails = fails + sync_(gui, 'toolbar log-x off');

% --- Log X, checkbox -> monitor -> toolbar ---------------------------------
chk = h('TransferLogXCheck');
chk.Value = true;
feval(chk.ValueChangedFcn, chk, []);
fails = fails + expect_(gui.Monitor.LogX, 'checkbox on -> Monitor.LogX true');
fails = fails + expect_(on_(h('ToolLogX')), 'toolbar followed checkbox');
fails = fails + sync_(gui, 'checkbox log-x on');

% --- Ghost and drive-voltage overlays, both directions ---------------------
for name = ["ToolGhost", "ToolVoltage"]
    fails = fails + click_(h(char(name)), false);
    fails = fails + sync_(gui, sprintf('%s off', name));
    fails = fails + click_(h(char(name)), true);
    fails = fails + sync_(gui, sprintf('%s on', name));
end
fails = fails + expect_(gui.Monitor.ShowGhost && gui.Monitor.ShowVoltage, ...
    'both overlays restored');

% --- The View menu drives the same state -----------------------------------
m = h('GhostMenu');
feval(m.MenuSelectedFcn, m, []);
fails = fails + expect_(~gui.Monitor.ShowGhost, 'menu toggled ghost off');
fails = fails + expect_(~on_(h('ToolGhost')), 'toolbar followed menu');
feval(m.MenuSelectedFcn, m, []);
fails = fails + expect_(gui.Monitor.ShowGhost, 'menu toggled ghost back on');
fails = fails + sync_(gui, 'after menu round trip');

% --- Full-resolution waveforms, menu -> monitor -----------------------------
m = h('WaveformResMenu');
fails = fails + expect_(gui.Monitor.DecimateWaveforms == ~on_(m.Checked), ...
    'waveform menu agrees with the monitor');
was = gui.Monitor.DecimateWaveforms;
feval(m.MenuSelectedFcn, m, []);
fails = fails + expect_(gui.Monitor.DecimateWaveforms == ~was, ...
    'menu toggled waveform resolution');
fails = fails + sync_(gui, 'waveform resolution toggled');
feval(m.MenuSelectedFcn, m, []);
fails = fails + expect_(gui.Monitor.DecimateWaveforms == was, ...
    'menu toggled waveform resolution back');

% --- The tab strip selects the view, and nothing else claims to -------------
tabs = private_(gui, 'PlotTabs');
fails = fails + expect_(numel(tabs.Children) == 3, 'three measurement tabs');
tabs.SelectedTab = private_(gui, 'BackgroundTab');
feval(tabs.SelectionChangedFcn, tabs, ...
    struct('NewValue', private_(gui, 'BackgroundTab')));
fails = fails + expect_(private_(gui, 'TransferView_') == "background", ...
    'selecting a tab set the view');
fails = fails + sync_(gui, 'on the background tab');

% A reset redraws every panel and leaves the operator on the tab they chose:
% it changes what the panels hold, not which one is being read.
reset = h('BtnReset');
feval(reset.ButtonPushedFcn, reset, []);
fails = fails + expect_(private_(gui, 'TransferView_') == "background", ...
    'reset did not steal the selected tab');
fails = fails + expect_(tabs.SelectedTab == private_(gui, 'BackgroundTab'), ...
    'tab strip still on the background tab');
fails = fails + sync_(gui, 'after reset');

delete(private_(gui, 'Figure'));
fprintf('\n%s: %d failure(s)\n', mfilename, fails);

% ------------------------------------------------------------------------- %
function n = expect_(tf, what)
if tf
    n = 0;
    fprintf('  ok   %s\n', what);
else
    n = 1;
    fprintf('  FAIL %s\n', what);
end
end

% ------------------------------------------------------------------------- %
function n = click_(tool, newState)
% Drive a toggle tool the way a user does: State first, then the callback.
tool.State = matlab.lang.OnOffSwitchState(newState);
try
    feval(tool.ClickedCallback, tool, []);
    n = 0;
catch ME
    fprintf('  FAIL %s callback threw: %s\n', tool.Tooltip(1:min(30,end)), ME.message);
    n = 1;
end
end

% ------------------------------------------------------------------------- %
function tf = on_(v)
% True for an 'on' State/Checked/Enable, given either the value or the object.
if isgraphics(v)
    v = v.State;
end
tf = strcmp(char(v), 'on');
end

% ------------------------------------------------------------------------- %
function n = sync_(gui, when)
% Every mirror of the display state must agree with the monitor that owns it.
% The view is not among them: the tab strip is its own and only readout.
mon  = gui.Monitor;
tools = {'ToolLogX', mon.LogX; 'ToolGhost', mon.ShowGhost
         'ToolVoltage', mon.ShowVoltage};
menus = {'GhostMenu', mon.ShowGhost; 'VoltageMenu', mon.ShowVoltage
         'WaveformResMenu', ~mon.DecimateWaveforms};
n = 0;
for k = 1:size(tools, 1)
    n = n + expect_(on_(private_(gui, tools{k,1}).State) == tools{k,2}, ...
        sprintf('%s state (%s)', tools{k,1}, when));
end
for k = 1:size(menus, 1)
    n = n + expect_(on_(private_(gui, menus{k,1}).Checked) == menus{k,2}, ...
        sprintf('%s checked (%s)', menus{k,1}, when));
end
n = n + expect_(private_(gui, 'TransferLogXCheck').Value == mon.LogX, ...
    sprintf('log-x checkbox (%s)', when));
end

% ------------------------------------------------------------------------- %
function v = private_(obj, name)
% The controls under test are private, which is the point of them. struct()
% is the read-only door a test may use; nothing else should.
w = warning('off', 'MATLAB:structOnObject');
s = struct(obj);
warning(w);
v = s.(name);
end
