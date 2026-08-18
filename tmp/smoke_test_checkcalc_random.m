function smoke_test_checkcalc_random()
% smoke_test_checkcalc_random()
% Exercise the Random column of the Check Calculations inputs table: a ticked
% row with a [min max] pair is drawn once per Run Check instead of being swept,
% integer parameters draw whole numbers, and anything that is not a usable pair
% falls back to sweeping what was typed with a warning.
%
%   matlab -batch "run('tmp/smoke_test_checkcalc_random.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

P = epsych.Protocol;
P.addParameter('Software', 'Atten', 10, Min=0, Max=100);
P.addParameter('Software', 'Steps', 2, Type='Integer', Min=1, Max=10);
pLevel = P.addParameter('Software', 'Level', 0, Min=-1000, Max=1000);
pLevel.Expression = "Atten + Steps";

D = epsych.ProtocolDesigner(P);
cleanupObj = onCleanup(@() delete(D));
D.onOpenCheckCalculationsDialog();

[inTbl, issueTbl, resTbl] = localCheckCalcTables_();
attenRow = localRowFor_(inTbl, 'Atten');
stepsRow = localRowFor_(inTbl, 'Steps');

% ===== A. The Random column exists and is editable =======================
try
    assert(isequal(inTbl.ColumnName(:).', {'Variable', 'Values', 'Random', 'Note'}), ...
        'unexpected input columns: %s', strjoin(string(inTbl.ColumnName), ', '));
    assert(isequal(inTbl.ColumnEditable, [false true true false]), ...
        'Values and Random must be the only editable columns');
    assert(islogical(inTbl.Data{attenRow, 3}) && ~inTbl.Data{attenRow, 3}, ...
        'Random must default to an unticked logical (checkbox) cell');
    fprintf('PASS: A. Random column present, editable, and unticked by default\n');
catch ME
    failures{end+1} = sprintf('A. column: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. A ticked [min max] row collapses to one drawn value ============
try
    localSetInput_(inTbl, attenRow, '[0 100]', true);
    localSetInput_(inTbl, stepsRow, '3', false);
    D.refreshCheckCalculations();

    drawn = localDrawnValue_(inTbl, attenRow);
    assert(drawn >= 0 && drawn <= 100, 'draw %g outside [0 100]', drawn);
    assert(size(resTbl.Data, 2) == 1, ...
        'a randomized input must not sweep: expected 1 combination, got %d', size(resTbl.Data, 2));

    swept = localResultValue_(resTbl, 'Atten');
    assert(abs(swept - drawn) < 1e-4, ...
        'the sweep used %g but the table reported a draw of %g', swept, drawn);
    level = localResultValue_(resTbl, 'Level');
    assert(abs(level - (swept + 3)) < 1e-9, ...
        'Level should be %g, got %g', swept + 3, level);
    assert(~any(strcmpi(issueTbl.Data(:, 1), 'Warning')), ...
        'a valid [min max] draw should raise no warning');
    fprintf('PASS: B. ticked [min max] draws one value and feeds the expression\n');
catch ME
    failures{end+1} = sprintf('B. draw: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. Each Run Check redraws =========================================
try
    draws = zeros(1, 12);
    for k = 1:numel(draws)
        D.refreshCheckCalculations();
        draws(k) = localDrawnValue_(inTbl, attenRow);
    end
    assert(all(draws >= 0 & draws <= 100), 'a draw fell outside [0 100]');
    assert(numel(unique(draws)) > 1, 'repeated checks returned the same value %g', draws(1));
    assert(inTbl.Data{attenRow, 3}, 'the Random tick must survive a refresh');
    assert(strcmp(strtrim(inTbl.Data{attenRow, 2}), '[0 100]'), ...
        'the typed range must survive a refresh, got "%s"', inTbl.Data{attenRow, 2});
    fprintf('PASS: C. every Run Check redraws and keeps the tick and range\n');
catch ME
    failures{end+1} = sprintf('C. redraw: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. Integer parameters draw whole numbers ==========================
try
    localSetInput_(inTbl, attenRow, '5', false);
    localSetInput_(inTbl, stepsRow, '[1 4]', true);
    draws = zeros(1, 15);
    for k = 1:numel(draws)
        D.refreshCheckCalculations();
        draws(k) = localDrawnValue_(inTbl, stepsRow);
    end
    assert(all(draws == round(draws)), 'an Integer parameter drew a fractional value');
    assert(all(draws >= 1 & draws <= 4), 'an Integer draw fell outside [1 4]');
    assert(numel(unique(draws)) > 1, 'integer draws never varied');
    fprintf('PASS: D. Integer inputs draw whole numbers inside the range\n');
catch ME
    failures{end+1} = sprintf('D. integer: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== E. Anything but a usable pair warns and sweeps ====================
try
    localSetInput_(inTbl, attenRow, '[1 2 3]', true);
    localSetInput_(inTbl, stepsRow, '3', false);
    D.refreshCheckCalculations();
    assert(localHasIssue_(issueTbl, 'Random needs exactly two values'), ...
        'a three-value Random row should warn; issues: %s', localIssueText_(issueTbl));
    assert(size(resTbl.Data, 2) == 3, ...
        'the typed values should still be swept: expected 3 combinations, got %d', ...
        size(resTbl.Data, 2));

    localSetInput_(inTbl, attenRow, '[80 20]', true);
    D.refreshCheckCalculations();
    assert(localHasIssue_(issueTbl, 'min <= max'), ...
        'a reversed pair should warn; issues: %s', localIssueText_(issueTbl));

    localSetInput_(inTbl, attenRow, '5', false);
    localSetInput_(inTbl, stepsRow, '[1.2 1.8]', true);
    D.refreshCheckCalculations();
    assert(localHasIssue_(issueTbl, 'No whole number'), ...
        'an Integer range holding no whole number should warn; issues: %s', ...
        localIssueText_(issueTbl));

    localSetInput_(inTbl, stepsRow, '', true);
    D.refreshCheckCalculations();
    assert(localHasIssue_(issueTbl, 'Random needs a [min max] pair'), ...
        'a ticked but empty row should warn; issues: %s', localIssueText_(issueTbl));
    fprintf('PASS: E. unusable Random rows warn and fall back to sweeping\n');
catch ME
    failures{end+1} = sprintf('E. fallback: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end

fprintf('\n===== SUMMARY =====\n');
if isempty(failures)
    fprintf('ALL CHECKS PASSED\n');
else
    fprintf('%d FAILURE(S):\n', numel(failures));
    fprintf('  - %s\n', failures{:});
end
end


function [inTbl, issueTbl, resTbl] = localCheckCalcTables_()
% The dialog's controls are protected, so reach them through the figure.
figs = findall(groot, 'Type', 'figure', 'Name', 'Check Calculations');
assert(~isempty(figs), 'the Check Calculations dialog did not open');
tbls = findall(figs(1), 'Type', 'uitable');
inTbl = localTableWithColumn_(tbls, 'Variable');
issueTbl = localTableWithColumn_(tbls, 'Severity');
resTbl = tbls(~ismember(tbls, [inTbl issueTbl]));
resTbl = resTbl(1);
end


function tbl = localTableWithColumn_(tbls, colName)
for k = 1:numel(tbls)
    if any(strcmp(tbls(k).ColumnName, colName))
        tbl = tbls(k);
        return
    end
end
error('no table with a "%s" column', colName);
end


function row = localRowFor_(tbl, paramName)
labels = string(tbl.Data(:, 1));
row = find(endsWith(labels, "." + paramName), 1);
assert(~isempty(row), 'no input row for %s (rows: %s)', paramName, strjoin(labels, ', '));
end


function localSetInput_(tbl, row, valuesText, randomize)
data = tbl.Data;
data{row, 2} = valuesText;
data{row, 3} = randomize;
tbl.Data = data;
end


function v = localDrawnValue_(tbl, row)
note = char(string(tbl.Data{row, 4}));
tok = regexp(note, '^random ([^\s;]+)', 'tokens', 'once');
assert(~isempty(tok), 'the Note cell does not report a draw: "%s"', note);
v = str2double(tok{1});
end


function v = localResultValue_(tbl, name)
rows = string(tbl.RowName);
idx = find(rows == name | endsWith(rows, "." + name), 1);
assert(~isempty(idx), 'no result row for %s (rows: %s)', name, strjoin(rows, ', '));
v = double(tbl.Data{idx, 1});
end


function tf = localHasIssue_(tbl, needle)
tf = any(contains(string(tbl.Data(:, 3)), needle));
end


function txt = localIssueText_(tbl)
txt = strjoin(string(tbl.Data(:, 3)), ' | ');
end
