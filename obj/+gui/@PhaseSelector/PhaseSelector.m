classdef PhaseSelector < handle
    % PhaseSelector(RUNTIME, PhasePath)
    % GUI component for selecting and saving experimental phases.
    %
    % Phases and protocols share one format: a phase file is a protocol file
    % (.eprot/.prot; see epsych.Protocol). Saving a phase serializes the session's
    % protocol with the current parameter values (Runtime.writeParametersProtocol);
    % loading a phase reads a protocol and applies its parameters to the live
    % session (Runtime.readParameters). Legacy JSON parameter snapshots remain
    % loadable. Selecting a phase in the dropdown prints its parameter changes to
    % the command window.
    %
    % Parameters:
    %   RUNTIME   - Main runtime object with read/write parameter methods.
    %   PhasePath - (optional) Directory containing phase files.
    %
    % Example:
    %   ps = gui.PhaseSelector(RUNTIME, 'C:\path\to\phase_files');
    %   parentUI = uipanel(...); % create parent UI container
    %   ps.addPhaseSelect(parentUI, [10 10 150 30]);
    %
    % Properties:
    %   PhasePath      - Directory containing phase files.
    %   CurrentPhase   - Index of currently loaded phase.
    %   h_PhaseSelect  - Handle to dropdown UI control.
    %   h_LoadPhase    - Handle to load button UI control.
    %   h_WritePhase   - Handle to write button UI control.
    %   h_Description  - Handle to description label UI control.
    %   RUNTIME        - Main runtime object.
    %   Names          - List of phase file names without extension.
    %   Filenames      - List of phase file names without path.
    %   FullFilenames  - Full paths to phase files.
    %   LastLoadedFile - File name of the most recently loaded phase.
    %   LastLoadedTime - Time the most recently loaded phase was loaded.
    %
    % Methods:
    %   PhaseSelector          - Constructor for PhaseSelector class.
    %   addDescriptionLabel    - Add label UI control for description text.
    %   addPhaseSelectDropdown - Add dropdown UI control for phase selection.
    %   addLoadPhaseButton     - Add button UI control for loading the selected phase.
    %   addSavePhaseButton     - Add button UI control for saving phase parameters.
    %   createGUI              - Create dropdown and button UI controls for phase selection, loading, and saving.
    %   findPhaseFiles         - Load phase files from PhasePath and update Names and FullFilenames.
    %   onPhaseSelectionChanged- Callback for dropdown value change; updates state without loading, and prints the phase's parameter changes.
    %   loadPhaseParameters    - Load parameters from the selected phase file into the runtime.
    %   showPhaseInfo          - Print a table of the parameter changes the selected phase would apply.
    %   set.PhasePath          - Set method for PhasePath property, loads phase files from new path.
    %   writePhaseParameters   - Save the current session as a protocol (.eprot) phase file.
    %   withLastLoaded         - Append the most-recently-loaded phase file name and load time to info text.
    %
    % See also: documentation/overviews/Architecture_Overview.md

    properties (SetObservable)
        PhasePath (1,1) string % Directory containing phase files (.eprot/.prot protocols; legacy .json)
        CurrentPhase (1,1) uint8 = 0 % Index of currently loaded phase (0 = no phase)
        h_PhaseSelect           % Handle to dropdown UI control
        h_LoadPhase             % Handle to load button UI control
        h_WritePhase            % Handle to write button UI control
        h_Description           % Handle to description label UI control
    end

    properties (SetAccess = private)
        RUNTIME                 % Main runtime object
        Names (1,:) string      % List of phase file names without extension
        Filenames (1,:) string      % List of phase file names without path
        FullFilenames (1,:) string {mustBeFile} % Full paths to phase files
        LastLoadedFile (1,1) string = ""      % File name (with extension) of the most recently loaded phase
        LastLoadedTime (1,1) datetime = NaT   % Time the most recently loaded phase was loaded
    end



    methods
        function obj = PhaseSelector(RUNTIME, PhasePath)
            % PhaseSelector(RUNTIME, PhasePath)
            % Constructor for PhaseSelector class.
            % Loads phase files from PhasePath if provided.
            %
            % Parameters:
            %   RUNTIME   - Main runtime object
            %   PhasePath - (optional) Directory containing phase files
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
            %   newPath - New directory path for phase files
            obj.PhasePath = newPath;
            obj.findPhaseFiles();
        end


        function findPhaseFiles(obj)
            % findPhaseFiles(obj)
            % Loads phase files (.eprot/.prot protocols, plus legacy .json snapshots)
            % from PhasePath and updates Names and FullFilenames.
            % Prompts user to select directory if PhasePath is not set or invalid.
            %
            % Updates:
            %   obj.Names, obj.FullFilenames
            if obj.PhasePath == ""
                [fn,pth] = uigetfile({'*.eprot;*.prot;*.json','Phase Files (*.eprot, *.prot, *.json)'}, ...
                    'Select Directory Containing Phase Files','MultiSelect','off');
                if isequal(fn,0) || isequal(pth,0)
                    vprintf(3,'User canceled directory selection. No phase files loaded.')
                    return
                end
                obj.PhasePath = pth;
            end

            assert(isfolder(obj.PhasePath), 'PhasePath must be a valid directory. Provided: "%s"', obj.PhasePath)

            phaseFiles = [dir(fullfile(obj.PhasePath, '*.eprot')); ...
                          dir(fullfile(obj.PhasePath, '*.prot')); ...
                          dir(fullfile(obj.PhasePath, '*.json'))];
            % One alphabetical list regardless of extension, so a phase keeps its
            % dropdown position when it is resaved in the protocol format.
            [~, order] = sort(lower({phaseFiles.name}));
            phaseFiles = phaseFiles(order);
            nFiles = numel(phaseFiles);

            % Always prepend the null/default phase
            obj.Names = ["< Select Phase >"];
            obj.Filenames = strings(1, 0); % always string array
            obj.FullFilenames = strings(1, 0); % always string array

            if nFiles > 0
                obj.Filenames = string({phaseFiles.name});
                obj.FullFilenames = string(fullfile({phaseFiles.folder}, {phaseFiles.name}));
                [~,names, ~] = fileparts(string({phaseFiles.name}));
                obj.Names = ["< Select Phase >", names];
                % Do NOT prepend empty string to Filenames/FullFilenames (mustBeFile constraint)
                vprintf(3, 'Found %d phase files from "%s".', nFiles, obj.PhasePath)
            else
                % No files: use string.empty for Filenames/FullFilenames (valid for mustBeFile)
                obj.Filenames = string.empty;
                obj.FullFilenames = string.empty;
                vprintf(3, 'No phase files found in PhasePath: "%s".', obj.PhasePath)
            end
        end


        function writePhaseParameters(obj, src)
            % writePhaseParameters(obj, src)
            % Save the current session as a protocol (.eprot) phase file.
            % Prompts user for a file location. Because the runtime borrows the
            % session protocol's parameter handles, the saved protocol is an exact
            % snapshot of the current parameter values, and the file can also be
            % opened and edited in epsych.ProtocolDesigner.
            %
            % Parameters:
            %   src - Source UI control (unused)
            %
            % See also: epsych.Runtime.writeParametersProtocol

            % Use obj.PhasePath as default save path if set, else current directory
            defaultPath = '.';
            if ~isempty(obj.PhasePath) && isfolder(obj.PhasePath)
                defaultPath = obj.PhasePath;
            end
            [fn,pth] = uiputfile({'*.eprot','Phase Protocol (*.eprot)'},'Save Current Parameters', defaultPath);
            if isequal(fn,0) || isequal(pth,0)
                vprintf(3,'User canceled save operation.');
                return
            end

            filepath = fullfile(pth, fn);
            [~,fn] = fileparts(filepath);
            vprintf(0, 'Writing current parameters to "%s" (%s)', fn, filepath)
            obj.RUNTIME.writeParametersProtocol(filepath);

            % Refresh phase file list and update dropdown if it exists
            obj.findPhaseFiles();
            if ~isempty(obj.h_PhaseSelect) && isvalid(obj.h_PhaseSelect)
                obj.h_PhaseSelect.Items = cellstr(obj.Names);
                obj.h_PhaseSelect.Value = obj.Names(1);
            end
        end


        function onPhaseSelectionChanged(obj, src)
            % onPhaseSelectionChanged(obj, src)
            % Callback for dropdown value change. Updates the selection state and enables
            % the Load button, but does NOT apply any parameters. Loading happens only
            % when the user presses the Load button (see loadPhaseParameters). Also prints
            % the newly selected phase's parameter changes to the command window (see
            % showPhaseInfo).
            %
            % Parameters:
            %   src - Source dropdown UI control
            [~, idx, phaseName] = obj.selectedPhaseFile();

            enable = matlab.lang.OnOffSwitchState(idx > 0);
            if ~isempty(obj.h_LoadPhase) && isvalid(obj.h_LoadPhase)
                obj.h_LoadPhase.Enable = enable;
            end

            if ~isempty(obj.h_Description) && isvalid(obj.h_Description)
                if idx == 0
                    obj.h_Description.Text = obj.withLastLoaded("No phase selected. Select a phase, then press Load to apply its parameters.");
                else
                    obj.h_Description.Text = obj.withLastLoaded(sprintf('Phase "%s" selected. Press Load to apply its parameters.', phaseName));
                end
            end

            if idx > 0
                obj.showPhaseInfo(src);
            end
        end


        function loadPhaseParameters(obj, ~)
            % loadPhaseParameters(obj)
            % Load parameters from the currently selected phase file into the runtime.
            % Invoked by the Load button. Reads the selection from the dropdown, applies the
            % resolved parameters to TRIALS, and updates the description. readParameters
            % also schedules a protocol recompile at the next safe trial boundary, so
            % design-time changes carried by the phase (Values lists, Expressions)
            % regenerate the trial table rather than only patching current values.
            %
            % Updates:
            %   obj.CurrentPhase
            [filepath, idx, phaseName] = obj.selectedPhaseFile();
            if idx == 0
                vprintf(1, 'No phase selected to load. Select a phase first.')
                return
            end

            obj.CurrentPhase = uint8(idx);
            [~,fn] = fileparts(filepath);

            vprintf(0, 'Reading parameters from "%s" (%s)', fn, filepath)

            % Announce the load with a modal dialog so it is obvious that parameters are
            % changing under the user. onCleanup guarantees the dialog is dismissed on
            % return or error -- a stranded modal would otherwise block the whole app.
            dlg = obj.openLoadDialog(phaseName);
            closeDlg = onCleanup(@() obj.closeLoadDialog(dlg));

            % Snapshot the current value of every parameter this phase targets BEFORE the
            % load mutates them (readParameters writes the live parameters in place). We
            % use it below to keep only the parameters the phase actually changes.
            before = obj.resolvePhaseAgainstRuntime(filepath);

            % readParameters resolves the file entries to live parameters and returns them
            % (with restored values). Use the returned set directly; re-reading via all_parameters
            % here would discard the loaded values.
            P = obj.RUNTIME.readParameters(filepath);

            % REMOVE TRIALTYPE
            P(string({P.Name}) == "TrialType") = [];

            % Keep only the parameters the phase actually changed. Comparing each parameter's
            % post-load value against the pre-load snapshot (matched by handle identity) means
            % unchanged parameters are not re-applied to TRIALS, avoiding a needless trial
            % re-dispatch. StimType values are not reliably comparable, so they are always kept;
            % parameters missing from the snapshot (e.g. write-only) are also kept to be safe.
            P = obj.keepChangedParameters(P, before);

            % Show exactly which parameters are being applied before writing them, so the
            % dialog reflects the pending change while updateTrialsFromParameters runs.
            obj.updateLoadDialog(dlg, phaseName, P);

            if isempty(P)
                vprintf(1, 'Phase "%s" loaded; no parameter values differed from the current session.', phaseName)
            else
                obj.RUNTIME.updateTrialsFromParameters(P);
            end

            % Changes are applied -- closeDlg (onCleanup) dismisses the dialog on return.

            % Record this as the most recently loaded phase so the info box can report the file
            % name and load time even after the dropdown selection later changes.
            [~, loadedName, loadedExt] = fileparts(filepath);
            obj.LastLoadedFile = loadedName + loadedExt;
            obj.LastLoadedTime = datetime('now', Format='HH:mm:ss');

            % update description text to show loaded phase description from JSON, if available
            if ~isempty(obj.h_Description)
                desc = "";
                if isprop(obj.RUNTIME, 'Phase') && ~isempty(obj.RUNTIME.Phase) && isfield(obj.RUNTIME.Phase(end), 'Description')
                    desc = obj.RUNTIME.Phase(end).Description;
                end
                if strlength(desc) > 0
                    baseText = string(desc);
                else
                    baseText = string(sprintf('Loaded phase: %s', phaseName));
                end
                if isempty(P)
                    baseText = baseText + " (no parameter changes)";
                end
                obj.h_Description.Text = obj.withLastLoaded(baseText);
            end
        end


        function showPhaseInfo(obj, ~)
            % showPhaseInfo(obj)
            % Print a table to the command window listing the parameters whose values would
            % change if the currently selected phase were loaded. Non-destructive: current
            % parameter values are read but nothing is applied to the runtime. Invoked
            % automatically by onPhaseSelectionChanged whenever a new phase is selected.
            [filepath, idx, phaseName] = obj.selectedPhaseFile();
            if idx == 0
                vprintf(1, 'No phase selected. Select a phase to preview its parameter changes.')
                return
            end

            T = obj.computePhaseChanges(filepath);

            if isempty(T)
                vprintf(0, 'Phase "%s" would not change any parameter values.', phaseName)
                return
            end

            vprintf(0, 'Phase "%s" would change %d parameter(s):', phaseName, height(T))
            disp(T)
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

            gl = uigridlayout(parent, [2 3]);
            gl.RowHeight = {30,'fit'};
            gl.ColumnWidth = {'1x',55,55};

            h.PhaseSelect = obj.addPhaseSelectDropdown(gl);
            h.PhaseSelect.Layout.Row = 1;
            h.PhaseSelect.Layout.Column = 1;

            h.LoadPhase = obj.addLoadPhaseButton(gl);
            h.LoadPhase.Layout.Row = 1;
            h.LoadPhase.Layout.Column = 2;

            h.SavePhase = obj.addSavePhaseButton(gl);
            h.SavePhase.Layout.Row = 1;
            h.SavePhase.Layout.Column = 3;

            h.Description = obj.addDescriptionLabel(gl);
            h.Description.Layout.Row = 2;
            h.Description.Layout.Column = [1 3];

            % Start on the null entry with Load/Info disabled until a phase is selected.
            if ~isempty(obj.h_PhaseSelect)
                obj.h_PhaseSelect.Value = obj.Names(1);
            end
            obj.onPhaseSelectionChanged(obj.h_PhaseSelect);

        end


        function h = addLoadPhaseButton(obj, parent)
            % h = addLoadPhaseButton(obj, parent)
            % Adds a button UI control to parent for loading the selected phase's parameters.
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
                'Text', 'Load', ...
                'Enable', 'off', ...
                'Tooltip', 'Apply the selected phase''s parameters to the current session', ...
                'ButtonPushedFcn', @(src,evt) obj.loadPhaseParameters(src));

            obj.h_LoadPhase = h;
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
                'ValueChangedFcn', @(src,evt)obj.onPhaseSelectionChanged(src));

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
                'Text', descriptionText, ...
                'WordWrap', 'on');

            obj.h_Description = h;
        end

    end


    methods (Access = private)
        function txt = withLastLoaded(obj, baseText)
            % txt = withLastLoaded(obj, baseText)
            % Append a line noting the most recently loaded phase file and the time it was
            % loaded to baseText, so the info box always reports the last load even after the
            % dropdown selection changes. Returns baseText unchanged (as a scalar string) when
            % no phase has been loaded yet.
            %
            % Parameters:
            %   baseText - Text to show above the last-loaded line (string or char)
            %
            % Returns:
            %   txt - Info text for h_Description.Text (2x1 string array when a load has occurred)
            txt = string(baseText);
            if strlength(obj.LastLoadedFile) == 0
                return
            end
            lastLine = sprintf('Loaded "%s" at %s', obj.LastLoadedFile, string(obj.LastLoadedTime));
            txt = [txt; string(lastLine)];
        end


        function [filepath, idx, phaseName] = selectedPhaseFile(obj)
            % [filepath, idx, phaseName] = selectedPhaseFile(obj)
            % Resolve the phase currently chosen in the dropdown to its file.
            %
            % Returns:
            %   filepath  - Full path to the selected phase file, or "" if none.
            %   idx       - Index into obj.Names (0 if the null entry or nothing is selected).
            %   phaseName - Display name of the selected phase, or "" if none.
            filepath = ""; idx = 0; phaseName = "";
            if isempty(obj.h_PhaseSelect) || ~isvalid(obj.h_PhaseSelect)
                return
            end
            sel = find(obj.Names == string(obj.h_PhaseSelect.Value), 1);
            % idx == 1 is the "< Select Phase >" null entry; anything past the
            % available files (Names has one extra leading entry) is invalid.
            if isempty(sel) || sel == 1 || isempty(obj.FullFilenames) || sel-1 > numel(obj.FullFilenames)
                return
            end
            idx = sel;
            filepath = obj.FullFilenames(idx-1); % idx-1 because Names includes the null entry
            phaseName = obj.Names(idx);
        end


        function T = computePhaseChanges(obj, filepath)
            % T = computePhaseChanges(obj, filepath)
            % Compute, without applying anything, which live parameters would change if the
            % phase file were loaded. Mirrors the resolution used by readParameters but
            % only reads current parameter values, so it is safe to call at any time.
            %
            % Returns:
            %   T - Table with columns Interface, Parameter, Current, New listing only the
            %       parameters whose applied value would differ from the current value. Empty
            %       table if nothing would change or the file cannot be parsed.
            Interface = strings(0,1);
            Parameter = strings(0,1);
            Current   = strings(0,1);
            New       = strings(0,1);

            R = obj.resolvePhaseAgainstRuntime(filepath);
            for k = 1:numel(R)
                r = R(k);

                % Read-only parameters are never written and StimType values are not simply
                % comparable, so exclude both from the preview. Write-only parameters have no
                % readable current value to compare against.
                if ~r.HasCurrent || strcmp(r.Param.Access,'Read') || strcmp(r.Param.Type,'StimType')
                    continue
                end

                if isequaln(r.Current, r.New), continue, end

                Interface(end+1,1) = r.ParentType;
                Parameter(end+1,1) = string(r.Param.Name);
                Current(end+1,1)   = obj.formatValue(r.Current);
                New(end+1,1)       = obj.formatValue(r.New);
            end

            T = table(Interface, Parameter, Current, New);
        end


        function R = resolvePhaseAgainstRuntime(obj, filepath)
            % R = resolvePhaseAgainstRuntime(obj, filepath)
            % Resolve each parameter entry in a phase file to the live hw.Parameter it targets
            % and capture that parameter's current value alongside the value the phase would
            % apply. Non-destructive: nothing is written to the runtime, so this is safe both
            % for previewing changes (computePhaseChanges) and for deciding which parameters an
            % actual load must update (loadPhaseParameters). Matches the resolution used by
            % readParameters (interface by ParentType, parameter by Name).
            %
            % Parameters:
            %   filepath - Full path to a phase file (.eprot/.prot or legacy .json).
            %
            % Returns:
            %   R - struct array (empty if nothing resolves) with fields:
            %         Param      - live hw.Parameter handle targeted by the entry
            %         ParentType - owning interface Type (string)
            %         Current    - current parameter value, or [] when not readable
            %         HasCurrent - false for write-only parameters whose value can't be read
            %         New        - value the phase would apply (see resolveFileValue)
            %       TrialType entries are skipped to mirror the load path.
            arguments
                obj
                filepath (1,1) string
            end

            R = struct('Param', {}, 'ParentType', {}, 'Current', {}, 'HasCurrent', {}, 'New', {});

            paramData = epsych.Runtime.phaseParameterData(filepath);
            if isempty(paramData)
                return
            end

            interfaceTypes = arrayfun(@(x) string(x.Type), obj.RUNTIME.Interfaces);

            for k = 1:numel(paramData)
                S = paramData(k);

                % Loading strips TrialType (see loadPhaseParameters), so ignore it here too.
                if string(S.Name) == "TrialType", continue, end

                parentType = string(S.ParentType);
                iface = obj.RUNTIME.Interfaces(interfaceTypes == parentType);
                if isempty(iface), continue, end

                xp = iface(1).find_parameter(S.Name, includeInvisible=true);
                if isempty(xp), continue, end
                xp = xp(1);

                % Write-only parameters cannot be read back, so record no current value.
                hasCurrent = ~strcmp(xp.Access,'Write');

                n = numel(R) + 1;
                R(n).Param      = xp;
                R(n).ParentType = parentType;
                if hasCurrent
                    R(n).Current = xp.Value;
                else
                    R(n).Current = [];
                end
                R(n).HasCurrent = hasCurrent;
                R(n).New        = obj.resolveFileValue(S);
            end
        end


        function P = keepChangedParameters(~, P, before)
            % P = keepChangedParameters(~, P, before)
            % Filter a resolved parameter set down to only those whose value the phase load
            % actually changed, comparing each parameter's (post-load) value against the
            % pre-load snapshot captured by resolvePhaseAgainstRuntime.
            %
            % Parameters:
            %   P      - hw.Parameter array returned by readParameters (already loaded).
            %   before - struct array from resolvePhaseAgainstRuntime (pre-load snapshot).
            %
            % Returns:
            %   P - Subset of the input containing only parameters that changed. StimType
            %       parameters (values not reliably comparable) and any parameter not covered
            %       by the snapshot are kept so a genuine change is never silently dropped.
            if isempty(P) || isempty(before)
                return
            end

            beforeParams = [before.Param];
            keep = true(1, numel(P));
            for k = 1:numel(P)
                if strcmp(P(k).Type, 'StimType'), continue, end
                j = find(beforeParams == P(k), 1);
                if ~isempty(j) && before(j).HasCurrent
                    keep(k) = ~isequaln(before(j).Current, P(k).Value);
                end
            end
            P = P(keep);
        end


        function v = resolveFileValue(~, S)
            % v = resolveFileValue(~, S)
            % Determine the value a phase-file parameter entry would apply, mirroring
            % readParameters: fromStruct restores the literal Value, then an Expression
            % with Values overrides it with its first evaluated level.
            hasExpr = isfield(S,'Expression') && strlength(string(S.Expression)) > 0;
            if isfield(S,'Values')
                vals = hw.Parameter.normalizeValues(S.Values);
            else
                vals = {};
            end
            if hasExpr && ~isempty(vals)
                v = vals{1};
            else
                v = S.Value;
            end
        end


        function s = formatValue(~, v)
            % s = formatValue(~, v)
            % Format a parameter value as a compact string for the Info table.
            if isempty(v)
                s = "[]";
            elseif isnumeric(v) || islogical(v)
                if isscalar(v)
                    s = string(num2str(v));
                else
                    s = "[" + strtrim(string(num2str(reshape(double(v),1,[])))) + "]";
                end
            elseif ischar(v) || isstring(v)
                s = string(v);
            else
                s = "<" + string(class(v)) + ">";
            end
        end


        function dlg = openLoadDialog(obj, phaseName)
            % dlg = openLoadDialog(obj, phaseName)
            % Show a modal, indeterminate progress dialog announcing that a phase is loading.
            %
            % Parameters:
            %   phaseName - Name of the phase being loaded (shown in the title)
            %
            % Returns:
            %   dlg - Handle to the progress dialog, or [] if no parent uifigure is available
            %         (in which case the load proceeds silently)
            dlg = [];
            if isempty(obj.h_PhaseSelect) || ~isvalid(obj.h_PhaseSelect)
                return
            end
            fig = ancestor(obj.h_PhaseSelect, 'figure');
            if isempty(fig), return, end
            dlg = uiprogressdlg(fig, ...
                'Title', sprintf('Loading phase: %s', phaseName), ...
                'Message', 'Reading phase parameters...', ...
                'Indeterminate', 'on');
            drawnow
        end


        function updateLoadDialog(obj, dlg, phaseName, P)
            % updateLoadDialog(obj, dlg, phaseName, P)
            % Populate the load dialog with the specific parameter changes being applied.
            %
            % Parameters:
            %   dlg       - Handle returned by openLoadDialog (may be [] if suppressed)
            %   phaseName - Name of the phase being applied
            %   P         - hw.Parameter array of the changes being written
            if isempty(dlg) || ~isvalid(dlg), return, end
            dlg.Title = sprintf('Applying phase: %s', phaseName);
            dlg.Message = obj.buildChangeSummary(P);
            drawnow
        end


        function closeLoadDialog(~, dlg)
            % closeLoadDialog(~, dlg)
            % Dismiss the load dialog if it is still open. Safe to call with [] or a stale handle.
            if ~isempty(dlg) && isvalid(dlg)
                close(dlg)
            end
        end


        function msg = buildChangeSummary(~, P)
            % msg = buildChangeSummary(~, P)
            % Build a cellstr listing each parameter (Name = new value) being applied,
            % suitable for a dialog Message. Long lists are truncated with a summary line.
            if isempty(P)
                msg = {'No matching parameters to change.'};
                return
            end
            maxShown = 20;
            n = numel(P);
            nShown = min(n, maxShown);
            lines = cell(1, nShown);
            for k = 1:nShown
                lines{k} = sprintf('   %s = %s', P(k).Name, P(k).ValueStr);
            end
            msg = [{sprintf('Applying %d parameter change(s):', n), ''}, lines];
            if n > maxShown
                msg{end+1} = sprintf('   ... and %d more', n - maxShown);
            end
        end
    end


end

