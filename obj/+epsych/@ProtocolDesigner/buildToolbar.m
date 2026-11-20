function buildToolbar(obj)
% buildToolbar(obj)
% Build the window's icon toolbar.
% Call once from buildUI() after the menus.
%
% A uitoolbar of uipushtools rather than a strip of text buttons: it is the
% toolbar every desktop application has, it costs the parameter table no
% height, and it matches the session window (epsych.RunExpt) and the Subjects
% window. Glyphs come from gui.toolbarIcon, which draws them as pixel art, so
% the toolbox still ships no image files.
%
% Every tool fronts a menu item, and its tooltip is that item's name plus its
% shortcut, so the toolbar doubles as a reminder of the keys. Order follows the
% usual File | Edit | Build | Help grouping: file commands, the two
% configuration dialogs, the compile/inspect tools, Find and Replace, then help.
%
% Tags are 'pd_tb_<name>' so a test can find a tool without its handle.
    tb = uitoolbar(obj.Figure);
    obj.Toolbar = tb;

    obj.BtnNew = addTool_("new", 'New Protocol (Ctrl+N)', ...
        @() obj.onNew(), false);
    obj.BtnLoad = addTool_("load", 'Open Protocol... (Ctrl+O)', ...
        @() obj.onLoad(), false);
    obj.BtnSave = addTool_("save", 'Save Protocol (Ctrl+S)', ...
        @() obj.onSave(), false);
    obj.BtnSaveAs = addTool_("saveas", 'Save Protocol As... (Ctrl+Shift+S)', ...
        @() obj.onSaveAs(), false);

    obj.BtnOpenInterfaceDialog = addTool_("interfaces", 'Interfaces and Modules... (Ctrl+Shift+I)', ...
        @() obj.onOpenInterfaceDialog(), true);
    obj.BtnOpenOptionsDialog = addTool_("gear", 'Protocol Options... (Ctrl+Shift+O)', ...
        @() obj.onOpenOptionsDialog(), false);

    obj.BtnToolbarCompile = addTool_("compile", 'Compile Protocol (Ctrl+Shift+C)', ...
        @() obj.onCompile(), true);
    obj.BtnOpenPreviewDialog = addTool_("preview", 'Preview Compiled Trials... (Ctrl+Shift+V)', ...
        @() obj.onOpenCompiledPreviewDialog(), false);
    obj.BtnOpenCheckCalcDialog = addTool_("checkcalc", 'Check Calculations... (Ctrl+Shift+K)', ...
        @() obj.onOpenCheckCalculationsDialog(), false);
    obj.BtnShowDependencies = addTool_("dependencies", 'Plot Parameter Dependencies... (Ctrl+Shift+G)', ...
        @() obj.onShowParameterDependencyGraph(), false);

    obj.BtnFindReplace = addTool_("findreplace", 'Find and Replace in Names... (Ctrl+H)', ...
        @() obj.onFindReplaceParameterNames(), true);

    obj.BtnShortcuts = addTool_("keyboard", 'Keyboard Shortcuts (Ctrl+Shift+?)', ...
        @() obj.showKeyboardShortcuts(), true);
    obj.BtnUserGuide = addTool_("wiki", 'Open User Guide', ...
        @() obj.onOpenDocumentation('user'), false);

    function tool = addTool_(icon, tooltip, callback, separator)
    % Append one push tool; separator starts a new group.
        tool = uipushtool(tb, ...
            'Tag', ['pd_tb_' char(icon)], ...
            'Icon', gui.toolbarIcon(icon), ...
            'Tooltip', tooltip, ...
            'Separator', matlab.lang.OnOffSwitchState(separator), ...
            'ClickedCallback', @(~, ~) callback());
    end
end
