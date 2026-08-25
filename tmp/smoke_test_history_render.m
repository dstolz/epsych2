function smoke_test_history_render()
% smoke_test_history_render()
% Cover gui.components.History's render path after the update-speed work: the Trial
% column that replaced the uitable RowName, block padding of the rendered
% row count, per-response row colors, sorting on raw values, per-parameter
% format alignment, and the guards that make a torn-down or reentrant
% update harmless.
% Headless-safe: every GUI is closed before returning.
%
%   matlab -batch "run('tmp/smoke_test_history_render.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % +psychophysics/FakeHistoryPsych.m merges into psychophysics package

PREF_GROUP = 'epsych2_gui_History';
TAGS = {'smokeHistRender1','smokeHistRender2'};
cleanupPrefs(PREF_GROUP, TAGS);
cleanupObj = onCleanup(@() cleanupPrefs(PREF_GROUP, TAGS));

% 1. Trial column replaces the row header --------------------------------
P = psychophysics.FakeHistoryPsych('FreqHz');
P.setData(makeData(7));
f = uifigure('Visible','off','Tag','SmokeHistRender1');
H = gui.components.History(P, f, PreferenceTag='smokeHistRender1');
H.ParametersOfInterest = {'FreqHz','LevelDB'};
H.ParameterColumnFormats = {'%0.1f','%d'};
H.update();

cn = cellstr(string(H.TableH.ColumnName(:)));
assert(isequal(cn, {'Trial';'Time';'Response';'FreqHz';'LevelDB'}), ...
    'Trial should lead the columns (got %s)', strjoin(cn',', '));
assert(isempty(H.TableH.RowName), 'row headers should be off');
assert(isequal(H.TableH.Data(1:7,1)', {'7','6','5','4','3','2','1'}), ...
    'Trial column should count down: newest trial is shown first');
fprintf('PASS: trial number renders as a column, row headers off\n');

% 2. Per-parameter formats still land on the right columns ---------------
% The Trial column shifted every parameter one place right; formats are
% keyed to ParametersOfInterest, so they must follow.
assert(isequal(H.TableH.Data{1,4}, '4000.0'), ...
    'FreqHz should use %%0.1f (got %s)', H.TableH.Data{1,4});
assert(isequal(H.TableH.Data{1,5}, '30'), ...
    'LevelDB should use %%d (got %s)', H.TableH.Data{1,5});
fprintf('PASS: per-parameter formats follow the shifted columns\n');

% 3. Block padding -------------------------------------------------------
assert(size(H.TableH.Data,1) == H.RowBlockSize, ...
    '7 trials should render as one block of %d rows (got %d)', ...
    H.RowBlockSize, size(H.TableH.Data,1));
assert(all(cellfun(@isempty, H.TableH.Data(8,:))), 'padding rows should be blank');
assert(isequal(H.TableH.BackgroundColor(8,:), [1 1 1]), 'padding rows should be white');
assert(size(H.TableH.BackgroundColor,1) == size(H.TableH.Data,1), ...
    'BackgroundColor must have one row per rendered row');
fprintf('PASS: rows padded to a full block, padding blank and white\n');

% 4. The row count only moves at block boundaries -------------------------
% This is the actual optimization: a uitable whose row count changes makes
% the view rebuild its row model, which costs far more than new contents.
counts = zeros(1,12);
for k = 1:12
    P.appendTrials(makeTrial(7+k)); % drives update through the NewData listener
    counts(k) = size(H.TableH.Data,1);
end
assert(all(mod(counts, H.RowBlockSize) == 0), ...
    'rendered row count should always be a whole number of blocks (got %s)', mat2str(counts));
assert(numel(unique(counts)) == 1, ...
    'growing 8->19 trials should not change the rendered row count (got %s)', mat2str(counts));
assert(isequal(H.TableH.Data(1,1), {'19'}), 'newest trial should be trial 19');
fprintf('PASS: row count held constant across 12 appended trials\n');

% 5. RowBlockSize = 1 restores an exact row count -------------------------
H.RowBlockSize = 1;
H.update();
assert(size(H.TableH.Data,1) == 19, ...
    'RowBlockSize=1 should render exactly one row per trial (got %d)', size(H.TableH.Data,1));
H.RowBlockSize = 50;
H.update();
fprintf('PASS: RowBlockSize=1 disables padding\n');

% 6. Row colors track the decoded response bit ---------------------------
bits = P.responseBits;
order = H.Info.DisplayOrder;
expected = hex2rgb(epsych.BitMask.getDefaultColors(bits(order)));
assert(isequal(H.TableH.BackgroundColor(1:numel(order),:), expected), ...
    'row colors should follow the decoded response bit in display order');
fprintf('PASS: row colors follow decoded response bits\n');

% 7. Sorting uses raw values, not the formatted text ----------------------
H.SortByColumn = "FreqHz"; H.SortDirection = "ascend"; H.update();
freqs = str2double(H.TableH.Data(1:19,4));
assert(issorted(freqs), 'sorting by FreqHz should order numerically');
H.SortByColumn = "Trial"; H.SortDirection = "ascend"; H.update();
assert(isequal(str2double(H.TableH.Data(1:19,1))', 1:19), ...
    'the Trial column should sort numerically');
H.SortByColumn = "Response"; H.SortDirection = "ascend"; H.update();
assert(issorted(string(H.TableH.Data(1:19,3))), 'sorting by Response should order as text');
H.SortByColumn = "Time"; H.SortDirection = "descend"; H.update();
fprintf('PASS: sorting on raw values across numeric and text columns\n');

% 8. update() after the table is destroyed must not error -----------------
% The NewData listener can outlive the figure during teardown.
delete(H.TableH);
H.update();
P.appendTrials(makeTrial(99));
fprintf('PASS: update after table teardown is a no-op\n');
delete(H); close(f);

% 9. Empty TrialID takes the early return --------------------------------
P2 = psychophysics.FakeHistoryPsych('FreqHz');
D2 = makeData(3);
D2(1).TrialID = [];
P2.setData(D2);
f2 = uifigure('Visible','off','Tag','SmokeHistRender2');
H2 = gui.components.History(P2, f2, PreferenceTag='smokeHistRender2');
H2.update();
assert(isvalid(H2), 'empty TrialID should return early, not error');
delete(H2); close(f2);
fprintf('PASS: empty TrialID returns early\n');

fprintf('smoke_test_history_render: ALL PASS\n');
end


function D = makeData(n)
% Per-trial DATA struct array shaped like RUNTIME.TRIALS.DATA.
D = makeTrial(1);
for k = 2:n
    D(k) = makeTrial(k);
end
end

function t = makeTrial(k)
t.TrialID = mod(k-1,4)+1;
t.RespCode = uint32(2^mod(k,5));
t.computerTimestamp = datetime('2026-08-12 09:00:00') + seconds(10*k);
t.FreqHz = 1000*2^mod(k,5);
t.LevelDB = 30 + 5*mod(k,7);
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
