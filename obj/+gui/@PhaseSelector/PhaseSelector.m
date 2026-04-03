classdef PhaseSelector < handle
    % PhaseSelector(RUNTIME, PhasePath)
    % GUI component for selecting and saving experimental phase parameter sets.
    %
    % Loads JSON files from a directory, provides dropdown for phase selection, and button for saving current parameters.
    %
    % Parameters:
    %   RUNTIME   - Main runtime object with read/write parameter methods.
    %   PhasePath - (optional) Directory containing phase JSON files.
    %
    % Example:
    %   ps = gui.PhaseSelector(RUNTIME, 'C:\path\to\phase_files');
    %   parentUI = uipanel(...); % create parent UI container
    %   ps.addPhaseSelect(parentUI, [10 10 150 30]);
    %
    % Properties:
    %   PhasePath      - Directory containing phase JSON files.
    %   CurrentPhase   - Index of currently selected phase.
    %   h_PhaseSelect  - Handle to dropdown UI control.
    %   h_WritePhase   - Handle to write button UI control.
    %   h_Description  - Handle to description label UI control.
    %   RUNTIME        - Main runtime object.
    %   Names          - List of phase file names without extension.
    %   Filenames      - List of phase file names without path.
    %   FullFilenames  - Full paths to phase files.
    %
    % Methods:
    %   PhaseSelector         - Constructor for PhaseSelector class.
    %   addDescriptionLabel   - Add label UI control for description text.
    %   addPhaseSelectDropdown- Add dropdown UI control for phase selection.
    %   addSavePhaseButton    - Add button UI control for saving phase parameters.
    %   createGUI             - Create dropdown and button UI controls for phase selection and saving.
    %   findPhaseFiles        - Load JSON files from PhasePath and update Names and FullFilenames.
    %   readPhaseParameters   - Callback for dropdown value change, loads parameters from selected phase file.
    %   set.PhasePath         - Set method for PhasePath property, loads phase files from new path.
    %   writePhaseParameters  - Save current hardware and software parameters to a new JSON file.
    %
    % See also: documentation/Architecture_Overview.md

    properties (SetObservable)
        PhasePath (1,1) string % Directory containing phase JSON files
        CurrentPhase (1,1) uint8 = 0 % Index of currently selected phase (0 = no phase)
        h_PhaseSelect           % Handle to dropdown UI control
        h_WritePhase            % Handle to write button UI control
        h_Description           % Handle to description label UI control
    end

    properties (SetAccess = private)
        RUNTIME                 % Main runtime object
        Names (1,:) string      % List of phase file names without extension
        Filenames (1,:) string      % List of phase file names without path
        FullFilenames (1,:) string {mustBeFile} % Full paths to phase files
    end



    methods
        function obj = PhaseSelector(RUNTIME, PhasePath)
            % PhaseSelector(RUNTIME, PhasePath)
            % Constructor for PhaseSelector class.
            % Loads phase files from PhasePath if provided.
            %
            % Parameters:
            %   RUNTIME   - Main runtime object
            %   PhasePath - (optional) Directory containing phase JSON files
            arguments
                RUNTIME
                PhasePath (1,1) string = ""
            end
            obj.RUNTIME = RUNTIME;
            obj.PhasePath = PhasePath;
        end


        function set.PhasePath(obj, newPath)
            % set.PhasePath(obj, newPath)
            % Set method for PhasePath property. Loads phase files from new path.
            %
            % Parameters:
            %   newPath - New directory path for phase JSON files
            obj.PhasePath = newPath;
            obj.findPhaseFiles();
        end


        function findPhaseFiles(obj)
            % findPhaseFiles(obj)
            % Loads JSON files from PhasePath and updates Names and FullFilenames.
            % Prompts user to select directory if PhasePath is not set or invalid.
            %
            % Updates:
            %   obj.Names, obj.FullFilenames
            if obj.PhasePath == ""
                [fn,pth] = uigetfile('*.json','Select Directory Containing Phase JSON Files','MultiSelect','off');
                if isequal(fn,0) || isequal(pth,0)
                    vprintf(3,'User canceled directory selection. No phase files loaded.')
                    return
                end
                obj.PhasePath = pth;
            end

            assert(isfolder(obj.PhasePath), 'PhasePath must be a valid directory. Provided: "%s"', obj.PhasePath)

            jsonFiles = dir(fullfile(obj.PhasePath, '*.json'));
            nFiles = numel(jsonFiles);

            % Always prepend the null/default phase
            obj.Names = ["< Select Phase >"];
            obj.Filenames = strings(1, 0); % always string array
            obj.FullFilenames = strings(1, 0); % always string array

            if nFiles > 0
                obj.Filenames = string({jsonFiles.name});
                obj.FullFilenames = string(fullfile({jsonFiles.folder}, {jsonFiles.name}));
                [~,names, ~] = fileparts(string({jsonFiles.name}));
                obj.Names = ["< Select Phase >", names];
                % Do NOT prepend empty string to Filenames/FullFilenames (mustBeFile constraint)
                vprintf(3, 'Found %d phase files from "%s".', nFiles, obj.PhasePath)
            else
                % No files: use string.empty for Filenames/FullFilenames (valid for mustBeFile)
                obj.Filenames = string.empty;
                obj.FullFilenames = string.empty;
                vprintf(3, 'No JSON files found in PhasePath: "%s".', obj.PhasePath)
            end
        end


        function writePhaseParameters(obj, src)
            % writePhaseParameters(obj, src)
            % Save current hardware and software parameters to a new JSON file.
            % Prompts user for a description and file location.
            %
            % Parameters:
            %   src - Source UI control (unused)
            %
            % See also: documentation/Architecture_Overview.md

            %{
            %  modal dialog for description entry
            d = dialog('Position',[300 300 440 210],'Name','Save Parameters','WindowStyle','modal','Color',[1 1 1]);

            % Title
            uicontrol('Parent',d,'Style','text','Position',[0 170 440 30], ...
                'String','Save Parameter Set','FontSize',15,'FontWeight','bold', ...
                'BackgroundColor',[1 1 1],'ForegroundColor',[0.1 0.2 0.4]);

            % Prompt
            uicontrol('Parent',d,'Style','text','Position',[30 120 380 30], ...
                'String','Enter a description for this parameter set:','HorizontalAlignment','left', ...
                'FontSize',12,'BackgroundColor',[1 1 1],'ForegroundColor',[0.1 0.1 0.1]);

            % Description edit box
            descEdit = uicontrol('Parent',d,'Style','edit','Position',[30 90 380 28], ...
                'HorizontalAlignment','left','FontSize',12,'String','', ...
                'BackgroundColor',[0.97 0.97 1]);

            % OK and Cancel buttons
            okBtn = uicontrol('Parent',d,'Style','pushbutton','String','Save','Position',[240 30 80 32], ...
                'FontSize',12,'FontWeight','bold','BackgroundColor',[0.8 0.93 0.8],'Callback','uiresume(gcbf)');
            cancelBtn = uicontrol('Parent',d,'Style','pushbutton','String','Cancel','Position',[330 30 80 32], ...
                'FontSize',12,'BackgroundColor',[0.95 0.85 0.85],'Callback','delete(gcbf)');

            % Add a border around the edit box (simulate with a frame)
            uicontrol('Parent',d,'Style','frame','Position',[28 88 384 32],'BackgroundColor',[0.85 0.88 0.95]);
            % Move edit box to front
            uistack(descEdit,'top');

            movegui(d,'center');
            uiwait(d);
            if ~isvalid(descEdit) || ~isvalid(d)
                vprintf(3,'User canceled description entry.');
                return
            end
            description = string(descEdit.String);
            delete(d);
            %}

            % Use obj.PhasePath as default save path if set, else current directory
            defaultPath = '.';
            if ~isempty(obj.PhasePath) && isfolder(obj.PhasePath)
                defaultPath = obj.PhasePath;
            end
            [fn,pth] = uiputfile('*.json','Save Current Parameters', defaultPath);
            if isequal(fn,0) || isequal(pth,0)
                vprintf(3,'User canceled save operation.');
                return
            end

            filepath = fullfile(pth, fn);
            [~,fn] = fileparts(filepath);
            vprintf(0, 'Writing current parameters to "%s" (%s)', fn, filepath)
            obj.RUNTIME.writeParametersJSON(filepath);
            % obj.RUNTIME.writeParametersJSON(filepath, description);
            % Refresh phase file list and update dropdown if it exists
            obj.findPhaseFiles();
            if ~isempty(obj.h_PhaseSelect) && isvalid(obj.h_PhaseSelect)
                obj.h_PhaseSelect.Items = cellstr(obj.Names);
                obj.h_PhaseSelect.Value = obj.Names(1);
            end
        end


        function readPhaseParameters(obj, src)
            % readPhaseParameters(obj, src)
            % Callback for dropdown value change. Loads parameters from selected phase file.
            %
            % Parameters:
            %   src - Source dropdown UI control
            %
            % Updates:
            %   obj.CurrentPhase
            idx = find(obj.Names == string(src.Value), 1);
            if isempty(idx) || idx == 1 || isempty(obj.FullFilenames) || idx > numel(obj.FullFilenames)+1
                % Null phase selected or no files: update description, disable write button
                obj.CurrentPhase = uint8(0);
                if ~isempty(obj.h_Description)
                    obj.h_Description.Text = "No phase selected. Please select a phase to load its parameters.";
                end

                return
            end

            obj.CurrentPhase = uint8(idx);
            filepath = obj.FullFilenames(idx-1); % idx-1 because Names includes the null entry
            [~,fn] = fileparts(filepath);

            vprintf(0, 'Reading parameters from "%s" (%s)', fn, filepath)
            obj.RUNTIME.readParametersJSON(filepath);

            P = obj.RUNTIME.getAllParameters;

            % REMOVE TRIALTYPE
            P(string({P.Name}) == "TrialType") = [];

            obj.RUNTIME.updateTrialsFromParameters(P);

            % update dropdown value to match selected phase (in case it was changed programmatically)
            src.Value = obj.Names(obj.CurrentPhase);

            % update write button state (enable if valid phase selected)
            if ~isempty(obj.h_WritePhase)
                obj.h_WritePhase.Enable = "on";
            end

            % update description text to show loaded phase description from JSON, if available
            if ~isempty(obj.h_Description)
                desc = "";
                if isprop(obj.RUNTIME, 'Phase') && ~isempty(obj.RUNTIME.Phase) && isfield(obj.RUNTIME.Phase(end), 'Description')
                    desc = obj.RUNTIME.Phase(end).Description;
                end
                if strlength(desc) > 0
                    obj.h_Description.Text = desc;
                else
                    obj.h_Description.Text = sprintf('Loaded phase: %s', obj.Names(obj.CurrentPhase));
                end
            end
        end

        function h = createGUI(obj, parent)
            % createGUI(obj, parent)
            % Creates dropdown and button UI controls for phase selection and saving.
            %
            % Parameters:
            %   parent - Handle to parent UI container (e.g., uifigure, uipanel)
            %
            % Returns:
            %   h - Struct containing handles to created UI controls
            arguments
                obj
                parent {mustBeNonempty} = uifigure
            end

            gl = uigridlayout(parent, [2 2]);
            gl.RowHeight = {30,'fit'};
            gl.ColumnWidth = {'fit',50};

            h.PhaseSelect = obj.addPhaseSelectDropdown(gl);
            h.PhaseSelect.Layout.Row = 1;
            h.PhaseSelect.Layout.Column = 1;

            h.SavePhase = obj.addSavePhaseButton(gl);
            h.SavePhase.Layout.Row = 1;
            h.SavePhase.Layout.Column = 2;

            h.Description = obj.addDescriptionLabel(gl);
            h.Description.Layout.Row = 2;
            h.Description.Layout.Column = [1 2];

            % Set initial dropdown value and disable write button
            if ~isempty(obj.h_PhaseSelect)
                obj.h_PhaseSelect.Value = obj.Names(1);
            end
            
        end


        function h = addSavePhaseButton(obj, parent)
            % h = addSavePhaseButton(obj, parent)
            % Adds a button UI control to parent for saving current phase parameters to file.
            %
            % Parameters:
            %   parent   - Handle to parent container (e.g., uifigure, uipanel)
            %
            % Returns:
            %   h - Handle to created button UI control
            arguments
                obj
                parent {mustBeNonempty} = gcf
            end

            h = uibutton(parent, ...
                'Text', 'Save', ...
                'ButtonPushedFcn', @(src,evt) obj.writePhaseParameters(src));

            obj.h_WritePhase = h;
        end



        function h = addPhaseSelectDropdown(obj, parent)
            % h = addPhaseSelectDropdown(obj, parent)
            % Adds a dropdown UI control to parent for selecting phase files.
            %
            % Parameters:
            %   parent   - Handle to parent container (e.g., uifigure, uipanel)
            %
            % Returns:
            %   h - Handle to created dropdown UI control
            arguments
                obj
                parent {mustBeNonempty} = gcf
            end

            h = uidropdown(parent, ...
                'Items', cellstr(obj.Names), ...
                'Value', obj.Names(1), ...
                'ValueChangedFcn', @(src,evt)obj.readPhaseParameters(src));

            obj.h_PhaseSelect = h;
        end

        function h = addDescriptionLabel(obj, parent)
            % h = addDescriptionLabel(obj, parent)
            % Adds a label UI control to parent for displaying description text.
            %
            % Parameters:
            %   parent   - Handle to parent container (e.g., uifigure, uipanel)
            %
            % Returns:
            %   h - Handle to created label UI control
            arguments
                obj
                parent {mustBeNonempty} = gcf
            end

            descriptionText = "No phase selected. Please select a phase to load its parameters.";
            h = uilabel(parent, ...
                'Text', descriptionText);

            obj.h_Description = h;
        end

    end


end
