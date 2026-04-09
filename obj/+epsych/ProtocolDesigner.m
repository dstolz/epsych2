classdef ProtocolDesigner < handle
    % epsych.ProtocolDesigner
    %
    % Lightweight UI for editing epsych.Protocol objects, including
    % interface-aware parameter editing, protocol options, and compiled trial preview.
    %
    %   gui = epsych.ProtocolDesigner();
    %   gui = epsych.ProtocolDesigner(protocolObj);

    properties
        Figure matlab.ui.Figure
        Protocol (1,1) epsych.Protocol

        TabGroup matlab.ui.container.TabGroup
        ParametersTab matlab.ui.container.Tab
        OptionsTab matlab.ui.container.Tab
        PreviewTab matlab.ui.container.Tab

        EditInfo matlab.ui.control.EditField
        BtnSave matlab.ui.control.Button
        BtnLoad matlab.ui.control.Button
        LabelStatus matlab.ui.control.Label

        DropDownInterfaceFilter matlab.ui.control.DropDown
        DropDownTargetInterface matlab.ui.control.DropDown
        DropDownTargetModule matlab.ui.control.DropDown
        BtnAddInterface matlab.ui.control.Button
        BtnRemoveInterface matlab.ui.control.Button
        TextAreaInterfaceSummary matlab.ui.control.TextArea
        TableParams matlab.ui.control.Table
        BtnAddParam matlab.ui.control.Button
        BtnRemoveParam matlab.ui.control.Button
        BtnRefreshParams matlab.ui.control.Button

        CheckRandomize matlab.ui.control.CheckBox
        SpinnerNumReps matlab.ui.control.Spinner
        EditISI matlab.ui.control.NumericEditField
        EditTrialFunc matlab.ui.control.EditField
        CheckCompileAtRuntime matlab.ui.control.CheckBox
        CheckIncludeWAVBuffers matlab.ui.control.CheckBox
        CheckUseOpenEx matlab.ui.control.CheckBox
        DropDownConnectionType matlab.ui.control.DropDown

        BtnCompile matlab.ui.control.Button
        LabelCompileSummary matlab.ui.control.Label
        TableCompiled matlab.ui.control.Table

        SelectedParamRow (1,1) double = 0
        ParameterHandles cell = {}
    end

    methods
        function obj = ProtocolDesigner(protocol)
            if nargin < 1 || isempty(protocol)
                obj.Protocol = epsych.Protocol();
            else
                obj.Protocol = protocol;
            end

            obj.buildUI();
            obj.refreshUI();
        end

        function buildUI(obj)
            obj.Figure = uifigure( ...
                'Name', 'Protocol Designer', ...
                'Position', [80 80 1180 780], ...
                'Color', [0.965 0.972 0.982]);

            uilabel(obj.Figure, ...
                'Text', 'Protocol Designer', ...
                'Position', [20 734 220 30], ...
                'FontSize', 20, ...
                'FontWeight', 'bold', ...
                'FontColor', [0.12 0.18 0.28]);

            uilabel(obj.Figure, ...
                'Text', 'Design interfaces, parameters, options, and compiled trial previews', ...
                'Position', [20 708 420 20], ...
                'FontSize', 11, ...
                'FontColor', [0.35 0.42 0.52]);

            uilabel(obj.Figure, 'Text', 'Info:', 'Position', [20 670 30 22], ...
                'FontWeight', 'bold', 'FontColor', [0.22 0.28 0.36]);
            obj.EditInfo = uieditfield(obj.Figure, 'text', ...
                'Position', [55 670 660 24], ...
                'ValueChangedFcn', @(~, ~) obj.onInfoChanged());

            uibutton(obj.Figure, 'push', ...
                'Text', 'Documentation', ...
                'Position', [730 668 110 28], ...
                'BackgroundColor', [0.93 0.90 0.84], ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onOpenDocumentation());

            obj.BtnSave = uibutton(obj.Figure, 'push', ...
                'Text', 'Save', ...
                'Position', [855 668 90 28], ...
                'BackgroundColor', [0.86 0.91 0.98], ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onSave());

            obj.BtnLoad = uibutton(obj.Figure, 'push', ...
                'Text', 'Load', ...
                'Position', [955 668 90 28], ...
                'BackgroundColor', [0.90 0.93 0.97], ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onLoad());

            obj.LabelStatus = uilabel(obj.Figure, ...
                'Text', 'Ready', ...
                'Position', [1060 668 100 28], ...
                'FontWeight', 'bold', ...
                'FontColor', [0.18 0.42 0.24]);

            obj.TabGroup = uitabgroup(obj.Figure, 'Position', [20 20 1140 630]);
            obj.ParametersTab = uitab(obj.TabGroup, 'Title', 'Parameters');
            obj.OptionsTab = uitab(obj.TabGroup, 'Title', 'Options');
            obj.PreviewTab = uitab(obj.TabGroup, 'Title', 'Compiled Preview');

            obj.buildParametersTab();
            obj.buildOptionsTab();
            obj.buildPreviewTab();
        end

        function buildParametersTab(obj)
            toolbarPanel = uipanel(obj.ParametersTab, ...
                'Position', [18 466 660 142], ...
                'Title', 'Interface Controls', ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.975 0.98 0.988], ...
                'ForegroundColor', [0.24 0.32 0.42]);

            obj.BtnAddInterface = uibutton(toolbarPanel, 'push', ...
                'Text', 'Add Interface', ...
                'Position', [16 82 110 28], ...
                'BackgroundColor', [0.84 0.92 0.88], ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onAddInterface());

            obj.BtnRemoveInterface = uibutton(toolbarPanel, 'push', ...
                'Text', 'Remove Interface', ...
                'Position', [136 82 125 28], ...
                'BackgroundColor', [0.96 0.88 0.88], ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onRemoveInterface());

            uilabel(toolbarPanel, 'Text', 'Filter Interface:', 'Position', [286 86 90 22], ...
                'FontWeight', 'bold');
            obj.DropDownInterfaceFilter = uidropdown(obj.ParametersTab, ...
                'Parent', toolbarPanel, ...
                'Position', [380 86 250 22], ...
                'ValueChangedFcn', @(~, ~) obj.refreshParameterTable());

            uilabel(toolbarPanel, 'Text', 'Add To Interface:', 'Position', [16 36 95 22], ...
                'FontWeight', 'bold');
            obj.DropDownTargetInterface = uidropdown(obj.ParametersTab, ...
                'Parent', toolbarPanel, ...
                'Position', [116 36 235 22], ...
                'ValueChangedFcn', @(~, ~) obj.onTargetInterfaceChanged());

            uilabel(toolbarPanel, 'Text', 'Module:', 'Position', [370 36 50 22], ...
                'FontWeight', 'bold');
            obj.DropDownTargetModule = uidropdown(obj.ParametersTab, ...
                'Parent', toolbarPanel, ...
                'Position', [425 36 120 22]);

            obj.BtnAddParam = uibutton(toolbarPanel, 'push', ...
                'Text', 'Add Parameter', ...
                'Position', [560 34 86 26], ...
                'BackgroundColor', [0.87 0.92 0.98], ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onAddParam());

            summaryPanel = uipanel(obj.ParametersTab, ...
                'Position', [694 466 424 142], ...
                'Title', 'Interface Summary', ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.98 0.985 0.992], ...
                'ForegroundColor', [0.24 0.32 0.42]);

            obj.TextAreaInterfaceSummary = uitextarea(obj.ParametersTab, ...
                'Parent', summaryPanel, ...
                'Position', [10 8 404 108], ...
                'Editable', 'off');

            uilabel(obj.ParametersTab, ...
                'Text', 'Parameters', ...
                'Position', [20 438 90 18], ...
                'FontWeight', 'bold', ...
                'FontColor', [0.22 0.28 0.36]);

            obj.TableParams = uitable(obj.ParametersTab, ...
                'Position', [18 78 1100 350], ...
                'ColumnName', {'Interface', 'Module', 'Name', 'Type', 'Value', 'Min', 'Max', 'Random', 'Expression', 'Access', 'Unit', 'Visible', 'Trigger', 'Description'}, ...
                'ColumnEditable', [false false false true true true true true true true true true true true], ...
                'ColumnFormat', {'char', 'char', 'char', obj.getTypeOptions(), 'char', 'numeric', 'numeric', 'logical', 'char', obj.getAccessOptions(), 'char', 'logical', 'logical', 'char'}, ...
                'ColumnWidth', {90, 90, 120, 80, 115, 65, 65, 70, 170, 90, 70, 70, 65, 190}, ...
                'CellEditCallback', @(~, evt) obj.onParamEdited(evt), ...
                'CellSelectionCallback', @(~, evt) obj.onParamSelected(evt));

            obj.BtnRemoveParam = uibutton(obj.ParametersTab, 'push', ...
                'Text', 'Remove Selected', ...
                'Position', [18 26 130 30], ...
                'BackgroundColor', [0.96 0.90 0.90], ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onRemoveParam());

            obj.BtnRefreshParams = uibutton(obj.ParametersTab, 'push', ...
                'Text', 'Refresh', ...
                'Position', [162 26 100 30], ...
                'BackgroundColor', [0.92 0.94 0.97], ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.refreshParameterTab());

            uibutton(obj.ParametersTab, 'push', ...
                'Text', 'Browse File Value', ...
                'Position', [276 26 130 30], ...
                'BackgroundColor', [0.90 0.93 0.88], ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onBrowseSelectedFileParameter());
        end

        function buildOptionsTab(obj)
            optionsPanel = uipanel(obj.OptionsTab, ...
                'Position', [18 18 1100 590], ...
                'Title', 'Protocol Options', ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.98 0.985 0.992], ...
                'ForegroundColor', [0.24 0.32 0.42]);

            uilabel(optionsPanel, 'Text', 'Trial Function:', 'Position', [20 520 85 22], ...
                'FontWeight', 'bold');
            obj.EditTrialFunc = uieditfield(obj.OptionsTab, 'text', ...
                'Parent', optionsPanel, ...
                'Position', [120 520 320 24], ...
                'ValueChangedFcn', @(~, ~) obj.onOptionControlChanged());

            uilabel(optionsPanel, 'Text', 'Num Reps:', 'Position', [20 470 65 22], ...
                'FontWeight', 'bold');
            obj.SpinnerNumReps = uispinner(obj.OptionsTab, ...
                'Parent', optionsPanel, ...
                'Position', [120 470 110 24], ...
                'Limits', [1 Inf], ...
                'RoundFractionalValues', true, ...
                'Step', 1, ...
                'ValueChangedFcn', @(~, ~) obj.onOptionControlChanged());

            uilabel(optionsPanel, 'Text', 'ISI (ms):', 'Position', [20 420 65 22], ...
                'FontWeight', 'bold');
            obj.EditISI = uieditfield(obj.OptionsTab, 'numeric', ...
                'Parent', optionsPanel, ...
                'Position', [120 420 110 24], ...
                'Limits', [0 Inf], ...
                'ValueChangedFcn', @(~, ~) obj.onOptionControlChanged());

            uilabel(optionsPanel, 'Text', 'Connection Type:', 'Position', [20 370 95 22], ...
                'FontWeight', 'bold');
            obj.DropDownConnectionType = uidropdown(obj.OptionsTab, ...
                'Parent', optionsPanel, ...
                'Items', {'GB', 'USB', 'Local', 'Network'}, ...
                'Position', [120 370 150 24], ...
                'ValueChangedFcn', @(~, ~) obj.onOptionControlChanged());

            obj.CheckRandomize = uicheckbox(obj.OptionsTab, ...
                'Parent', optionsPanel, ...
                'Text', 'Randomize Trials', ...
                'Position', [520 520 160 22], ...
                'FontWeight', 'bold', ...
                'ValueChangedFcn', @(~, ~) obj.onOptionControlChanged());

            obj.CheckCompileAtRuntime = uicheckbox(obj.OptionsTab, ...
                'Parent', optionsPanel, ...
                'Text', 'Compile At Runtime', ...
                'Position', [520 470 180 22], ...
                'FontWeight', 'bold', ...
                'ValueChangedFcn', @(~, ~) obj.onOptionControlChanged());

            obj.CheckIncludeWAVBuffers = uicheckbox(obj.OptionsTab, ...
                'Parent', optionsPanel, ...
                'Text', 'Include WAV Buffers', ...
                'Position', [520 420 180 22], ...
                'FontWeight', 'bold', ...
                'ValueChangedFcn', @(~, ~) obj.onOptionControlChanged());

            obj.CheckUseOpenEx = uicheckbox(obj.OptionsTab, ...
                'Parent', optionsPanel, ...
                'Text', 'Use OpenEx', ...
                'Position', [520 370 140 22], ...
                'FontWeight', 'bold', ...
                'ValueChangedFcn', @(~, ~) obj.onOptionControlChanged());

            uilabel(optionsPanel, ...
                'Text', 'Core timing and runtime settings for compiled protocols.', ...
                'Position', [20 558 360 18], ...
                'FontAngle', 'italic', ...
                'FontColor', [0.38 0.45 0.55]);
        end

        function buildPreviewTab(obj)
            previewPanel = uipanel(obj.PreviewTab, ...
                'Position', [18 18 1100 590], ...
                'Title', 'Compiled Trial Preview', ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.98 0.985 0.992], ...
                'ForegroundColor', [0.24 0.32 0.42]);

            obj.BtnCompile = uibutton(obj.PreviewTab, 'push', ...
                'Parent', previewPanel, ...
                'Text', 'Compile Protocol', ...
                'Position', [18 540 140 30], ...
                'BackgroundColor', [0.86 0.91 0.98], ...
                'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) obj.onCompile());

            obj.LabelCompileSummary = uilabel(obj.PreviewTab, ...
                'Parent', previewPanel, ...
                'Text', 'Not compiled', ...
                'Position', [180 540 890 28], ...
                'FontWeight', 'bold', ...
                'FontColor', [0.22 0.28 0.36]);

            obj.TableCompiled = uitable(obj.PreviewTab, ...
                'Parent', previewPanel, ...
                'Position', [18 18 1060 505], ...
                'ColumnEditable', false);
        end

        function refreshUI(obj)
            obj.EditInfo.Value = obj.Protocol.Info;
            obj.refreshParameterTab();
            obj.refreshOptionsTab();
            obj.refreshCompiledPreview();
        end

        function refreshParameterTab(obj)
            obj.refreshExpressionValues();
            obj.refreshInterfaceControls();
            obj.refreshInterfaceSummary();
            obj.refreshParameterTable();
        end

        function refreshInterfaceControls(obj)
            interfaceItems = obj.getInterfaceItems();

            filterItems = [{'All Interfaces'}, interfaceItems];
            currentFilter = '';
            if ~isempty(obj.DropDownInterfaceFilter.Items)
                currentFilter = obj.DropDownInterfaceFilter.Value;
            end
            obj.DropDownInterfaceFilter.Items = filterItems;
            if any(strcmp(currentFilter, filterItems))
                obj.DropDownInterfaceFilter.Value = currentFilter;
            else
                obj.DropDownInterfaceFilter.Value = filterItems{1};
            end

            currentTarget = '';
            if ~isempty(obj.DropDownTargetInterface.Items)
                currentTarget = obj.DropDownTargetInterface.Value;
            end
            obj.DropDownTargetInterface.Items = interfaceItems;
            if isempty(interfaceItems)
                obj.DropDownTargetInterface.Items = {'<none>'};
                obj.DropDownTargetInterface.Value = '<none>';
            elseif any(strcmp(currentTarget, interfaceItems))
                obj.DropDownTargetInterface.Value = currentTarget;
            else
                obj.DropDownTargetInterface.Value = interfaceItems{1};
            end

            obj.refreshTargetModuleControls();
        end

        function refreshTargetModuleControls(obj)
            moduleItems = obj.getTargetModuleItems();
            currentModule = '';
            if ~isempty(obj.DropDownTargetModule.Items)
                currentModule = obj.DropDownTargetModule.Value;
            end

            if isempty(moduleItems)
                obj.DropDownTargetModule.Items = {'<none>'};
                obj.DropDownTargetModule.Value = '<none>';
            else
                obj.DropDownTargetModule.Items = moduleItems;
                if any(strcmp(currentModule, moduleItems))
                    obj.DropDownTargetModule.Value = currentModule;
                else
                    obj.DropDownTargetModule.Value = moduleItems{1};
                end
            end
        end

        function refreshInterfaceSummary(obj)
            lines = cell(0, 1);

            for ifaceIdx = 1:length(obj.Protocol.Interfaces)
                iface = obj.Protocol.Interfaces(ifaceIdx);
                ifaceLabel = obj.interfaceLabel(iface, ifaceIdx);
                lines{end + 1, 1} = sprintf('%s', ifaceLabel); %#ok<AGROW>

                for moduleIdx = 1:length(iface.Module)
                    module = iface.Module(moduleIdx);
                    lines{end + 1, 1} = sprintf('  Module %d: %s (%d params)', ...
                        moduleIdx, module.Name, length(module.Parameters)); %#ok<AGROW>
                end
            end

            if isempty(lines)
                lines = {'No interfaces available.'};
            end

            obj.TextAreaInterfaceSummary.Value = lines;
        end

        function refreshParameterTable(obj)
            filterIndex = obj.selectedFilterIndex();
            [tableData, parameterHandles] = obj.getParameterTableData(filterIndex);
            obj.ParameterHandles = parameterHandles;
            obj.TableParams.Data = tableData;
            obj.SelectedParamRow = 0;
        end

        function refreshOptionsTab(obj)
            obj.EditTrialFunc.Value = obj.Protocol.Options.trialFunc;
            obj.SpinnerNumReps.Value = obj.Protocol.Options.numReps;
            obj.EditISI.Value = obj.Protocol.Options.ISI;
            obj.CheckRandomize.Value = obj.Protocol.Options.randomize;
            obj.CheckCompileAtRuntime.Value = obj.Protocol.Options.compileAtRuntime;
            obj.CheckIncludeWAVBuffers.Value = obj.Protocol.Options.IncludeWAVBuffers;
            obj.CheckUseOpenEx.Value = obj.Protocol.Options.UseOpenEx;

            connectionType = obj.Protocol.Options.ConnectionType;
            if any(strcmp(connectionType, obj.DropDownConnectionType.Items))
                obj.DropDownConnectionType.Value = connectionType;
            else
                obj.DropDownConnectionType.Items = unique([obj.DropDownConnectionType.Items, {connectionType}], 'stable');
                obj.DropDownConnectionType.Value = connectionType;
            end
        end

        function refreshCompiledPreview(obj)
            writeParams = obj.Protocol.COMPILED.writeparams;
            trials = obj.Protocol.COMPILED.trials;

            if isempty(writeParams)
                obj.TableCompiled.ColumnName = {'No Compiled Trials'};
                obj.TableCompiled.Data = cell(0, 1);
                obj.LabelCompileSummary.Text = 'Not compiled';
                return
            end

            previewCount = min(size(trials, 1), 200);
            previewData = trials(1:previewCount, :);
            obj.TableCompiled.ColumnName = writeParams;
            obj.TableCompiled.Data = previewData;
            obj.LabelCompileSummary.Text = sprintf('Showing %d of %d compiled trials', previewCount, obj.Protocol.COMPILED.ntrials);
        end

        function onInfoChanged(obj)
            obj.Protocol.Info = obj.EditInfo.Value;
            obj.LabelStatus.Text = 'Protocol info updated';
        end

        function onTargetInterfaceChanged(obj)
            obj.refreshTargetModuleControls();
        end

        function onParamSelected(obj, evt)
            obj.SelectedParamRow = 0;
            if isempty(evt.Indices)
                return
            end

            obj.SelectedParamRow = evt.Indices(1, 1);
            parameter = obj.ParameterHandles{obj.SelectedParamRow};
            if isequal(parameter.Type, 'File')
                obj.LabelStatus.Text = sprintf('Selected file parameter %s', parameter.Name);
            elseif obj.hasParameterExpression(parameter)
                obj.LabelStatus.Text = sprintf('%s = %s', obj.getParameterExpression(parameter), parameter.ValueStr);
            end
        end

        function onParamEdited(obj, evt)
            row = evt.Indices(1);
            col = evt.Indices(2);

            if row < 1 || row > numel(obj.ParameterHandles)
                return
            end

            parameter = obj.ParameterHandles{row};
            originalType = parameter.Type;
            statusMessage = sprintf('Updated parameter %s', parameter.Name);
            try
                switch col
                    case 4
                        parameter.Type = char(evt.NewData);
                        if isequal(parameter.Type, 'File')
                            allowMultiple = obj.promptForFileSelectionMode(parameter);
                            if isempty(allowMultiple)
                                parameter.Type = originalType;
                                obj.refreshParameterTable();
                                obj.LabelStatus.Text = sprintf('File type selection cancelled for %s', parameter.Name);
                                return
                            end

                            parameter.isArray = allowMultiple;
                            [fileValue, cancelled] = obj.promptForParameterFileValue(parameter, allowMultiple);
                            if cancelled
                                parameter.Type = originalType;
                                obj.refreshParameterTable();
                                obj.LabelStatus.Text = sprintf('File selection cancelled for %s', parameter.Name);
                                return
                            end
                            parameter.Value = fileValue;
                        elseif obj.hasParameterExpression(parameter) && ~obj.parameterSupportsExpression(parameter)
                            obj.clearParameterExpression(parameter);
                            statusMessage = sprintf('Cleared expression for %s because type %s does not support expressions', parameter.Name, parameter.Type);
                        end
                    case 5
                        if obj.hasParameterExpression(parameter)
                            obj.refreshParameterTable();
                            obj.LabelStatus.Text = sprintf('Parameter %s is expression-controlled. Edit the Expression column instead.', parameter.Name);
                            return
                        end
                        if isequal(parameter.Type, 'File')
                            [fileValue, cancelled] = obj.promptForParameterFileValue(parameter, parameter.isArray);
                            if cancelled
                                obj.refreshParameterTable();
                                obj.LabelStatus.Text = sprintf('File selection cancelled for %s', parameter.Name);
                                return
                            end
                            parameter.Value = fileValue;
                        else
                            parameter.Value = obj.parseValue(evt.NewData);
                        end
                    case 5
                        expressionText = strtrim(char(string(evt.NewData)));
                        if isempty(expressionText)
                            obj.clearParameterExpression(parameter);
                            statusMessage = sprintf('Cleared expression for %s', parameter.Name);
                        else
                            obj.setParameterExpression(parameter, expressionText);
                            obj.evaluateAndApplyParameterExpression(parameter, expressionText);
                            statusMessage = sprintf('%s = %s', expressionText, parameter.ValueStr);
                        end
                    case 6
                        parameter.Type = char(evt.NewData);
                        if isequal(parameter.Type, 'File')
                            allowMultiple = obj.promptForFileSelectionMode(parameter);
                            if isempty(allowMultiple)
                                parameter.Type = originalType;
                                obj.refreshParameterTable();
                                obj.LabelStatus.Text = sprintf('File type selection cancelled for %s', parameter.Name);
                                return
                            end

                            parameter.isArray = allowMultiple;
                            [fileValue, cancelled] = obj.promptForParameterFileValue(parameter, allowMultiple);
                            if cancelled
                                parameter.Type = originalType;
                                obj.refreshParameterTable();
                                obj.LabelStatus.Text = sprintf('File selection cancelled for %s', parameter.Name);
                                return
                            end
                            parameter.Value = fileValue;
                        elseif obj.hasParameterExpression(parameter) && ~obj.parameterSupportsExpression(parameter)
                            obj.clearParameterExpression(parameter);
                            statusMessage = sprintf('Cleared expression for %s because type %s does not support expressions', parameter.Name, parameter.Type);
                        end
                    case 7
                        parameter.Access = char(evt.NewData);
                    case 8
                        parameter.Unit = char(evt.NewData);
                    case 9
                        parameter.isRandom = logical(evt.NewData);
                    case 10
                        parameter.Visible = logical(evt.NewData);
                    case 11
                        parameter.isArray = logical(evt.NewData);
                    case 12
                        parameter.isTrigger = logical(evt.NewData);
                    case 13
                        parameter.Min = double(evt.NewData);
                    case 14
                        parameter.Max = double(evt.NewData);
                    case 15
                        parameter.Description = string(evt.NewData);
                end
            catch ME
                obj.refreshParameterTable();
                obj.LabelStatus.Text = ME.message;
                return
            end

            obj.refreshExpressionValues();
            obj.refreshParameterTable();
            obj.LabelStatus.Text = statusMessage;
        end

        function onAddInterface(obj)
            specs = obj.getAvailableInterfaceSpecs();
            labels = cellfun(@(spec) spec.label, specs, UniformOutput = false);
            [selection, ok] = listdlg('PromptString', 'Select interface type to add:', ...
                'SelectionMode', 'single', ...
                'ListString', labels);
            if ~ok || isempty(selection)
                return
            end

            try
                spec = specs{selection};
                options = obj.promptForInterfaceOptions(spec);
                if isempty(options)
                    return
                end

                interface = spec.createFcn(options);
                obj.Protocol.addInterface(interface);
                obj.refreshParameterTab();
                obj.LabelStatus.Text = sprintf('Added interface %s', char(interface.Type));
            catch ME
                obj.LabelStatus.Text = sprintf('Add interface failed: %s', ME.message);
            end
        end

        function onRemoveInterface(obj)
            interfaceIndex = obj.selectedTargetInterfaceIndex();
            if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
                obj.LabelStatus.Text = 'Select an interface to remove';
                return
            end

            iface = obj.Protocol.Interfaces(interfaceIndex);
            if ~strcmp(questdlg(sprintf('Remove interface %s?', char(iface.Type)), ...
                    'Remove Interface', 'Remove', 'Cancel', 'Cancel'), 'Remove')
                return
            end

            obj.Protocol.removeInterface(interfaceIndex);
            obj.refreshParameterTab();
            obj.LabelStatus.Text = sprintf('Removed interface %s', char(iface.Type));
        end

        function onAddParam(obj)
            module = obj.getSelectedTargetModule();
            if isempty(module)
                obj.LabelStatus.Text = 'No target module selected';
                return
            end

            defaultName = obj.getUniqueParameterName(module, 'param');
            answer = inputdlg({'Parameter Name'}, 'Add Parameter', 1, {defaultName});
            if isempty(answer)
                return
            end

            requestedName = strtrim(answer{1});
            if isempty(requestedName)
                requestedName = defaultName;
            end

            parameterName = obj.getUniqueParameterName(module, requestedName);
            module.add_parameter(parameterName, 1, ...
                Type = 'Float', ...
                Access = 'Any', ...
                Unit = '', ...
                isRandom = false, ...
                Visible = true, ...
                isArray = false, ...
                    case 6
                        parameter.Min = double(evt.NewData);
                    case 7
                        parameter.Max = double(evt.NewData);
                    case 8
                        parameter.isRandom = logical(evt.NewData);
                    case 9
                Min = -inf, ...
                Max = inf, ...
                Description = "");

            obj.refreshParameterTab();
            obj.LabelStatus.Text = sprintf('Added parameter %s. Edit the new row to customize it.', parameterName);
        end

        function onRemoveParam(obj)
                    case 10
            allowMultiple = obj.resolveFileSelectionMode(parameter);
                    case 11
            if cancelled
                    case 12

                    case 13
            parameter.Value = fileValue;
                    case 14
            obj.Protocol.setOption('trialFunc', obj.EditTrialFunc.Value);
            obj.Protocol.setOption('numReps', obj.SpinnerNumReps.Value);
            obj.Protocol.setOption('ISI', obj.EditISI.Value);
            obj.Protocol.setOption('randomize', obj.CheckRandomize.Value);
            obj.Protocol.setOption('compileAtRuntime', obj.CheckCompileAtRuntime.Value);
            obj.Protocol.setOption('IncludeWAVBuffers', obj.CheckIncludeWAVBuffers.Value);
            obj.Protocol.setOption('UseOpenEx', obj.CheckUseOpenEx.Value);
            obj.Protocol.setOption('ConnectionType', obj.DropDownConnectionType.Value);
            obj.LabelStatus.Text = 'Options updated';
        end

        function onCompile(obj)
            obj.Protocol.compile();
            obj.refreshCompiledPreview();
            obj.LabelStatus.Text = sprintf('Compiled %d trials', obj.Protocol.COMPILED.ntrials);
        end

        function onSave(obj)
            [fileName, folder] = uiputfile('*.eprot', 'Save Protocol');
            if isequal(fileName, 0)
                return
            end

            obj.Protocol.save(fullfile(folder, fileName));
            obj.LabelStatus.Text = 'Protocol saved';
        end

        function onLoad(obj)
            [fileName, folder] = uigetfile({'*.eprot;*.prot', 'Protocol Files (*.eprot, *.prot)'}, 'Load Protocol');
            if isequal(fileName, 0)
                return
            end

            obj.Protocol = epsych.Protocol.load(fullfile(folder, fileName));
            obj.refreshUI();
            obj.LabelStatus.Text = 'Protocol loaded';
        end

        function onOpenDocumentation(obj)
            docPath = obj.getDocumentationPath();
            if ~isfile(docPath)
                obj.LabelStatus.Text = 'Documentation file not found';
                uialert(obj.Figure, sprintf('Documentation file not found:\n%s', docPath), 'Missing Documentation');
                return
            end

            matlab.desktop.editor.openDocument(docPath);
            obj.LabelStatus.Text = 'Opened Protocol Designer documentation';
        end
    end

    methods (Access = private)
        function docPath = getDocumentationPath(~)
            classFile = mfilename('fullpath');
            repoRoot = fileparts(fileparts(fileparts(classFile)));
            docPath = fullfile(repoRoot, 'documentation', 'design', 'ProtocolDesigner.md');
        end

        function items = getInterfaceItems(obj)
            items = cell(1, length(obj.Protocol.Interfaces));
            for idx = 1:length(obj.Protocol.Interfaces)
                items{idx} = obj.interfaceLabel(obj.Protocol.Interfaces(idx), idx);
            end
        end

        function label = interfaceLabel(~, iface, idx)
            label = sprintf('%d: %s', idx, char(iface.Type));
        end

        function idx = selectedFilterIndex(obj)
            value = obj.DropDownInterfaceFilter.Value;
            if strcmp(value, 'All Interfaces')
                idx = 0;
                return
            end

            idx = obj.parseIndexedLabel(value);
        end

        function idx = selectedTargetInterfaceIndex(obj)
            value = obj.DropDownTargetInterface.Value;
            idx = obj.parseIndexedLabel(value);
        end

        function items = getTargetModuleItems(obj)
            items = {};
            if isempty(obj.Protocol.Interfaces)
                return
            end

            interfaceIndex = obj.selectedTargetInterfaceIndex();
            if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
                return
            end

            iface = obj.Protocol.Interfaces(interfaceIndex);
            items = cell(1, length(iface.Module));
            for moduleIdx = 1:length(iface.Module)
                items{moduleIdx} = sprintf('%d: %s', moduleIdx, iface.Module(moduleIdx).Name);
            end
        end

        function module = getSelectedTargetModule(obj)
            module = [];
            interfaceIndex = obj.selectedTargetInterfaceIndex();
            if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
                return
            end

            iface = obj.Protocol.Interfaces(interfaceIndex);
            if isempty(iface.Module) || strcmp(obj.DropDownTargetModule.Value, '<none>')
                return
            end

            moduleIndex = obj.parseIndexedLabel(obj.DropDownTargetModule.Value);
            if moduleIndex < 1 || moduleIndex > length(iface.Module)
                return
            end

            module = iface.Module(moduleIndex);
        end

        function [tableData, parameterHandles] = getParameterTableData(obj, filterIndex)
            tableData = cell(0, 14);
            parameterHandles = {};

            for ifaceIdx = 1:length(obj.Protocol.Interfaces)
                if filterIndex ~= 0 && ifaceIdx ~= filterIndex
                    continue
                end

                iface = obj.Protocol.Interfaces(ifaceIdx);
                ifaceLabel = obj.interfaceLabel(iface, ifaceIdx);

                for moduleIdx = 1:length(iface.Module)
                    module = iface.Module(moduleIdx);
                    for paramIdx = 1:length(module.Parameters)
                        parameter = module.Parameters(paramIdx);
                        tableData(end + 1, :) = { ...
                            ifaceLabel, ...
                            module.Name, ...
                            parameter.Name, ...
                            parameter.Type, ...
                            parameter.ValueStr, ...
                            parameter.Min, ...
                            parameter.Max, ...
                            parameter.isRandom, ...
                            obj.getParameterExpression(parameter), ...
                            parameter.Access, ...
                            parameter.Unit, ...
                            parameter.Visible, ...
                            parameter.isTrigger, ...
                            char(parameter.Description)}; %#ok<AGROW>
                        parameterHandles{end + 1, 1} = parameter; %#ok<AGROW>
                    end
                end
            end
        end

        function idx = parseIndexedLabel(~, label)
            tokens = regexp(label, '^(\d+):', 'tokens', 'once');
            if isempty(tokens)
                idx = 0;
            else
                idx = str2double(tokens{1});
            end
        end

        function value = parseValue(~, rawValue)
            if isstring(rawValue)
                rawValue = char(rawValue);
            end

            if ischar(rawValue)
                numericValue = str2num(rawValue); %#ok<ST2NM>
                if ~isempty(numericValue)
                    value = numericValue;
                else
                    value = rawValue;
                end
            else
                value = rawValue;
            end
        end

        function refreshExpressionValues(obj)
            parameters = obj.getAllParameters();
            expressionParameters = parameters(arrayfun(@(p) obj.hasParameterExpression(p), parameters));
            if isempty(expressionParameters)
                return
            end

            pending = expressionParameters;
            maxPasses = max(1, numel(pending));
            firstError = '';

            for passIdx = 1:maxPasses
                nextPending = hw.Parameter.empty(1, 0);
                progressMade = false;

                for paramIdx = 1:numel(pending)
                    parameter = pending(paramIdx);
                    expressionText = obj.getParameterExpression(parameter);
                    try
                        obj.evaluateAndApplyParameterExpression(parameter, expressionText);
                        progressMade = true;
                    catch ME
                        nextPending(end + 1) = parameter; %#ok<AGROW>
                        if isempty(firstError)
                            firstError = sprintf('Expression error for %s: %s', parameter.Name, ME.message);
                        end
                    end
                end

                if isempty(nextPending)
                    return
                end
                if ~progressMade
                    obj.LabelStatus.Text = firstError;
                    return
                end
                pending = nextPending;
            end

            if ~isempty(firstError)
                obj.LabelStatus.Text = firstError;
            end
        end

        function parameters = getAllParameters(obj)
            parameters = hw.Parameter.empty(1, 0);
            for ifaceIdx = 1:length(obj.Protocol.Interfaces)
                iface = obj.Protocol.Interfaces(ifaceIdx);
                for moduleIdx = 1:length(iface.Module)
                    module = iface.Module(moduleIdx);
                    if ~isempty(module.Parameters)
                        parameters = [parameters, module.Parameters]; %#ok<AGROW>
                    end
                end
            end
        end

        function tf = parameterSupportsExpression(~, parameter)
            tf = ismember(parameter.Type, {'Float', 'Integer', 'Boolean'}) && ~parameter.isTrigger;
        end

        function tf = hasParameterExpression(obj, parameter)
            expressionText = obj.getParameterExpression(parameter);
            tf = strlength(string(expressionText)) > 0;
        end

        function expressionText = getParameterExpression(~, parameter)
            expressionText = '';
            if ~isstruct(parameter.UserData)
                return
            end
            if isfield(parameter.UserData, 'Expression') && ~isempty(parameter.UserData.Expression)
                expressionText = char(string(parameter.UserData.Expression));
            end
        end

        function setParameterExpression(obj, parameter, expressionText)
            if ~obj.parameterSupportsExpression(parameter)
                error('Expressions are only allowed for numeric scalar parameter types.');
            end

            expressionText = strtrim(char(string(expressionText)));
            if isempty(expressionText)
                obj.clearParameterExpression(parameter);
                return
            end

            if isempty(parameter.UserData) || ~isstruct(parameter.UserData)
                parameter.UserData = struct();
            end
            parameter.UserData.Expression = expressionText;
        end

        function clearParameterExpression(~, parameter)
            if isstruct(parameter.UserData) && isfield(parameter.UserData, 'Expression')
                parameter.UserData = rmfield(parameter.UserData, 'Expression');
            end
        end

        function evaluateAndApplyParameterExpression(obj, parameter, expressionText)
            if ~obj.parameterSupportsExpression(parameter)
                error('Parameter %s does not support expressions for type %s.', parameter.Name, parameter.Type);
            end

            result = obj.evaluateParameterExpression(parameter, expressionText);
            result = obj.normalizeExpressionResult(parameter, result);

            parameter.Value = result;
            parameter.isArray = false;
        end

        function result = evaluateParameterExpression(obj, targetParameter, expressionText)
            expressionText = strtrim(char(string(expressionText)));
            if isempty(expressionText)
                error('Expression cannot be empty.');
            end

            context = obj.buildExpressionContext(targetParameter);
            allowedFunctions = {'abs', 'acos', 'asin', 'atan', 'ceil', 'cos', 'exp', 'floor', 'log', 'log10', 'max', 'min', 'mod', 'mean', 'pi', 'power', 'round', 'sign', 'sin', 'sqrt', 'sum', 'tan', 'true', 'false', 'inf', 'nan'};

            if ~isempty(regexp(expressionText, '[;''"=\[\]{}!&|]', 'once'))
                error('Expression contains unsupported characters.');
            end

            identifiers = unique(regexp(expressionText, '\<[A-Za-z]\w*\>', 'match'));
            contextNames = fieldnames(context);
            for idx = 1:numel(identifiers)
                token = identifiers{idx};
                if any(strcmp(token, contextNames)) || any(strcmp(token, allowedFunctions))
                    continue
                end
                error('Unknown symbol "%s" in expression.', token);
            end

            names = fieldnames(context);
            for idx = 1:numel(names)
                eval(sprintf('%s = context.(names{%d});', names{idx}, idx)); %#ok<EVLDIR>
            end
            result = eval(expressionText); %#ok<EVLDIR>
        end

        function context = buildExpressionContext(obj, targetParameter)
            parameters = obj.getAllParameters();
            context = struct();

            for idx = 1:numel(parameters)
                parameter = parameters(idx);
                if isequal(parameter, targetParameter)
                    continue
                end
                if ~obj.parameterCanParticipateInExpression(parameter)
                    continue
                end

                bareAlias = parameter.validName;
                aliasCount = sum(arrayfun(@(p) strcmp(p.validName, bareAlias), parameters));
                if aliasCount == 1
                    context.(bareAlias) = double(parameter.Value);
                end

                qualifiedAlias = obj.getQualifiedExpressionAlias(parameter);
                context.(qualifiedAlias) = double(parameter.Value);
            end
        end

        function tf = parameterCanParticipateInExpression(~, parameter)
            if ~ismember(parameter.Type, {'Float', 'Integer', 'Boolean'})
                tf = false;
                return
            end
            value = parameter.Value;
            tf = (isnumeric(value) || islogical(value)) && isscalar(value);
        end

        function alias = getQualifiedExpressionAlias(obj, parameter)
            for ifaceIdx = 1:length(obj.Protocol.Interfaces)
                iface = obj.Protocol.Interfaces(ifaceIdx);
                for moduleIdx = 1:length(iface.Module)
                    module = iface.Module(moduleIdx);
                    for paramIdx = 1:length(module.Parameters)
                        if isequal(module.Parameters(paramIdx), parameter)
                            interfaceLabel = sprintf('%s%d', char(iface.Type), ifaceIdx);
                            moduleLabel = module.Name;
                            alias = matlab.lang.makeValidName(sprintf('%s_%s_%s', interfaceLabel, moduleLabel, parameter.Name));
                            return
                        end
                    end
                end
            end
            alias = matlab.lang.makeValidName(sprintf('%s_%s', parameter.Module.Name, parameter.Name));
        end

        function result = normalizeExpressionResult(~, parameter, result)
            if ~(isnumeric(result) || islogical(result)) || ~isscalar(result) || ~isfinite(double(result))
                error('Expression for %s must evaluate to a finite numeric scalar.', parameter.Name);
            end

            switch parameter.Type
                case 'Integer'
                    rounded = round(double(result));
                    if abs(double(result) - rounded) > 1e-9
                        error('Expression for %s must evaluate to an integer.', parameter.Name);
                    end
                    result = rounded;
                case 'Boolean'
                    result = logical(result ~= 0);
                otherwise
                    result = double(result);
            end
        end

        function options = getTypeOptions(~)
            options = {'Float', 'Integer', 'Boolean', 'Buffer', 'Coefficient Buffer', 'String', 'File', 'Undefined'};
        end

        function allowMultiple = promptForFileSelectionMode(obj, parameter)
            configuredMode = obj.getParameterFileConfig(parameter).allowMultiple;
            if ~isempty(configuredMode)
                allowMultiple = configuredMode;
                obj.LabelStatus.Text = sprintf('Using configured file mode for %s', parameter.Name);
                return
            end

            choice = questdlg(sprintf('Allow multiple files for parameter %s?', parameter.Name), ...
                'File Parameter Mode', 'Single File', 'Multiple Files', 'Cancel', 'Single File');

            switch choice
                case 'Single File'
                    allowMultiple = false;
                case 'Multiple Files'
                    allowMultiple = true;
                otherwise
                    allowMultiple = [];
            end

            if ~isempty(allowMultiple)
                obj.LabelStatus.Text = sprintf('File mode set for %s', parameter.Name);
            end
        end

        function [fileValue, cancelled] = promptForParameterFileValue(obj, parameter, allowMultiple)
            fileConfig = obj.getParameterFileConfig(parameter);
            startPath = obj.getParameterFileStartPath(parameter, fileConfig.initialPath);
            fileFilter = fileConfig.fileFilter;
            dialogTitle = fileConfig.dialogTitle;

            if allowMultiple
                [fileName, folder] = uigetfile(fileFilter, dialogTitle, fullfile(startPath, '*'), 'MultiSelect', 'on');
            else
                [fileName, folder] = uigetfile(fileFilter, dialogTitle, fullfile(startPath, '*'));
            end

            if isequal(fileName, 0)
                fileValue = [];
                cancelled = true;
                return
            end

            if iscell(fileName)
                fileValue = cellfun(@(name) fullfile(folder, name), fileName, 'UniformOutput', false);
                obj.setLastBrowseDirectory(folder);
            else
                fileValue = fullfile(folder, fileName);
                obj.setLastBrowseDirectory(folder);
            end

            cancelled = false;
        end

        function startPath = getParameterFileStartPath(obj, parameter, configuredInitialPath)
            startPath = obj.getLastBrowseDirectory();
            if nargin >= 3 && ~isempty(configuredInitialPath) && isfolder(configuredInitialPath)
                startPath = configuredInitialPath;
            end
            currentValue = parameter.Value;

            if ischar(currentValue) || isstring(currentValue)
                candidatePath = fileparts(char(string(currentValue)));
                if isfolder(candidatePath)
                    startPath = candidatePath;
                end
            elseif iscell(currentValue) && ~isempty(currentValue)
                firstValue = currentValue{1};
                if iscell(firstValue) && ~isempty(firstValue)
                    firstValue = firstValue{1};
                end
                candidatePath = fileparts(char(string(firstValue)));
                if isfolder(candidatePath)
                    startPath = candidatePath;
                end
            end

            if isempty(startPath) || ~isfolder(startPath)
                startPath = obj.getRepositoryRoot();
            end
        end

        function parameter = getSelectedParameter(obj)
            if obj.SelectedParamRow < 1 || obj.SelectedParamRow > numel(obj.ParameterHandles)
                parameter = [];
                return
            end
            parameter = obj.ParameterHandles{obj.SelectedParamRow};
        end

        function allowMultiple = resolveFileSelectionMode(obj, parameter)
            configuredMode = obj.getParameterFileConfig(parameter).allowMultiple;
            if isempty(configuredMode)
                allowMultiple = parameter.isArray;
            else
                allowMultiple = configuredMode;
            end
        end

        function config = getParameterFileConfig(obj, parameter)
            config = struct( ...
                'fileFilter', {{'*.*', 'All Files (*.*)'}}, ...
                'dialogTitle', sprintf('Select File Value for %s', parameter.Name), ...
                'allowMultiple', [], ...
                'initialPath', '');

            userData = parameter.UserData;
            if ~isstruct(userData)
                return
            end

            if isfield(userData, 'FileFilter') && ~isempty(userData.FileFilter)
                config.fileFilter = userData.FileFilter;
            elseif isfield(userData, 'FileExtensions') && ~isempty(userData.FileExtensions)
                config.fileFilter = obj.buildFileFilterFromExtensions(userData.FileExtensions);
            end

            if isfield(userData, 'FileDialogTitle') && ~isempty(userData.FileDialogTitle)
                config.dialogTitle = char(string(userData.FileDialogTitle));
            end

            if isfield(userData, 'AllowMultipleFiles') && ~isempty(userData.AllowMultipleFiles)
                config.allowMultiple = logical(userData.AllowMultipleFiles);
            elseif isfield(userData, 'FileMultiSelect') && ~isempty(userData.FileMultiSelect)
                config.allowMultiple = logical(userData.FileMultiSelect);
            end

            if isfield(userData, 'InitialPath') && ~isempty(userData.InitialPath)
                candidatePath = char(string(userData.InitialPath));
                if isfolder(candidatePath)
                    config.initialPath = candidatePath;
                end
            elseif isfield(userData, 'FileInitialPath') && ~isempty(userData.FileInitialPath)
                candidatePath = char(string(userData.FileInitialPath));
                if isfolder(candidatePath)
                    config.initialPath = candidatePath;
                end
            end
        end

        function fileFilter = buildFileFilterFromExtensions(~, extensions)
            extensions = cellstr(extensions);
            normalizedExtensions = cellfun(@(ext) regexprep(char(string(ext)), '^\.?', '.'), extensions, UniformOutput = false);
            pattern = strjoin(cellfun(@(ext) ['*' ext], normalizedExtensions, UniformOutput = false), ';');
            description = sprintf('Supported Files (%s)', strjoin(normalizedExtensions, ', '));
            fileFilter = {pattern, description; '*.*', 'All Files (*.*)'};
        end

        function options = getAccessOptions(~)
            options = {'Read', 'Write', 'Any'};
        end

        function specs = getAvailableInterfaceSpecs(~)
            specs = {
                hw.Software.getCreationSpec(), ...
                hw.TDT_Synapse.getCreationSpec(), ...
                hw.TDT_RPcox.getCreationSpec() ...
                };
            for specIdx = 1:numel(specs)
                specs{specIdx} = hw.Interface.normalizeCreationSpec(specs{specIdx});
            end
        end

        function options = promptForInterfaceOptions(obj, spec)
            fields = spec.options;
            if isempty(fields)
                options = struct();
                return
            end

            dialogHeight = max(220, 120 + 78 * numel(fields));
            dialog = uifigure( ...
                'Name', sprintf('Add %s Interface', spec.label), ...
                'Position', [240 140 620 dialogHeight], ...
                'WindowStyle', 'modal', ...
                'Resize', 'off');

            controls = struct();
            okPressed = false;
            y = dialogHeight - 70;

            for idx = 1:numel(fields)
                field = fields(idx);
                labelText = field.label;
                if field.required
                    labelText = [labelText ' *'];
                end

                uilabel(dialog, ...
                    'Text', labelText, ...
                    'Position', [20 y + 30 180 22], ...
                    'FontWeight', 'bold');

                description = field.description;
                extra = obj.describeInterfaceField(field);
                if isempty(description)
                    description = extra;
                elseif ~isempty(extra)
                    description = sprintf('%s %s', description, extra);
                end

                if ~isempty(description)
                    uilabel(dialog, ...
                        'Text', description, ...
                        'Position', [20 y 580 22], ...
                        'FontAngle', 'italic');
                end

                controls.(field.name) = obj.createInterfaceOptionControl(dialog, field, [220 y + 4 370 28]);
                y = y - 78;
            end

            uibutton(dialog, 'push', ...
                'Text', 'Cancel', ...
                'Position', [390 18 90 30], ...
                'ButtonPushedFcn', @(~, ~) close(dialog));

            uibutton(dialog, 'push', ...
                'Text', 'Add Interface', ...
                'Position', [490 18 100 30], ...
                'ButtonPushedFcn', @onOkPressed);

            uiwait(dialog);

            if ~okPressed
                options = [];
                if isvalid(dialog)
                    delete(dialog);
                end
                return
            end

            options = struct();
            for idx = 1:numel(fields)
                field = fields(idx);
                rawValue = obj.readInterfaceControlValue(controls.(field.name), field);
                options.(field.name) = obj.parseInterfaceOptionValue(field, rawValue);
            end

            if isvalid(dialog)
                delete(dialog);
            end

            function onOkPressed(~, ~)
                try
                    for innerIdx = 1:numel(fields)
                        innerField = fields(innerIdx);
                        rawValue = obj.readInterfaceControlValue(controls.(innerField.name), innerField);
                        value = obj.parseInterfaceOptionValue(innerField, rawValue);
                        if innerField.required && obj.isMissingInterfaceOption(value)
                            error('Missing required option "%s".', innerField.label);
                        end
                        if ~isempty(innerField.choices)
                            if iscell(value)
                                if ~all(ismember(value, innerField.choices))
                                    error('Option "%s" must use only: %s.', innerField.label, strjoin(innerField.choices, ', '));
                                end
                            elseif ~any(strcmp(char(string(value)), innerField.choices))
                                error('Option "%s" must be one of: %s.', innerField.label, strjoin(innerField.choices, ', '));
                            end
                        end
                        if strcmp(innerField.inputType, 'numeric') && any(isnan(value))
                            error('Option "%s" must be numeric.', innerField.label);
                        end
                    end
                catch ME
                    uialert(dialog, ME.message, 'Invalid Interface Options');
                    return
                end

                okPressed = true;
                uiresume(dialog);
            end
        end

        function defaultText = formatInterfaceDefault(~, defaultValue, isList)
            if iscell(defaultValue)
                defaultText = strjoin(defaultValue, ', ');
            elseif isstring(defaultValue)
                defaultText = char(defaultValue);
            elseif isnumeric(defaultValue)
                if isscalar(defaultValue)
                    defaultText = num2str(defaultValue);
                else
                    defaultText = strjoin(arrayfun(@num2str, defaultValue, UniformOutput = false), ', ');
                end
            elseif islogical(defaultValue)
                defaultText = num2str(defaultValue);
            else
                defaultText = '';
            end

            if isList && isempty(defaultText)
                defaultText = '';
            end
        end

        function value = parseInterfaceOptionValue(obj, field, rawValue)
            if isstring(rawValue)
                rawValue = char(rawValue);
            end

            switch field.inputType
                case 'numeric'
                    if isnumeric(rawValue)
                        value = rawValue;
                    else
                        value = str2double(rawValue);
                    end
                case {'logical', 'boolean', 'bool'}
                    if islogical(rawValue)
                        value = rawValue;
                    elseif isnumeric(rawValue)
                        value = logical(rawValue);
                    else
                        value = strcmpi(strtrim(rawValue), 'true') || strcmp(rawValue, '1');
                    end
                case 'choice'
                    value = strtrim(rawValue);
                otherwise
                    if field.isList
                        if iscell(rawValue)
                            value = rawValue;
                        else
                            value = obj.parseList(rawValue);
                        end
                    else
                        value = strtrim(rawValue);
                    end
            end
        end

        function tf = isMissingInterfaceOption(~, value)
            if ischar(value) || isstring(value)
                tf = strlength(string(value)) == 0;
            elseif iscell(value)
                tf = isempty(value) || all(cellfun(@(item) strlength(string(item)) == 0, value));
            else
                tf = isempty(value) || (isnumeric(value) && any(isnan(value)));
            end
        end

        function description = describeInterfaceField(~, field)
            parts = {};
            if field.getFile
                if field.isList
                    parts{end + 1} = 'Use Browse to select one or more files.'; %#ok<AGROW>
                else
                    parts{end + 1} = 'Use Browse to select a file.'; %#ok<AGROW>
                end
            elseif field.getFolder
                parts{end + 1} = 'Use Browse to select a folder.'; %#ok<AGROW>
            end

            if strcmp(field.controlType, 'dropdown') && ~isempty(field.choices)
                parts{end + 1} = sprintf('Choices: %s.', strjoin(field.choices, ', ')); %#ok<AGROW>
            elseif strcmp(field.controlType, 'multiselect') && ~isempty(field.choices)
                parts{end + 1} = sprintf('Select one or more values from: %s.', strjoin(field.choices, ', ')); %#ok<AGROW>
            elseif strcmp(field.controlType, 'checkbox')
                parts{end + 1} = 'Toggle on or off.'; %#ok<AGROW>
            elseif field.isList
                parts{end + 1} = 'Enter multiple values separated by commas or semicolons.'; %#ok<AGROW>
            elseif strcmp(field.inputType, 'numeric')
                parts{end + 1} = 'Numeric value.'; %#ok<AGROW>
            end

            if isempty(parts)
                description = '';
            else
                description = strjoin(parts, ' ');
            end
        end

        function control = createInterfaceOptionControl(obj, parent, field, position)
            defaultValue = obj.formatInterfaceDefault(field.defaultValue, field.isList);
            if field.getFile || field.getFolder
                control = obj.createPathPickerControl(parent, field, position, defaultValue);
                return
            end

            switch field.controlType
                case 'dropdown'
                    items = field.choices;
                    if isempty(items)
                        items = {defaultValue};
                    end
                    control = uidropdown(parent, ...
                        'Items', items, ...
                        'Position', position);
                    if any(strcmp(defaultValue, items))
                        control.Value = defaultValue;
                    else
                        control.Value = items{1};
                    end
                case 'multiselect'
                    items = field.choices;
                    if isempty(items)
                        items = obj.parseList(defaultValue);
                    end
                    control = uilistbox(parent, ...
                        'Items', items, ...
                        'Position', [position(1) position(2) position(3) 56], ...
                        'Multiselect', 'on');
                    if iscell(field.defaultValue)
                        selectedItems = field.defaultValue;
                    else
                        selectedItems = obj.parseList(defaultValue);
                    end
                    selectedItems = intersect(selectedItems, items, 'stable');
                    if isempty(selectedItems)
                        control.Value = {};
                    else
                        control.Value = selectedItems;
                    end
                case 'numeric'
                    numericDefault = str2double(defaultValue);
                    if isnan(numericDefault)
                        numericDefault = 0;
                    end
                    control = uieditfield(parent, 'numeric', ...
                        'Position', position, ...
                        'Value', numericDefault);
                case 'checkbox'
                    control = uicheckbox(parent, ...
                        'Position', [position(1) position(2) 180 position(4)], ...
                        'Text', '', ...
                        'Value', logical(field.defaultValue));
                case 'textarea'
                    control = uitextarea(parent, ...
                        'Position', [position(1) position(2) position(3) 52], ...
                        'Value', {defaultValue});
                otherwise
                    control = uieditfield(parent, 'text', ...
                        'Position', position, ...
                        'Value', defaultValue);
            end
        end

        function rawValue = readInterfaceControlValue(~, control, field)
            if isstruct(control)
                control = control.Primary;
            end

            if strcmp(field.controlType, 'dropdown')
                rawValue = control.Value;
            elseif strcmp(field.controlType, 'multiselect')
                rawValue = cellstr(control.Value);
            elseif strcmp(field.controlType, 'checkbox')
                rawValue = control.Value;
            elseif field.getFile && isa(control, 'matlab.ui.control.TextArea')
                rawValue = cellstr(control.Value);
            elseif isa(control, 'matlab.ui.control.NumericEditField')
                rawValue = control.Value;
            elseif isa(control, 'matlab.ui.control.TextArea')
                rawValue = strjoin(control.Value, ', ');
            else
                rawValue = control.Value;
            end
        end

        function control = createPathPickerControl(obj, parent, field, position, defaultValue)
            browseWidth = 80;
            gap = 8;
            editorWidth = position(3) - browseWidth - gap;
            if editorWidth < 160
                editorWidth = position(3);
                browseWidth = 0;
                gap = 0;
            end

            if strcmp(field.controlType, 'textarea') || field.isList
                primary = uitextarea(parent, ...
                    'Position', [position(1) position(2) editorWidth 52], ...
                    'Value', obj.stringToTextAreaValue(defaultValue));
                buttonY = position(2) + 11;
            else
                primary = uieditfield(parent, 'text', ...
                    'Position', [position(1) position(2) editorWidth position(4)], ...
                    'Value', defaultValue);
                buttonY = position(2);
            end

            control = struct('Primary', primary);
            if browseWidth > 0
                control.Browse = uibutton(parent, 'push', ...
                    'Text', 'Browse', ...
                    'Position', [position(1) + editorWidth + gap buttonY browseWidth 28], ...
                    'ButtonPushedFcn', @(~, ~) obj.onBrowseInterfacePath(control.Primary, field));
            else
                control.Browse = [];
            end
        end

        function onBrowseInterfacePath(obj, control, field)
            startPath = obj.getBrowseStartPath(control, field);

            if field.isList
                [fileName, folder] = uigetfile(field.fileFilter, field.fileDialogTitle, fullfile(startPath, '*'), 'MultiSelect', 'on');
            elseif field.getFile
                [fileName, folder] = uigetfile(field.fileFilter, field.fileDialogTitle, fullfile(startPath, '*'));
            else
                folder = uigetdir(startPath, field.fileDialogTitle);
                if isequal(folder, 0)
                    return
                end
                fileName = [];
            end

            if field.getFile && isequal(fileName, 0)
                return
            end

            if field.getFolder
                selectedPaths = {folder};
            elseif iscell(fileName)
                selectedPaths = cellfun(@(name) fullfile(folder, name), fileName, 'UniformOutput', false);
            else
                selectedPaths = {fullfile(folder, fileName)};
            end

            if field.getFolder
                obj.setLastBrowseDirectory(selectedPaths{1});
            else
                obj.setLastBrowseDirectory(fileparts(selectedPaths{1}));
            end

            if isa(control, 'matlab.ui.control.TextArea')
                control.Value = selectedPaths;
            else
                control.Value = selectedPaths{1};
            end

            if field.getFolder
                obj.LabelStatus.Text = sprintf('Selected folder for %s', field.label);
            else
                obj.LabelStatus.Text = sprintf('Selected %d file(s) for %s', numel(selectedPaths), field.label);
            end
        end

        function startPath = getBrowseStartPath(obj, control, field)
            startPath = obj.getCurrentControlPath(control, field);
            if isempty(startPath)
                startPath = obj.getLastBrowseDirectory();
            end
            if isempty(startPath) || ~isfolder(startPath)
                startPath = obj.getRepositoryRoot();
            end
        end

        function path = getCurrentControlPath(~, control, field)
            path = '';
            if isa(control, 'matlab.ui.control.TextArea')
                values = cellstr(control.Value);
                values = values(~cellfun(@isempty, values));
                if isempty(values)
                    return
                end
                currentValue = values{1};
            else
                currentValue = control.Value;
            end

            if isstring(currentValue)
                currentValue = char(currentValue);
            end
            if isempty(currentValue)
                return
            end

            if field.getFolder
                candidatePath = currentValue;
            else
                candidatePath = fileparts(currentValue);
            end

            if isfolder(candidatePath)
                path = candidatePath;
            end
        end

        function rootPath = getRepositoryRoot(~)
            classFile = mfilename('fullpath');
            rootPath = fileparts(fileparts(fileparts(classFile)));
        end

        function lastPath = getLastBrowseDirectory(~)
            lastPath = getappdata(0, 'EPsych.ProtocolDesigner.LastBrowseDirectory');
            if isempty(lastPath)
                lastPath = '';
            end
        end

        function setLastBrowseDirectory(~, folderPath)
            if isstring(folderPath)
                folderPath = char(folderPath);
            end
            if ~isempty(folderPath) && isfolder(folderPath)
                setappdata(0, 'EPsych.ProtocolDesigner.LastBrowseDirectory', folderPath);
            end
        end

        function values = stringToTextAreaValue(~, textValue)
            if isstring(textValue)
                textValue = char(textValue);
            end

            if isempty(textValue)
                values = {''};
                return
            end

            values = regexp(textValue, '\r\n|\n|\r', 'split');
            if isempty(values)
                values = {textValue};
            end
        end

        function values = parseList(~, rawValue)
            if isstring(rawValue)
                rawValue = char(rawValue);
            end

            parts = regexp(rawValue, '\s*[,;]\s*', 'split');
            parts = parts(~cellfun(@isempty, parts));
            if isempty(parts)
                values = {rawValue};
            else
                values = parts;
            end
        end

        function uniqueName = getUniqueParameterName(~, module, baseName)
            if isstring(baseName)
                baseName = char(baseName);
            end

            baseName = strtrim(baseName);
            if isempty(baseName)
                baseName = 'param';
            end

            existingNames = {module.Parameters.Name};
            uniqueName = baseName;
            suffix = 1;
            while any(strcmp(uniqueName, existingNames))
                uniqueName = sprintf('%s_%d', baseName, suffix);
                suffix = suffix + 1;
            end
        end
    end
end