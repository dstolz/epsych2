classdef ProtocolDesigner < handle
    % epsych.ProtocolDesigner(protocol)
    % Edit epsych.Protocol objects from a dedicated UI for interfaces,
    % parameters, protocol options, and compiled trial preview data.
    %
    % Important properties:
    % 	Protocol		- Protocol instance currently bound to the designer.
    % 	TableParams	- Parameter table for interface and module settings.
    % 	TableCompiled	- Trial preview table populated after compilation.
    %
    % Key methods:
    % 	refreshUI	- Reload visible controls from the bound protocol.
    % 	onCompile	- Compile the current protocol and refresh preview data.
    % 	onSave		- Save the bound protocol to an .eprot file.
    % 	onLoad		- Load a protocol from disk and rebuild the UI state.
    %
    % See also documentation/design/ProtocolDesigner.md.
    %
    % Example:
    % 	gui = epsych.ProtocolDesigner();
    % 	gui = epsych.ProtocolDesigner(protocolObj);

    properties (Hidden, SetAccess = protected)
        Figure matlab.ui.Figure
        Protocol (1,1) epsych.Protocol
        CurrentProtocolPath (1,:) char = ''

        MainPanel matlab.ui.container.Panel
        FileMenu matlab.ui.container.Menu
        RecentProtocolsMenu matlab.ui.container.Menu

        EditInfo matlab.ui.control.EditField
        BtnSave matlab.ui.control.Button
        BtnLoad matlab.ui.control.Button
        StatusBar gui.StatusBar  % Footer status-label component.

        DropDownInterfaceType matlab.ui.control.DropDown
        LabelInterfaceDescription matlab.ui.control.Label
        DropDownInterfaceFilter matlab.ui.control.DropDown
        DropDownColorBy matlab.ui.control.DropDown
        DropDownTargetInterface matlab.ui.control.DropDown
        DropDownTargetModule matlab.ui.control.DropDown
        DropDownTableView matlab.ui.control.DropDown
        BtnAddInterface matlab.ui.control.Button
        BtnAddModule matlab.ui.control.Button
        BtnRemoveInterface matlab.ui.control.Button
        BtnRemoveModule matlab.ui.control.Button
        BtnModifyInterface matlab.ui.control.Button
        BtnOpenOptionsDialog matlab.ui.control.Button
        BtnOpenPreviewDialog matlab.ui.control.Button
        InterfaceTree matlab.ui.container.Tree
        TableParams matlab.ui.control.Table
        BtnAddParam matlab.ui.control.Button
        BtnRemoveParam matlab.ui.control.Button
        BtnRefreshParams matlab.ui.control.Button
        BtnReadHWParams matlab.ui.control.Button
        EditFindParam matlab.ui.control.EditField
        ParamNameFilter (1,:) char = ''  % Find box text narrowing the parameter table

        FindReplaceFigure matlab.ui.Figure
        FindReplaceFind matlab.ui.control.EditField
        FindReplaceWith matlab.ui.control.EditField
        FindReplaceMatchCase matlab.ui.control.CheckBox
        FindReplaceWholeName matlab.ui.control.CheckBox
        FindReplaceScope matlab.ui.control.DropDown
        FindReplaceTable matlab.ui.control.Table
        FindReplaceSummary matlab.ui.control.Label
        FindReplaceApply matlab.ui.control.Button
        % Rename plan last shown in the Find and Replace dialog.
        FindReplaceChanges struct = struct('Parameter', {}, 'Module', {}, ...
            'Location', {}, 'OldName', {}, 'NewName', {}, 'Status', {}, 'Message', {})

        EditTrialFunc matlab.ui.control.EditField
        CheckCompileAtRuntime matlab.ui.control.CheckBox
        CheckIncludeWAVBuffers matlab.ui.control.CheckBox
        DropDownConnectionType matlab.ui.control.DropDown

        BtnCompile matlab.ui.control.Button
        LabelCompileSummary matlab.ui.control.Label
        TableCompiled matlab.ui.control.Table

        CheckCalcRunButton matlab.ui.control.Button
        CheckCalcComboLabel matlab.ui.control.Label
        CheckCalcStatusLabel matlab.ui.control.Label
        CheckCalcIssuesTable matlab.ui.control.Table
        CheckCalcInputsPanel matlab.ui.container.Panel
        CheckCalcAnalysisArea matlab.ui.control.TextArea
        CheckCalcTrialsTable matlab.ui.control.Table
        % One row per sweep input variable: identifier + label/edit-field handles
        CheckCalcInputFields struct = struct('identifier', {}, 'label', {}, 'field', {})
        CheckCalcReport struct = struct()  % last sweepExpressions report shown in the dialog

        SelectedInterfaceRow (1,1) double = 0
        SelectedModuleRow (1,1) double = 0
        SelectedParamRow (1,1) double = 0
        SelectedParamCol (1,1) double = 0
        ParameterHandles cell = {}

        IsModified_ (1,1) logical = false  % true when unsaved changes exist
    end

    methods
        function obj = ProtocolDesigner(protocol)
            % ProtocolDesigner(protocol)
            % Construct a protocol designer and bind it to a protocol instance.
            % Creates the UI immediately and loads the visible state from Protocol.
            %
            % Parameters:
            % 	protocol	- Protocol instance to edit (default: epsych.Protocol()).
            %
            % Returns:
            % 	obj		- Initialized epsych.ProtocolDesigner handle.
            if nargin < 1 || isempty(protocol)
                obj.Protocol = epsych.Protocol();
            elseif ischar(protocol) || isstring(protocol)
                obj.Protocol = epsych.Protocol.load(char(protocol));
                obj.CurrentProtocolPath = char(protocol);
            else
                obj.Protocol = protocol;
            end

            obj.buildUI();

            % Extend StatusBar with ProtocolDesigner-specific error terms.
            obj.StatusBar.ErrorPatterns = [obj.StatusBar.ErrorPatterns, { ...
                'compile failed', ...
                'no interface selected', ...
                'no module selected', ...
                'no parameter selected', ...
                'no target module selected', ...
                'no writable parameters', ...
                'no interfaces defined', ...
                'read hardware parameters failed'}];

            obj.refreshUI();

            if nargout == 0
                clear obj
            end
        end

        function onFigureKeyPress(obj, evt)
            % onFigureKeyPress — Handle ProtocolDesigner keyboard shortcuts.
            % Ctrl+1..Ctrl+9: Change selected parameter type
            % Ctrl+F: Focus the parameter Find box
            % Ctrl+H: Open Find and Replace for parameter names
            % Ctrl+Shift+B: Add boolean parameter
            % Ctrl+Shift+T: Add boolean parameter with trigger=true
            % Ctrl+Shift+F: Add float parameter
            % Ctrl+S: Save current protocol
            % Ctrl+Shift+S: Save protocol as
            % Ctrl+Shift+N: Add integer parameter
            % Ctrl+Shift+Y: Cycle Color By setting
            % Ctrl+Shift+C: Compile protocol
            % Ctrl+Shift+V: Open compiled preview dialog
            % Ctrl+Shift+K: Open check calculations dialog
            % Ctrl+Shift+G: Plot parameter dependency graph
            % Ctrl+Shift+O: Open options dialog
            % Ctrl+Shift+A: Add interface
            % Ctrl+Shift+M: Add module
            % Ctrl+Shift+R: Remove parameter
            % Ctrl+Shift+D: Open selected parameter details
            % Ctrl+Shift+L: Toggle simple/detailed parameter view
            % Ctrl+Shift+/: Show keyboard shortcuts help

            if isempty(evt)
                return
            end

            modifiers = string(evt.Modifier);
            hasCtrl = any(modifiers == "control") || any(modifiers == "command");
            hasShift = any(modifiers == "shift");
            if ~hasCtrl
                return
            end

            key = string(evt.Key);
            switch lower(key)
                case "1"
                    obj.onChangeSelectedParameterType('Float');
                case "2"
                    obj.onChangeSelectedParameterType('Integer');
                case "3"
                    obj.onChangeSelectedParameterType('Boolean');
                case "4"
                    obj.onChangeSelectedParameterType('Buffer');
                case "5"
                    obj.onChangeSelectedParameterType('Coefficient Buffer');
                case "6"
                    obj.onChangeSelectedParameterType('String');
                case "7"
                    obj.onChangeSelectedParameterType('File');
                case "8"
                    obj.onChangeSelectedParameterType('StimType');
                case "9"
                    obj.onChangeSelectedParameterType('Undefined');
                case "b"
                    if hasShift
                        obj.onAddParamWithDefaults('boolean', false);
                    end
                case "t"
                    if hasShift
                        obj.onAddParamWithDefaults('boolean', true);
                    end
                case "f"
                    if hasShift
                        obj.onAddParamWithDefaults('float', false);
                    else
                        obj.focusParameterFind();
                    end
                case "h"
                    obj.onFindReplaceParameterNames();
                case "s"
                    if hasShift
                        obj.onSaveAs();
                    else
                        obj.onSave();
                    end
                case "n"
                    if hasShift
                        obj.onAddParamWithDefaults('integer', false);
                    end
                case "y"
                    if hasShift
                        obj.onCycleColorBy();
                    end
                case "c"
                    if hasShift
                        obj.onCompile();
                    end
                case "v"
                    if hasShift
                        obj.onOpenCompiledPreviewDialog();
                    end
                case "k"
                    if hasShift
                        obj.onOpenCheckCalculationsDialog();
                    end
                case "g"
                    if hasShift
                        obj.onShowParameterDependencyGraph();
                    end
                case "o"
                    if hasShift
                        obj.onOpenOptionsDialog();
                    end
                case "a"
                    if hasShift
                        obj.onAddInterface();
                    end
                case "m"
                    if hasShift
                        obj.onAddModule();
                    end
                case "r"
                    if hasShift
                        obj.onRemoveParam();
                    end
                case "d"
                    if hasShift
                        obj.onShowSelectedParameterDetails();
                    end
                case "l"
                    if hasShift
                        obj.onToggleTableView();
                    end
                case {"slash", "question"}
                    if hasShift
                        obj.showKeyboardShortcuts();
                    end
                otherwise
                    return
            end
        end

        function answer = promptForParameterName(obj, defaultName)
            % promptForParameterName(obj, defaultName)
            % Prompt for a new parameter name with a modal dialog owned by the designer.
            dlgSize = [360 150];
            figPos = obj.Figure.Position;
            dlgPos = [figPos(1) + round((figPos(3) - dlgSize(1)) / 2), ...
                      figPos(2) + round((figPos(4) - dlgSize(2)) / 2), ...
                      dlgSize];

            dlg = uifigure( ...
                'Name', 'Add Parameter', ...
                'Position', dlgPos, ...
                'Resize', 'off', ...
                'WindowStyle', 'modal');

            uilabel(dlg, ...
                'Text', 'Parameter Name', ...
                'Position', [20 100 320 22]);

            edt = uieditfield(dlg, 'text', ...
                'Position', [20 70 320 22], ...
                'Value', defaultName);

            uibutton(dlg, 'push', ...
                'Text', 'OK', ...
                'Position', [200 20 70 30], ...
                'ButtonPushedFcn', @(~, ~) onOk());

            uibutton(dlg, 'push', ...
                'Text', 'Cancel', ...
                'Position', [285 20 70 30], ...
                'ButtonPushedFcn', @(~, ~) onCancel());

            dlg.UserData = [];
            dlg.CloseRequestFcn = @(src, ~) onCancel();
            uiwait(dlg);

            if ~isvalid(dlg)
                answer = {};
                return
            end

            result = dlg.UserData;
            delete(dlg);

            if isempty(result)
                answer = {};
            else
                answer = {char(result)};
            end

            function onOk()
                dlg.UserData = string(strtrim(edt.Value));
                uiresume(dlg);
            end

            function onCancel()
                dlg.UserData = [];
                uiresume(dlg);
            end
        end

    end

    methods (Static)
        function obj = openFromFile(fileName)
            % obj = epsych.ProtocolDesigner.openFromFile(fileName)
            % Load a serialized protocol from disk and open it in the designer.
            %
            % Parameters:
            % 	fileName	- Path to a .eprot or .prot file.
            %
            % Returns:
            % 	obj		- Initialized epsych.ProtocolDesigner handle.
            arguments
                fileName {mustBeTextScalar}
            end

            fileName = string(fileName);
            if strlength(fileName) == 0 || ~isfile(fileName)
                error('epsych:ProtocolDesigner:FileNotFound', ...
                    'Protocol file not found: %s', fileName);
            end

            warning('off', 'MATLAB:dispatcher:UnresolvedFunctionHandle');
            protocol = epsych.Protocol.load(char(fileName));
            warning('on', 'MATLAB:dispatcher:UnresolvedFunctionHandle');

            obj = epsych.ProtocolDesigner(protocol);
            obj.CurrentProtocolPath = char(fileName);
            obj.addRecentProtocolPath(fileName);
            obj.refreshRecentProtocolMenu();
        end
    end
end
