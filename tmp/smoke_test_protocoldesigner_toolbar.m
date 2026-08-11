function smoke_test_protocoldesigner_toolbar()
% smoke_test_protocoldesigner_toolbar()
% Gate on the ProtocolDesigner toolbar refactor: the main window builds with a
% toolbar and no interface panel, every toolbar action resolves to a real
% method, the Interfaces dialog builds and is reused rather than duplicated, and
% every refresh path survives the dialog being closed.
%
%   matlab -batch "run('tmp/smoke_test_protocoldesigner_toolbar.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};
outDir = fullfile(tempdir, 'epsych_smoke_pd_toolbar');
if ~isfolder(outDir), mkdir(outDir); end

pd = epsych.ProtocolDesigner();
cleanupPd = onCleanup(@() localForceClose_(pd));

% Reach the protected UI properties the same way the class does.
peek = @(name) localPeek_(pd, name);

%% 1. Toolbar exists and holds the expected buttons
toolbar = peek('ToolbarPanel');
if isempty(toolbar) || ~isvalid(toolbar)
    failures{end+1} = 'ToolbarPanel was not created';
else
    buttons = findobj(toolbar, 'Type', 'uibutton');
    labels = sort(reshape(string(arrayfun(@(b) string(b.Text), buttons)), 1, []));
    expected = sort(string({'New', 'Open...', 'Save', 'Interfaces...', 'Options...', ...
        'Compile', 'Preview...', 'Check Calcs...', 'Dependencies...', ...
        'Find/Replace...', 'Shortcuts'}));
    if ~isequal(labels, expected)
        failures{end+1} = sprintf('Toolbar buttons mismatch. Got: %s', strjoin(labels, ', '));
    end

    % Every button must be wired and every tooltip filled in.
    for idx = 1:numel(buttons)
        if isempty(buttons(idx).ButtonPushedFcn)
            failures{end+1} = sprintf('Toolbar button "%s" has no callback', buttons(idx).Text);
        end
        if strlength(string(buttons(idx).Tooltip)) == 0
            failures{end+1} = sprintf('Toolbar button "%s" has no tooltip', buttons(idx).Text);
        end
    end

    % Buttons must fit inside the strip and not overlap each other.
    xs = cell2mat(arrayfun(@(b) b.Position([1 3]), buttons, 'UniformOutput', false));
    [left, order] = sort(xs(:, 1));
    right = left + xs(order, 2);
    if any(right(1:end-1) > left(2:end))
        failures{end+1} = 'Toolbar buttons overlap';
    end
    if max(right) > toolbar.Position(3)
        failures{end+1} = sprintf('Toolbar buttons overflow the strip (%g > %g)', max(right), toolbar.Position(3));
    end
end

%% 2. Main window no longer carries the interface controls
if ~isempty(peek('InterfaceTree')) && isvalid(peek('InterfaceTree'))
    failures{end+1} = 'InterfaceTree exists before the Interfaces dialog was opened';
end
if ~isempty(peek('DropDownInterfaceType')) && isvalid(peek('DropDownInterfaceType'))
    failures{end+1} = 'DropDownInterfaceType exists before the Interfaces dialog was opened';
end

%% 3. Every refresh path runs with the dialogs closed
try
    pd.refreshUI();
catch ME
    failures{end+1} = sprintf('refreshUI with dialogs closed failed: %s', ME.message);
end
try
    pd.refreshParameterTab();
catch ME
    failures{end+1} = sprintf('refreshParameterTab with dialogs closed failed: %s', ME.message);
end

%% 4. Parameter table fills the widened panel
tbl = peek('TableParams');
panelWidth = tbl.Parent.Position(3);
if tbl.Position(1) + tbl.Position(3) > panelWidth - 10
    failures{end+1} = sprintf('Parameter table overflows its panel (%g > %g)', ...
        tbl.Position(1) + tbl.Position(3), panelWidth);
end
if tbl.Position(3) < 1200
    failures{end+1} = sprintf('Parameter table did not widen (width %g)', tbl.Position(3));
end
% Simple view must fill the widened table without overflowing it; Detailed view
% shows all 15 columns and is expected to scroll.
viewDropDown = peek('DropDownTableView');
restoreView = viewDropDown.Value;
viewDropDown.Value = 'Simple';
pd.refreshParameterTable();
simpleWidth = sum(cell2mat(tbl.ColumnWidth));
if simpleWidth < 1150 || simpleWidth > tbl.Position(3)
    failures{end+1} = sprintf('Simple column widths (%g) do not fill the table (%g)', simpleWidth, tbl.Position(3));
end
viewDropDown.Value = 'Detailed';
pd.refreshParameterTable();
if numel(tbl.ColumnWidth) ~= numel(tbl.ColumnName)
    failures{end+1} = 'Detailed column widths do not cover every column';
end
viewDropDown.Value = restoreView;
pd.refreshParameterTable();

%% 5. Interfaces dialog builds, and reopening reuses the same window
pd.onOpenInterfaceDialog();
dlg1 = peek('InterfaceFigure');
if isempty(dlg1) || ~isvalid(dlg1)
    failures{end+1} = 'Interfaces dialog was not created';
else
    tree = peek('InterfaceTree');
    if isempty(tree) || ~isvalid(tree)
        failures{end+1} = 'InterfaceTree missing after opening the dialog';
    elseif ~isequal(ancestor(tree, 'figure'), dlg1)
        failures{end+1} = 'InterfaceTree was not parented to the Interfaces dialog';
    end
    if isempty(peek('BtnModifyInterface')) || ~isvalid(peek('BtnModifyInterface'))
        failures{end+1} = 'BtnModifyInterface was left unassigned';
    end
    % Children must stay inside the dialog.
    for child = findobj(dlg1, '-property', 'Position')'
        if ~isa(child, 'matlab.ui.container.Panel') || ~isequal(child.Parent, dlg1)
            continue
        end
        if any(child.Position(1:2) < 0) || ...
                child.Position(1) + child.Position(3) > dlg1.Position(3) || ...
                child.Position(2) + child.Position(4) > dlg1.Position(4)
            failures{end+1} = sprintf('Dialog panel "%s" falls outside the dialog', child.Title);
        end
    end
end

pd.onOpenInterfaceDialog();
if ~isequal(peek('InterfaceFigure'), dlg1)
    failures{end+1} = 'Reopening the Interfaces dialog created a duplicate window';
end
if numel(findall(groot, 'Type', 'figure', 'Name', 'Interfaces')) ~= 1
    failures{end+1} = 'More than one Interfaces window is open';
end

%% 6. Closing the dialog leaves the designer usable
delete(dlg1);
try
    pd.refreshUI();
    pd.refreshParameterTab();
catch ME
    failures{end+1} = sprintf('refresh after closing the Interfaces dialog failed: %s', ME.message);
end

% Reopening rebuilds the controls.
pd.onOpenInterfaceDialog();
if isempty(peek('InterfaceTree')) || ~isvalid(peek('InterfaceTree'))
    failures{end+1} = 'Interfaces dialog did not rebuild its tree on reopen';
end

%% 6b. Parameter editing still works with the Interfaces dialog closed
delete(peek('InterfaceFigure'));
try
    rowsBefore = size(peek('TableParams').Data, 1);
    pd.onAddParamWithDefaults('float', false);
    if size(peek('TableParams').Data, 1) ~= rowsBefore + 1
        failures{end+1} = 'Adding a parameter with the Interfaces dialog closed did not add a row';
    end
    pd.onRemoveParam();
catch ME
    failures{end+1} = sprintf('parameter edit with the Interfaces dialog closed failed: %s', ME.message);
end

%% 7. Options dialog is likewise a singleton and stays in sync
pd.onOpenOptionsDialog();
optDlg = peek('OptionsFigure');
pd.onOpenOptionsDialog();
if ~isequal(peek('OptionsFigure'), optDlg)
    failures{end+1} = 'Reopening Protocol Options created a duplicate window';
end
if numel(findall(groot, 'Type', 'figure', 'Name', 'Protocol Options')) ~= 1
    failures{end+1} = 'More than one Protocol Options window is open';
end
if ~isequal(peek('EditTrialFunc').Value, pd_protocolTrialFunc_(pd))
    failures{end+1} = 'Options dialog did not sync trialFunc from the protocol';
end

%% 8. Keyboard shortcuts still dispatch (Ctrl+Shift+I opens Interfaces)
delete(peek('InterfaceFigure'));
pd.onFigureKeyPress(struct('Modifier', {{'control', 'shift'}}, 'Key', 'i'));
if isempty(peek('InterfaceFigure')) || ~isvalid(peek('InterfaceFigure'))
    failures{end+1} = 'Ctrl+Shift+I did not open the Interfaces dialog';
end

%% 9. Screenshots for visual review
try
    drawnow
    exportapp(localPeek_(pd, 'Figure'), fullfile(outDir, 'designer_main.png'));
    exportapp(peek('InterfaceFigure'), fullfile(outDir, 'designer_interfaces.png'));
    fprintf('Screenshots written to %s\n', outDir);
catch ME
    failures{end+1} = sprintf('screenshot export failed: %s', ME.message);
end

%% Report
fprintf('\n==== smoke_test_protocoldesigner_toolbar ====\n');
if isempty(failures)
    fprintf('PASS\n');
else
    fprintf('FAIL (%d)\n', numel(failures));
    for idx = 1:numel(failures)
        fprintf('  %d. %s\n', idx, failures{idx});
    end
end
end

function value = localPeek_(pd, name)
% Read a protected ProtocolDesigner property for assertions.
warnState = warning('off', 'MATLAB:structOnObject');
restore = onCleanup(@() warning(warnState));
s = struct(pd);
value = s.(name);
end

function value = pd_protocolTrialFunc_(pd)
warnState = warning('off', 'MATLAB:structOnObject');
restore = onCleanup(@() warning(warnState));
s = struct(pd);
value = s.Protocol.Options.trialFunc;
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
