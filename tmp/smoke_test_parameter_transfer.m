function smoke_test_parameter_transfer()
% smoke_test_parameter_transfer()
% Exercise the Protocol Designer's Copy or Move Parameters feature headlessly:
% the transfer plan (pure, no mutation), copies and moves between modules on
% one interface and across interfaces, name-conflict policies, the expression
% rewriting that keeps every reference naming the same parameter, refusal of a
% stale plan, compiling afterwards, and the dialog itself.
%
%   matlab -batch "run('tmp/smoke_test_parameter_transfer.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

% ===== A. Copy across interfaces; planning is pure =======================
designer = [];
try
    [designer, m] = localBuildDesigner_();
    paramsCount = numel(m.Params.Parameters);

    % Names must be unique across the protocol to compile, and the originals
    % keep theirs, so copies into another module are always renamed.
    plan = designer.planParameterTransfer([m.ToneLevel, m.Derived], m.RPA);
    assert(isequal({plan.Entries.Status}, {'copy', 'copy'}), 'statuses were %s', strjoin({plan.Entries.Status}, ','));
    assert(isequal({plan.Entries.NewName}, {'ToneLevel_1', 'Derived_1'}), 'names were %s', strjoin({plan.Entries.NewName}, ','));
    assert(strcmp(plan.Entries(2).NewExpression, 'ToneLevel_1 + 5'), ...
        'a sibling copied with its reader should follow it, got "%s"', plan.Entries(2).NewExpression);
    assert(strcmp(plan.Entries(1).HardwareName, 'ToneLevel'), 'a renamed hardware copy must keep its device tag');
    assert(isempty(plan.Rewrites), 'a copy must not rewrite other expressions');

    % Planning must not touch the protocol
    assert(isscalar(m.RPA.Parameters), 'planning added a parameter');
    assert(numel(m.Params.Parameters) == paramsCount, 'planning removed a parameter');

    transferred = designer.applyParameterTransfer(plan);
    assert(numel(transferred) == 2, 'expected 2 transferred, got %d', numel(transferred));
    assert(numel(m.RPA.Parameters) == 3, 'RPA should now hold 3 parameters');
    assert(numel(m.Params.Parameters) == paramsCount, 'a copy must leave the source module intact');
    copyLevel = localFind_(m.RPA, 'ToneLevel_1');
    assert(copyLevel ~= m.ToneLevel, 'a copy must be a new handle');
    assert(copyLevel.Parent == m.TDT, 'the copy must belong to the target interface');
    assert(copyLevel.Module == m.RPA, 'the copy must point at the target module');
    assert(copyLevel.Min == 0 && copyLevel.Max == 100 && isequal(copyLevel.Values, {60}), ...
        'the copy lost its metadata or values');
    assert(strcmp(hw.Interface.getHardwareParameterName(copyLevel), 'ToneLevel'), ...
        'the renamed copy writes tag %s', hw.Interface.getHardwareParameterName(copyLevel));
    assert(m.ToneLevel.Module == m.Params, 'the original moved');

    copyDerived = localFind_(m.RPA, 'Derived_1');
    assert(strcmp(char(copyDerived.Expression), 'ToneLevel_1 + 5'), 'copied expression was "%s"', char(copyDerived.Expression));
    assert(isequal(copyDerived.Values, {65}), 'copied expression did not evaluate in its new module');

    % Copied alone, its sibling reference is qualified back to the original
    plan = designer.planParameterTransfer(m.Derived, m.RPB);
    assert(strcmp(plan.Entries.NewExpression, 'Params.ToneLevel + 5'), ...
        'a lone copy should qualify its sibling, got "%s"', plan.Entries.NewExpression);

    fprintf('PASS: A. Copy across interfaces\n');
catch ME
    failures{end + 1} = sprintf('A. Copy across interfaces: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end
localCleanup_(designer);

% ===== B. Property references and roving notes ===========================
designer = [];
try
    [designer, m] = localBuildDesigner_();

    plan = designer.planParameterTransfer(m.Combo, m.Aux);
    assert(strcmp(plan.Entries.NewExpression, 'Params.ToneDur.Max - Params.MaskLevel'), ...
        'lone copy of a property reference became "%s"', plan.Entries.NewExpression);

    plan = designer.planParameterTransfer([m.Combo, m.ToneDur], m.Aux);
    assert(strcmp(plan.Entries(1).NewExpression, 'ToneDur_1.Max - Params.MaskLevel'), ...
        'grouped copy of a property reference became "%s"', plan.Entries(1).NewExpression);
    assert(all(cellfun(@isempty, {plan.Entries.HardwareName})), 'a Software target has no device tags');

    plan = designer.planParameterTransfer(m.Freq, m.Aux);
    assert(contains(plan.Entries.Message, 'Roves over 3 values'), ...
        'a roved unpaired copy should warn about the trial count, got "%s"', plan.Entries.Message);

    fprintf('PASS: B. Property references and roving notes\n');
catch ME
    failures{end + 1} = sprintf('B. Property references: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end
localCleanup_(designer);

% ===== C. Name conflicts ==================================================
designer = [];
try
    [designer, m] = localBuildDesigner_();
    existing = localFind_(m.RPA, 'MaskLevel');

    plan = designer.planParameterTransfer(m.MaskLevel, m.RPA, OnConflict = 'rename');
    assert(strcmp(plan.Entries.Status, 'copy') && strcmp(plan.Entries.NewName, 'MaskLevel_1'), ...
        'rename should give MaskLevel_1, got %s/%s', plan.Entries.Status, plan.Entries.NewName);

    plan = designer.planParameterTransfer(m.MaskLevel, m.RPA, OnConflict = 'skip');
    assert(strcmp(plan.Entries.Status, 'skip'), 'skip policy was not honoured');
    assert(isempty(designer.applyParameterTransfer(plan)), 'a skipped entry must not be applied');

    plan = designer.planParameterTransfer(m.MaskLevel, m.RPA, OnConflict = 'overwrite');
    assert(strcmp(plan.Entries.Status, 'overwrite') && plan.Entries.Existing == existing, ...
        'overwrite should target the existing parameter');
    designer.applyParameterTransfer(plan);
    assert(isscalar(m.RPA.Parameters), 'overwrite must not add a parameter');
    assert(m.RPA.Parameters(1) == existing, 'overwrite must keep the existing handle');
    assert(isequal(existing.Values, {40}), 'overwrite did not take the source values');

    % Copying into the parameter's own module
    plan = designer.planParameterTransfer(m.MaskLevel, m.Params);
    assert(strcmp(plan.Entries.NewName, 'MaskLevel_1'), 'a duplicate should be renamed');
    plan = designer.planParameterTransfer(m.MaskLevel, m.Params, OnConflict = 'overwrite');
    assert(strcmp(plan.Entries.Status, 'skip'), 'a parameter must not overwrite itself');

    % Two selected parameters claiming one name: a move frees both, and the
    % second is renamed apart from the first
    duplicate = m.RPB.add_parameter('ToneDur', 1);
    plan = designer.planParameterTransfer([m.ToneDur, duplicate], m.Aux, Mode = 'move');
    assert(isequal({plan.Entries.NewName}, {'ToneDur', 'ToneDur_1'}), ...
        'colliding selections should be renamed apart, got %s', strjoin({plan.Entries.NewName}, ','));

    fprintf('PASS: C. Name conflicts\n');
catch ME
    failures{end + 1} = sprintf('C. Name conflicts: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end
localCleanup_(designer);

% ===== D. Move within one interface keeps the handle ======================
designer = [];
try
    [designer, m] = localBuildDesigner_();

    plan = designer.planParameterTransfer(m.ToneDur, m.Aux, Mode = 'move');
    assert(strcmp(plan.Entries.Status, 'move'), 'expected a move');
    rewrites = containers.Map({plan.Rewrites.OldExpression}, {plan.Rewrites.NewExpression});
    assert(numel(plan.Rewrites) == 2, 'expected 2 rewrites, got %d', numel(plan.Rewrites));
    assert(strcmp(rewrites('ToneDur.Max - MaskLevel'), 'Aux.ToneDur.Max - MaskLevel'), ...
        'sibling property reference became "%s"', rewrites('ToneDur.Max - MaskLevel'));
    assert(strcmp(rewrites('Params.ToneDur * 2'), 'Aux.ToneDur * 2'), ...
        'qualified reference became "%s"', rewrites('Params.ToneDur * 2'));

    transferred = designer.applyParameterTransfer(plan);
    assert(transferred == m.ToneDur, 'a same-interface move must keep the handle');
    assert(m.ToneDur.Module == m.Aux, 'the moved parameter must point at its new module');
    assert(~any(m.Params.Parameters == m.ToneDur), 'the source module still holds the parameter');
    assert(any(m.Aux.Parameters == m.ToneDur), 'the target module does not hold the parameter');
    assert(isequal(m.Combo.Values, {460}), 'Combo no longer evaluates after the move');
    assert(isequal(m.AuxRef.Values, {50}), 'AuxRef no longer evaluates after the move');
    assert(isempty(designer.TableParams.UserData.ExpressionErrors), 'the move left expression errors');

    % Moving into the module a parameter is already in does nothing
    plan = designer.planParameterTransfer(m.ToneDur, m.Aux, Mode = 'move');
    assert(strcmp(plan.Entries.Status, 'skip'), 'a move into the same module should be skipped');

    fprintf('PASS: D. Move within one interface\n');
catch ME
    failures{end + 1} = sprintf('D. Move within one interface: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end
localCleanup_(designer);

% ===== E. Move across interfaces, renamed on conflict =====================
designer = [];
try
    [designer, m] = localBuildDesigner_();
    m.RPB.add_parameter('ToneDur', 1);

    plan = designer.planParameterTransfer([m.ToneDur, m.ToneLevel, m.Derived], m.RPB, Mode = 'move');
    assert(isequal({plan.Entries.NewName}, {'ToneDur_1', 'ToneLevel', 'Derived'}), ...
        'names were %s', strjoin({plan.Entries.NewName}, ','));
    designer.applyParameterTransfer(plan);

    assert(~any(m.Params.Parameters == m.ToneDur) && ~any(m.Params.Parameters == m.ToneLevel), ...
        'moved parameters are still in the source module');
    moved = localFind_(m.RPB, 'ToneDur_1');
    assert(~isempty(moved) && moved ~= m.ToneDur && moved.Parent == m.TDT, ...
        'a cross-interface move must build the parameter on the target interface');
    assert(moved.Min == 0 && moved.Max == 500, 'the moved parameter lost its bounds');
    assert(strcmp(hw.Interface.getHardwareParameterName(moved), 'ToneDur'), 'the renamed move lost its device tag');
    assert(contains(plan.Entries(1).Message, 'already addresses device tag ToneDur'), ...
        'two parameters writing one tag should be flagged, got "%s"', plan.Entries(1).Message);
    assert(strcmp(char(m.Combo.Expression), 'RPB.ToneDur_1.Max - MaskLevel'), ...
        'Combo became "%s"', char(m.Combo.Expression));
    assert(strcmp(char(m.AuxRef.Expression), 'RPB.ToneDur_1 * 2'), ...
        'AuxRef became "%s"', char(m.AuxRef.Expression));
    assert(strcmp(char(localFind_(m.RPB, 'Derived').Expression), 'ToneLevel + 5'), ...
        'Derived should still read its moved sibling bare');
    assert(isequal(m.Combo.Values, {460}) && isequal(m.AuxRef.Values, {50}), ...
        'repointed expressions no longer evaluate');
    assert(isempty(designer.TableParams.UserData.ExpressionErrors), 'the move left expression errors');

    fprintf('PASS: E. Move across interfaces\n');
catch ME
    failures{end + 1} = sprintf('E. Move across interfaces: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end
localCleanup_(designer);

% ===== F. A stale plan is refused, not half-applied =======================
designer = [];
try
    [designer, m] = localBuildDesigner_();

    plan = designer.planParameterTransfer([m.MaskLevel, m.ToneLevel], m.Aux, Mode = 'move');
    m.ToneLevel.Name = 'Renamed';
    threw = false;
    try
        designer.applyParameterTransfer(plan);
    catch ME
        threw = strcmp(ME.identifier, 'epsych:ProtocolDesigner:StalePlan');
    end
    assert(threw, 'a stale plan should throw epsych:ProtocolDesigner:StalePlan');
    assert(isempty(m.Aux.Parameters(arrayfun(@(p) strcmp(p.Name, 'MaskLevel'), m.Aux.Parameters))), ...
        'a stale plan was partly applied');
    assert(any(m.Params.Parameters == m.MaskLevel), 'a stale plan removed a source parameter');

    fprintf('PASS: F. Stale plan refused\n');
catch ME
    failures{end + 1} = sprintf('F. Stale plan: %s', ME.message);
    fprintf('FAIL: F. %s\n', ME.message);
end
localCleanup_(designer);

% ===== G. Compile after a transfer ========================================
designer = [];
try
    [designer, m] = localBuildDesigner_();
    % The fixture duplicates MaskLevel on purpose for the conflict tests, and
    % compile refuses duplicate names anywhere in the protocol.
    m.RPA.Parameters = hw.Parameter.empty(1, 0);
    designer.Protocol.compile();
    baseline = designer.Protocol.COMPILED.ntrials;

    copied = designer.applyParameterTransfer(designer.planParameterTransfer(m.Freq, m.Aux));
    assert(strcmp(copied.Name, 'Freq_1'), 'the copy should be renamed, got %s', copied.Name);
    assert(~isstruct(copied.UserData) || ~isfield(copied.UserData, 'HardwareName'), ...
        'a Software copy should carry no device tag');
    report = designer.Protocol.validate();
    assert(isempty(report) || ~any([report.severity] == 2), 'transfer left a fatal validation issue');
    designer.Protocol.compile();
    assert(designer.Protocol.COMPILED.ntrials == 3 * baseline, ...
        'an unpaired roved copy should triple the trials (%d -> %d)', baseline, designer.Protocol.COMPILED.ntrials);

    fprintf('PASS: G. Compile after transfer\n');
catch ME
    failures{end + 1} = sprintf('G. Compile after transfer: %s', ME.message);
    fprintf('FAIL: G. %s\n', ME.message);
end
localCleanup_(designer);

% ===== H. The dialog previews and applies =================================
designer = [];
try
    [designer, m] = localBuildDesigner_();

    % Seed from the selected table row
    row = find(cellfun(@(p) p == m.ToneDur, designer.ParameterHandles), 1);
    designer.onParamSelected(struct('Indices', [row 2]));
    designer.onCopyMoveParameters();
    dialog = designer.TransferFigure;
    assert(~isempty(dialog) && isvalid(dialog), 'dialog did not open');
    assert(isscalar(designer.TransferChecked) && designer.TransferChecked == m.ToneDur, ...
        'the selected row should be ticked');
    assert(contains(designer.TransferSource.Value, 'Params'), 'source should be the selected row''s module');

    designer.onCopyMoveParameters();
    assert(designer.TransferFigure == dialog, 'reopening should raise the existing dialog');

    % Aim at RPA and tick MaskLevel as well, through the table callback
    designer.TransferTarget.Value = designer.TransferTarget.Items{contains(designer.TransferTarget.Items, 'RPA')};
    designer.refreshTransferPreview();
    tbl = designer.TransferTable;
    maskRow = find(strcmp(tbl.Data(:, 2), 'MaskLevel'), 1);
    tbl.CellEditCallback(tbl, struct('Indices', [maskRow 1], 'NewData', true));
    plan = designer.TransferPlan;
    assert(numel(plan.Entries) == 2, 'expected 2 planned entries, got %d', numel(plan.Entries));
    assert(strcmp(tbl.Data{maskRow, 5}, 'MaskLevel_1'), 'preview should show the renamed copy');
    durRow = find(strcmp(tbl.Data(:, 2), 'ToneDur'), 1);
    assert(strcmp(tbl.Data{durRow, 5}, 'ToneDur_1'), 'preview should show the renamed copy');
    assert(strcmp(designer.TransferApply.Enable, 'on'), 'Apply should be enabled');

    designer.TransferMode.Value = 'move';
    designer.refreshTransferPreview();
    assert(strcmp(designer.TransferApply.Text, 'Move'), 'Apply should read Move');
    designer.TransferMode.Value = 'copy';
    designer.refreshTransferPreview();

    designer.TransferApply.ButtonPushedFcn(designer.TransferApply, []);
    assert(~isempty(localFind_(m.RPA, 'ToneDur_1')) && ~isempty(localFind_(m.RPA, 'MaskLevel_1')), ...
        'Apply did not copy the ticked parameters');
    assert(any(m.Params.Parameters == m.ToneDur), 'a copy from the dialog moved the original');

    % Apply closes the dialog and reports in the main window
    assert(isempty(designer.TransferFigure) || ~isvalid(designer.TransferFigure), ...
        'the dialog should close after Apply');
    statusText = designer.StatusBar.Label.Text;
    assert(contains(statusText, 'Copied 2 parameter(s)'), 'status should report the copy, got "%s"', statusText);

    % Removing the target module elsewhere must not retarget the dialog silently
    designer.onCopyMoveParameters();
    designer.TransferTarget.Value = designer.TransferTarget.Items{contains(designer.TransferTarget.Items, 'RPA')};
    designer.refreshTransferPreview();
    tdtModules = m.TDT.Module;
    m.TDT.setModules(tdtModules(tdtModules ~= m.RPA));
    designer.refreshParameterTab();
    assert(~contains(designer.TransferTarget.Value, 'RPA'), 'dialog still targets a removed module');

    fprintf('PASS: H. Dialog\n');
catch ME
    failures{end + 1} = sprintf('H. Dialog: %s', ME.message);
    fprintf('FAIL: H. %s\n', ME.message);
end
localCleanup_(designer);

% ===== I. Problems after a transfer are reported ==========================
designer = [];
try
    [designer, m] = localBuildDesigner_();
    broken = m.Params.add_parameter('Broken', 1);
    broken.Expression = "NoSuchThing + 1";
    designer.refreshParameterTab();

    [transferred, problems] = designer.applyParameterTransfer( ...
        designer.planParameterTransfer([m.ToneLevel, broken], m.Aux));
    assert(numel(transferred) == 2, 'both parameters should still be copied');
    assert(~isempty(problems) && all(contains(problems, 'Broken_1')), ...
        'the copy that cannot evaluate should be reported, got: %s', strjoin(problems, ' | '));

    [~, problems] = designer.applyParameterTransfer(designer.planParameterTransfer(m.MaskLevel, m.Aux));
    assert(isempty(problems), 'a clean copy should report no problems, got: %s', strjoin(problems, ' | '));

    fprintf('PASS: I. Problems reported\n');
catch ME
    failures{end + 1} = sprintf('I. Problems reported: %s', ME.message);
    fprintf('FAIL: I. %s\n', ME.message);
end
localCleanup_(designer);

% ===== Summary ===========================================================
if isempty(failures)
    fprintf('\nsmoke_test_parameter_transfer: ALL SECTIONS PASS\n');
else
    fprintf('\nsmoke_test_parameter_transfer: %d FAILURE(S)\n', numel(failures));
    error('smoke_test_parameter_transfer failed:\n  %s', strjoin(failures, sprintf('\n  ')));
end
end

function [designer, m] = localBuildDesigner_()
% A Software interface with modules Params and Aux, and an offline TDT_RPcox
% interface with modules RPA and RPB, wired with sibling, property, and
% cross-module expressions.
    protocol = epsych.Protocol();
    sw = protocol.Interfaces(1);
    m.Params = sw.Module;
    m.Aux = hw.Module(sw, 'Aux', 'Aux', uint8(2));
    sw.set_module([m.Params, m.Aux]);

    m.ToneLevel = m.Params.add_parameter('ToneLevel', 60, Min = 0, Max = 100);
    m.ToneDur = m.Params.add_parameter('ToneDur', 25, Min = 0, Max = 500);
    m.MaskLevel = m.Params.add_parameter('MaskLevel', 40);
    m.Derived = m.Params.add_parameter('Derived', 1);
    m.Derived.Expression = "ToneLevel + 5";
    m.Combo = m.Params.add_parameter('Combo', 1);
    m.Combo.Expression = "ToneDur.Max - MaskLevel";
    m.Freq = m.Params.add_parameter('Freq', [1000 2000 4000]);

    m.AuxGain = m.Aux.add_parameter('AuxGain', 3);
    m.AuxRef = m.Aux.add_parameter('AuxRef', 1);
    m.AuxRef.Expression = "Params.ToneDur * 2";

    m.TDT = hw.TDT_RPcox({}, {}, {}, Interface = 'GB', Connect = false);
    m.RPA = hw.Module(m.TDT, 'RP2', 'RPA', uint8(1));
    m.RPB = hw.Module(m.TDT, 'RX8', 'RPB', uint8(2));
    m.TDT.setModules([m.RPA, m.RPB]);
    protocol.addInterface(m.TDT);
    m.RPA.add_parameter('MaskLevel', 10);

    designer = epsych.ProtocolDesigner(protocol);
end

function parameter = localFind_(module, name)
    parameter = module.Parameters(arrayfun(@(p) strcmp(p.Name, name), module.Parameters));
end

function localCleanup_(designer)
    if isempty(designer) || ~isvalid(designer)
        return
    end
    if ~isempty(designer.TransferFigure) && isvalid(designer.TransferFigure)
        delete(designer.TransferFigure);
    end
    if ~isempty(designer.Figure) && isvalid(designer.Figure)
        delete(designer.Figure);
    end
end
