function smoke_test_designer_interface_removal()
% smoke_test_designer_interface_removal()
% Gate on Protocol Designer state after an interface is removed.
%
% Interface labels lead with their position ('3: TDT_RPcox'), so removing an
% earlier interface renames every later one. Everything that remembers an
% interface by label - the Filter dropdown, the Add To Interface / Module
% dropdowns, the interface tree selection - has to follow the interface it was
% showing to its new position, or fall back to something valid when that
% interface is the one that went. Before the fix the dropdowns silently snapped
% to the first interface ("Add Parameter" then landed in the wrong module), the
% Filter and Color By disagreed, the selection kept pointing at the removed
% slot, an open Find and Replace dialog still planned renames for parameters
% that were gone, and a refused removal still reported "Removed interface".
%
%   matlab -batch "run('tmp/smoke_test_designer_interface_removal.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

% questdlg would block a headless run. The stub confirms (answers with the
% first button) unless the test has put another answer in appdata.
stubDir = tempname;
mkdir(stubDir);
fid = fopen(fullfile(stubDir, 'questdlg.m'), 'w');
fprintf(fid, ['function answer = questdlg(varargin)\n' ...
    'answer = getappdata(0, ''SmokeQuestdlgAnswer'');\n' ...
    'if isempty(answer)\n    answer = varargin{3};\nend\nend\n']);
fclose(fid);
warnState = warning('off', 'all');
addpath(stubDir, '-begin');
warning(warnState);
cleanupStub = onCleanup(@() localRemoveStub_(stubDir));

failures = {};

% ===== A. A surviving interface keeps its filter and target ===============
pd = localFixture_();
cleanupPd = onCleanup(@() localForceClose_(pd));
try
    pd.onOpenInterfaceDialog();
    % Clicking a tree node also points Filter and Target at it, so choose
    % RPcox in both AFTER selecting Synapse, the interface to be removed.
    localSelectTree_(pd, 2, 0);
    localSetFilter_(pd, '3: TDT_RPcox');
    localSetTarget_(pd, '3: TDT_RPcox');
    pd.onRemoveInterface();

    assert(isequal(localTypes_(pd), {'Software', 'TDT_RPcox'}), 'Synapse should be gone');
    assert(strcmp(pd.DropDownInterfaceFilter.Value, '2: TDT_RPcox'), ...
        'Filter should follow RPcox to its new position, got "%s"', pd.DropDownInterfaceFilter.Value);
    assert(isequal(pd.DropDownInterfaceFilter.Items, {'All Interfaces', '1: Software', '2: TDT_RPcox'}), ...
        'Filter items are stale: %s', strjoin(pd.DropDownInterfaceFilter.Items, ' | '));
    assert(strcmp(pd.DropDownTargetInterface.Value, '2: TDT_RPcox'), ...
        'Add To Interface should follow RPcox, got "%s"', pd.DropDownTargetInterface.Value);
    assert(strcmp(pd.DropDownTargetModule.Value, '1: RPMod'), ...
        'Module should list RPcox''s module, got "%s"', pd.DropDownTargetModule.Value);
    assert(strcmp(pd.DropDownColorBy.Value, 'Type'), ...
        'Color By should stay with the filter, got "%s"', pd.DropDownColorBy.Value);
    rows = pd.TableParams.Data(:, 1);
    assert(numel(rows) == 1 && startsWith(rows{1}, '2: TDT_RPcox > '), ...
        'Table should show only RPcox rows, got: %s', strjoin(rows, ' | '));
    assert(numel(pd.ParameterHandles) == size(pd.TableParams.Data, 1), 'ParameterHandles out of step with the table');
    assert(pd.SelectedInterfaceRow == 2, 'selection should land on the interface that took the slot, got %d', pd.SelectedInterfaceRow);
    assert(localModuleRow_(pd) == 0, 'module selection should clear');
    assert(contains(pd.StatusBar.Label.Text, 'Removed interface TDT_Synapse'), ...
        'status: %s', pd.StatusBar.Label.Text);
    fprintf('PASS: A. filter / target / module follow a surviving interface\n');
catch ME
    failures{end+1} = sprintf('A. surviving interface: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end
localForceClose_(pd);

% ===== B. Filter and target on the removed interface fall back ============
pd = localFixture_();
cleanupPd = onCleanup(@() localForceClose_(pd));
try
    pd.onOpenInterfaceDialog();
    localSelectTree_(pd, 2, 1);                       % its module, so the row must clear too
    assert(strcmp(pd.DropDownInterfaceFilter.Value, '2: TDT_Synapse') ...
        && strcmp(pd.DropDownTargetInterface.Value, '2: TDT_Synapse'), ...
        'fixture: a tree click should focus Filter and Target on the interface');
    pd.onRemoveInterface();

    assert(strcmp(pd.DropDownInterfaceFilter.Value, 'All Interfaces'), ...
        'Filter on the removed interface should widen to All, got "%s"', pd.DropDownInterfaceFilter.Value);
    assert(strcmp(pd.DropDownColorBy.Value, 'Interface'), ...
        'Color By should follow the filter back to Interface, got "%s"', pd.DropDownColorBy.Value);
    rows = pd.TableParams.Data(:, 1);
    assert(numel(rows) == 2, 'Software and RPcox rows expected, got %d', numel(rows));
    assert(any(startsWith(rows, '2: TDT_RPcox')), 'RPcox rows should carry the new index');
    assert(strcmp(pd.DropDownTargetInterface.Value, '2: TDT_RPcox'), ...
        'Add To Interface should land on the interface now selected, got "%s"', pd.DropDownTargetInterface.Value);
    assert(strcmp(pd.DropDownTargetModule.Value, '1: RPMod'), ...
        'Module dropdown still describes the removed interface: "%s"', pd.DropDownTargetModule.Value);
    assert(pd.SelectedInterfaceRow == 2, 'selection should be 2, got %d', pd.SelectedInterfaceRow);
    assert(localModuleRow_(pd) == 0, 'stale module row %d survived the removal', localModuleRow_(pd));
    fprintf('PASS: B. filter / target fall back when their interface is removed\n');
catch ME
    failures{end+1} = sprintf('B. removed interface: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end
localForceClose_(pd);

% ===== C. Removing the last interface ======================================
pd = localFixture_();
cleanupPd = onCleanup(@() localForceClose_(pd));
try
    pd.onOpenInterfaceDialog();
    localSelectTree_(pd, 3, 1);
    localSetFilter_(pd, '3: TDT_RPcox');
    localSetTarget_(pd, '3: TDT_RPcox');
    pd.onRemoveInterface();

    assert(isequal(localTypes_(pd), {'Software', 'TDT_Synapse'}), 'RPcox should be gone');
    assert(pd.SelectedInterfaceRow == 2, 'selection should clamp to the new last interface, got %d', pd.SelectedInterfaceRow);
    assert(localModuleRow_(pd) == 0, 'module row should clear');
    assert(strcmp(pd.DropDownInterfaceFilter.Value, 'All Interfaces'), 'filter should widen');
    assert(strcmp(pd.DropDownTargetInterface.Value, '2: TDT_Synapse'), ...
        'target should be the last remaining interface, got "%s"', pd.DropDownTargetInterface.Value);
    assert(strcmp(pd.DropDownTargetModule.Value, '1: SynMod'), 'module got "%s"', pd.DropDownTargetModule.Value);
    assert(strcmp(pd.BtnRemoveModule.Enable, 'off'), 'Remove Module must be off with no module selected');

    % The Interfaces dialog: tree rebuilt, selection agrees, type addable again.
    tree = pd.InterfaceTree;
    assert(numel(tree.Children) == 2, 'tree should list 2 interfaces, lists %d', numel(tree.Children));
    assert(~any(contains({tree.Children.Text}, 'TDT_RPcox')), 'tree still lists the removed interface');
    assert(~isempty(tree.SelectedNodes), 'tree lost its selection');
    assert(tree.SelectedNodes(1).NodeData.interfaceIndex == pd.SelectedInterfaceRow, ...
        'tree highlights interface %d but the designer selected %d', ...
        tree.SelectedNodes(1).NodeData.interfaceIndex, pd.SelectedInterfaceRow);
    rpLabel = hw.TDT_RPcox.getCreationSpec().label;
    assert(any(strcmp(pd.DropDownInterfaceType.Items, rpLabel)), ...
        'the removed type should be addable again: %s', strjoin(pd.DropDownInterfaceType.Items, ' | '));
    fprintf('PASS: C. removing the last interface clamps selection, tree, and add list\n');
catch ME
    failures{end+1} = sprintf('C. last interface: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end
localForceClose_(pd);

% ===== D. An open Find and Replace dialog stops planning for removed rows ==
pd = localFixture_();
cleanupPd = onCleanup(@() localForceClose_(pd));
try
    pd.onOpenInterfaceDialog();
    pd.onFindReplaceParameterNames();
    pd.FindReplaceFind.Value = 'Param';
    pd.FindReplaceWith.Value = 'Prm';
    pd.refreshFindReplacePreview();
    assert(numel(pd.FindReplaceChanges) == 3, 'fixture: expected 3 planned renames, got %d', numel(pd.FindReplaceChanges));

    localSelectTree_(pd, 2, 0);
    pd.onRemoveInterface();

    names = arrayfun(@(c) char(c.Parameter.Name), pd.FindReplaceChanges, 'UniformOutput', false);
    assert(numel(names) == 2 && ~any(strcmp(names, 'SynParam')), ...
        'Find and Replace still plans for the removed interface: %s', strjoin(names, ', '));
    delete(pd.FindReplaceFigure);
    fprintf('PASS: D. Find and Replace preview drops the removed interface\n');
catch ME
    failures{end+1} = sprintf('D. find and replace: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end
localForceClose_(pd);

% ===== E. A refused removal says so and changes nothing ====================
pd = epsych.ProtocolDesigner(epsych.Protocol);
cleanupPd = onCleanup(@() localForceClose_(pd));
try
    pd.onOpenInterfaceDialog();
    localSelectTree_(pd, 1, 0);
    pd.onRemoveInterface();
    assert(isscalar(pd.Protocol.Interfaces), 'the only interface must stay');
    assert(~contains(pd.StatusBar.Label.Text, 'Removed interface'), ...
        'status claims a removal that did not happen: %s', pd.StatusBar.Label.Text);
    assert(contains(lower(pd.StatusBar.Label.Text), 'only interface'), ...
        'status should explain the refusal: %s', pd.StatusBar.Label.Text);
    fprintf('PASS: E. removing the only interface is reported as refused\n');
catch ME
    failures{end+1} = sprintf('E. only interface: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end
localForceClose_(pd);

% ===== F. Removing Software resets it and says so ==========================
pd = localFixture_();
cleanupPd = onCleanup(@() localForceClose_(pd));
try
    pd.onOpenInterfaceDialog();
    localSelectTree_(pd, 1, 0);
    pd.onRemoveInterface();
    assert(isequal(localTypes_(pd), {'Software', 'TDT_Synapse', 'TDT_RPcox'}), ...
        'a protocol always keeps one Software interface: %s', strjoin(localTypes_(pd), ', '));
    names = cellfun(@(h) char(h.Name), pd.ParameterHandles, 'UniformOutput', false);
    assert(~any(strcmp(names, 'SwParam')), 'the old Software parameters should be gone');
    assert(~contains(pd.StatusBar.Label.Text, 'Removed interface'), ...
        'status should not claim a removal: %s', pd.StatusBar.Label.Text);
    assert(contains(pd.StatusBar.Label.Text, 'Reset'), 'status should say reset: %s', pd.StatusBar.Label.Text);
    fprintf('PASS: F. removing Software resets it and reports the reset\n');
catch ME
    failures{end+1} = sprintf('F. software reset: %s', ME.message);
    fprintf('FAIL: F. %s\n', ME.message);
end
localForceClose_(pd);

% ===== G. Cancelling the confirmation changes nothing =====================
pd = localFixture_();
cleanupPd = onCleanup(@() localForceClose_(pd));
try
    pd.onOpenInterfaceDialog();
    localSelectTree_(pd, 2, 0);
    localSetFilter_(pd, '3: TDT_RPcox');
    localSetTarget_(pd, '3: TDT_RPcox');
    setappdata(0, 'SmokeQuestdlgAnswer', 'Cancel');
    pd.onRemoveInterface();
    rmappdata(0, 'SmokeQuestdlgAnswer');

    assert(isequal(localTypes_(pd), {'Software', 'TDT_Synapse', 'TDT_RPcox'}), 'nothing should be removed');
    assert(strcmp(pd.DropDownInterfaceFilter.Value, '3: TDT_RPcox'), 'filter moved: %s', pd.DropDownInterfaceFilter.Value);
    assert(strcmp(pd.DropDownTargetInterface.Value, '3: TDT_RPcox'), 'target moved: %s', pd.DropDownTargetInterface.Value);
    assert(pd.SelectedInterfaceRow == 2, 'selection moved: %d', pd.SelectedInterfaceRow);
    fprintf('PASS: G. cancelling the confirmation leaves the designer alone\n');
catch ME
    failures{end+1} = sprintf('G. cancel: %s', ME.message);
    fprintf('FAIL: G. %s\n', ME.message);
end
if isappdata(0, 'SmokeQuestdlgAnswer')
    rmappdata(0, 'SmokeQuestdlgAnswer');
end
localForceClose_(pd);

% ===== Summary ============================================================
if isempty(failures)
    fprintf('\nALL PASS: designer interface removal\n');
else
    fprintf('\n%d FAILURE(S):\n', numel(failures));
    fprintf('  %s\n', failures{:});
    error('smoke:designerInterfaceRemoval', 'smoke test failed');
end

end


function pd = localFixture_()
% Software(1) + TDT_Synapse(2) + TDT_RPcox(3), each with one module and one
% parameter, none connected.
P = epsych.Protocol;
P.addParameter('Software', 'SwParam', 1);
syn = hw.TDT_Synapse('localhost', Connect = false);
P.addInterface(syn);
rp = hw.TDT_RPcox({}, {}, {}, Interface = 'GB', Connect = false);
P.addInterface(rp);
synModule = hw.Module(syn, 'SynMod', 'SynMod', uint8(1));
syn.setModules(synModule);
synModule.add_parameter('SynParam', 1, Type = 'Float', Access = 'Read / Write');
rpModule = hw.Module(rp, 'RPMod', 'RPMod', uint8(1));
rp.setModules(rpModule);
rpModule.add_parameter('RPParam', 1, Type = 'Float', Access = 'Read / Write');
pd = epsych.ProtocolDesigner(P);
end


function localSetFilter_(pd, label)
pd.DropDownInterfaceFilter.Value = label;
pd.onInterfaceFilterChanged();
end


function localSetTarget_(pd, label)
pd.DropDownTargetInterface.Value = label;
pd.onTargetInterfaceChanged();
end


function localSelectTree_(pd, interfaceIdx, moduleIdx)
% Select a node the way a click does: set the selection, then run the callback.
node = pd.InterfaceTree.Children(interfaceIdx);
if moduleIdx >= 1
    node = node.Children(3 + moduleIdx);              % three info rows precede the modules
end
pd.InterfaceTree.SelectedNodes = node;
pd.onInterfaceRegistrySelected(struct('SelectedNodes', node));
end


function types = localTypes_(pd)
types = arrayfun(@(i) char(string(i.Type)), pd.Protocol.Interfaces, 'UniformOutput', false);
end


function row = localModuleRow_(pd)
row = 0;
ud = pd.Figure.UserData;
if isstruct(ud) && isfield(ud, 'SelectedModuleRow') && ~isempty(ud.SelectedModuleRow)
    row = ud.SelectedModuleRow;
end
end


function localRemoveStub_(stubDir)
rmpath(stubDir);
if isappdata(0, 'SmokeQuestdlgAnswer')
    rmappdata(0, 'SmokeQuestdlgAnswer');
end
if isfolder(stubDir)
    rmdir(stubDir, 's');
end
end


function localForceClose_(pd)
if isvalid(pd)
    warnState = warning('off', 'MATLAB:structOnObject');
    s = struct(pd);
    warning(warnState);
    figs = {s.Figure, s.InterfaceFigure, s.OptionsFigure, s.PreviewFigure, s.CheckCalcFigure, s.FindReplaceFigure};
    for idx = 1:numel(figs)
        if ~isempty(figs{idx}) && isvalid(figs{idx})
            delete(figs{idx});
        end
    end
end
end
