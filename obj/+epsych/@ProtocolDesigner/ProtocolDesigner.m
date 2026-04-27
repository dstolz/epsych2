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
        LabelStatus matlab.ui.control.Label

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

        SelectedInterfaceRow (1,1) double = 0
        SelectedModuleRow (1,1) double = 0
        SelectedParamRow (1,1) double = 0
        SelectedParamCol (1,1) double = 0
        ParameterHandles cell = {}
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
            obj.refreshUI();

            if nargout == 0
                clear obj
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
