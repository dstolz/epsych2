classdef ProtocolDesigner < handle
    % epsych.ProtocolDesigner(protocol)
    % Edit epsych.Protocol objects from a dedicated UI for interfaces,
    % parameters, protocol options, and compiled trial preview data.
    %
    % Important properties:
    % 	Protocol        - Protocol instance currently bound to the designer.
    % 	TableParams     - Parameter table for interface and module settings.
    % 	TableCompiled   - Trial preview table populated after compilation.
    %
    % Function tree:
    %
    %   ProtocolDesigner          - Constructor; binds protocol and builds UI.
    %   openFromFile              - (Static) Load a .eprot file and open in designer.
    %
    %   UI construction
    %   ├─ buildUI                - Create the top-level figure and persistent controls.
    %   ├─ buildOptionsTab        - Build the Options tab controls (reps, ISI, flags).
    %   ├─ buildParametersTab     - Build the Parameters tab controls and table.
    %   └─ buildPreviewTab        - Build the compiled-preview tab controls.
    %
    %   UI refresh
    %   ├─ refreshUI                   - Reload all visible controls from Protocol state.
    %   ├─ refreshInterfaceControls    - Refresh interface type/description controls.
    %   ├─ refreshInterfaceSummary     - Update the interface summary label below the tree.
    %   ├─ refreshModuleActionButtons  - Enable/disable module add/remove buttons.
    %   ├─ refreshOptionsTab           - Sync Options tab controls with Protocol properties.
    %   ├─ refreshParameterTab         - Sync Parameters tab with the current interface.
    %   ├─ refreshParameterTable       - Rebuild parameter table rows from the model.
    %   ├─ refreshTargetModuleControls - Refresh target interface/module dropdowns.
    %   └─ refreshCompiledPreview      - Rebuild the compiled-preview table.
    %
    %   User actions (callbacks)
    %   ├─ onLoad                       - Prompt to load a protocol file from disk.
    %   ├─ onSave                       - Save the protocol (prompt if no current path).
    %   ├─ onCompile                    - Compile the protocol and refresh preview.
    %   ├─ onEditInfo                   - Handle edits to the protocol name field.
    %   ├─ onInfoChanged                - Sync UI title after protocol info changes.
    %   ├─ onAddInterface               - Add the selected interface spec to the protocol.
    %   ├─ onRemoveInterface            - Remove the selected interface from the protocol.
    %   ├─ onModifyInterfaceOptions     - Open interface options dialog for selection.
    %   ├─ onAddModule                  - Add a new module to the selected interface.
    %   ├─ onRemoveModule               - Remove the selected module from its interface.
    %   ├─ onAddParam                   - Add a new parameter row to the parameter table.
    %   ├─ onRemoveParam                - Remove the selected parameter row.
    %   ├─ onParamEdited                - Apply an in-table parameter edit to the model.
    %   ├─ onParamSelected              - Handle parameter row/cell selection changes.
    %   ├─ onBrowseSelectedFileParameter- Open file browser for the selected File parameter.
    %   ├─ onInterfaceFilterChanged     - Respond to filter dropdown change; refresh table.
    %   ├─ onInterfaceRegistrySelected  - Respond to selection of an interface in the tree.
    %   ├─ onInterfaceSpecChanged       - Respond to a change in the interface type dropdown.
    %   ├─ onTargetInterfaceChanged     - Respond to changes in the target interface dropdown.
    %   ├─ onOptionControlChanged       - Respond to a change in an option control value.
    %   ├─ onOpenOptionsDialog          - Open the module options dialog.
    %   ├─ onOpenCompiledPreviewDialog  - Open the full compiled preview in a modal dialog.
    %   ├─ onOpenDocumentation          - Open documentation for the selected interface.
    %   └─ onOpenAsJSON                 - Serialize protocol to temp JSON and open in editor.
    %
    %   Queries (public getters)
    %   ├─ getAddableInterfaceSpecs          - Return interface specs that can be added.
    %   ├─ getCompiledWriteParamType         - Return write-param type for one compiled column.
    %   ├─ getCompiledWriteParamTypes        - Return write-param types for all compiled columns.
    %   ├─ getFileNameDisplayText            - Return display text for the current file path.
    %   ├─ getTrialFunctionPathWarning       - Return warning if the trial function path is bad.
    %   ├─ normalizeCompiledPreviewData      - Normalize compiled trial data for the preview table.
    %   ├─ normalizeCompiledPreviewValue     - Normalize a single compiled preview cell value.
    %   ├─ normalizeCompiledPreviewValueAsText - Convert a compiled preview value to display text.
    %   ├─ setStatus                         - Update the footer status label.
    %   └─ suggestNextStep                   - Return a short next-step hint for the current state.
    %
    %   Private helpers (private/)
    %
    %     Persistence
    %     ├─ addRecentProtocolPath        - Persist a path to the recent-protocols preference.
    %     ├─ removeRecentProtocolPath     - Remove a path from the recent-protocols preference.
    %     ├─ getRecentProtocolPaths       - Read the recent-protocols list from preferences.
    %     ├─ getLastProtocolFilePath      - Read the last-used protocol file path from prefs.
    %     ├─ setLastProtocolFilePath      - Persist the last-used protocol file path.
    %     ├─ getLastBrowseDirectory       - Read the last-used browse directory from prefs.
    %     ├─ setLastBrowseDirectory       - Persist the last-used browse directory.
    %     ├─ getRepositoryRoot            - Locate the epsych2 repository root directory.
    %     ├─ refreshRecentProtocolMenu    - Repopulate the Recent Protocols submenu.
    %     └─ onOpenRecentProtocol         - Load a protocol from a recent-protocols menu entry.
    %
    %     File / path helpers
    %     ├─ openProtocolFile             - Execute the full open-and-bind flow for a file.
    %     ├─ getProtocolFileDialogStartPath - Determine start path for protocol file dialogs.
    %     ├─ getBrowseStartPath           - Determine start directory for file browse dialogs.
    %     ├─ getShortDisplayPath          - Shorten a file path to a display-friendly string.
    %     ├─ getDocumentationPath         - Resolve the documentation path for an interface.
    %     ├─ buildFileFilterFromExtensions - Convert extension list to a uigetfile filter spec.
    %     ├─ normalizeDialogFileFilter    - Normalize a file filter for uigetfile/uiputfile.
    %     ├─ validateDialogSelectionPaths - Validate that file-dialog selections are accessible.
    %     └─ onBrowseInterfacePath        - Open a file browser for an interface path field.
    %
    %     Interface helpers
    %     ├─ getAvailableInterfaceSpecs   - Return all registered interface specs (filtered).
    %     ├─ getSelectedInterfaceSpec     - Return the spec for the currently selected interface.
    %     ├─ getSelectedInterfaceRowIndex - Return the row index of the selected interface.
    %     ├─ getInterfaceIndexFromTreeNode - Resolve an interface index from a tree node.
    %     ├─ getInterfaceEditState        - Return enabled/disabled state for interface buttons.
    %     ├─ getInterfaceItems            - Build display items for the interface tree.
    %     ├─ canEditInterfaceModules      - Return true if the interface allows module editing.
    %     ├─ interfaceLabel               - Format the display label for an interface node.
    %     ├─ isMissingInterfaceOption     - Return true if a required interface option is unset.
    %     ├─ describeInterfaceField       - Return a human-readable description of a field.
    %     ├─ formatInterfaceDefault       - Format an interface field default value for display.
    %     ├─ refreshInterfaceBuilder      - Rebuild interface-option controls for the selection.
    %     ├─ createInterfaceOptionControl - Build a uicontrol for one interface option field.
    %     ├─ readInterfaceControlValue    - Read the current value from an option control.
    %     ├─ parseInterfaceOptionValue    - Parse a raw value from an interface option control.
    %     ├─ editInterfaceOptionValue     - Apply a new value to one option in an interface.
    %     ├─ formatInterfaceOptionDisplayValue - Format an option value for the options dialog.
    %     ├─ applyUpdatedModuleOptions    - Write edited option values back to the module.
    %     ├─ promptForInterfaceOptions    - Show a dialog to collect required interface options.
    %     ├─ selectedFilterIndex          - Return the current interface-filter dropdown index.
    %     └─ selectedTargetInterfaceIndex - Return the selected target interface index.
    %
    %     Module helpers
    %     ├─ getModuleEditState           - Return enabled/disabled state for module buttons.
    %     ├─ getModuleIndexFromTreeNode   - Resolve a module index from a tree node.
    %     ├─ getSelectedModuleRow         - Return the row index of the selected module.
    %     ├─ getSelectedTargetModule      - Return the module struct for the target module.
    %     ├─ setSelectedModuleRow         - Set the selected module row and update controls.
    %     ├─ getTargetModuleItems         - Build dropdown items for the target-module selector.
    %     ├─ moduleDisplayLabel           - Format the display label for a module node.
    %     ├─ getUniqueModuleText          - Return a unique display label for a module.
    %     ├─ getUniqueModuleTextForEdit   - Return a unique editable label for a module rename.
    %     ├─ cloneModulesToInterface      - Copy modules from one interface to another.
    %     ├─ replaceInterfaceModules      - Replace all modules in an interface with a new set.
    %     ├─ getSingleModuleOptionNumeric - Read one option value from a module as a number.
    %     ├─ getSingleModuleOptionText    - Read one option value from a module as a string.
    %     └─ createPathPickerControl      - Build a path-picker row (edit + browse button).
    %
    %     Parameter helpers
    %     ├─ getAllParameters              - Collect all parameters across interfaces as a flat array.
    %     ├─ getSelectedParameter         - Return the parameter struct at the current selection.
    %     ├─ getUniqueParameterName       - Return a unique parameter name (deduplicates existing).
    %     ├─ validateParameterName        - Validate a name and return an error message if invalid.
    %     ├─ getParameterTableData        - Build the full cell array of parameter table data.
    %     ├─ getParameterValueDisplay     - Return a truncated display string for a value.
    %     ├─ getParameterValueFull        - Return the complete, untruncated value string.
    %     ├─ getTypeOptions               - Return type option strings for parameter type dropdowns.
    %     ├─ getAccessOptions             - Return R/W access option strings for dropdowns.
    %     ├─ resolveParameterTargetModule - Map a parameter to its assigned target module index.
    %     ├─ sanitizeParameterTrigger     - Validate and clear invalid trigger assignments.
    %     ├─ parameterAllowsTrigger       - Return true if the parameter type allows a trigger.
    %     ├─ editParameterFileValue       - Open the modal file-value editor for a File parameter.
    %     ├─ editParameterStringValue     - Open the modal string-value editor for a String parameter.
    %     ├─ promptForParameterFileValue  - Show the file-selector dialog for a File parameter.
    %     ├─ getParameterFileConfig       - Return the file-selection config for a File parameter.
    %     ├─ getParameterFileList         - Return the current file list for a File parameter.
    %     ├─ getParameterFileStartPath    - Determine the start directory for a File parameter browser.
    %     ├─ isFileLikeValue              - Return true if a value looks like a file path.
    %     ├─ normalizeFileValueToList     - Normalize a file parameter value to a cell array.
    %     ├─ resolveFileSelectionMode     - Determine single vs. multi-file selection mode.
    %     ├─ getFileDisplayItems          - Build display items for the file-selection list.
    %     ├─ getFileSelectionCountText    - Return a summary string for the file selection count.
    %     ├─ getFilePreviewLines          - Read the first few lines of a file for preview.
    %     ├─ validateDialogSelectionPaths - Validate that file-dialog selections are accessible.
    %     ├─ formatStringParameterValue   - Format a string parameter value for table display.
    %     ├─ parseStringParameterValue    - Parse a raw string from a table cell into a value.
    %     ├─ parseValue                   - Parse a string representation into a typed value.
    %     ├─ parseList                    - Split a delimited string into trimmed tokens.
    %     └─ parseNumericList             - Parse a string into a numeric vector.
    %
    %     Pair helpers
    %     ├─ getParameterPair             - Return the pair struct for a paired parameter.
    %     ├─ setParameterPair             - Update the pair group assignment for a parameter.
    %     ├─ getPairDisplayValue          - Format a parameter pair value for table display.
    %     ├─ getPairDropdownOptions        - Build dropdown items for a paired-parameter column.
    %     ├─ promptForNewPairName         - Show an input dialog for a new pair name.
    %     └─ validatePairedParameterLengths - Collect errors for pairs with mismatched value counts.
    %
    %     Expression helpers
    %     ├─ buildExpressionContext       - Build the variable context used during evaluation.
    %     ├─ getExpressionAliases         - Return alias-to-parameter mappings for evaluation.
    %     ├─ getQualifiedExpressionAlias  - Qualify a short alias to a fully-scoped reference.
    %     ├─ resolveQualifiedExpressionReference - Resolve a qualified alias to a parameter value.
    %     ├─ evaluateParameterExpression  - Evaluate one expression against current parameters.
    %     ├─ evaluateAndApplyParameterExpression - Evaluate and store the result of an expression.
    %     ├─ refreshExpressionValues      - Re-evaluate and display all active expressions.
    %     ├─ getParameterExpression       - Read the stored expression for a parameter.
    %     ├─ setParameterExpression       - Store an expression string on a parameter.
    %     ├─ clearParameterExpression     - Remove the expression from a parameter.
    %     ├─ hasParameterExpression       - Return true if the parameter has an active expression.
    %     ├─ normalizeExpressionResult    - Normalize the raw expression result to a string.
    %     ├─ getExpressionErrorMessage    - Build an error message string for an expression failure.
    %     ├─ applyExpressionErrorStyles   - Apply cell styles to highlight expression errors.
    %     ├─ setExpressionErrors          - Store and display expression error state.
    %     ├─ validateExpressionReferences - Check that all expression aliases resolve correctly.
    %     ├─ parameterCanParticipateInExpression - Return true if a param can be an expression term.
    %     └─ parameterSupportsExpression  - Return true if the parameter type supports expressions.
    %
    %     Miscellaneous helpers
    %     ├─ coerceLogicalValue           - Cast a value to logical with fallback.
    %     ├─ coerceNumericValue           - Cast a value to double with fallback.
    %     ├─ coerceValueForType           - Coerce a raw value to the expected parameter type.
    %     ├─ onOffForCondition            - Return "on"/"off" string from a logical condition.
    %     ├─ getCurrentControlPath        - Return the path of the currently selected tree node.
    %     ├─ makeUniqueDisplayItems       - Deduplicate and suffix display item labels.
    %     ├─ parseIndexedLabel            - Parse an indexed label string to name and index.
    %     ├─ stringToTextAreaValue        - Convert a string to a textarea-compatible cell array.
    %     └─ showCompileFailure           - Report a compile failure with validation context.
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
