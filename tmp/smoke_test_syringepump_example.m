% smoke_test_syringepump_example.m
% Headless check of the examples/syringepump worked example — no pump required.
%
% Builds the protocol against tmp/NE1000_Mock, runs a short session through
% run_pump_session, and asserts what the example claims: the pump's Volume
% becomes a per-trial trial-table column, PumpBoxGUI opens with a
% gui.SyringePump panel bound to the session's pump, and the volume the pump
% reports back lands in DATA.
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_syringepump_example.m')"

% Bootstrap: `matlab -batch` starts with whatever path the user profile leaves
% behind, and this file lives in tmp/, which is only on the path once
% epsych_startup has run.
if exist('gui.SyringePump', 'class') ~= 8
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end
addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'examples', 'syringepump'));

fprintf('\n=== SyringePump Example Smoke Test ===\n\n');
results = {};

RUNTIME = [];
boxGUI = [];

%% 1. The protocol compiles with the pump as a trial-table column
try
    [P, pump] = create_pump_protocol('', Save = false);

    results(end+1,:) = check('Protocol carries an hw.NE1000', ...
        any(arrayfun(@(i) isa(i, 'hw.NE1000'), P.Interfaces)));
    results(end+1,:) = check('Pump connected for the build', pump.IsConnected);
    results(end+1,:) = check('Rate units authored as uL/min', strcmp(pump.RateUnits, 'UM'));
    results(end+1,:) = check('One condition per reward volume', P.COMPILED.ntrials == 3);
    results(end+1,:) = check('Volume is a trial-table column', ...
        ismember('Volume', P.COMPILED.writeparams));
    results(end+1,:) = check('Rate is a trial-table column', ...
        ismember('Rate', P.COMPILED.writeparams));

    col = find(strcmp(P.COMPILED.writeparams, 'Volume'), 1);
    levels = sort(cell2mat(P.COMPILED.trials(:, col)))';
    results(end+1,:) = check('Reward volumes are 20/40/60 uL', ...
        isequal(round(levels * 1000), [20 40 60]));
    results(end+1,:) = check('Volume labeled from the syringe, not the rate units', ...
        strcmp(pump.find_parameter('Volume').Unit, 'mL'));
    delete(pump)
catch ME
    results(end+1,:) = check(['Protocol: ' ME.message], false);
end

%% 1b. The saved .eprot reloads with an offline pump carrying its parameters
eprot = [tempname '.eprot'];
try
    [~, pump] = create_pump_protocol(eprot);
    delete(pump)

    Q = epsych.Protocol.load(eprot);
    reloaded = Q.Interfaces(arrayfun(@(i) isa(i, 'hw.NE1000'), Q.Interfaces));
    results(end+1,:) = check('Reloads as an hw.NE1000', isscalar(reloaded));
    results(end+1,:) = check('Reloads offline', ~reloaded.IsConnected);

    pv = reloaded.find_parameter('Volume');
    results(end+1,:) = check('Reward levels survived the round trip', ...
        isequal(round(cell2mat(pv.Values) * 1000), [20 40 60]));
    results(end+1,:) = check('Corrected unit label survived', strcmp(pv.Unit, 'mL'));

    Q.compile();
    results(end+1,:) = check('The reloaded protocol still compiles', Q.COMPILED.ntrials == 3);
    delete(reloaded)
catch ME
    results(end+1,:) = check(['Round trip: ' ME.message], false);
end
if isfile(eprot), delete(eprot); end

%% 2. A session runs, the GUI opens, and the pump reports back
try
    RUNTIME = run_pump_session(NumTrials = 4, TrialPause = 0);

    D = RUNTIME.TRIALS(1).DATA;
    results(end+1,:) = check('Every trial produced a DATA record', numel(D) == 4);
    results(end+1,:) = check('DATA carries the pump read-back', ...
        isfield(D, 'VolumeInfused') && isfield(D, 'VolumeWithdrawn'));
    results(end+1,:) = check('Infused volume accumulates across trials', ...
        D(end).VolumeInfused > D(1).VolumeInfused);
    results(end+1,:) = check('Each trial dispensed its own reward size', ...
        all(abs(diff([D.VolumeInfused]) - [D(2:end).Volume]) < 1e-9));
    results(end+1,:) = check('Dispatched volumes come from the level list', ...
        all(ismember(round([D.Volume] * 1000), [20 40 60])));
catch ME
    results(end+1,:) = check(['Session: ' ME.message], false);
end

%% 3. The box GUI is bound to the session's pump
try
    fig = findall(0, 'Type', 'figure', 'Tag', 'PumpBoxGUI');
    results(end+1,:) = check('PumpBoxGUI opened', ~isempty(fig));

    boxGUI = fig(1).UserData;   % gui.BehaviorGUI parks itself there
    results(end+1,:) = check('Figure carries the PumpBoxGUI', isa(boxGUI, 'PumpBoxGUI'));
    results(end+1,:) = check('It built a gui.SyringePump panel', ...
        isa(boxGUI.Pump, 'gui.SyringePump'));

    sessionPump = RUNTIME.Interfaces(arrayfun(@(i) isa(i, 'hw.NE1000'), RUNTIME.Interfaces));
    results(end+1,:) = check('The panel adopted the session pump', ...
        boxGUI.Pump.Interface == sessionPump);
    results(end+1,:) = check('The panel reports the link is up', boxGUI.Pump.IsConnected);
    results(end+1,:) = check('The panel read a volume back', ...
        ~isnan(boxGUI.Pump.VolumeInfused));
    results(end+1,:) = check('Session pump is still connected', sessionPump.IsConnected);
    results(end+1,:) = check('Session pump was left stopped', ...
        ~ismember(sessionPump.get_parameter('Status'), {'Infusing', 'Withdrawing'}));
catch ME
    results(end+1,:) = check(['Box GUI: ' ME.message], false);
end

%% 4. Teardown leaves nothing behind
try
    fig = findall(0, 'Type', 'figure', 'Tag', 'PumpBoxGUI');
    sessionPump = RUNTIME.Interfaces(arrayfun(@(i) isa(i, 'hw.NE1000'), RUNTIME.Interfaces));
    delete(fig)
    drawnow

    results(end+1,:) = check('Closing the GUI keeps the borrowed pump', ...
        isvalid(sessionPump) && sessionPump.IsConnected);
    results(end+1,:) = check('No pump readout timers left behind', ...
        isempty(timerfindall('Name', 'SyringePump_Timer_*')));

    delete(sessionPump)
catch ME
    results(end+1,:) = check(['Teardown: ' ME.message], false);
end

%% Cleanup
delete(findall(0, 'Type', 'figure', 'Tag', 'PumpBoxGUI'))

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
    error('smoke_test_syringepump_example:Failed', '%d smoke test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end
