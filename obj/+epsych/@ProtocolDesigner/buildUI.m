function buildUI(obj)
    % buildUI(obj)
    % Create the top-level figure and persistent controls.
    % Call once during construction before refreshUI().
    obj.Figure = uifigure( ...
        'Name', 'Protocol Designer', ...
        'Position', [52 38 1380 920], ...
        'Color', [0.945 0.951 0.960], ...
        'CloseRequestFcn', @(~, ~) obj.onCloseRequest(), ...
        'WindowKeyPressFcn', @(~, evt) obj.onFigureKeyPress(evt));

    obj.FileMenu = uimenu(obj.Figure, 'Text', 'File');
    uimenu(obj.FileMenu, 'Text', 'New Protocol',          'Accelerator', 'N', 'MenuSelectedFcn', @(~, ~) obj.onNew());
    uimenu(obj.FileMenu, 'Text', 'Edit Info...',           'Accelerator', 'I', 'Separator', 'on', 'MenuSelectedFcn', @(~, ~) obj.onEditInfo());
    uimenu(obj.FileMenu, 'Text', 'Load Protocol...',       'Accelerator', 'O', 'MenuSelectedFcn', @(~, ~) obj.onLoad());
    uimenu(obj.FileMenu, 'Text', 'Save Protocol...',       'Accelerator', 'S', 'MenuSelectedFcn', @(~, ~) obj.onSave());
    uimenu(obj.FileMenu, 'Text', localShortcutText_('Save Protocol As...', 'Ctrl+Shift+S'), 'MenuSelectedFcn', @(~, ~) obj.onSaveAs());
    uimenu(obj.FileMenu, 'Text', 'Version History...',     'MenuSelectedFcn', @(~, ~) obj.onVersionHistory());
    uimenu(obj.FileMenu, 'Text', 'Open as JSON in Editor', 'Accelerator', 'J', 'Separator', 'on', 'MenuSelectedFcn', @(~, ~) obj.onOpenAsJSON());
    uimenu(obj.FileMenu, 'Text', 'Export Current Protocol to Workspace', 'Separator', 'on', 'MenuSelectedFcn', @(~, ~) obj.onExportProtocolToWorkspace());
    obj.RecentProtocolsMenu = uimenu(obj.FileMenu, 'Text', 'Recent Protocols', 'Separator', 'on');
    obj.refreshRecentProtocolMenu();

    parameterMenu = uimenu(obj.Figure, 'Text', 'Parameter');
    typeMenu = uimenu(parameterMenu, 'Text', 'Change Selected Type');
    uimenu(typeMenu, 'Text', localShortcutText_('Float', 'Ctrl+1'), 'MenuSelectedFcn', @(~, ~) obj.onChangeSelectedParameterType('Float'));
    uimenu(typeMenu, 'Text', localShortcutText_('Integer', 'Ctrl+2'), 'MenuSelectedFcn', @(~, ~) obj.onChangeSelectedParameterType('Integer'));
    uimenu(typeMenu, 'Text', localShortcutText_('Boolean', 'Ctrl+3'), 'MenuSelectedFcn', @(~, ~) obj.onChangeSelectedParameterType('Boolean'));
    uimenu(typeMenu, 'Text', localShortcutText_('Buffer', 'Ctrl+4'), 'MenuSelectedFcn', @(~, ~) obj.onChangeSelectedParameterType('Buffer'));
    uimenu(typeMenu, 'Text', localShortcutText_('Coefficient Buffer', 'Ctrl+5'), 'MenuSelectedFcn', @(~, ~) obj.onChangeSelectedParameterType('Coefficient Buffer'));
    uimenu(typeMenu, 'Text', localShortcutText_('String', 'Ctrl+6'), 'MenuSelectedFcn', @(~, ~) obj.onChangeSelectedParameterType('String'));
    uimenu(typeMenu, 'Text', localShortcutText_('File', 'Ctrl+7'), 'MenuSelectedFcn', @(~, ~) obj.onChangeSelectedParameterType('File'));
    uimenu(typeMenu, 'Text', localShortcutText_('StimType', 'Ctrl+8'), 'MenuSelectedFcn', @(~, ~) obj.onChangeSelectedParameterType('StimType'));
    uimenu(typeMenu, 'Text', localShortcutText_('Undefined', 'Ctrl+9'), 'MenuSelectedFcn', @(~, ~) obj.onChangeSelectedParameterType('Undefined'));

    uimenu(parameterMenu, 'Text', localShortcutText_('Add Boolean Parameter', 'Ctrl+Shift+B'), 'Separator', 'on', 'MenuSelectedFcn', @(~, ~) obj.onAddParamWithDefaults('boolean', false));
    uimenu(parameterMenu, 'Text', localShortcutText_('Add Trigger Boolean Parameter', 'Ctrl+Shift+T'), 'MenuSelectedFcn', @(~, ~) obj.onAddParamWithDefaults('boolean', true));
    uimenu(parameterMenu, 'Text', localShortcutText_('Add Float Parameter', 'Ctrl+Shift+F'), 'MenuSelectedFcn', @(~, ~) obj.onAddParamWithDefaults('float', false));
    uimenu(parameterMenu, 'Text', localShortcutText_('Add Integer Parameter', 'Ctrl+Shift+N'), 'MenuSelectedFcn', @(~, ~) obj.onAddParamWithDefaults('integer', false));
    uimenu(parameterMenu, 'Text', localShortcutText_('Remove Selected Parameter', 'Ctrl+Shift+R'), 'Separator', 'on', 'MenuSelectedFcn', @(~, ~) obj.onRemoveParam());
    uimenu(parameterMenu, 'Text', localShortcutText_('Show Selected Parameter Details', 'Ctrl+Shift+D'), 'MenuSelectedFcn', @(~, ~) obj.onShowSelectedParameterDetails());
    uimenu(parameterMenu, 'Text', localShortcutText_('Find Parameter by Name', 'Ctrl+F'), 'Separator', 'on', 'MenuSelectedFcn', @(~, ~) obj.focusParameterFind());
    uimenu(parameterMenu, 'Text', localShortcutText_('Find and Replace in Names...', 'Ctrl+H'), 'MenuSelectedFcn', @(~, ~) obj.onFindReplaceParameterNames());

    interfaceMenu = uimenu(obj.Figure, 'Text', 'Interface');
    uimenu(interfaceMenu, 'Text', localShortcutText_('Interfaces and Modules...', 'Ctrl+Shift+I'), 'MenuSelectedFcn', @(~, ~) obj.onOpenInterfaceDialog());
    uimenu(interfaceMenu, 'Text', localShortcutText_('Add Interface', 'Ctrl+Shift+A'), 'Separator', 'on', 'MenuSelectedFcn', @(~, ~) obj.onAddInterface());
    uimenu(interfaceMenu, 'Text', localShortcutText_('Add Module', 'Ctrl+Shift+M'), 'MenuSelectedFcn', @(~, ~) obj.onAddModule());

    protocolMenu = uimenu(obj.Figure, 'Text', 'Protocol');
    uimenu(protocolMenu, 'Text', localShortcutText_('Compile Protocol', 'Ctrl+Shift+C'), 'MenuSelectedFcn', @(~, ~) obj.onCompile());
    uimenu(protocolMenu, 'Text', localShortcutText_('Open Compiled Preview Dialog', 'Ctrl+Shift+V'), 'MenuSelectedFcn', @(~, ~) obj.onOpenCompiledPreviewDialog());
    uimenu(protocolMenu, 'Text', localShortcutText_('Check Calculations...', 'Ctrl+Shift+K'), 'MenuSelectedFcn', @(~, ~) obj.onOpenCheckCalculationsDialog());
    uimenu(protocolMenu, 'Text', localShortcutText_('Plot Parameter Dependencies...', 'Ctrl+Shift+G'), 'MenuSelectedFcn', @(~, ~) obj.onShowParameterDependencyGraph());
    uimenu(protocolMenu, 'Text', localShortcutText_('Open Options Dialog', 'Ctrl+Shift+O'), 'MenuSelectedFcn', @(~, ~) obj.onOpenOptionsDialog());

    viewMenu = uimenu(obj.Figure, 'Text', 'View');
    uimenu(viewMenu, 'Text', localShortcutText_('Cycle Color By', 'Ctrl+Shift+Y'), 'MenuSelectedFcn', @(~, ~) obj.onCycleColorBy());
    uimenu(viewMenu, 'Text', localShortcutText_('Toggle Parameter Table View', 'Ctrl+Shift+L'), 'MenuSelectedFcn', @(~, ~) obj.onToggleTableView());

    helpMenu = uimenu(obj.Figure, 'Text', 'Help');
    uimenu(helpMenu, 'Text', localShortcutText_('Keyboard Shortcuts', 'Ctrl+Shift+?'), 'MenuSelectedFcn', @(~, ~) obj.showKeyboardShortcuts());
    uimenu(helpMenu, 'Text', 'Open User Guide', 'MenuSelectedFcn', @(~, ~) obj.onOpenDocumentation('user'));
    uimenu(helpMenu, 'Text', 'Open Developer Documentation', 'MenuSelectedFcn', @(~, ~) obj.onOpenDocumentation('developer'));

    obj.StatusBar = gui.components.StatusBar(obj.Figure, ...
        'Position',    [20 14 1340 34], ...
        'InitialText', 'Loading Protocol Designer...');

    obj.buildToolbar();

    obj.MainPanel = uipanel(obj.Figure, ...
        'Position', [20 56 1340 794], ...
        'BackgroundColor', [0.972 0.978 0.986], ...
        'BorderType', 'none');

    obj.buildParametersTab();
end

function menuText = localShortcutText_(label, shortcut)
% localShortcutText_(label, shortcut)
% Append shortcut text to a menu label for commands without Accelerator support.
    menuText = sprintf('%s (%s)', label, shortcut);
end

