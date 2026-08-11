function smoke_test_preview_transpose()
% smoke_test_preview_transpose()
% Headless smoke test for the Transpose checkbox on the Compiled Trial
% Preview dialog: verifies the checkbox exists, and that toggling it swaps
% the table between trials-as-rows and trials-as-columns without changing
% the underlying data.
%
% Run with: matlab -batch "run('tmp/smoke_test_preview_transpose.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot);
epsych_startup();

fprintf('--- Compiled Preview transpose smoke test ---\n');

protocol = epsych.Protocol(Name = 'PreviewTransposeSmokeTest');
module = protocol.Interfaces(1).Module;
module.add_parameter('freq', [1000 2000 4000], Type = 'Float', Unit = 'Hz');
module.add_parameter('level', [30 60], Type = 'Float', Unit = 'dB');
protocol.compile();

designer = epsych.ProtocolDesigner(protocol);
cleanupDesigner = onCleanup(@() localForceClose_(designer));

designer.onOpenCompiledPreviewDialog();

peek = @(name) localPeek_(designer, name);

chk = peek('CheckTransposePreview');
assert(~isempty(chk) && isvalid(chk), 'CheckTransposePreview was not created');
assert(strcmp(chk.Text, 'Transpose'), 'CheckTransposePreview has unexpected label "%s"', chk.Text);
assert(chk.Value == false, 'CheckTransposePreview should default to unchecked');

tbl = peek('TableCompiled');
nParams = numel(protocol.COMPILED.parameters);
nTrials = protocol.COMPILED.ntrials;

% Untransposed: rows = trials, columns = parameters.
assert(isequal(size(tbl.Data), [nTrials, nParams]), ...
    'Untransposed table size mismatch: got [%d %d], expected [%d %d]', ...
    size(tbl.Data, 1), size(tbl.Data, 2), nTrials, nParams);
assert(numel(tbl.ColumnName) == nParams, 'Untransposed ColumnName count mismatch');
untransposedData = tbl.Data;
untransposedColumnNames = tbl.ColumnName;

% Toggle on.
chk.Value = true;
chk.ValueChangedFcn(chk, []);

assert(isequal(size(tbl.Data), [nParams, nTrials]), ...
    'Transposed table size mismatch: got [%d %d], expected [%d %d]', ...
    size(tbl.Data, 1), size(tbl.Data, 2), nParams, nTrials);
assert(isequal(tbl.RowName, untransposedColumnNames), ...
    'Transposed RowName should equal the untransposed ColumnName');
assert(numel(tbl.ColumnName) == nTrials, 'Transposed ColumnName should have one entry per trial');
assert(isequal(tbl.Data, untransposedData.'), 'Transposed data should equal the transpose of the original data');

% Toggle back off.
chk.Value = false;
chk.ValueChangedFcn(chk, []);
assert(isequal(tbl.Data, untransposedData), 'Data should match the original after toggling back off');
assert(isequal(tbl.RowName, 'numbered'), 'RowName should reset to "numbered" after toggling back off');

fprintf('PASS: transpose checkbox toggles the compiled preview table correctly\n');
end

function value = localPeek_(pd, name)
warnState = warning('off', 'MATLAB:structOnObject');
restore = onCleanup(@() warning(warnState));
s = struct(pd);
value = s.(name);
end

function localForceClose_(pd)
if isvalid(pd)
    warnState = warning('off', 'MATLAB:structOnObject');
    s = struct(pd);
    warning(warnState);
    figs = {s.Figure, s.InterfaceFigure, s.OptionsFigure, s.PreviewFigure, s.CheckCalcFigure};
    for idx = 1:numel(figs)
        if ~isempty(figs{idx}) && isvalid(figs{idx})
            delete(figs{idx});
        end
    end
end
end
