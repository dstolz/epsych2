% smoke_test_bpod_protocol.m
% Protocol round-trip tests for hw.Bpod — no hardware required.
%
% Targets the failure mode that is otherwise SILENT: epsych.Protocol rebuilds
% interfaces through a hard-coded switch whose `otherwise` branch returns
% hw.Software(). A backend missing from that switch saves fine and reloads as a
% software stub with its modules and every parameter NAME intact, so the trial
% table still compiles, epsych.SelfTest still passes, and the first sign of
% trouble is a session that will not start — or worse, one that starts and
% drives nothing. These tests assert the reloaded interface is really a hw.Bpod
% and that its construction options survived.
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_bpod_protocol.m')"

% Bootstrap: `matlab -batch` starts with whatever path the user profile leaves
% behind, and this file lives in tmp/, which is only on the path once
% epsych_startup has run.
if exist('hw.Bpod', 'class') ~= 8
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end

fprintf('\n=== hw.Bpod Protocol Round-Trip Test ===\n\n');
results = {};

scratch = tempname;
mkdir(scratch);
cleanupScratch = onCleanup(@() rmdir(scratch, 's'));
protocolFile = fullfile(scratch, 'bpod_roundtrip.eprot');

reloaded = [];

%% 1. Build a protocol carrying a Bpod interface
try
    prot = epsych.Protocol(Name = 'BpodRoundTrip');

    iface = hw.Bpod('COM3', Connect = false, BoxID = 2, StateMatrixFcn = 'foo');
    m = hw.Module(iface, 'Bpod', 'Bpod', uint8(1));
    m.Fs = hw.Bpod.TICK_HZ;

    % A representative slice of the real table: the three trial triggers, one
    % trial-config column, one trial result, and one invisible I/O line.
    m.add_parameter('x_NewTrial_2', false,      Type = 'Boolean', Access = 'Any', Visible = false, isTrigger = true);
    m.add_parameter('x_ResetTrig_2', false,     Type = 'Boolean', Access = 'Any', Visible = false, isTrigger = true);
    m.add_parameter('x_TrialComplete_2', false, Type = 'Boolean', Access = 'Read', Visible = false);
    m.add_parameter('Valve1', false,            Type = 'Boolean', Access = 'Any', Visible = false);
    m.add_parameter('RespCode', 0,              Type = 'Integer', Access = 'Read');
    m.add_parameter('TrialDuration', [0.25 0.5 1.0], Type = 'Float',   Access = 'Any', Unit = 's');
    m.add_parameter('TrialType', [1 2],              Type = 'Integer', Access = 'Any');
    iface.setModules(m);

    prot.addInterface(iface);
    % A new protocol already carries an hw.Software interface, so look the Bpod
    % up by type rather than assuming it landed at a particular index.
    results(end+1,:) = check('Protocol accepts a Bpod interface', ...
        ~isempty(prot.findInterface('Bpod')));
    results(end+1,:) = check('Software interface is still present', ...
        ~isempty(prot.findInterface('Software')));
catch ME
    results(end+1,:) = check(['Build protocol: ' ME.message], false);
end

%% 2. Save and reload
try
    prot.save(protocolFile);
    results(end+1,:) = check('Protocol saved', isfile(protocolFile));

    reloaded = epsych.Protocol.load(protocolFile);
    results(end+1,:) = check('Protocol reloaded', ~isempty(reloaded));

    back = reloaded.findInterface('Bpod');

    % THE LOAD-BEARING ASSERTION. Without a 'Bpod' case in
    % createInterfaceFromStruct_ the interface comes back as hw.Software with
    % its modules and parameter names intact, findInterface returns empty, and
    % nothing warns. Do not weaken this to a count or a name check: those pass
    % on the software stub.
    results(end+1,:) = check('Reloaded interface is found by type', ~isempty(back));
    results(end+1,:) = check('Reloaded interface is a hw.Bpod', isa(back, 'hw.Bpod'));
    results(end+1,:) = check('Reloaded interface is NOT a software stub', ...
        ~isempty(back) && ~isa(back, 'hw.Software'));
catch ME
    results(end+1,:) = check(['Save/reload: ' ME.message], false);
end

%% 3. Construction options survived the round trip
try
    back = reloaded.findInterface('Bpod');
    if isempty(back)
        results(end+1,:) = check('Options round-trip (no Bpod interface reloaded)', false);
    else
        % Port is a char serial name, not a numeric TCP port. Coercing it with
        % double() would silently store [67 79 77 51].
        results(end+1,:) = check('Port survived as a char name', ...
            ischar(back.Port) && strcmp(back.Port, 'COM3'));
        % BoxID names every per-box parameter the runtime resolves literally
        % (x_NewTrial_2, x_TrialComplete_2, ...). A BoxID that reverts to 1
        % rebuilds the table under names no subject looks for.
        results(end+1,:) = check('BoxID survived',         isprop(back, 'BoxID') && back.BoxID == 2);
        results(end+1,:) = check('StateMatrixFcn survived', ...
            isprop(back, 'StateMatrixFcn') && strcmp(back.StateMatrixFcn, 'foo'));
        results(end+1,:) = check('AutoDetect survived',    isprop(back, 'AutoDetect') && ~back.AutoDetect);
        results(end+1,:) = check('Reloaded interface is offline', ~back.IsConnected);
    end
catch ME
    results(end+1,:) = check(['Options round-trip: ' ME.message], false);
end

%% 4. Modules and parameter metadata survived
try
    back = reloaded.findInterface('Bpod');
    if isempty(back)
        back = reloaded.Interfaces(end);
    end
    results(end+1,:) = check('One module survived', numel(back.Module) == 1);
    results(end+1,:) = check('Module Fs survived', back.Module(1).Fs == hw.Bpod.TICK_HZ);
    results(end+1,:) = check('All seven parameters survived', ...
        numel(back.Module(1).Parameters) == 7);

    newTrial = back.find_parameter('x_NewTrial_2', includeInvisible = true);
    results(end+1,:) = check('x_NewTrial_2 is still a trigger', ...
        ~isempty(newTrial) && newTrial.isTrigger);
    % A 'Write' trigger is invisible to find_parameter's Access='Read' filter
    % and the session dies with epsych:RunExpt:MissingTrigger.
    results(end+1,:) = check('x_NewTrial_2 Access is still Any', ...
        ~isempty(newTrial) && strcmp(newTrial.Access, 'Any'));

    complete = back.find_parameter('x_TrialComplete_2', includeInvisible = true);
    results(end+1,:) = check('x_TrialComplete_2 Access is still Read', ...
        ~isempty(complete) && strcmp(complete.Access, 'Read'));
    results(end+1,:) = check('x_TrialComplete_2 is still invisible', ...
        ~isempty(complete) && ~complete.Visible);

    dur = back.find_parameter('TrialDuration');
    results(end+1,:) = check('TrialDuration kept its three trial levels', ...
        ~isempty(dur) && numel(dur.Values) == 3);
    results(end+1,:) = check('TrialDuration kept its unit', ...
        ~isempty(dur) && strcmp(dur.Unit, 's'));

    resp = back.find_parameter('RespCode');
    results(end+1,:) = check('RespCode is still a read-only result', ...
        ~isempty(resp) && strcmp(resp.Access, 'Read'));
catch ME
    results(end+1,:) = check(['Module round-trip: ' ME.message], false);
end

%% 5. The reloaded protocol compiles into a trial table
try
    reloaded.compile();
    wp = reloaded.COMPILED.writeparams;

    % Visible && Access ~= 'Read' is the trial-table filter. The three x_*_2
    % triggers are invisible, so they must not become columns; if they did, each
    % would multiply the trial count by its level set.
    results(end+1,:) = check('x_NewTrial_2 is not a trial column',      ~any(strcmp(wp, 'x_NewTrial_2')));
    results(end+1,:) = check('x_ResetTrig_2 is not a trial column',     ~any(strcmp(wp, 'x_ResetTrig_2')));
    results(end+1,:) = check('x_TrialComplete_2 is not a trial column', ~any(strcmp(wp, 'x_TrialComplete_2')));
    results(end+1,:) = check('Invisible I/O lines are not trial columns', ~any(strcmp(wp, 'Valve1')));
    results(end+1,:) = check('Read-only results are not trial columns',   ~any(strcmp(wp, 'RespCode')));

    results(end+1,:) = check('TrialDuration is a trial column', any(strcmp(wp, 'TrialDuration')));
    results(end+1,:) = check('TrialType is a trial column',     any(strcmp(wp, 'TrialType')));

    % 3 durations x 2 trial types = 6, and nothing else contributes.
    results(end+1,:) = check('Trial table is the 3 x 2 cross product', ...
        reloaded.COMPILED.ntrials == 6);

    trigs = back.find_parameter({'x_NewTrial_2', 'x_ResetTrig_2'}, includeInvisible = true);
    results(end+1,:) = check('Triggers survive as triggers', ...
        ~isempty(trigs) && all([trigs.isTrigger]));
    % isTrigger sets UpdateEveryTrial=false, which is what dispatchNextTrial
    % filters on to keep a trigger out of the per-trial parameter write.
    results(end+1,:) = check('Triggers are excluded from per-trial dispatch', ...
        ~isempty(trigs) && ~any([trigs.UpdateEveryTrial]));
catch ME
    results(end+1,:) = check(['Compile: ' ME.message], false);
end

%% 6. Registry source guards
% These three registries are hard-coded lists with no reflection whatsoever, and
% each omission fails silently in a different way. They live in @ProtocolDesigner/private
% and @Protocol, so they are unreachable from a script — assert against the source.
try
    protocolDir = fileparts(which('epsych.Protocol'));
    designerDir = fileparts(which('epsych.ProtocolDesigner'));

    % Omitting this one is the failure the whole file exists for.
    createSrc = fileread(fullfile(protocolDir, 'createInterfaceFromStruct_.m'));
    results(end+1,:) = check('createInterfaceFromStruct_ has a Bpod case', ...
        contains(createSrc, "case 'Bpod'"));
    results(end+1,:) = check('createInterfaceFromStruct_ restores BoxID', ...
        contains(createSrc, 'BoxID'));
    results(end+1,:) = check('createInterfaceFromStruct_ restores StateMatrixFcn', ...
        contains(createSrc, 'StateMatrixFcn'));

    % toStruct writes only the properties it names, so BoxID and StateMatrixFcn
    % are dropped on save unless it knows about them — and a dropped option is
    % indistinguishable from an option the user never set.
    toSrc = fileread(fullfile(protocolDir, 'toStruct.m'));
    results(end+1,:) = check('toStruct serializes BoxID', contains(toSrc, 'BoxID'));
    results(end+1,:) = check('toStruct serializes StateMatrixFcn', ...
        contains(toSrc, 'StateMatrixFcn'));

    % Omitting this one makes the backend simply not appear in the designer's
    % Add Interface list, the way hw.VlcRecorder does not.
    specSrc = fileread(fullfile(designerDir, 'private', 'getAvailableInterfaceSpecs.m'));
    results(end+1,:) = check('Designer registry lists a Bpod spec', ...
        contains(specSrc, 'localSerializedBpodSpec_'));
    results(end+1,:) = check('Designer registry calls hw.Bpod.getCreationSpec', ...
        contains(specSrc, 'hw.Bpod.getCreationSpec'));
    % The designer must never touch hardware while editing a protocol, and
    % hw.Bpod's own createFcn does not pass Connect=false.
    results(end+1,:) = check('Designer factory constructs with Connect = false', ...
        contains(specSrc, 'hw.Bpod(port, Connect = false') || ...
        contains(specSrc, 'hw.Bpod(port, Connect=false'));

    % Omitting this one makes Modify error outright with
    % "Editing is not implemented for interface type Bpod".
    editSrc = fileread(fullfile(designerDir, 'private', 'getInterfaceEditState.m'));
    results(end+1,:) = check('Designer can edit Bpod options', ...
        contains(editSrc, "case 'Bpod'"));
    results(end+1,:) = check('Edit state reads the getCreationSpec option names', ...
        contains(editSrc, 'boxID') && contains(editSrc, 'stateMatrixFcn'));
catch ME
    results(end+1,:) = check(['Designer registry: ' ME.message], false);
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
fprintf('\n%d passed, %d failed, %d total\n\n', sum(passed), sum(~passed), numel(passed));

if any(~passed)
    error('smoke_test_bpod_protocol:Failed', '%d test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end
