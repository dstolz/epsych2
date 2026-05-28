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
    %   Weight  - Body weight in grams (default: NaN)
    %   Notes   - Freeform notes (default: '')
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
        ddSpecies_ % uidropdown  – Species
        efWeight_  % uieditfield – Weight (numeric)
        taNotes_   % uitextarea  – Notes
        confirmed_ = false  % true when user clicks OK
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

        function obj = open(S, boxids)
            % obj = epsych.DefaultSubject.open()
            % obj = epsych.DefaultSubject.open(S)
            % obj = epsych.DefaultSubject.open(S, boxids)
            % Show the subject entry dialog and return a populated DefaultSubject.
            % Parameters:
            %   S      - (optional) epsych.Subject or struct used to pre-fill the dialog
            %   boxids - (optional) vector of available box IDs (default: 1:16)
            % Returns:
            %   obj - populated epsych.DefaultSubject, or [] if the dialog was cancelled
            arguments
                S      = []
                boxids = 1:16
            end

            if isa(S, 'epsych.Subject')
                seed = epsych.DefaultSubject(S.toStruct());
            elseif isstruct(S)
                seed = epsych.DefaultSubject(S);
            else
                seed = epsych.DefaultSubject();
            end

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
            self.fig_ = uifigure( ...
                'Name',             'Add Subject', ...
                'Position',         [0 0 400 310], ...
                'Resize',           'off', ...
                'CloseRequestFcn',  @(~,~) self.onCancel_());
            movegui(self.fig_, 'center');

            gl = uigridlayout(self.fig_, [7, 3]);
            gl.RowHeight    = {22, 22, 22, 22, 22, 80, 34};
            gl.ColumnWidth  = {'fit', '1x', 40};
            gl.Padding      = [14 14 14 14];
            gl.RowSpacing   = 6;
            gl.ColumnSpacing = 8;

            % --- Box ID -------------------------------------------------------
            lbl = uilabel(gl, 'Text', 'Box ID:', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = 1; lbl.Layout.Column = 1;
            boxItems = arrayfun(@num2str, boxids, 'uni', false);
            self.ddBoxID_ = uidropdown(gl, 'Items', boxItems);
            self.ddBoxID_.Layout.Row = 1; self.ddBoxID_.Layout.Column = [2 3];
            sel = num2str(self.BoxID);
            if ismember(sel, boxItems)
                self.ddBoxID_.Value = sel;
            end

            % --- Name ---------------------------------------------------------
            lbl = uilabel(gl, 'Text', 'Name:', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = 2; lbl.Layout.Column = 1;
            self.efName_ = uieditfield(gl, 'text', 'Value', char(self.Name));
            self.efName_.Layout.Row = 2; self.efName_.Layout.Column = [2 3];

            % --- Sex ----------------------------------------------------------
            lbl = uilabel(gl, 'Text', 'Sex:', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = 3; lbl.Layout.Column = 1;
            sexItems = {'Male', 'Female', 'Unknown'};
            self.ddSex_ = uidropdown(gl, 'Items', sexItems, 'Value', sexItems{1});
            self.ddSex_.Layout.Row = 3; self.ddSex_.Layout.Column = [2 3];
            if ismember(self.Sex, sexItems)
                self.ddSex_.Value = self.Sex;
            end

            % --- Species (dropdown + add button) ------------------------------
            lbl = uilabel(gl, 'Text', 'Species:', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = 4; lbl.Layout.Column = 1;
            spItems = epsych.DefaultSubject.loadSpeciesList_();
            self.ddSpecies_ = uidropdown(gl, 'Items', spItems, 'Value', spItems{1});
            self.ddSpecies_.Layout.Row = 4; self.ddSpecies_.Layout.Column = 2;
            if ismember(self.Species, spItems)
                self.ddSpecies_.Value = self.Species;
            end
            btnSp = uibutton(gl, 'Text', '+', 'Tooltip', 'Add a new species', ...
                'ButtonPushedFcn', @(~,~) self.onAddSpecies_());
            btnSp.Layout.Row = 4; btnSp.Layout.Column = 3;

            % --- Weight -------------------------------------------------------
            lbl = uilabel(gl, 'Text', 'Weight (g):', 'HorizontalAlignment', 'right');
            lbl.Layout.Row = 5; lbl.Layout.Column = 1;
            wval = self.Weight;
            if ~isnumeric(wval) || isnan(wval), wval = 0; end
            self.efWeight_ = uieditfield(gl, 'numeric', ...
                'Value', wval, 'Limits', [0 Inf], 'LowerLimitInclusive', 'on');
            self.efWeight_.Layout.Row = 5; self.efWeight_.Layout.Column = [2 3];

            % --- Notes --------------------------------------------------------
            lbl = uilabel(gl, 'Text', 'Notes:', ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'top');
            lbl.Layout.Row = 6; lbl.Layout.Column = 1;
            notesVal = self.Notes;
            if ischar(notesVal) && ~isempty(notesVal)
                notesVal = strsplit(notesVal, newline);
            elseif isempty(notesVal)
                notesVal = {''};
            end
            self.taNotes_ = uitextarea(gl, 'Value', notesVal);
            self.taNotes_.Layout.Row = 6; self.taNotes_.Layout.Column = [2 3];

            % --- Cancel / OK buttons ------------------------------------------
            btnCancel = uibutton(gl, 'Text', 'Cancel', ...
                'ButtonPushedFcn', @(~,~) self.onCancel_());
            btnCancel.Layout.Row = 7; btnCancel.Layout.Column = 2;
            btnOK = uibutton(gl, 'Text', 'OK', ...
                'ButtonPushedFcn', @(~,~) self.onOK_());
            btnOK.Layout.Row = 7; btnOK.Layout.Column = 3;
        end

        % --- Callbacks --------------------------------------------------------

        function onOK_(self)
            if isempty(strtrim(self.efName_.Value))
                uialert(self.fig_, 'A subject name is required.', 'Missing Field', ...
                    'Icon', 'warning');
                return
            end
            self.collectFromUI_();
            self.confirmed_ = true;
            uiresume(self.fig_);
        end

        function onCancel_(self)
            self.confirmed_ = false;
            uiresume(self.fig_);
        end

        function onAddSpecies_(self)
            answer = inputdlg('Enter new species name:', 'Add Species', 1);
            if isempty(answer) || isempty(strtrim(char(answer))), return, end
            newSp = strtrim(char(answer));
            current = self.ddSpecies_.Items;
            if ismember(newSp, current)
                uialert(self.fig_, sprintf('"%s" is already in the list.', newSp), ...
                    'Duplicate Species');
                return
            end
            updated = [newSp, current];
            self.ddSpecies_.Items = updated;
            self.ddSpecies_.Value = newSp;
            epsych.DefaultSubject.saveSpeciesList_(updated);
        end

        % --- Data helpers -----------------------------------------------------

        function collectFromUI_(self)
            % Copy current UI control values into subject properties.
            self.BoxID   = str2double(self.ddBoxID_.Value);
            self.Name    = strtrim(self.efName_.Value);
            self.Sex     = self.ddSex_.Value;
            self.Species = self.ddSpecies_.Value;
            w = self.efWeight_.Value;
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
        end

    end

    % -----------------------------------------------------------------------
    % Static private — species preference helpers (shared with ep_AddSubject)
    % -----------------------------------------------------------------------
    methods (Static, Access = private)

        function list = loadSpeciesList_()
            % Returns the user's saved species list, falling back to a built-in default.
            default = {'Mouse','Rat','Gerbil','Guinea Pig','Ferret','Cat', ...
                       'Non-Human Primate','Other'};
            list = cellstr(getpref('ep_AddSubject', 'species', default));
        end

        function saveSpeciesList_(list)
            setpref('ep_AddSubject', 'species', list);
        end

    end

end
