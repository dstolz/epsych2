% smoke_test_syringepump_gui.m
% Offline smoke tests for gui.SyringePump — no pump required.
%
% Drives the panel against tmp/NE1000_Mock, so every write the GUI makes
% travels the real hw.NE1000 protocol path and is asserted on the simulated
% pump's state. Covers the three sources a panel can be built over (an
% interface, an epsych.Runtime, nothing at all), the settings round trip,
% the volume readout and its unit conversion, the units menu (which converts
% the rate rather than reinterpreting it), the rejection path, pop-out, and
% teardown ownership.
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_syringepump_gui.m')"

% Bootstrap: `matlab -batch` starts with whatever path the user profile leaves
% behind, and this file lives in tmp/, which is only on the path once
% epsych_startup has run.
if exist('gui.SyringePump', 'class') ~= 8
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end

fprintf('\n=== gui.SyringePump Smoke Test ===\n\n');
results = {};

PREF = 'smoke_test_syringepump';
figs = matlab.ui.Figure.empty;

%% 1. Attach to a connected pump and apply the defaults
mock = hw.NE1000.empty;
panel = [];
try
    mock = NE1000_Mock(SyringeDiameter = 21.59);   % powers up in mL/hr
    fig = uifigure(Visible = 'off', Name = 'Pump Smoke', Tag = PREF);
    figs(end+1) = fig;

    panel = gui.SyringePump(mock, fig, PreferenceTag = PREF);

    results(end+1,:) = check('Panel reports the link is up',  panel.IsConnected);
    results(end+1,:) = check('Panel adopted the interface',   panel.Interface == mock);
    results(end+1,:) = check('Rate units switched to mL/min', strcmp(mock.RateUnits, 'MM') ...
        && strcmp(mock.SimRateUnits, 'MM'));
    results(end+1,:) = check('Default rate pushed (0.7 mL/min)', abs(mock.SimRate - 0.7) < 1e-9);
    results(end+1,:) = check('Default diameter in place (21.59 mm)', ...
        abs(mock.SimDiameter - 21.59) < 0.01);
    results(end+1,:) = check('Default direction is Infuse', strcmp(mock.SimDir, 'INF'));
    results(end+1,:) = check('TTL trigger starts disabled', ...
        ~panel.TTLTrigger && strcmp(mock.SimTrigger, 'OF'));

    % The Rate parameter's unit label must follow the units it is now in,
    % since it is a trial-table column and shows up in monitors.
    P = mock.find_parameter('Rate');
    results(end+1,:) = check('Rate parameter relabeled', strcmp(P(1).Unit, 'mL/min'));
catch ME
    results(end+1,:) = check(['Attach: ' ME.message], false);
end

%% 2. Settings write through to the pump
try
    panel.Rate = 2.5;
    results(end+1,:) = check('Rate property writes the pump', ...
        abs(mock.SimRate - 2.5) < 1e-9 && strcmp(mock.SimRateUnits, 'MM'));

    panel.Diameter = 14.43;
    results(end+1,:) = check('Diameter property writes the pump', ...
        abs(mock.SimDiameter - 14.43) < 0.01);

    panel.Direction = 'Withdraw';
    results(end+1,:) = check('Direction property writes the pump', strcmp(mock.SimDir, 'WDR'));

    panel.Direction = 'Infuse';
    panel.Diameter = 21.59;
    results(end+1,:) = check('Settings restore', strcmp(mock.SimDir, 'INF') ...
        && abs(mock.SimDiameter - 21.59) < 0.01);
catch ME
    results(end+1,:) = check(['Settings: ' ME.message], false);
end

%% 3. Volume readout and unit conversion
try
    mock.SimInfused = 1.234;      % the mock reports volumes in mL
    mock.SimWithdrawn = 0.05;
    pause(0.06)                   % outlast the interface's DIS cache
    panel.refresh();

    results(end+1,:) = check('Pump reported its volume units', strcmp(mock.DispensedUnits, 'ML'));
    results(end+1,:) = check('Infused volume shown in mL', ...
        abs(panel.VolumeInfused - 1.234) < 1e-9);
    results(end+1,:) = check('Withdrawn volume shown in mL', ...
        abs(panel.VolumeWithdrawn - 0.05) < 1e-9);
    results(end+1,:) = check('Status polled from the pump', ...
        ismember(panel.Status, {'Stopped', 'Paused', 'Infusing', 'Withdrawing'}));
catch ME
    results(end+1,:) = check(['Readout: ' ME.message], false);
end

%% 4. Pump control
try
    panel.startPump();
    results(end+1,:) = check('startPump runs the pump', mock.SimStatus == 'I');
    results(end+1,:) = check('Status reflects infusing', strcmp(panel.Status, 'Infusing'));

    % A diameter change is rejected while pumping; the panel must keep the
    % operator's value and leave the pump alone rather than throw.
    panel.Diameter = 30;
    results(end+1,:) = check('Diameter rejected mid-run leaves the pump alone', ...
        abs(mock.SimDiameter - 21.59) < 0.01);
    results(end+1,:) = check('Rejected value stays in the panel', abs(panel.Diameter - 30) < 1e-9);

    panel.stopPump();
    results(end+1,:) = check('stopPump stops the pump', any(mock.SimStatus == 'PS'));

    panel.Diameter = 21.59;
    mock.SimInfused = 3;
    mock.SimWithdrawn = 2;
    panel.zeroVolume();
    results(end+1,:) = check('zeroVolume clears both accumulators', ...
        mock.SimInfused == 0 && mock.SimWithdrawn == 0);
catch ME
    results(end+1,:) = check(['Pump control: ' ME.message], false);
end

%% 5. Reading the pump instead of asserting over it
try
    mock.SimRate = 4;
    mock.SimDir = 'WDR';
    fig2 = uifigure(Visible = 'off', Name = 'Pump Read', Tag = [PREF '_read']);
    figs(end+1) = fig2;

    reader = gui.SyringePump(mock, fig2, ApplyOnStart = false, ...
        PreferenceTag = [PREF '_read']);
    results(end+1,:) = check('ApplyOnStart=false reads the rate',      abs(reader.Rate - 4) < 1e-9);
    results(end+1,:) = check('ApplyOnStart=false reads the direction', strcmp(reader.Direction, 'Withdraw'));
    results(end+1,:) = check('ApplyOnStart=false wrote nothing',       abs(mock.SimRate - 4) < 1e-9);
    delete(reader)
    mock.set_parameter('Direction', 'Infuse');
catch ME
    results(end+1,:) = check(['Read-only attach: ' ME.message], false);
end

%% 5b. TTL trigger control: an operator switch, a programmatic mode
try
    panel.TTLTrigger = true;
    results(end+1,:) = check('Enabling hands the pump its trigger', ...
        strcmp(mock.SimTrigger, 'LE') && mock.TTLTrigger);
    results(end+1,:) = check('The checkbox follows the property', ...
        panel.isSectionVisible("TTL"));

    panel.TriggerMode = 'ST';
    results(end+1,:) = check('The mode reaches the pump through the interface', ...
        strcmp(mock.SimTrigger, 'ST') && strcmp(mock.TriggerMode, 'ST'));

    % The mode is programmatic only: it is nobody's section and nothing in
    % the panel can change it.
    results(end+1,:) = check('No section offers the trigger mode', ...
        ~any(contains(lower(gui.SyringePump.SECTIONS), "mode")));

    panel.TTLTrigger = false;
    results(end+1,:) = check('Disabling takes it back (TRG OF)', strcmp(mock.SimTrigger, 'OF'));

    % Hidden is only hidden, as with every other setting.
    panel.hide("TTL");
    panel.TTLTrigger = true;
    results(end+1,:) = check('A hidden TTL setting still writes the pump', ...
        strcmp(mock.SimTrigger, 'ST'));
    panel.show("TTL");
    panel.TTLTrigger = false;

    % A panel told which mode to use asserts it; one that was not adopts
    % whatever the interface (i.e. the protocol) is set to.
    mock.TriggerMode = 'RL';
    figTTL = uifigure(Visible = 'off', Name = 'Pump TTL', Tag = [PREF '_ttl']);
    figs(end+1) = figTTL;
    moded = gui.SyringePump(mock, figTTL, ApplyOnStart = false, ...
        TriggerMode = 'FH', PreferenceTag = [PREF '_ttl']);
    results(end+1,:) = check('The TriggerMode option reaches the interface', ...
        strcmp(moded.TriggerMode, 'FH') && strcmp(mock.TriggerMode, 'FH'));
    delete(moded)

    mock.TriggerMode = 'SL';
    plain = gui.SyringePump(mock, figTTL, ApplyOnStart = false, ...
        PreferenceTag = [PREF '_ttl2']);
    results(end+1,:) = check('Without it, the interface keeps its mode', ...
        strcmp(plain.TriggerMode, 'SL') && strcmp(mock.TriggerMode, 'SL'));
    delete(plain)
    delete(figTTL)
    figs(end) = [];

    mock.TriggerMode = 'LE';
    panel.TriggerMode = 'LE';
catch ME
    results(end+1,:) = check(['TTL trigger: ' ME.message], false);
end

%% 5c. Units are the operator's, and the rate is converted with them
try
    cmU = panel.ContextMenu;
    panel.Rate = 0.5;                       % mL/min, the panel's default units

    openMenu(cmU);
    clickMenu(unitsItem(cmU, 'Rate', 'uL/min'));
    results(end+1,:) = check('Menu switches the rate units', strcmp(panel.RateUnits, 'UM'));
    results(end+1,:) = check('The rate is converted, not reinterpreted', ...
        abs(panel.Rate - 500) < 1e-9);
    results(end+1,:) = check('The pump takes the same speed in the new units', ...
        strcmp(mock.RateUnits, 'UM') && strcmp(mock.SimRateUnits, 'UM') ...
        && abs(mock.SimRate - 500) < 1e-6);

    P = mock.find_parameter('Rate');
    results(end+1,:) = check('Rate parameter relabeled with them', strcmp(P(1).Unit, 'uL/min'));

    % findall cannot regexp a uilabel Text, so the row label is matched here.
    texts = string({findall(panel.Parent, 'Type', 'uilabel').Text});
    results(end+1,:) = check('The rate row carries the units', ...
        any(texts == "Rate (uL/min)"));

    % Per hour is the other half of the choice.
    openMenu(cmU);
    clickMenu(unitsItem(cmU, 'Rate', 'mL/hr'));
    results(end+1,:) = check('Per-hour units convert too', ...
        strcmp(panel.RateUnits, 'MH') && abs(panel.Rate - 30) < 1e-9 ...
        && abs(mock.SimRate - 30) < 1e-6);

    openMenu(cmU);
    clickMenu(unitsItem(cmU, 'Rate', 'mL/min'));
    results(end+1,:) = check('Switching back lands on the original number', ...
        abs(panel.Rate - 0.5) < 1e-9);

    % Volume units are display only: the pump is told nothing.
    mock.SimInfused = 1.234;                % the mock reports volumes in mL
    pause(0.06)                             % outlast the interface's DIS cache
    panel.refresh();
    wrote = mock.SimRate;

    openMenu(cmU);
    clickMenu(unitsItem(cmU, 'Volume', 'uL'));
    results(end+1,:) = check('Volume units rescale the readout', ...
        strcmp(panel.VolumeUnits, 'uL') && abs(panel.VolumeInfused - 1234) < 1e-6);

    openMenu(cmU);
    clickMenu(unitsItem(cmU, 'Volume', 'Follow the pump'));
    results(end+1,:) = check('Following the pump uses what it reported', ...
        strcmp(panel.VolumeUnits, 'auto') && abs(panel.VolumeInfused - 1.234) < 1e-9);
    results(end+1,:) = check('Changing the readout units writes nothing', ...
        abs(mock.SimRate - wrote) < 1e-9);

    % An operator's units persist, and the remembered rate comes back in
    % them -- a bare number restored into different units would change the
    % speed of the pump a session later.
    openMenu(cmU);
    clickMenu(unitsItem(cmU, 'Rate', 'uL/min'));
    figU = uifigure(Visible = 'off', Name = 'Pump Units', Tag = PREF);
    figs(end+1) = figU;
    remembered = gui.SyringePump(mock, figU, ApplyOnStart = false, PreferenceTag = PREF);
    results(end+1,:) = check('A new panel restores the operator units', ...
        strcmp(remembered.RateUnits, 'UM') && strcmp(remembered.VolumeUnits, 'auto'));
    results(end+1,:) = check('The remembered rate comes back in them', ...
        abs(remembered.Rate - 500) < 1e-9);
    delete(remembered)

    % A caller that states its own units outranks the memory, and the
    % remembered rate is converted into what it asked for. (ApplyOnStart
    % stays true: hw.NE1000 reads RAT as a bare number, so asking the panel
    % to read the pump would make the pump's number, not the memory, the
    % thing being outranked.)
    figU2 = uifigure(Visible = 'off', Name = 'Pump Units 2', Tag = PREF);
    figs(end+1) = figU2;
    stated = gui.SyringePump(mock, figU2, RateUnits = 'MM', PreferenceTag = PREF);
    results(end+1,:) = check('An explicit RateUnits beats the remembered one', ...
        strcmp(stated.RateUnits, 'MM') && abs(stated.Rate - 0.5) < 1e-9 ...
        && abs(mock.SimRate - 0.5) < 1e-9 && strcmp(mock.SimRateUnits, 'MM'));
    delete(stated)

    openMenu(cmU);
    clickMenu(unitsItem(cmU, 'Rate', 'mL/min'));
    openMenu(cmU);
    clickMenu(unitsItem(cmU, 'Volume', 'mL'));

    % Units cannot change under a running pump: mid-run the pump refuses a
    % RAT carrying units and hw.NE1000 falls back to the bare value, which
    % the pump would take in its OLD units. The panel refuses instead.
    panel.startPump();
    openMenu(cmU);
    clickMenu(unitsItem(cmU, 'Rate', 'uL/min'));
    results(end+1,:) = check('A running pump refuses a units change', ...
        strcmp(panel.RateUnits, 'MM') && strcmp(mock.SimRateUnits, 'MM') ...
        && abs(panel.Rate - 0.5) < 1e-9 && abs(mock.SimRate - 0.5) < 1e-9);
    panel.stopPump();
catch ME
    results(end+1,:) = check(['Units: ' ME.message], false);
end

%% 6. Pop-out is a second panel over the same pump
try
    sibling = panel.popOut();
    results(end+1,:) = check('popOut opens a window',      panel.hasPopOut());
    results(end+1,:) = check('Pop-out shares the pump',    sibling.Interface == mock);
    panel.closePopOut();
    results(end+1,:) = check('closePopOut releases it',    ~panel.hasPopOut());
    results(end+1,:) = check('Pop-out did not close the link', mock.IsConnected);
catch ME
    results(end+1,:) = check(['Pop-out: ' ME.message], false);
end

%% 7. An epsych.Runtime source finds the pump among its interfaces
try
    R = epsych.Runtime;
    R.Interfaces = mock;
    fig3 = uifigure(Visible = 'off', Name = 'Pump Runtime', Tag = [PREF '_rt']);
    figs(end+1) = fig3;

    fromRuntime = gui.SyringePump(R, fig3, ApplyOnStart = false, ...
        PreferenceTag = [PREF '_rt']);
    results(end+1,:) = check('Runtime source resolves the NE1000', fromRuntime.Interface == mock);
    delete(fig3)
    figs(end) = [];
    results(end+1,:) = check('Closing a borrowed panel keeps the link', ...
        isvalid(mock) && mock.IsConnected);
catch ME
    results(end+1,:) = check(['Runtime source: ' ME.message], false);
end

%% 8. Standalone: no pump anywhere, operator picks a port
try
    fig4 = uifigure(Visible = 'off', Name = 'Pump Standalone', Tag = [PREF '_solo']);
    figs(end+1) = fig4;

    solo = gui.SyringePump([], fig4, PreferenceTag = [PREF '_solo']);
    results(end+1,:) = check('Standalone panel opens',        isvalid(solo));
    results(end+1,:) = check('Standalone made an interface',  isa(solo.Interface, 'hw.NE1000'));
    results(end+1,:) = check('Standalone is disconnected',    ~solo.IsConnected);
    results(end+1,:) = check('Standalone keeps the defaults', ...
        abs(solo.Diameter - 21.59) < 1e-9 && abs(solo.Rate - 0.7) < 1e-9 ...
        && strcmp(solo.Direction, 'Infuse'));

    % Every action must degrade quietly with no pump on the other end.
    solo.refresh();
    solo.startPump();
    solo.zeroVolume();
    solo.refreshPorts();
    solo.Rate = 1.25;
    results(end+1,:) = check('Offline actions do not throw', abs(solo.Rate - 1.25) < 1e-9);

    ownedIface = solo.Interface;
    delete(fig4)
    figs(end) = [];
    results(end+1,:) = check('Standalone panel is deleted with its figure', ~isvalid(solo));
    results(end+1,:) = check('Standalone released the interface it made',  ~isvalid(ownedIface));
catch ME
    results(end+1,:) = check(['Standalone: ' ME.message], false);
end

%% 9. Section visibility
try
    results(end+1,:) = check('Everything is shown by default', ...
        isequal(sort(panel.Sections), sort(gui.SyringePump.SECTIONS)));

    panel.hide(["Diameter", "Connection"]);   % Connection = Port + Detect
    results(end+1,:) = check('hide removes the named sections', ...
        ~panel.isSectionVisible("Diameter") && ~panel.isSectionVisible("Port") ...
        && ~panel.isSectionVisible("Detect"));
    results(end+1,:) = check('hide leaves the rest alone', ...
        panel.isSectionVisible("Rate") && panel.isSectionVisible("Triggers"));

    heights = cell2mat(findall(panel.Parent, 'Type', 'uigridlayout', ...
        '-depth', 1).RowHeight);
    results(end+1,:) = check('Hidden rows collapse to zero height', ...
        nnz(heights == 0) == 2);   % the diameter row and the port row

    panel.show("Diameter");
    results(end+1,:) = check('show restores a section', panel.isSectionVisible("Diameter"));

    % A hidden control is only hidden: the panel still drives the pump.
    panel.hide("Rate");
    panel.Rate = 3;
    results(end+1,:) = check('A hidden setting still writes the pump', ...
        abs(mock.SimRate - 3) < 1e-9);
    panel.show("Rate");

    % Nothing to read out means no reason to talk to the pump.
    panel.Sections = "Settings";
    results(end+1,:) = check('No readout stops the poll timer', ...
        strcmp(panel.Timer.Running, 'off'));
    panel.Sections = "All";
    results(end+1,:) = check('Restoring the readout restarts it', ...
        strcmp(panel.Timer.Running, 'on'));

    panel.Sections = ["Volume", "Nonsense"];
    results(end+1,:) = check('An unknown section name is skipped, not fatal', ...
        isequal(panel.Sections, "Volume"));
    panel.Sections = "All";
catch ME
    results(end+1,:) = check(['Sections: ' ME.message], false);
end

%% 10. The right-click menu shows, hides, and sets values
try
    cm = panel.ContextMenu;
    openMenu(cm);

    item = submenuItem(cm, 'Show', 'Diameter');
    clickMenu(item);
    results(end+1,:) = check('Menu hides a section',     ~panel.isSectionVisible("Diameter"));

    openMenu(cm);
    item = submenuItem(cm, 'Show', 'Diameter');
    results(end+1,:) = check('Menu check mark follows Sections', strcmp(item.Checked, 'off'));
    clickMenu(item);
    results(end+1,:) = check('Menu shows it again',      panel.isSectionVisible("Diameter"));

    % Values are reachable from the menu whether or not their row is shown.
    panel.hide("Direction");
    openMenu(cm);
    valueMenu = findall(cm, 'Type', 'uimenu', 'Text', 'Set Value');
    dirMenu = findall(valueMenu, 'Type', 'uimenu', '-regexp', 'Text', '^Direction');
    item = findall(dirMenu, 'Type', 'uimenu', 'Text', 'Withdraw');
    clickMenu(item);
    results(end+1,:) = check('Menu sets a value while its row is hidden', ...
        strcmp(panel.Direction, 'Withdraw') && strcmp(mock.SimDir, 'WDR'));
    panel.show("Direction");

    % The trigger is on the menu as a state, never as a mode.
    panel.hide("TTL");
    openMenu(cm);
    valueMenu = findall(cm, 'Type', 'uimenu', 'Text', 'Set Value');
    ttlMenu = findall(valueMenu, 'Type', 'uimenu', '-regexp', 'Text', '^TTL Trigger');
    clickMenu(findall(ttlMenu, 'Type', 'uimenu', 'Text', 'Enabled'));
    results(end+1,:) = check('Menu enables the trigger while its row is hidden', ...
        panel.TTLTrigger && strcmp(mock.SimTrigger, 'LE'));
    clickMenu(findall(ttlMenu, 'Type', 'uimenu', 'Text', 'Disabled'));
    results(end+1,:) = check('Menu disables it again', ...
        ~panel.TTLTrigger && strcmp(mock.SimTrigger, 'OF'));
    panel.show("TTL");
catch ME
    results(end+1,:) = check(['Context menu: ' ME.message], false);
end

%% 11. The operator's configuration is remembered
try
    % Hiding through the menu is an operator choice, so it persists...
    openMenu(panel.ContextMenu);
    clickMenu(submenuItem(panel.ContextMenu, 'Show', 'Detect'));

    fig5 = uifigure(Visible = 'off', Name = 'Pump Again', Tag = PREF);
    figs(end+1) = fig5;
    again = gui.SyringePump(mock, fig5, ApplyOnStart = false, PreferenceTag = PREF);
    results(end+1,:) = check('A new panel restores the operator layout', ...
        ~again.isSectionVisible("Detect"));
    results(end+1,:) = check('A new panel restores an operator value', ...
        strcmp(again.Direction, 'Withdraw'));
    delete(again)

    % ...while a caller that states its wishes still outranks the memory.
    % (ApplyOnStart stays true here: asking the panel to read the pump
    % instead would make the pump, not the memory, the thing being outranked.)
    fig6 = uifigure(Visible = 'off', Name = 'Pump Stated', Tag = PREF);
    figs(end+1) = fig6;
    stated = gui.SyringePump(mock, fig6, Direction = 'Infuse', PreferenceTag = PREF);
    results(end+1,:) = check('An explicit option beats the remembered value', ...
        strcmp(stated.Direction, 'Infuse') && strcmp(mock.SimDir, 'INF'));
    delete(stated)

    % A programmatic layout change is the paradigm's, not the operator's,
    % so it must not be written into the operator's saved configuration.
    panel.Sections = ["Volume", "Status"];
    fig7 = uifigure(Visible = 'off', Name = 'Pump Prog', Tag = PREF);
    figs(end+1) = fig7;
    prog = gui.SyringePump(mock, fig7, ApplyOnStart = false, PreferenceTag = PREF);
    results(end+1,:) = check('A programmatic layout is not remembered', ...
        prog.isSectionVisible("Rate"));
    delete(prog)
    panel.Sections = "All";

    % Reset to Default forgets the operator's layout for good.
    openMenu(panel.ContextMenu);
    clickMenu(submenuItem(panel.ContextMenu, 'Show', 'Reset to Default'));
    saved = getpref('epsych2_gui_SyringePump', matlab.lang.makeValidName(PREF));
    results(end+1,:) = check('Reset to Default forgets the saved layout', ...
        ~isfield(saved, 'Sections'));
    results(end+1,:) = check('Reset to Default restores everything', ...
        isequal(sort(panel.Sections), sort(gui.SyringePump.SECTIONS)));
catch ME
    results(end+1,:) = check(['Remembered configuration: ' ME.message], false);
end

%% 12. Teardown
try
    delete(figs(isvalid(figs)))
    figs = matlab.ui.Figure.empty;
    results(end+1,:) = check('Panel deleted with its figure', ~isvalid(panel));
    results(end+1,:) = check('Borrowed interface survives',   isvalid(mock) && mock.IsConnected);
    results(end+1,:) = check('No readout timers left behind', ...
        isempty(timerfindall('Name', 'SyringePump_Timer_*')));
    mock.disconnect();
catch ME
    results(end+1,:) = check(['Teardown: ' ME.message], false);
end

%% Cleanup
delete(figs(isvalid(figs)))
try
    grp = 'epsych2_gui_SyringePump';
    for tag = {PREF, [PREF '_read'], [PREF '_rt'], [PREF '_solo']}
        name = matlab.lang.makeValidName(tag{1});
        if ispref(grp, name), rmpref(grp, name); end
    end
catch
end

%% Summary
labels = results(:,1);
passed = cell2mat(results(:,2));
for i = 1:numel(labels)
    if passed(i)
        fprintf('  PASS  %s\n', labels{i});
    else
        fprintf('  FAIL  %s\n', labels{i});
    end
end
fprintf('\n%d passed, %d failed, %d total\n\n', ...
    sum(passed), sum(~passed), numel(passed));

if any(~passed)
    error('smoke_test_syringepump_gui:Failed', '%d smoke test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end


function openMenu(cm)
% openMenu(cm)
% Fire the context menu's opening callback, which is what rebuilds its
% submenus — the state under test lives in that rebuild.
feval(cm.ContextMenuOpeningFcn, cm, []);
end


function item = unitsItem(cm, group, text)
% item = unitsItem(cm, group, text)
% One entry of the Units menu, e.g. unitsItem(cm, 'Rate', 'mL/min'). The
% group labels carry their current value, so they are matched by prefix.
m = findall(cm, 'Type', 'uimenu', 'Text', 'Units');
g = findall(m, 'Type', 'uimenu', '-regexp', 'Text', ['^' group]);
item = findall(g, 'Type', 'uimenu', 'Text', text);
end


function item = submenuItem(cm, submenu, text)
% item = submenuItem(cm, submenu, text)
% One entry of a named submenu, by its exact label.
m = findall(cm, 'Type', 'uimenu', 'Text', submenu);
item = findall(m, 'Type', 'uimenu', 'Text', text);
end


function clickMenu(item)
% clickMenu(item)
% Select a menu entry the way a right-click would.
feval(item.MenuSelectedFcn, item, []);
end
