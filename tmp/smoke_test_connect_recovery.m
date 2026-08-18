% smoke_test_connect_recovery.m
% Offline smoke tests for operator recovery from a failed hardware connect.
%
% Covers the three pieces added so a pump nobody switched on no longer ends
% the command in HardwareInitializationFailed:
%   - the hw.Interface capability hooks and their safe defaults
%   - gui.selectSerialPort, driven from a timer the way an operator would
%     drive it (refresh, probe, select, cancel)
%   - epsych.Runtime.Interfaces honouring RunOffline
%
% The uiconfirm prompt in RunExpt.promptConnectFailure_ is not covered: it is
% modal and has no programmatic handle. Its three outcomes are exercised by
% the branches below that it selects between.
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_connect_recovery.m')"

% Bootstrap: `matlab -batch` starts with whatever path the user profile leaves
% behind, and this file lives in tmp/, which is only on the path once
% epsych_startup has run.
if exist('gui.selectSerialPort', 'file') ~= 2
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end

fprintf('\n=== Connect Recovery Smoke Test ===\n\n');
results = {};

ports = cellstr(serialportlist('available'));
hasPort = ~isempty(ports);
if ~hasPort
    fprintf('  NOTE  no serial ports available; port-selection cases are skipped\n\n');
end

%% 1. Safe defaults on a backend that declares nothing
sw = hw.Software.empty;
try
    sw = hw.Software();
    results(end+1,:) = check('Software offers no connection recovery', ...
        isempty(sw.connectionRecoveryLabel()));
    results(end+1,:) = check('Software refuses recoverConnection', ...
        ~sw.recoverConnection([]));
    results(end+1,:) = check('Software cannot run offline', ~sw.canRunOffline());
    results(end+1,:) = check('RunOffline defaults false', ~sw.RunOffline);
    results(end+1,:) = check('displayLabel is human-readable', ...
        ~isempty(sw.displayLabel()) && ~strcmp(sw.displayLabel(), 'hw.Software'));
catch ME
    results(end+1,:) = check(sprintf('Software defaults threw: %s', ME.message), false);
end

%% 2. The pump declares both capabilities
pump = hw.NE1000.empty;
try
    pump = hw.NE1000('COM_NONE', Connect = false);
    results(end+1,:) = check('Pump offers a port picker', ...
        contains(pump.connectionRecoveryLabel(), 'Port'));
    results(end+1,:) = check('Pump may run offline', pump.canRunOffline());
    results(end+1,:) = check('Pump label names the device', ...
        contains(pump.displayLabel(), 'NE-1000'));
catch ME
    results(end+1,:) = check(sprintf('Pump capabilities threw: %s', ME.message), false);
end

%% 3. A disconnected pump degrades instead of throwing
% This is what makes RunOffline safe: every transaction no-ops and reads
% serve the cached value, so trial dispatch over an offline pump is inert.
try
    results(end+1,:) = check('Offline pump reports no connection', ~pump.IsConnected);

    pump.mode = hw.DeviceState.Record;
    results(end+1,:) = check('Offline pump accepts a mode change', ...
        pump.mode == hw.DeviceState.Record);
    results(end+1,:) = check('Offline pump never reports Idle to the run loop', ...
        pump.mode ~= hw.DeviceState.Idle);
catch ME
    results(end+1,:) = check(sprintf('Offline pump threw: %s', ME.message), false);
end

%% 4. gui.selectSerialPort — cancel returns nothing
try
    driver = portDialogDriver('NE-1000 Syringe Pump', @(fig) clickButton(fig, 'Cancel'));
    chosen = gui.selectSerialPort(Title = 'NE-1000 Syringe Pump', CurrentPort = 'COM_NONE');
    stopDriver(driver);
    results(end+1,:) = check('Cancel returns an empty port', isempty(chosen));
catch ME
    results(end+1,:) = check(sprintf('Cancel case threw: %s', ME.message), false);
end

%% 5. Refresh re-enumerates, and OK returns the selection
if hasPort
    try
        want = ports{1};
        driver = portDialogDriver('Pick a port', @(fig) selectAndAccept(fig, want));
        chosen = gui.selectSerialPort(Title = 'Pick a port');
        stopDriver(driver);
        results(end+1,:) = check('Refresh then OK returns the selected port', ...
            strcmp(chosen, want));
    catch ME
        results(end+1,:) = check(sprintf('Select case threw: %s', ME.message), false);
    end
end

%% 6. A probe that finds nothing says so; one that finds a port selects it
try
    driver = portDialogDriver('Probe empty', @(fig) probeThenCancel(fig));
    chosen = gui.selectSerialPort(Title = 'Probe empty', Probe = @() '');
    stopDriver(driver);
    results(end+1,:) = check('A probe that finds nothing still cancels cleanly', isempty(chosen));
catch ME
    results(end+1,:) = check(sprintf('Empty probe threw: %s', ME.message), false);
end

if hasPort
    try
        want = ports{1};
        driver = portDialogDriver('Probe hit', @(fig) probeThenAccept(fig));
        chosen = gui.selectSerialPort(Title = 'Probe hit', Probe = @() want);
        stopDriver(driver);
        results(end+1,:) = check('A probe that finds a port preselects it for OK', ...
            strcmp(chosen, want));
    catch ME
        results(end+1,:) = check(sprintf('Probe hit threw: %s', ME.message), false);
    end
end

%% 7. Runtime.Interfaces rejects a dead interface, accepts a consented one
rt = epsych.Runtime.empty;
try
    rt = epsych.Runtime();
    threw = false;
    try
        rt.Interfaces = pump;      % Port 'COM_NONE' cannot open
    catch
        threw = true;
    end
    results(end+1,:) = check('A pump that cannot connect still fails the setter', threw);

    pump.RunOffline = true;
    ok = true;
    try
        rt.Interfaces = [sw pump];
    catch ME
        ok = false;
        fprintf('    (setter threw: %s)\n', ME.message);
    end
    results(end+1,:) = check('RunOffline lets the setter pass over it', ok);
    results(end+1,:) = check('The offline interface stays in the array', ...
        ok && numel(rt.Interfaces) == 2 && any(arrayfun(@(x) isa(x,'hw.NE1000'), rt.Interfaces)));
    results(end+1,:) = check('The offline interface still knows its runtime', ...
        ok && ~isempty(pump.Runtime));
catch ME
    results(end+1,:) = check(sprintf('Runtime case threw: %s', ME.message), false);
end

%% Teardown
for h = {rt, pump, sw}
    try
        if ~isempty(h{1}) && isvalid(h{1})
            delete(h{1});
        end
    catch ME
        fprintf('    (teardown: %s)\n', ME.message);
    end
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
    error('smoke_test_connect_recovery:Failed', '%d smoke test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end


function t = portDialogDriver(title, action)
% t = portDialogDriver(title, action)
% Stand in for the operator: wait for the modal dialog named `title` to
% exist, then run `action` on it. gui.selectSerialPort blocks in uiwait, so
% the only way in is a timer — which MATLAB keeps servicing meanwhile.
t = timer(ExecutionMode = 'fixedSpacing', Period = 0.25, StartDelay = 0.25, ...
    TasksToExecute = 40, Name = 'portDialogDriver', ...
    TimerFcn = @(src, ~) tick(src));
start(t);

    function tick(src)
        fig = findall(groot, 'Type', 'figure', 'Name', title);
        if isempty(fig)
            return
        end
        % The figure handle exists before its components do, and building a
        % uifigure takes a visible fraction of a second under -batch. Wait for
        % the button every layout has rather than clicking into a bare figure.
        if isempty(findall(fig(1), '-isa', 'matlab.ui.control.Button', 'Text', 'Cancel'))
            return
        end
        stop(src);
        try
            action(fig(1));
        catch ME
            fprintf('    (driver failed: %s)\n', ME.message);
            delete(fig(1));   % never leave the test blocked in uiwait
        end
    end
end


function stopDriver(t)
if isvalid(t)
    stop(t);
    delete(t);
end
end


function selectAndAccept(fig, port)
% Press Refresh, choose `port` in the list, then OK — the ordinary path.
clickButton(fig, 'Refresh');
lb = findall(fig, '-isa', 'matlab.ui.control.ListBox');
lb.Value = port;
% Setting Value programmatically does not fire ValueChangedFcn, so the
% dialog is told the same way the click would tell it.
feval(lb.ValueChangedFcn, lb, []);
clickButton(fig, 'OK');
end


function probeThenCancel(fig)
clickButton(fig, 'Detect Device');
clickButton(fig, 'Cancel');
end


function probeThenAccept(fig)
% The probe selects the port it found, so OK needs no further choice.
clickButton(fig, 'Detect Device');
clickButton(fig, 'OK');
end


function clickButton(fig, text)
% clickButton(fig, text)
% Press a button the way a mouse would.
b = findall(fig, '-isa', 'matlab.ui.control.Button', 'Text', text);
feval(b(1).ButtonPushedFcn, b(1), []);
end
