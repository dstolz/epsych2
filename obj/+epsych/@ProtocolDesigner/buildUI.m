function buildUI(obj)
    % buildUI(obj)
    % Create the top-level figure, tabs, and persistent controls.
    % Call once during construction before refreshUI().
    obj.Figure = uifigure( ...
        'Name', 'Protocol Designer', ...
        'Position', [52 38 1380 920], ...
        'Color', [0.945 0.951 0.960]);

    fileMenu = uimenu(obj.Figure, 'Text', 'File');
    uimenu(fileMenu, 'Text', 'Edit Info...', 'MenuSelectedFcn', @(~, ~) obj.onEditInfo());
    uimenu(fileMenu, 'Text', 'Load Protocol...', 'MenuSelectedFcn', @(~, ~) obj.onLoad());
    uimenu(fileMenu, 'Text', 'Save Protocol...', 'MenuSelectedFcn', @(~, ~) obj.onSave());

    helpMenu = uimenu(obj.Figure, 'Text', 'Help');
    uimenu(helpMenu, 'Text', 'Open Documentation', 'MenuSelectedFcn', @(~, ~) obj.onOpenDocumentation());

    obj.LabelStatus = uilabel(obj.Figure, ...
        'Text', 'Ready', ...
        'Position', [20 18 1340 28], ...
        'FontWeight', 'bold', ...
        'FontColor', [0.97 0.98 0.99], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', [0.17 0.24 0.34]);

    obj.TabGroup = uitabgroup(obj.Figure, ...
        'Position', [20 56 1340 844], ...
        'SelectionChangedFcn', @(~, evt) obj.onTabSelectionChanged(evt));
    obj.ParametersTab = uitab(obj.TabGroup, 'Title', 'Parameters');
    obj.OptionsTab = uitab(obj.TabGroup, 'Title', 'Options');
    obj.PreviewTab = uitab(obj.TabGroup, 'Title', 'Compiled Preview');

    obj.buildParametersTab();
    obj.buildOptionsTab();
    obj.buildPreviewTab();
end

