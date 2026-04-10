classdef ProtocolDesigner < handle
    % epsych.ProtocolDesigner(protocol)
    % Edit epsych.Protocol objects with interface-aware parameter editing,
    % protocol option controls, and compiled trial preview tables.
    %
    % Important properties:
    %  Protocol		- Protocol model currently bound to the UI.
    %  TableParams	- Parameter table with inline editing and error styling.
    %  TableCompiled	- Preview table populated after compile().
    %
    % Key methods:
    %  refreshUI		- Reload all visible controls from the bound protocol.
    %  onCompile		- Compile the current protocol and update preview data.
    %  onSave		- Save the bound protocol to an .eprot file.
    %  onLoad		- Load a protocol from disk and rebuild the visible state.
    %
    % See also documentation/design/ProtocolDesigner.md for workflow details.
    %
    % Example:
    %  gui = epsych.ProtocolDesigner();
    %  gui = epsych.ProtocolDesigner(protocolObj);

    properties
        Figure matlab.ui.Figure
        Protocol (1,1) epsych.Protocol

        MainPanel matlab.ui.container.Panel

        EditInfo matlab.ui.control.EditField
        BtnSave matlab.ui.control.Button
        BtnLoad matlab.ui.control.Button
        LabelStatus matlab.ui.control.Label

        DropDownInterfaceType matlab.ui.control.DropDown
        LabelInterfaceDescription matlab.ui.control.Label
        DropDownInterfaceFilter matlab.ui.control.DropDown
        DropDownTargetInterface matlab.ui.control.DropDown
        DropDownTargetModule matlab.ui.control.DropDown
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
        ParameterHandles cell = {}
    end

    methods
        function obj = ProtocolDesigner(protocol)
            % ProtocolDesigner(protocol)
            % Construct the designer and bind it to a protocol instance.
            % Creates the UI immediately and populates controls from Protocol.
            %
            % Parameters:
            % 	protocol	- epsych.Protocol instance to edit (default: new protocol).
            if nargin < 1 || isempty(protocol)
                obj.Protocol = epsych.Protocol();
            else
                obj.Protocol = protocol;
            end

            obj.buildUI();
            obj.refreshUI();
        end

    end
end
