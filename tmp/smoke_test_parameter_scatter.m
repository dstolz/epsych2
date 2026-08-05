function smoke_test_parameter_scatter()
% smoke_test_parameter_scatter()
% Exercise gui.ParameterScatter: offline construction in a uifigure,
% parameter list filtering (non-scalar/non-numeric fields excluded, Trial
% Number included), immediate updates on selection changes, color-by mode,
% preference persistence across instances, the runtime/NewData event path
% with invisible-parameter exclusion and BoxID filtering, the preallocated
% empty-trial guard, and the legacy-figure hosting path with resizing.
% Headless-safe: every GUI is closed before returning.
%
%   matlab -batch "run('tmp/smoke_test_parameter_scatter.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % FakeScatterRuntime lives beside this test

PREF_GROUP = 'epsych2_gui_ParameterScatter';
TAGS = {'smokePS1','smokePS2','smokePS3','smokePS4'};
cleanupObj = onCleanup(@() cleanupPrefs(PREF_GROUP, TAGS));

% 1. Offline DATA in a uifigure: parameter list + defaults ----------------
D = makeData(20);
f1 = uifigure('Visible','off','Tag','SmokeScatter1');
S = gui.ParameterScatter(D, f1, PreferenceTag='smokePS1');
items = S.DropdownX.Items;
assert(ismember('Trial Number', items), 'Trial Number missing from parameter list');
assert(all(ismember({'FreqHz','LevelDB','RespCode'}, items)), 'numeric fields missing');
assert(~ismember('ArrParam', items), 'array-valued field should be excluded');
assert(~ismember('NoteStr', items), 'char field should be excluded');
assert(~ismember('computerTimestamp', items), 'datetime field should be excluded');
assert(strcmp(S.XParameter,'Trial Number'), 'default X should be Trial Number (got %s)', S.XParameter);
assert(numel(S.ScatterH.XData) == 20, 'scatter should show all 20 trials');
fprintf('PASS: offline construction, parameter filtering, defaults\n');

% 2. Programmatic selection changes update the plot immediately -----------
S.XParameter = 'FreqHz';
S.YParameter = 'LevelDB';
assert(isequal(S.ScatterH.XData, [D.FreqHz]), 'XData should track FreqHz');
assert(isequal(S.ScatterH.YData, [D.LevelDB]), 'YData should track LevelDB');
assert(strcmp(S.AxesH.XLabel.String,'FreqHz'), 'x label should follow selection');
fprintf('PASS: selection changes redraw immediately\n');

% 3. Color-by third parameter --------------------------------------------
S.ColorParameter = 'RespCode';
assert(numel(S.ScatterH.CData) == 20, 'colorized CData should be one value per trial');
assert(~isempty(S.ColorbarH) && isvalid(S.ColorbarH), 'colorbar should appear in color-by mode');
assert(strcmp(S.ColorbarH.Label.String,'RespCode'), 'colorbar label should name the parameter');
S.ColorParameter = '(none)';
assert(size(S.ScatterH.CData,2) == 3 && size(S.ScatterH.CData,1) == 1, ...
    'flat mode should use a single RGB marker color');
fprintf('PASS: color-by parameter and back to flat color\n');

% 4. Preferences persist across instances --------------------------------
S.DropdownX.Value = 'LevelDB';
S.DropdownY.Value = 'FreqHz';
S.DropdownC.Value = 'RespCode';
S.onSelectionChanged; % simulates the user's dropdown interaction
delete(S); close(f1);
f1b = uifigure('Visible','off','Tag','SmokeScatter1b');
S2 = gui.ParameterScatter(D, f1b, PreferenceTag='smokePS1');
assert(strcmp(S2.XParameter,'LevelDB'), 'saved X selection not restored (got %s)', S2.XParameter);
assert(strcmp(S2.YParameter,'FreqHz'), 'saved Y selection not restored (got %s)', S2.YParameter);
assert(strcmp(S2.ColorParameter,'RespCode'), 'saved color selection not restored (got %s)', S2.ColorParameter);
delete(S2); close(f1b);
fprintf('PASS: selections persist across sessions via preferences\n');

% 5. Runtime event path: NewData updates, invisible + BoxID filtering -----
R = FakeScatterRuntime;
D5 = makeData(5);
for k = 1:5, D5(k).HiddenParam = k; end
trials = struct('DATA',D5,'Subject',struct('Name','SMOKE'),'BoxID',1);
R.TRIALS = trials;
f2 = uifigure('Visible','off','Tag','SmokeScatter2');
S3 = gui.ParameterScatter(R, f2, PreferenceTag='smokePS2');
R.HELPER.notify('NewData', epsych.TrialsData(trials));
assert(numel(S3.ScatterH.XData) == 5, 'NewData event should populate 5 trials');
assert(~ismember('HiddenParam', S3.DropdownX.Items), 'invisible parameter should be excluded');
assert(ismember('FreqHz', S3.DropdownX.Items), 'visible parameter should be offered');

S3.BoxID = 2; % events from other boxes must now be ignored
trials6 = trials;
trials6.DATA = makeData(6);
R.HELPER.notify('NewData', epsych.TrialsData(trials6));
assert(numel(S3.ScatterH.XData) == 5, 'event from non-matching box should be ignored');
S3.BoxID = [];
R.HELPER.notify('NewData', epsych.TrialsData(trials6));
assert(numel(S3.ScatterH.XData) == 6, 'event should apply once BoxID filter cleared');
delete(S3); close(f2);
fprintf('PASS: runtime NewData path, invisible exclusion, BoxID filter\n');

% 6. Preallocated-but-empty DATA guard ------------------------------------
Dpre = struct('TrialID',[],'FreqHz',[]);
f3 = uifigure('Visible','off','Tag','SmokeScatter3');
S4 = gui.ParameterScatter(Dpre, f3, PreferenceTag='smokePS3');
assert(isempty(S4.ScatterH.XData), 'preallocated empty trial should plot nothing');
delete(S4); close(f3);
fprintf('PASS: preallocated empty-trial guard\n');

% 7. Legacy figure hosting with resize ------------------------------------
f4 = figure('Visible','off','Tag','SmokeScatter4');
S5 = gui.ParameterScatter(D, f4, PreferenceTag='smokePS4');
assert(strcmp(S5.DropdownX.Style,'popupmenu'), 'legacy hosting should use popupmenu controls');
assert(numel(S5.ScatterH.XData) == 20, 'legacy hosting should plot all trials');
f4.Position(3:4) = [900 500];
drawnow; % fires the wrapper panel SizeChangedFcn
S5.XParameter = 'FreqHz';
assert(isequal(S5.ScatterH.XData,[D.FreqHz]), 'legacy dropdown selection should redraw');
delete(S5); close(f4);
fprintf('PASS: legacy figure hosting and resize\n');

fprintf('smoke_test_parameter_scatter: ALL PASS\n');
end


function D = makeData(n)
% Per-trial DATA struct array shaped like RUNTIME.TRIALS.DATA.
D = struct([]);
for k = 1:n
    D(k).TrialID = mod(k-1,4)+1;      % schedule ID, deliberately non-chronological
    D(k).RespCode = uint32(2^mod(k,3));
    D(k).FreqHz = 1000*2^mod(k,5);
    D(k).LevelDB = 30 + 5*mod(k,7);
    D(k).computerTimestamp = datetime('now') + seconds(k);
    D(k).ArrParam = 1:4;              % non-scalar: must be excluded
    D(k).NoteStr = 'abc';             % non-numeric: must be excluded
    D(k).isTest = false;
end
end

function cleanupPrefs(group, tags)
% Remove only the preference keys this test created.
for k = 1:numel(tags)
    tag = matlab.lang.makeValidName(tags{k});
    if ispref(group, tag)
        rmpref(group, tag);
    end
end
end
