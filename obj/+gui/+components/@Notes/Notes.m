classdef Notes < gui.PopOut
    % obj = gui.components.Notes(source, container)
    % A line of notes, stamped with the trial it was typed on, saved with the data.
    %
    % One edit field, one commit button, and a box holding everything typed so
    % far. Tap Enter in the field or click the button and the line is committed,
    % stamped with the trial the session is on -- trial 0 before the first trial
    % completes -- and appended to the log:
    %
    %   [T000 --:--:--] started, animal alert
    %   [T042 00:17:05] ear plug slipped
    %
    % The log box fills whatever row a tiled layout gives it, so a GUI that
    % allots it one row gets a two-line log and one that allots it '1x' gets a
    % full-height one, with no option to set.
    %
    % Nothing is stored here. Notes live in epsych.SessionNotes -- normally
    % RUNTIME.NOTES -- which is what puts them in the data file:
    % epsych.SessionSnapshot.forSubject folds them into the Info variable every
    % saving function already writes (Info.Notes, Info.NotesText), and each
    % committed note is appended to the session journal, so a crashed session
    % keeps them too. Several gui.components.Notes over one store -- an embedded one and
    % its pop-out -- show the same log and update together.
    %
    % A GUI with no room for a log can take the panel as a single button
    % instead -- ButtonOnly=true, or gui.BehaviorGUI.addNotesButton -- which
    % opens the notes in a window of their own. That window is an ordinary
    % gui.PopOut pop-out over the SAME store, so it shows every note the
    % session already has and anything typed into it is the session's note,
    % saved with the data like any other. It remembers its position, offers
    % "Keep Window on Top", and closes with the GUI that owns the button.
    %
    % The log box is READ-ONLY by default. "Editable" on the right-click menu
    % makes it typeable, for fixing a typo or pasting in something longer, and
    % when it is edited that text becomes what is saved (Records are re-parsed
    % from it). The setting is remembered per host GUI, so a rig that wants a
    % hand-editable log gets one every session.
    %
    % Notes are session-level by default: one log, written into every subject's
    % data file. Subject=i tags this component's notes with one subject, and
    % then only that subject's file carries them -- for a multi-box rig where a
    % remark is about one animal rather than the room.
    %
    % Properties:
    %   Editable  - Whether the log box can be typed in (also on the menu)
    %   TimeStamp - "elapsed" (default), "clock", or "none"
    %   FontSize  - Font size of the log and the entry field
    %   Store     - The epsych.SessionNotes these notes are kept in
    %   IsButtonOnly - True when this is the button form, with no log of its own
    %   ContextMenu - the right-click menu; host GUIs may append items
    %
    % Methods:
    %   commit      - Commit the entry field's text, as Enter would
    %   addNote     - Add a note programmatically
    %   clearNotes  - Discard every note
    %   setEditable - Turn hand-editing of the log on or off
    %
    % Examples:
    %   % In a gui.BehaviorGUI subclass build():
    %   obj.NotesPanel = obj.addNotes(g);           % g is a uigridlayout cell
    %
    %   % Wall-clock stamps, tagged to subject 2, hand-editable from the start:
    %   obj.addNotes(g, TimeStamp="clock", Subject=2, Editable=true);
    %
    %   % Just a button; the notes live in the window it opens:
    %   obj.addNotesButton(toolRow);
    %
    %   % From anywhere holding the runtime, no GUI involved:
    %   RUNTIME.NOTES.add('water bottle refilled');
    %
    % A review (epsych.ReviewSession) shows the notes the session was saved
    % with and refuses new ones: there is nothing left to write them to.
    %
    % Documentation: documentation/gui/gui_Notes.md
    % See also: epsych.SessionNotes, gui.BehaviorGUI.addNotes, gui.PopOut

    properties (Dependent)
        Editable    % Whether the log box can be typed in
        TimeStamp   % Stamp format: "elapsed", "clock" or "none"
        FontSize    % Font size of the log and entry field, in points
        IsButtonOnly % True when this instance is just a button opening the notes window
    end

    properties (SetAccess = private)
        Parent                              % Hosting container supplied at construction
        Store epsych.SessionNotes {mustBeScalarOrEmpty} = epsych.SessionNotes.empty % Where the notes are kept
        GridH                               % Layout holding the log and the entry row
        LogH                                % uitextarea showing every note
        EntryH                              % uieditfield the note is typed into
        CommitH                             % Button committing the entry field
        OpenH                               % Button opening the notes window (button form only)
        ContextMenu = []                    % Right-click menu
        hl_Notes = event.listener.empty     % Listener on the store's NotesChanged
    end

    properties (Access = private)
        Source_ = []                        % Construction source, reused to build a pop-out
        Subject_ (1,1) double = 0           % Subject these notes are tagged with; 0 = session-wide
        TimeStamp_ (1,1) string = "elapsed"
        FontSize_ (1,1) double = 12
        Editable_ (1,1) logical = false
        PreferenceTag_ (1,:) char = ''
        ReviewMode_ (1,1) logical = false
        ButtonOnly_ (1,1) logical = false
        EditMenuH_ = []
        selfDeleteListener_ = event.listener.empty
    end

    properties (Constant, Access = private)
        PREF_GROUP = 'epsych2_gui_Notes'
        ENTRY_ROW_HEIGHT = 26   % px; one line of text plus its border
    end

    methods (Static)
        function s = getComponentSpec()
            % s = gui.components.Notes.getComponentSpec()
            % Ctrl+Shift+N puts the caret where the note gets typed;
            % KeyBinding='none' at the call site drops it.
            %
            % The ButtonOnly form is reached through the same spec with
            % ButtonOnly=true (gui.BehaviorGUI.addNotesButton), not through a
            % variant: it is the same component, configured differently.
            % See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type           = 'Notes';
            s.label          = 'Session Notes';
            s.category       = 'Add-ons';
            s.description    = 'Operator note pad: a typed line stamped with the trial, saved with the data';
            s.shape          = ["runtime","parent"];
            s.keyBinding     = 'ctrl+shift+n';
            s.keyAction      = 'focusEntry';
            s.keyDescription = 'Add a session note';
            s.options        = [ ...
                gui.ComponentSpecOption('name','Subject','inputType','numeric','defaultValue',0), ...
                gui.ComponentSpecOption('name','TimeStamp','inputType','choice', ...
                    'choices',{{'elapsed','clock','none'}},'defaultValue','elapsed'), ...
                gui.ComponentSpecOption('name','Editable','inputType','logical','defaultValue',false), ...
                gui.ComponentSpecOption('name','ButtonOnly','inputType','logical','defaultValue',false), ...
                gui.ComponentSpecOption('name','Text','inputType','text','defaultValue','Notes'), ...
                gui.ComponentSpecOption('name','FontSize','inputType','numeric','defaultValue',12), ...
                gui.ComponentSpecOption('name','PreferenceTag','inputType','text')];
        end
    end

    methods
        function focusEntry(obj)
            % obj.focusEntry()
            % Put the caret where the note gets typed. The ButtonOnly form
            % keeps its entry field in a window of its own, so there this
            % opens that window instead -- the same thing its button does.
            %
            % This is the Ctrl+Shift+N action named by getComponentSpec. It
            % lives here rather than on gui.BehaviorGUI because everything it
            % touches is this component's own state.
            try
                if obj.IsButtonOnly
                    obj.popOut();
                elseif ~isempty(obj.EntryH) && isvalid(obj.EntryH)
                    focus(obj.EntryH);
                end
            catch ME
                vprintf(2, 'gui.components.Notes: could not reach the notes entry (%s)', ME.message)
            end
        end
    end

    methods

        function obj = Notes(source, container, options)
            % obj = gui.components.Notes(source, container, ...)
            %  source    - epsych.Runtime (uses RUNTIME.NOTES), an
            %              epsych.SessionNotes to share, or [] for a
            %              standalone store owned by this component.
            %  container - Figure, panel, tab, or layout cell to build into.
            %  Subject   - Tag notes with one subject index, or 0 (default)
            %              for the whole session. A tagged note is written
            %              only into that subject's data file.
            %  TimeStamp - "elapsed" (default), "clock", or "none".
            %  Editable  - Start with the log box hand-editable. Default
            %              false. A setting saved for this PreferenceTag
            %              takes precedence.
            %  FontSize  - Points for the log and entry field. Default 12.
            %  Placeholder - Grey prompt in the empty entry field.
            %  ButtonOnly - Build just a button that opens the notes in a
            %              window of their own, for a GUI with no room for a
            %              log. Default false.
            %  Text      - Label on that button. Default 'Notes'.
            %  PreferenceTag - Key for saved settings (defaults to the
            %              hosting figure's Tag or Name).
            arguments
                source
                container (1,1)
                options.Subject (1,1) double {mustBeInteger, mustBeNonnegative} = 0
                options.TimeStamp (1,1) string {mustBeMember(options.TimeStamp, ...
                    ["elapsed","clock","none"])} = "elapsed"
                options.Editable (1,1) logical = false
                options.FontSize (1,1) double {mustBePositive, mustBeFinite} = 12
                options.Placeholder (1,:) char = 'Add a note...'
                options.ButtonOnly (1,1) logical = false
                options.Text (1,:) char = 'Notes'
                options.PreferenceTag (1,:) char = ''
            end

            obj.Parent         = container;
            obj.Source_        = source;
            obj.Subject_       = options.Subject;
            obj.TimeStamp_     = options.TimeStamp;
            obj.FontSize_      = options.FontSize;
            obj.Editable_      = options.Editable;
            obj.ButtonOnly_    = options.ButtonOnly;
            obj.PreferenceTag_ = options.PreferenceTag;

            % A log and one entry line: the default 780x560 is a window sized
            % for a plot, and a notes window that large just holds whitespace.
            obj.PopOutSize = [520 420];

            obj.resolveStore_(source);

            if obj.ButtonOnly_
                % No log of its own; the pop-out it opens is the display, and
                % the store behind it is the same one either way.
                obj.buildButton_(container, options.Text);
                return
            end

            obj.buildUI_(container, options.Placeholder);
            obj.loadPreferences_();
            obj.applyEditable_();
            obj.applyReviewMode_();
            obj.attachListener_();
            obj.refresh_();
        end

        function delete(obj)
            % Release the store listener and the context menu. The graphics
            % are left for the hosting figure to tear down.
            try
                if ~isempty(obj.hl_Notes) && isvalid(obj.hl_Notes)
                    obj.hl_Notes.Enabled = false;
                    delete(obj.hl_Notes);
                end
            catch
            end
            try
                delete(obj.selfDeleteListener_);
            catch
            end
            try
                if ~isempty(obj.ContextMenu) && isvalid(obj.ContextMenu)
                    delete(obj.ContextMenu);
                end
            catch
            end
        end

        % --- settings ------------------------------------------------------

        function tf = get.Editable(obj),  tf = obj.Editable_;  end
        function set.Editable(obj, tf),   obj.setEditable(tf); end

        function tf = get.IsButtonOnly(obj), tf = obj.ButtonOnly_; end

        function s = get.TimeStamp(obj),  s = obj.TimeStamp_;  end
        function set.TimeStamp(obj, s)
            arguments
                obj
                s (1,1) string {mustBeMember(s, ["elapsed","clock","none"])}
            end
            obj.TimeStamp_ = s;
            obj.refresh_();
        end

        function sz = get.FontSize(obj),  sz = obj.FontSize_;  end
        function set.FontSize(obj, points)
            arguments
                obj
                points (1,1) double {mustBePositive, mustBeFinite}
            end
            % Clamped rather than refused, so a scripted value cannot leave
            % the log unreadable.
            obj.FontSize_ = min(max(round(points), 6), 72);
            obj.applyFontSize_();
        end

        function setEditable(obj, tf)
            % setEditable(obj, tf)
            % Turn hand-editing of the log box on or off. Persists like a
            % menu choice. Refused in a review, where an edit has nowhere to
            % be saved to.
            arguments
                obj
                tf (1,1) logical
            end
            if obj.ReviewMode_ && tf
                vprintf(1, 'gui.components.Notes: a reviewed session''s notes are a record and cannot be edited')
                return
            end
            obj.Editable_ = tf;
            obj.applyEditable_();
            obj.savePreferences_();
        end

        % --- notes ---------------------------------------------------------

        function rec = commit(obj)
            % rec = commit(obj)
            % Commit whatever is in the entry field, as tapping Enter does,
            % and clear the field. An empty field commits nothing.
            rec = epsych.SessionNotes.emptyRecords();
            if isempty(obj.EntryH) || ~isvalid(obj.EntryH), return; end

            text = strtrim(char(string(obj.EntryH.Value)));
            if isempty(text), return; end

            rec = obj.addNote(text);
            obj.EntryH.Value = '';
        end

        function rec = addNote(obj, text)
            % rec = addNote(obj, text)
            % Add a note through this component's store, tagged with this
            % component's Subject.
            arguments
                obj
                text (1,:) char
            end
            rec = epsych.SessionNotes.emptyRecords();
            if isempty(obj.Store) || ~isvalid(obj.Store), return; end
            rec = obj.Store.add(text, Subject = obj.Subject_);
        end

        function clearNotes(obj)
            % clearNotes(obj)
            % Discard every note in the store, after confirming.
            if isempty(obj.Store) || ~isvalid(obj.Store), return; end

            f = ancestor(obj.Parent, 'figure');
            try
                answer = uiconfirm(f, ...
                    'Discard every note typed this session?', 'Clear Notes', ...
                    'Options', {'Clear','Cancel'}, 'DefaultOption', 2, ...
                    'CancelOption', 2, 'Icon', 'warning');
            catch ME
                % No uifigure to ask in (a scripted call, a legacy figure):
                % clearing without asking would be the destructive reading.
                vprintf(2, 'gui.components.Notes: could not confirm the clear (%s)', ME.message)
                answer = 'Cancel';
            end

            if strcmp(answer, 'Clear')
                obj.Store.clear();
            end
        end
    end

    methods (Access = protected)

        function c = popOutHostContainer_(obj)
            % Container this component was built into (gui.PopOut).
            c = obj.Parent;
        end

        function h = createPopOut_(obj, container)
            % A second view on the SAME store, so both windows show the same
            % log and either can add to it.
            h = gui.components.Notes(obj.Store, container, ...
                Subject       = obj.Subject_, ...
                TimeStamp     = obj.TimeStamp_, ...
                Editable      = obj.Editable_, ...
                FontSize      = obj.FontSize_, ...
                PreferenceTag = obj.popOutPreferenceTag_());
        end
    end

    methods (Access = private)

        function resolveStore_(obj, source)
            % The store this component writes to. A runtime lends its own, an
            % epsych.SessionNotes is shared as given, and anything else --
            % including [] -- gets a private store, so the component still
            % works in a demo or a test with no session behind it.
            if isa(source, 'epsych.SessionNotes')
                obj.Store = source;
                return
            end

            if isa(source, 'epsych.Runtime') && isvalid(source)
                if isempty(source.NOTES) || ~isvalid(source.NOTES)
                    source.NOTES = epsych.SessionNotes(source);
                end
                obj.Store       = source.NOTES;
                obj.ReviewMode_ = source.ReviewMode;
                return
            end

            vprintf(2, 'gui.components.Notes: no session supplied; these notes are not attached to a data file')
            obj.Store = epsych.SessionNotes();
        end

        function buildButton_(obj, parent, text)
            % The button form: one button, and the notes live in the pop-out
            % it opens. popOut is the ordinary gui.PopOut path -- so the
            % window remembers where it was, can be pinned on top, raises
            % rather than duplicating when it is already open, and is closed
            % by the destroy listener when the GUI that owns the button goes.
            obj.OpenH = uibutton(parent, ...
                'Text',            text, ...
                'Icon',            gui.toolbarIcon("notes"), ...
                'Tooltip',         'Session notes: type a line, Enter commits it', ...
                'FontSize',        obj.FontSize_, ...
                'ButtonPushedFcn', @(~,~) obj.popOut());

            obj.selfDeleteListener_ = listener(obj.OpenH, 'ObjectBeingDestroyed', ...
                @(~,~) delete(obj));
        end

        function buildUI_(obj, parent, placeholder)
            % Log above, entry row below. A grid rather than hand-placed
            % children so the log takes every pixel the host's own row gives
            % this component and the entry row keeps its one line.
            obj.GridH = uigridlayout(parent, [2 2], ...
                'RowHeight',   {'1x', obj.ENTRY_ROW_HEIGHT}, ...
                'ColumnWidth', {'1x', obj.ENTRY_ROW_HEIGHT}, ...
                'RowSpacing',  4, ...
                'ColumnSpacing', 4, ...
                'Padding',     [4 4 4 4]);

            obj.LogH = uitextarea(obj.GridH, ...
                'Value',          {''}, ...
                'Editable',       'off', ...
                'FontSize',       obj.FontSize_, ...
                'ValueChangedFcn', @(~,~) obj.onLogEdited_());
            obj.LogH.Layout.Row    = 1;
            obj.LogH.Layout.Column = [1 2];

            obj.EntryH = uieditfield(obj.GridH, 'text', ...
                'FontSize',        obj.FontSize_, ...
                'ValueChangedFcn', @(~,~) obj.commit());
            obj.EntryH.Layout.Row    = 2;
            obj.EntryH.Layout.Column = 1;

            % Placeholder is R2023b+; on an older release the tooltip is the
            % prompt, which is the whole of what is lost.
            try
                obj.EntryH.Placeholder = placeholder;
            catch
                obj.EntryH.Tooltip = placeholder;
            end

            obj.CommitH = uibutton(obj.GridH, ...
                'Text',            '', ...
                'Icon',            gui.toolbarIcon("addnote"), ...
                'Tooltip',         'Add this note (or press Enter)', ...
                'ButtonPushedFcn', @(~,~) obj.commit());
            obj.CommitH.Layout.Row    = 2;
            obj.CommitH.Layout.Column = 2;

            obj.selfDeleteListener_ = listener(obj.GridH, 'ObjectBeingDestroyed', ...
                @(~,~) delete(obj));

            obj.createContextMenu_();
        end

        function createContextMenu_(obj)
            f = ancestor(obj.Parent, 'figure');
            if isempty(f) || ~isvalid(f), return; end

            try
                cm = uicontextmenu(f);
                obj.ContextMenu = cm;

                obj.EditMenuH_ = uimenu(cm, 'Text', 'Editable', ...
                    'Checked', matlab.lang.OnOffSwitchState(obj.Editable_), ...
                    'MenuSelectedFcn', @(~,~) obj.setEditable(~obj.Editable_));
                uimenu(cm, 'Text', 'Copy All', ...
                    'MenuSelectedFcn', @(~,~) obj.copyAll_());
                uimenu(cm, 'Text', 'Clear Notes...', 'Separator', 'on', ...
                    'MenuSelectedFcn', @(~,~) obj.clearNotes());

                % Brings "Keep Window on Top" with it, in a pop-out window.
                obj.addPopOutMenu_(cm);
            catch ME
                vprintf(3, 'gui.components.Notes: context menu unavailable: %s', ME.message)
                obj.ContextMenu = [];
                return
            end

            % On the log, the entry field and the button alike: an operator
            % right-clicks whichever part of the panel is under the pointer.
            for h = [obj.LogH, obj.EntryH, obj.CommitH]
                try
                    h.ContextMenu = cm;
                catch ME
                    vprintf(3, 'gui.components.Notes: could not attach the context menu (%s)', ME.message)
                end
            end
        end

        function attachListener_(obj)
            if isempty(obj.Store) || ~isvalid(obj.Store), return; end
            obj.hl_Notes = listener(obj.Store, 'NotesChanged', @(~,~) obj.refresh_());
        end

        function refresh_(obj)
            if ~isvalid(obj) || isempty(obj.LogH) || ~isvalid(obj.LogH), return; end
            if isempty(obj.Store) || ~isvalid(obj.Store), return; end

            try
                lines = obj.Store.render(TimeStamp = obj.TimeStamp_, Subject = obj.Subject_);
                if isempty(lines), lines = {''}; end
                obj.LogH.Value = lines;

                % The newest note is the one worth seeing; a log longer than
                % the box otherwise scrolls out of view as it fills.
                try
                    scroll(obj.LogH, 'bottom');
                catch
                end
            catch ME
                vprintf(0, 1, ME)
            end
        end

        function onLogEdited_(obj)
            % Edited text wins: what the operator left in the box becomes the
            % log, and the records are re-parsed from it.
            if ~obj.Editable_ || isempty(obj.Store) || ~isvalid(obj.Store), return; end
            obj.Store.setText(obj.LogH.Value);
        end

        function applyEditable_(obj)
            if ~isempty(obj.LogH) && isvalid(obj.LogH)
                obj.LogH.Editable = matlab.lang.OnOffSwitchState(obj.Editable_);
            end
            if ~isempty(obj.EditMenuH_) && isvalid(obj.EditMenuH_)
                obj.EditMenuH_.Checked = matlab.lang.OnOffSwitchState(obj.Editable_);
            end
        end

        function applyFontSize_(obj)
            for h = [obj.LogH, obj.EntryH, obj.OpenH]
                if ~isempty(h) && isvalid(h), h.FontSize = obj.FontSize_; end
            end
        end

        function applyReviewMode_(obj)
            % A reviewed session's notes are a record of what was written at
            % the time. Nothing here can reach the file that holds them, so
            % the entry row says so rather than accepting notes that vanish.
            if ~obj.ReviewMode_, return; end

            obj.Editable_ = false;
            obj.applyEditable_();

            for h = [obj.EntryH, obj.CommitH]
                if isempty(h) || ~isvalid(h), continue; end
                h.Enable  = 'off';
                h.Tooltip = 'Reviewing a finished session: its notes are a record';
            end
            if ~isempty(obj.EditMenuH_) && isvalid(obj.EditMenuH_)
                obj.EditMenuH_.Enable = 'off';
            end
        end

        function copyAll_(obj)
            % The whole log on the clipboard, for a notebook entry.
            try
                clipboard('copy', char(strjoin(obj.LogH.Value, newline)));
                vprintf(2, 'gui.components.Notes: copied %d line(s) to the clipboard', numel(obj.LogH.Value))
            catch ME
                vprintf(0, 1, ME)
            end
        end

        % --- preferences ---------------------------------------------------

        function tag = preferenceTag_(obj)
            tag = obj.PreferenceTag_;
            if isempty(tag)
                f = ancestor(obj.Parent, 'figure');
                if ~isempty(f) && isvalid(f)
                    tag = char(f.Tag);
                    if isempty(tag), tag = char(f.Name); end
                end
            end
            if isempty(tag), tag = 'default'; end
            tag = matlab.lang.makeValidName(tag);
        end

        function loadPreferences_(obj)
            % Only Editable is remembered. The stamp format is the paradigm's
            % choice rather than the operator's, and a size the operator
            % cannot change has nothing to restore.
            try
                key = obj.preferenceTag_();
                if ispref(gui.components.Notes.PREF_GROUP, key)
                    P = getpref(gui.components.Notes.PREF_GROUP, key);
                    if isstruct(P) && isfield(P, 'Editable')
                        obj.Editable_ = logical(P.Editable);
                    end
                end
            catch ME
                vprintf(3, 'gui.components.Notes: could not read saved settings (%s)', ME.message)
            end
        end

        function savePreferences_(obj)
            try
                setpref(gui.components.Notes.PREF_GROUP, obj.preferenceTag_(), ...
                    struct('Editable', obj.Editable_));
            catch ME
                vprintf(3, 'gui.components.Notes: could not save settings (%s)', ME.message)
            end
        end
    end
end
