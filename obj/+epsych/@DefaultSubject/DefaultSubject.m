classdef DefaultSubject < epsych.Subject
    % epsych.DefaultSubject
    % obj = epsych.DefaultSubject()
    % obj = epsych.DefaultSubject(S)
    % Concrete subject implementation with a built-in uifigure data-entry dialog.
    %
    % Satisfies all abstract requirements of epsych.Subject.  A subject can be
    % constructed from a plain struct (e.g., when loading a saved config), built
    % programmatically, or collected interactively via the static open() method.
    %
    % Properties (required, implements epsych.Subject abstract):
    %   BoxID   - Apparatus/box index (positive integer; default: 1)
    %   Name    - Subject identifier string (default: '')
    %   Sex     - Sex descriptor, e.g. 'Male' (default: '')
    %   Species - Species name (default: '')
    %
    % Properties (optional, inherited from epsych.Subject):
    %   Weight  - Body weight in grams (default: NaN = not measured)
    %   Notes   - Freeform notes (default: '')
    %
    % Dialog features:
    %   * Modal, centered window with Edit/Add mode detection
    %   * Species dropdown is editable — type a new species to add it; the
    %     list and the last-used species persist across sessions (prefs)
    %   * Duplicate subject names rejected live via the ReservedNames option
    %   * Blank weight is stored as NaN (never coerced to 0 g)
    %   * Keyboard: Ctrl+Enter = OK, Escape = Cancel
    %
    % Usage:
    %   % Programmatic construction
    %   s = epsych.DefaultSubject;
    %   s.BoxID = 1; s.Name = 'M001'; s.Sex = 'Male'; s.Species = 'Mouse';
    %
    %   % From struct (legacy config reload)
    %   s = epsych.DefaultSubject(struct('BoxID',1,'Name','M001','Sex','Male','Species','Mouse'));
    %
    %   % Interactive GUI dialog
    %   s = epsych.DefaultSubject.open();
    %   s = epsych.DefaultSubject.open(existingSubject, availableBoxIDs);
    %   s = epsych.DefaultSubject.open([], 1:16, 'ReservedNames', {'M001','M002'});
    %
    % See also: epsych.Subject, epsych.RunExpt

    % MATLAB does not allow size/validation constraints on properties that are
    % declared abstract in the superclass, so the four required fields are
    % declared here without constraints.  Validation is enforced by isValid().
    properties
        BoxID   = 1   % Apparatus/box index (≥1, positive integer)
        Name    = ''  % Subject identifier
        Sex     = ''  % Sex descriptor ('Male', 'Female', 'Unknown')
        Species = ''  % Species name (e.g. 'Mouse', 'Rat')
    end

    % UI component handles — valid only while the dialog is open
    properties (Access = private)
        fig_       % uifigure
        ddBoxID_   % uidropdown  – Box ID
        efName_    % uieditfield – Name
        ddSex_     % uidropdown  – Sex
        ddSpecies_ % uidropdown  – Species (editable)
        efWeight_  % uieditfield – Weight (numeric, blank = not measured)
        taNotes_   % uitextarea  – Notes
        reservedNames_ = {}     % names rejected by onOK_ (duplicates)
        confirmed_     = false  % true when user clicks OK
    end

    % -----------------------------------------------------------------------
    methods

        function self = DefaultSubject(S)
            % self = DefaultSubject()
            % self = DefaultSubject(S)
            % Construct a DefaultSubject, optionally pre-populating from struct S.
            % Parameters:
            %   S - (optional) struct with any subset of fields:
            %       BoxID, Name, Sex, Species, Weight, Notes
            if nargin < 1 || isempty(S)
                return
            end
            self.fromStruct_(S);
        end

    end

    % -----------------------------------------------------------------------
    % Static factory
    % -----------------------------------------------------------------------
    methods (Static)

        function obj = open(S, boxids, options)
            % obj = epsych.DefaultSubject.open()
            % obj = epsych.DefaultSubject.open(S)
            % obj = epsych.DefaultSubject.open(S, boxids)
            % obj = epsych.DefaultSubject.open(S, boxids, 'ReservedNames', names)
            % Show the subject entry dialog and return a populated DefaultSubject.
            % Parameters:
            %   S      - (optional) epsych.Subject or struct used to pre-fill the dialog
            %   boxids - (optional) vector of available box IDs (default: 1:16)
            % Options:
            %   ReservedNames - cellstr/string of subject names already in use;
            %                   the dialog refuses to accept any of them
            % Returns:
            %   obj - populated epsych.DefaultSubject, or [] if the dialog was cancelled
            arguments
                S      = []
                boxids = 1:16
                options.ReservedNames = {}
            end

            if isa(S, 'epsych.Subject')
                seed = epsych.DefaultSubject(S.toStruct());
            elseif isstruct(S)
                seed = epsych.DefaultSubject(S);
            else
                seed = epsych.DefaultSubject();
            end

            seed.reservedNames_ = cellstr(options.ReservedNames);
            seed.buildUI_(boxids);
            uiwait(seed.fig_);

            figStillOpen = isvalid(seed) && isgraphics(seed.fig_);

            if ~isvalid(seed) || ~seed.confirmed_
                obj = [];
                if figStillOpen
                    delete(seed.fig_);
                end
                return
            end

            obj = seed;
            if figStillOpen
                delete(seed.fig_);
            end
        end

    end

    % -----------------------------------------------------------------------
    % Private — GUI construction and callbacks
    % -----------------------------------------------------------------------
    methods (Access = private)

        function buildUI_(self, boxids)
            % buildUI_(self, boxids)
            % Construct the uifigure dialog for subject data entry.

            % ---- Color palette -------------------------------------------
            HDR_BG   = [0.17 0.33 0.53];   % steel-blue header
            FIG_BG   = [0.96 0.97 0.98];   % pale blue-gray body
            LBL_CLR  = [0.28 0.28 0.33];   % dark-neutral label text
            OK_BG    = [0.13 0.46 0.72];   % action-blue OK button

            % An existing name means the dialog is editing, not adding
            isEdit = strlength(string(self.Name)) > 0;
            if isEdit
                dlgTitle = 'Edit Subject';
            else
                dlgTitle = 'Add Subject';
            end

            self.fig_ = uifigure( ...
                'Name',            dlgTitle, ...
                'Position',        [0 0 440 400], ...
                'Resize',          'off', ...
                'Color',           FIG_BG, ...
                'WindowStyle',     'modal', ...
                'KeyPressFcn',     @(~,evt) self.onKeyPress_(evt), ...
                'CloseRequestFcn', @(~,~) self.onCancel_());
            movegui(self.fig_, 'center');

            % Outer layout: [header | form | button bar]
            outerGL = uigridlayout(self.fig_, [3, 1]);
            outerGL.RowHeight     = {54, '1x', 58};
            outerGL.ColumnWidth   = {'1x'};
            outerGL.Padding       = [0 0 0 0];
            outerGL.RowSpacing    = 0;
            outerGL.ColumnSpacing = 0;

            % --- Header -------------------------------------------------------
            hdrPanel = uipanel(outerGL, ...
                'BackgroundColor', HDR_BG, ...
                'BorderType',      'none');
            hdrPanel.Layout.Row = 1; hdrPanel.Layout.Column = 1;
            hdrInner = uigridlayout(hdrPanel, [1, 1]);
            hdrInner.Padding = [0 0 0 0];
            hdrLbl = uilabel(hdrInner, ...
                'Text',               dlgTitle, ...
                'BackgroundColor',    HDR_BG, ...
                'FontColor',          [1 1 1], ...
                'FontSize',           18, ...
                'FontWeight',         'bold', ...
                'HorizontalAlignment','center', ...
                'VerticalAlignment',  'center');
            hdrLbl.Layout.Row = 1; hdrLbl.Layout.Column = 1;

            % --- Form grid (6 rows x 2 cols) ----------------------------------
            formGL = uigridlayout(outerGL, [6, 2]);
            formGL.Layout.Row    = 2;
            formGL.Layout.Column = 1;
            formGL.RowHeight     = {30, 30, 30, 30, 30, '1x'};
            formGL.ColumnWidth   = {100, '1x'};
            formGL.Padding       = [20 14 20 14];
            formGL.RowSpacing    = 8;
            formGL.ColumnSpacing = 8;

            % Shared label appearance
            lblProps = {'HorizontalAlignment','right', 'VerticalAlignment','center', ...
                        'FontSize',13, 'FontColor',LBL_CLR};

            % Box ID
            lbl = uilabel(formGL, 'Text', 'Box ID', lblProps{:});
            lbl.Layout.Row = 1; lbl.Layout.Column = 1;
            boxItems = arrayfun(@num2str, boxids, 'uni', false);
            self.ddBoxID_ = uidropdown(formGL, 'Items', boxItems, 'FontSize', 13, ...
                'Tooltip', 'Apparatus/box the subject runs in (occupied boxes are hidden)');
            self.ddBoxID_.Layout.Row = 1; self.ddBoxID_.Layout.Column = 2;
            sel = num2str(self.BoxID);
            if ismember(sel, boxItems)
                self.ddBoxID_.Value = sel;
            end

            % Name (required)
            lbl = uilabel(formGL, 'Text', 'Name *', lblProps{:});
            lbl.Layout.Row = 2; lbl.Layout.Column = 1;
            self.efName_ = uieditfield(formGL, 'text', ...
                'Value',       char(self.Name), ...
                'FontSize',    13, ...
                'Placeholder', 'Required');
            self.efName_.Layout.Row = 2; self.efName_.Layout.Column = 2;

            % Sex
            lbl = uilabel(formGL, 'Text', 'Sex', lblProps{:});
            lbl.Layout.Row = 3; lbl.Layout.Column = 1;
            sexItems = {'Male', 'Female', 'Unknown'};
            self.ddSex_ = uidropdown(formGL, 'Items', sexItems, ...
                'Value', 'Unknown', 'FontSize', 13);
            self.ddSex_.Layout.Row = 3; self.ddSex_.Layout.Column = 2;
            sexSeed = epsych.DefaultSubject.normalizeSex_(self.Sex);
            if ismember(sexSeed, sexItems)
                self.ddSex_.Value = sexSeed;
            end

            % Species — editable dropdown; typing a new value adds it to the list
            lbl = uilabel(formGL, 'Text', 'Species', lblProps{:});
            lbl.Layout.Row = 4; lbl.Layout.Column = 1;
            spItems = epsych.DefaultSubject.loadSpeciesList_();
            self.ddSpecies_ = uidropdown(formGL, 'Items', spItems, ...
                'Editable', 'on', 'FontSize', 13, ...
                'Tooltip', 'Pick a species or type a new one to add it to the list');
            self.ddSpecies_.Layout.Row = 4; self.ddSpecies_.Layout.Column = 2;
            spSeed = strtrim(char(self.Species));
            if isempty(spSeed)
                spSeed = getpref('ep_AddSubject', 'user_species', '');
            end
            idx = find(strcmpi(spItems, spSeed), 1);
            if ~isempty(idx)
                self.ddSpecies_.Value = spItems{idx};
            elseif ~isempty(spSeed)
                self.ddSpecies_.Value = spSeed;
            end

            % Weight — blank means "not measured" and is stored as NaN
            lbl = uilabel(formGL, 'Text', 'Weight (g)', lblProps{:});
            lbl.Layout.Row = 5; lbl.Layout.Column = 1;
            self.efWeight_ = uieditfield(formGL, 'numeric', ...
                'AllowEmpty',         'on', ...
                'Value',              [], ...
                'Limits',             [0 Inf], ...
                'LowerLimitInclusive','off', ...
                'FontSize',           13, ...
                'Tooltip',            'Leave blank if not measured');
            if isnumeric(self.Weight) && isscalar(self.Weight) && isfinite(self.Weight) && self.Weight > 0
                self.efWeight_.Value = self.Weight;
            end
            self.efWeight_.Layout.Row = 5; self.efWeight_.Layout.Column = 2;

            % Notes
            lbl = uilabel(formGL, 'Text', 'Notes', ...
                'HorizontalAlignment','right', 'VerticalAlignment','top', ...
                'FontSize',13, 'FontColor',LBL_CLR);
            lbl.Layout.Row = 6; lbl.Layout.Column = 1;
            notesVal = self.Notes;
            if ischar(notesVal) && ~isempty(notesVal)
                notesVal = strsplit(notesVal, newline);
            elseif isempty(notesVal)
                notesVal = {''};
            end
            self.taNotes_ = uitextarea(formGL, 'Value', notesVal, 'FontSize', 13);
            self.taNotes_.Layout.Row = 6; self.taNotes_.Layout.Column = 2;

            % --- Button bar ---------------------------------------------------
            btnPanel = uipanel(outerGL, ...
                'BackgroundColor', [0.91 0.92 0.94], ...
                'BorderType',      'none');
            btnPanel.Layout.Row = 3; btnPanel.Layout.Column = 1;
            btnGL = uigridlayout(btnPanel, [1, 4]);
            btnGL.ColumnWidth  = {'1x', '1x', 110, 90};
            btnGL.RowHeight    = {'1x'};
            btnGL.Padding      = [16 10 16 10];
            btnGL.ColumnSpacing = 8;

            btnCancel = uibutton(btnGL, 'Text', 'Cancel', ...
                'FontSize',        13, ...
                'Tooltip',         'Discard (Esc)', ...
                'BackgroundColor', [0.80 0.80 0.83], ...
                'ButtonPushedFcn', @(~,~) self.onCancel_());
            btnCancel.Layout.Row = 1; btnCancel.Layout.Column = 3;

            btnOK = uibutton(btnGL, 'Text', 'OK', ...
                'FontSize',        13, ...
                'FontWeight',      'bold', ...
                'FontColor',       [1 1 1], ...
                'Tooltip',         'Accept (Ctrl+Enter)', ...
                'BackgroundColor', OK_BG, ...
                'ButtonPushedFcn', @(~,~) self.onOK_());
            btnOK.Layout.Row = 1; btnOK.Layout.Column = 4;

            focus(self.efName_);
        end

        % --- Callbacks --------------------------------------------------------

        function onKeyPress_(self, evt)
            % Escape cancels; Ctrl+Enter accepts (plain Enter is left alone so
            % it can insert newlines in the Notes area).
            switch evt.Key
                case 'escape'
                    self.onCancel_();
                case 'return'
                    if any(strcmp(evt.Modifier, 'control'))
                        self.onOK_();
                    end
            end
        end

        function onOK_(self)
            name = strtrim(self.efName_.Value);
            if isempty(name)
                uialert(self.fig_, 'A subject name is required.', 'Missing Field', ...
                    'Icon', 'warning');
                return
            end
            if any(strcmpi(name, self.reservedNames_))
                uialert(self.fig_, ...
                    sprintf('The subject name "%s" is already in use.', name), ...
                    'Duplicate Name', 'Icon', 'warning');
                return
            end
            species = strtrim(self.ddSpecies_.Value);
            if isempty(species)
                uialert(self.fig_, 'A species is required.', 'Missing Field', ...
                    'Icon', 'warning');
                return
            end
            self.collectFromUI_();
            epsych.DefaultSubject.rememberSpecies_(species);
            self.confirmed_ = true;
            uiresume(self.fig_);
        end

        function onCancel_(self)
            self.confirmed_ = false;
            uiresume(self.fig_);
        end

        % --- Data helpers -----------------------------------------------------

        function collectFromUI_(self)
            % Copy current UI control values into subject properties.
            self.BoxID   = str2double(self.ddBoxID_.Value);
            self.Name    = strtrim(self.efName_.Value);
            self.Sex     = self.ddSex_.Value;
            self.Species = strtrim(self.ddSpecies_.Value);
            w = self.efWeight_.Value;
            if isempty(w), w = NaN; end
            self.Weight  = w;
            notes = self.taNotes_.Value;
            if iscell(notes), notes = strjoin(notes, newline); end
            self.Notes = char(notes);
        end

        function fromStruct_(self, S)
            % Populate properties from struct fields; unknown fields are ignored.
            fields = {'BoxID', 'Name', 'Sex', 'Species', 'Weight', 'Notes'};
            for k = 1:numel(fields)
                f = fields{k};
                if isfield(S, f) && ~isempty(S.(f))
                    self.(f) = S.(f);
                end
            end
            self.Sex = epsych.DefaultSubject.normalizeSex_(self.Sex);
        end

    end

    % -----------------------------------------------------------------------
    % Static private — species/sex helpers (prefs shared with legacy ep_AddSubject)
    % -----------------------------------------------------------------------
    methods (Static, Access = private)

        function list = loadSpeciesList_()
            % Returns the user's saved species list (trimmed, deduplicated,
            % sorted), falling back to a built-in default.
            default = {'Mouse','Rat','Gerbil','Guinea Pig','Ferret','Cat', ...
                       'Non-Human Primate','Other'};
            list = cellstr(getpref('ep_AddSubject', 'species', default));
            list = strtrim(list(:)');  % legacy GUIDE dialog saved a column
            list = list(~cellfun('isempty', list));
            list = list(~strcmp(list, '< ADD SPECIES >'));  % legacy sentinel entry
            [~, ia] = unique(lower(list), 'stable');
            list = sort(list(ia));
            if isempty(list)
                list = default;
            end
        end

        function rememberSpecies_(species)
            % Persist a species selection: add it to the saved list if new and
            % remember it as the last-used default for the next dialog.
            list = epsych.DefaultSubject.loadSpeciesList_();
            if ~any(strcmpi(list, species))
                list = sort([list, {species}]);
                vprintf(1, 'A new species was added to the list: %s', species)
            end
            setpref('ep_AddSubject', {'species','user_species'}, {list, species});
        end

        function sex = normalizeSex_(sex)
            % Map legacy single-letter codes onto the dialog's canonical labels.
            sex = char(string(sex));
            switch lower(strtrim(sex))
                case {'m','male'},   sex = 'Male';
                case {'f','female'}, sex = 'Female';
                case {'u','unk','unknown'}, sex = 'Unknown';
            end
        end

    end

end
