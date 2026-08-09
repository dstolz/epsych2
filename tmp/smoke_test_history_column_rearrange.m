function smoke_test_history_column_rearrange()
% smoke_test_history_column_rearrange()
% Exercise gui.History's drag-to-rearrange column support: default column
% order, applying a simulated drag-to-rearrange event, persisting that
% order via getpref/setpref, recalling it in a fresh instance keyed to the
% same PreferenceTag, and gracefully handling a saved order that no longer
% matches the current column set.
% Headless-safe: every GUI is closed before returning.
%
%   matlab -batch "run('tmp/smoke_test_history_column_rearrange.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % +psychophysics/FakeHistoryPsych.m merges into psychophysics package

PREF_GROUP = 'epsych2_gui_History';
TAGS = {'smokeHistCol1','smokeHistCol2','smokeHistCol3'};
cleanupPrefs(PREF_GROUP, TAGS); % guard against stale state from a prior crashed run
cleanupObj = onCleanup(@() cleanupPrefs(PREF_GROUP, TAGS));

% 1. Default column order on first construction --------------------------
P1 = psychophysics.FakeHistoryPsych('FreqHz');
P1.setData(makeData(5));
f1 = uifigure('Visible','off','Tag','SmokeHistCol1');
H1 = gui.History(P1, f1, PreferenceTag='smokeHistCol1');
assert(isequal(H1.TableH.ColumnRearrangeable, matlab.lang.OnOffSwitchState.on), ...
    'table should be configured as column-rearrangeable');
defaultOrder = {'Time';'Response';'FreqHz';'LevelDB'};
assert(isequal(cellstr(string(H1.TableH.ColumnName(:))), defaultOrder), ...
    'default column order should be Time, Response, then DATA fields in order');
fprintf('PASS: default column order\n');

% 2. Simulate a drag-to-rearrange event and confirm it persists ----------
fakeEvent = struct('Interaction','rearrange', ...
    'DisplayColumnName',{{'LevelDB','Time','FreqHz','Response'}});
feval(H1.TableH.DisplayDataChangedFcn, H1.TableH, fakeEvent);
H1.update(); % next refresh should apply the newly-recorded order
rearrangedOrder = {'LevelDB';'Time';'FreqHz';'Response'};
assert(isequal(cellstr(string(H1.TableH.ColumnName(:))), rearrangedOrder), ...
    'column order should follow the simulated drag-to-rearrange event');
delete(H1); close(f1);
fprintf('PASS: simulated drag-to-rearrange reorders columns\n');

% 3. A fresh instance with the same PreferenceTag recalls the order ------
P2 = psychophysics.FakeHistoryPsych('FreqHz');
P2.setData(makeData(5));
f2 = uifigure('Visible','off','Tag','SmokeHistCol2');
H2 = gui.History(P2, f2, PreferenceTag='smokeHistCol1');
assert(isequal(cellstr(string(H2.TableH.ColumnName(:))), rearrangedOrder), ...
    'saved column order should be recalled by a new instance on load');
delete(H2); close(f2);
fprintf('PASS: column order recalled from a prior session via preferences\n');

% 4. A column present in the saved order but absent from the current set -
% must not error; remaining known columns keep the saved relative order,
% and the new/unknown column is appended.
P3 = psychophysics.FakeHistoryPsych('FreqHz');
P3.setData(makeDataNoLevel(5)); % no LevelDB field this session
f3 = uifigure('Visible','off','Tag','SmokeHistCol3');
H3 = gui.History(P3, f3, PreferenceTag='smokeHistCol1');
gotOrder = cellstr(string(H3.TableH.ColumnName(:)));
assert(isequal(gotOrder, {'Time';'FreqHz';'Response'}), ...
    'missing saved column should be dropped, remaining known columns kept in saved order (got %s)', ...
    strjoin(gotOrder,', '));
delete(H3); close(f3);
fprintf('PASS: stale saved column order degrades gracefully\n');

fprintf('smoke_test_history_column_rearrange: ALL PASS\n');
end


function D = makeData(n)
% Per-trial DATA struct array shaped like RUNTIME.TRIALS.DATA.
D = struct([]);
for k = 1:n
    D(k).TrialID = mod(k-1,4)+1;
    D(k).RespCode = uint32(2^mod(k,3));
    D(k).computerTimestamp = datetime('now') + seconds(k);
    D(k).FreqHz = 1000*2^mod(k,5);
    D(k).LevelDB = 30 + 5*mod(k,7);
end
end

function D = makeDataNoLevel(n)
% Same as makeData but without LevelDB, to simulate a changed parameter set.
D = struct([]);
for k = 1:n
    D(k).TrialID = mod(k-1,4)+1;
    D(k).RespCode = uint32(2^mod(k,3));
    D(k).computerTimestamp = datetime('now') + seconds(k);
    D(k).FreqHz = 1000*2^mod(k,5);
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
