function P = projectDialog_(self, seed)
% P = projectDialog_(self, seed)
% Modal dialog for a project's identity, its session defaults, links, and
% archived flag.
%
% Shaped after epsych.DefaultSubject.open: modal uifigure, uiwait, [] on
% cancel, Esc cancels and Ctrl+Enter accepts.
%
% Parameters:
%   seed - struct with Name, Notes, Investigator, IACUCProtocol,
%          DefaultProtocol, DefaultDataPath, SavingFcn, TimerPeriod,
%          VideoRootDir, IntanRootDir, IntanSettingsFile, BehaviorGUI, Links,
%          Archived.
%
% Returns:
%   P - struct with the same fields, or [] when cancelled.
%
% The Session Defaults tab holds what used to be in RunExpt's Customize dialog.
% Those settings describe a paradigm, not a rig: which function saves the data,
% how fast the timer runs, where recordings go, which behavior GUI runs. A
% project applies them when its subjects are added to a session
% (epsych.SubjectRoster.assignToSession), so a rig that runs two studies stops
% needing the operator to re-enter them between sessions.
%
% No session default may be left blank. Every field arrives already filled --
% from the value most recently used in this dialog, else from the machine's own
% preference -- because a blank one silently inherits whatever the last session
% happened to leave behind, which is exactly the ambiguity moving these here was
% meant to remove. The two exceptions are deliberate: Default Protocol, because a
% study is often created before its protocol exists, and Intan Settings File,
% because there is no default file to propose and the protocol usually carries
% its own.
%
% The Behavior GUI dropdown also offers what other projects in this roster already
% use, rather than only the session's preference: the roster is the shared
% thing, so a rig that has never run a paradigm still proposes its GUI, and this
% window works with no session open.
%
% Links are validated here, not only on commit, so an address the roster would
% refuse is caught while the operator can still see and fix what they typed --
% and the normalized form (https:// added, a path turned into a file URL) is
% written back into the table, so what is saved is what is shown.
%
% See also: epsych.SubjectRoster.addProject, epsych.SubjectRoster.assignToSession,
%   epsych.SubjectRoster.makeLink, epsych.DefaultSubject.open
arguments
    self
    seed (1,1) struct
end

P = [];
accepted = false;
result = struct();   % filled by onOK; shared with the nested callbacks

PREFS = self.PREF_GROUP;   % local functions are not methods, so it is passed in

isEdit = ~isempty(seed.Name);
if isEdit
    title = 'Edit Project';
else
    title = 'New Project';
end

% ---- what each field opens on -------------------------------------------
% Most recently used first, then this machine's own setting. An older project
% whose field is empty is filled the same way, so saving it writes a value
% instead of leaving the session to guess.
vProtocol  = localSeed(seed.DefaultProtocol,  PREFS, 'Protocol', '');
vDataPath  = localSeed(seed.DefaultDataPath,  PREFS, 'DataPath', ...
    char(getpref('RunExpt','DataPath', cd)));
vSaving    = localSeed(seed.SavingFcn,        PREFS, 'SavingFcn', ...
    char(getpref('ep_RunExpt_FUNCS','SavingFcn','ep_SaveDataFcn')));
vBehaviorGUI = localSeed(seed.BehaviorGUI,       PREFS, 'BehaviorGUI', ...
    char(getpref('ep_RunExpt_FUNCS','BehaviorGUI','ep_GenericGUI')));
vVideo     = localSeed(seed.VideoRootDir,     PREFS, 'VideoRootDir', ...
    localOr(char(getpref('ep_RunExpt_Video','RecordingRootDir','')), vDataPath));
vIntan     = localSeed(seed.IntanRootDir,     PREFS, 'IntanRootDir', ...
    localOr(char(getpref('ep_RunExpt_Intan','RecordingRootDir','')), vDataPath));
vIntanSet  = localSeed(seed.IntanSettingsFile, PREFS, 'IntanSettingsFile', ...
    char(getpref('ep_RunExpt_Intan','SettingsFile','')));
vInvestigator = localSeed(seed.Investigator,  PREFS, 'Investigator', '');
vIacuc        = localSeed(seed.IACUCProtocol, PREFS, 'IACUCProtocol', '');

% NaN is the record's "inherit" state; the field itself cannot hold it.
vPeriod = seed.TimerPeriod;
if ~isscalar(vPeriod) || isnan(vPeriod)
    vPeriod = localRecentPeriod(PREFS, getpref('ep_RunExpt_TIMER','Period',0.01));
end

dlg = uifigure('Name', title, 'Position', [0 0 620 560], ...
    'Resize','off', 'WindowStyle','modal', ...
    'WindowKeyPressFcn', @(~,evt) onKey(evt), ...
    'CloseRequestFcn', @(~,~) onCancel());
movegui(dlg, 'center');

gOuter = uigridlayout(dlg, [2 1]);
gOuter.RowHeight = {'1x', 32};
gOuter.Padding = [12 12 12 12];
gOuter.RowSpacing = 8;

tg = uitabgroup(gOuter);
tg.Layout.Row = 1; tg.Layout.Column = 1;

% ---- TAB: Project --------------------------------------------------------
tabProject = uitab(tg, 'Title','Project');
g = uigridlayout(tabProject, [6 3]);
g.RowHeight = {28, 28, 28, 64, 148, 24};
g.ColumnWidth = {130, '1x', 80};
g.Padding = [10 12 10 12];
g.RowSpacing = 8;
g.ColumnSpacing = 8;

localLabel(g, 1, 'Project Name:');
efName = uieditfield(g, 'text', 'Value', seed.Name);
efName.Layout.Row = 1; efName.Layout.Column = [2 3];

localLabel(g, 2, 'Investigator:');
ddInvestigator = uidropdown(g, 'Editable','on', ...
    'Items', localItems(PREFS, 'Investigator', vInvestigator, ''), ...
    'Value', vInvestigator, ...
    'Tooltip', 'Who is responsible for this study. Recorded, not enforced.');
ddInvestigator.Layout.Row = 2; ddInvestigator.Layout.Column = [2 3];

localLabel(g, 3, 'IACUC Protocol:');
ddIacuc = uidropdown(g, 'Editable','on', ...
    'Items', localItems(PREFS, 'IACUCProtocol', vIacuc, ''), ...
    'Value', vIacuc, ...
    'Tooltip', ['Animal-use protocol number this study runs under.' newline ...
                'Kept with the project so an export can answer for it.']);
ddIacuc.Layout.Row = 3; ddIacuc.Layout.Column = [2 3];

localLabel(g, 4, 'Notes:');
taNotes = uitextarea(g, 'Value', seed.Notes);
taNotes.Layout.Row = 4; taNotes.Layout.Column = [2 3];

% ---- Links: an editable two-column table plus its own button strip --------
% A table rather than a growing stack of edit fields: the count is unbounded,
% both columns are free text, and reordering by retyping is good enough for a
% handful of addresses.
localLabel(g, 5, 'Links:');
gLinks = uigridlayout(g, [1 2]);
gLinks.Layout.Row = 5; gLinks.Layout.Column = [2 3];
gLinks.ColumnWidth = {'1x', 80};
gLinks.Padding = [0 0 0 0];
gLinks.ColumnSpacing = 6;

tblLinks = uitable(gLinks, ...
    'ColumnName', {'Label','Address'}, ...
    'ColumnFormat', {'char','char'}, ...
    'ColumnEditable', [true true], ...
    'ColumnWidth', {130, 'auto'}, ...
    'RowName', {}, ...
    'SelectionType','row', ...
    'Data', localLinkData(seed.Links), ...
    'Tooltip', ['Addresses for this study''s logs: notebook, shared sheet, issue tracker.' newline ...
                'http, https, mailto, and file addresses only, plus local and UNC paths.' newline ...
                'Leave the label blank to name a link after its host.']);

gLinkBtns = uigridlayout(gLinks, [4 1]);
gLinkBtns.RowHeight = {24, 24, 24, '1x'};
gLinkBtns.Padding = [0 0 0 0];
gLinkBtns.RowSpacing = 4;
uibutton(gLinkBtns, 'Text','Add', 'ButtonPushedFcn', @(~,~) onAddLink());
uibutton(gLinkBtns, 'Text','Remove', 'ButtonPushedFcn', @(~,~) onRemoveLink());
uibutton(gLinkBtns, 'Text','Open', 'ButtonPushedFcn', @(~,~) onOpenLink(), ...
    'Tooltip','Open the selected address, to check it before saving.');

cbArchived = uicheckbox(g, 'Text','Archived (hidden from the project list)', ...
    'Value', seed.Archived, ...
    'Tooltip', ['Finished studies stay in the roster with their subjects and' newline ...
                'protocol memory intact; they are only hidden from the list.']);
cbArchived.Layout.Row = 6; cbArchived.Layout.Column = [2 3];

% ---- TAB: Session Defaults ----------------------------------------------
tabSession = uitab(tg, 'Title','Session Defaults');
gs = uigridlayout(tabSession, [8 3]);
gs.RowHeight = repmat({28}, 1, 8);
gs.Scrollable = 'on';
gs.ColumnWidth = {130, '1x', 80};
gs.Padding = [10 12 10 12];
gs.RowSpacing = 8;
gs.ColumnSpacing = 8;

localLabel(gs, 1, 'Default Protocol:');
% Every session default carries a Tag: this tab is what the self-test and the
% smoke test look at, and finding a field by its label would break on rewording.
ddProtocol = uidropdown(gs, 'Editable','on', ...
    'Tag','ProjectDlg_DefaultProtocol', ...
    'Items', localItems(PREFS, 'Protocol', vProtocol, ''), ...
    'Value', vProtocol, ...
    'Tooltip', ['Applied to a member with no protocol of its own.' newline ...
                'The one field that may be left empty: a study often exists' newline ...
                'before its protocol does, and then each subject is given one.']);
ddProtocol.Layout.Row = 1; ddProtocol.Layout.Column = 2;
btnProtocol = uibutton(gs, 'Text','Browse...', 'ButtonPushedFcn', @(~,~) onBrowseProtocol());
btnProtocol.Layout.Row = 1; btnProtocol.Layout.Column = 3;

localLabel(gs, 2, 'Data Save Path:');
ddDataPath = uidropdown(gs, 'Editable','on', ...
    'Tag','ProjectDlg_DefaultDataPath', ...
    'Items', localItems(PREFS, 'DataPath', vDataPath, ''), ...
    'Value', vDataPath, ...
    'Tooltip', ['Where this project''s data is written: <path>\<subject>\.' newline ...
                'Applied to the session when this project''s subjects are added.']);
ddDataPath.Layout.Row = 2; ddDataPath.Layout.Column = 2;
btnDataPath = uibutton(gs, 'Text','Browse...', 'ButtonPushedFcn', @(~,~) onBrowseDataPath());
btnDataPath.Layout.Row = 2; btnDataPath.Layout.Column = 3;

localLabel(gs, 3, 'Saving Function:');
ddSaving = uidropdown(gs, 'Editable','on', ...
    'Tag','ProjectDlg_SavingFcn', ...
    'Items', localItems(PREFS, 'SavingFcn', vSaving, 'ep_SaveDataFcn'), ...
    'Value', vSaving, ...
    'Tooltip', ['Function called after the run to save the session''s data.' newline ...
                'Signature: SaveFcn(RUNTIME) -- 1 input, 0 outputs.' newline ...
                'Default: ep_SaveDataFcn']);
ddSaving.Layout.Row = 3; ddSaving.Layout.Column = 2;
ddSaving.ValueChangedFcn = @(h,~) onSavingChanged(h);
onSavingChanged(ddSaving);
btnSaving = uibutton(gs, 'Text','Reset', ...
    'ButtonPushedFcn', @(~,~) localReset(ddSaving, 'ep_SaveDataFcn', @onSavingChanged));
btnSaving.Layout.Row = 3; btnSaving.Layout.Column = 3;

localLabel(gs, 4, 'Behavior GUI:');
ddBehaviorGUI = uidropdown(gs, 'Editable','on', ...
    'Tag','ProjectDlg_BehaviorGUI', ...
    'Items', localBehaviorGUIItems(self.Roster, PREFS, vBehaviorGUI), ...
    'Value', localBehaviorGUIDisplay(vBehaviorGUI), ...
    'Tooltip', ['Behavior GUI launched when a session with this project''s subjects starts.' newline ...
                'Signature: BehaviorGUI(RUNTIME) -- typically a gui.BehaviorGUI subclass.' newline ...
                'Pick one another project uses, or type a class or function name.' newline ...
                '"(none)" runs no GUI; "(session default)" leaves the session''s own.']);
ddBehaviorGUI.Layout.Row = 4; ddBehaviorGUI.Layout.Column = 2;
ddBehaviorGUI.ValueChangedFcn = @(h,~) onBehaviorGUIChanged(h);
onBehaviorGUIChanged(ddBehaviorGUI);
btnBehaviorGUI = uibutton(gs, 'Text','Reset', ...
    'ButtonPushedFcn', @(~,~) localReset(ddBehaviorGUI, 'ep_GenericGUI', @onBehaviorGUIChanged));
btnBehaviorGUI.Layout.Row = 4; btnBehaviorGUI.Layout.Column = 3;

localLabel(gs, 5, 'Timer Period (s):');
efPeriod = uieditfield(gs, 'numeric', 'Value', vPeriod, ...
    'Tag','ProjectDlg_TimerPeriod', ...
    'Limits', [0.001 1], ...
    'LowerLimitInclusive','on', 'UpperLimitInclusive','on', ...
    'Tooltip', ['PsychTimer callback period in seconds.' newline ...
                'Smaller values increase timing resolution at the cost of CPU.' newline ...
                'Valid range: 0.001 - 1 s.  Default: 0.01']);
efPeriod.Layout.Row = 5; efPeriod.Layout.Column = 2;
btnPeriod = uibutton(gs, 'Text','Reset', 'ButtonPushedFcn', @(~,~) set(efPeriod,'Value',0.01));
btnPeriod.Layout.Row = 5; btnPeriod.Layout.Column = 3;

localLabel(gs, 6, 'Video Recording Path:');
ddVideo = uidropdown(gs, 'Editable','on', ...
    'Tag','ProjectDlg_VideoRootDir', ...
    'Items', localItems(PREFS, 'VideoRootDir', vVideo, ''), ...
    'Value', vVideo, ...
    'Tooltip', ['Root for webcam recordings made via the "Record video" toolbar toggle.' newline ...
                'Files save to <root>\<subject>\<subject>_<yyMMddTHHmmss>.ts.']);
ddVideo.Layout.Row = 6; ddVideo.Layout.Column = 2;
btnVideo = uibutton(gs, 'Text','Browse...', ...
    'ButtonPushedFcn', @(~,~) onBrowseDir(ddVideo, 'Select Video Recording Root'));
btnVideo.Layout.Row = 6; btnVideo.Layout.Column = 3;

localLabel(gs, 7, 'Intan Recording Path:');
ddIntan = uidropdown(gs, 'Editable','on', ...
    'Tag','ProjectDlg_IntanRootDir', ...
    'Items', localItems(PREFS, 'IntanRootDir', vIntan, ''), ...
    'Value', vIntan, ...
    'Tooltip', ['Root for Intan RHX recordings, under <root>\<subject>\.' newline ...
                'Must contain no spaces (RHX commands cannot express them).']);
ddIntan.Layout.Row = 7; ddIntan.Layout.Column = 2;
btnIntan = uibutton(gs, 'Text','Browse...', ...
    'ButtonPushedFcn', @(~,~) onBrowseDir(ddIntan, 'Select Intan Recording Root'));
btnIntan.Layout.Row = 7; btnIntan.Layout.Column = 3;

% A plain field, not a dropdown like its neighbours: this is the one session
% default with no value to propose, since the .eprot usually carries its own
% and wins over whatever is set here.
localLabel(gs, 8, 'Intan Settings File:');
efIntanSet = uieditfield(gs, 'text', 'Value', vIntanSet, ...
    'Tag','ProjectDlg_IntanSettingsFile', ...
    'Placeholder', '(none; the protocol''s own setting is used)', ...
    'Tooltip', ['RHX .xml loaded when the Intan interface connects.' newline ...
                'A protocol that names its own settings file wins over this.' newline ...
                'Must contain no spaces (RHX commands cannot express them).']);
efIntanSet.Layout.Row = 8; efIntanSet.Layout.Column = 2;
btnIntanSet = uibutton(gs, 'Text','Browse...', ...
    'ButtonPushedFcn', @(~,~) onBrowseFile(efIntanSet, 'Select Intan Settings File', ...
        {'*.xml','RHX Settings (*.xml)'; '*.*','All Files (*.*)'}));
btnIntanSet.Layout.Row = 8; btnIntanSet.Layout.Column = 3;

% ---- Buttons -------------------------------------------------------------
gButtons = uigridlayout(gOuter, [1 3]);
gButtons.Layout.Row = 2; gButtons.Layout.Column = 1;
gButtons.ColumnWidth = {'1x', 90, 90};
gButtons.Padding = [0 0 0 0];
uilabel(gButtons, 'Text','');
uibutton(gButtons, 'Text','OK', 'ButtonPushedFcn', @(~,~) onOK());
uibutton(gButtons, 'Text','Cancel', 'ButtonPushedFcn', @(~,~) onCancel());

focus(efName);
uiwait(dlg);

if accepted
    P = result;
end

if isgraphics(dlg)
    dlg.CloseRequestFcn = '';
    delete(dlg);
end

% -------------------------------------------------------------------
    function onOK()
        name = strtrim(efName.Value);

        [ok, why] = epsych.SubjectRoster.isNameSafe(name);
        if ~ok
            uialert(dlg, why, title, 'Icon','warning');
            return
        end

        % Checked here so the operator does not lose typed notes to an error
        % raised after the dialog closes.
        other = self.Roster.findProject(name);
        if ~isempty(other) && ~strcmp(other.Name, seed.Name)
            uialert(dlg, sprintf('A project named "%s" already exists.', name), ...
                title, 'Icon','warning');
            return
        end

        dataPath = strtrim(ddDataPath.Value);
        saving   = strtrim(ddSaving.Value);
        behGUI   = localBehaviorGUIValue(ddBehaviorGUI.Value);
        video    = strtrim(ddVideo.Value);
        intan    = strtrim(ddIntan.Value);
        intanSet = strtrim(efIntanSet.Value);

        % A blank session default would silently inherit whatever the previous
        % session left on the rig, so it is refused rather than stored.
        blanks = {};
        if isempty(dataPath), blanks{end+1} = 'Data Save Path'; end
        if isempty(saving),   blanks{end+1} = 'Saving Function'; end
        if isempty(video),    blanks{end+1} = 'Video Recording Path'; end
        if isempty(intan),    blanks{end+1} = 'Intan Recording Path'; end
        if ~isempty(blanks)
            uialert(dlg, sprintf(['%s must have a value. Every session default ' ...
                'is filled in for you; clearing one would leave the session to ' ...
                'follow whatever the previous study left behind.'], ...
                strjoin(blanks, ', ')), title, 'Icon','warning');
            return
        end

        % RHX set/execute commands cannot express spaces, so a spaced path
        % would fail silently at run time rather than here.
        if any(isspace(intan))
            uialert(dlg, 'The Intan Recording Path must not contain spaces (RHX command limitation).', ...
                title, 'Icon','warning');
            return
        end
        if ~isempty(intanSet) && any(isspace(intanSet))
            uialert(dlg, 'The Intan Settings File path must not contain spaces (RHX command limitation).', ...
                title, 'Icon','warning');
            return
        end

        [links, ok] = collectLinks();
        if ~ok, return, end

        result = struct( ...
            'Name', name, ...
            'Notes', char(strjoin(string(taNotes.Value), newline)), ...
            'Investigator', strtrim(ddInvestigator.Value), ...
            'IACUCProtocol', strtrim(ddIacuc.Value), ...
            'DefaultProtocol', strtrim(ddProtocol.Value), ...
            'DefaultDataPath', dataPath, ...
            'SavingFcn', saving, ...
            'TimerPeriod', efPeriod.Value, ...
            'VideoRootDir', video, ...
            'IntanRootDir', intan, ...
            'IntanSettingsFile', intanSet, ...
            'BehaviorGUI', behGUI, ...
            'Archived', cbArchived.Value);

        % Assigned, never passed to struct() above: a struct-array value makes
        % struct() build one result per link instead of one result holding them.
        result.Links = links;

        % Remembered only once the values are accepted, so a cancelled or
        % refused dialog does not seed the next project with a typo.
        localRemember(PREFS, 'Protocol',      result.DefaultProtocol);
        localRemember(PREFS, 'DataPath',      dataPath);
        localRemember(PREFS, 'SavingFcn',     saving);
        localRemember(PREFS, 'BehaviorGUI',   behGUI);
        localRemember(PREFS, 'VideoRootDir',  video);
        localRemember(PREFS, 'IntanRootDir',  intan);
        localRemember(PREFS, 'IntanSettingsFile', intanSet);
        localRemember(PREFS, 'Investigator',  result.Investigator);
        localRemember(PREFS, 'IACUCProtocol', result.IACUCProtocol);
        setpref(PREFS, 'RecentTimerPeriod', efPeriod.Value);

        accepted = true;
        uiresume(dlg);
    end

% -------------------------------------------------------------------
    function [links, ok] = collectLinks()
        % Table rows -> validated link records, refusing on the first bad one.
        links = epsych.SubjectRoster.emptyLink();
        ok = false;

        data = tblLinks.Data;
        for i = 1:size(data, 1)
            label = strtrim(char(string(data{i,1})));
            addr  = strtrim(char(string(data{i,2})));

            % A wholly blank row is the one Add just created and the operator
            % thought better of; a labelled row with no address is a mistake.
            if isempty(addr) && isempty(label), continue, end
            if isempty(addr)
                uialert(dlg, sprintf('Link %d ("%s") has no address.', i, label), ...
                    title, 'Icon','warning');
                return
            end

            try
                links(end+1) = epsych.SubjectRoster.makeLink(label, addr);
            catch ME
                uialert(dlg, sprintf('Link %d: %s', i, ME.message), title, 'Icon','warning');
                return
            end

            % Show what will actually be stored.
            data{i,1} = links(end).Label;
            data{i,2} = links(end).URL;
        end

        tblLinks.Data = data;
        ok = true;
    end

% -------------------------------------------------------------------
    function onAddLink()
        tblLinks.Data = [tblLinks.Data; {'', ''}];
        tblLinks.Selection = size(tblLinks.Data, 1);
    end

% -------------------------------------------------------------------
    function onRemoveLink()
        rows = tblLinks.Selection;
        if isempty(rows), return, end
        data = tblLinks.Data;
        data(rows, :) = [];
        tblLinks.Data = data;
        tblLinks.Selection = [];
    end

% -------------------------------------------------------------------
    function onOpenLink()
        rows = tblLinks.Selection;
        if isempty(rows)
            uialert(dlg, 'Select a link first.', title, 'Icon','info');
            return
        end

        try
            epsych.SubjectRoster.openLink(char(string(tblLinks.Data{rows(1), 2})));
        catch ME
            vprintf(0, 1, ME);
            uialert(dlg, ME.message, title, 'Icon','warning');
        end
    end

% -------------------------------------------------------------------
    function onCancel()
        accepted = false;
        uiresume(dlg);
    end

% -------------------------------------------------------------------
    function onKey(evt)
        if strcmp(evt.Key, 'escape')
            onCancel();
        elseif strcmp(evt.Key, 'return') && any(strcmp(evt.Modifier, 'control'))
            onOK();
        end
    end

% -------------------------------------------------------------------
    function onBehaviorGUIChanged(h)
        % Flag a name that will not resolve at run start, without refusing it:
        % a lab may add its GUI to the path later, and the same tint is what the
        % Customize dialog's function fields use.
        v = localBehaviorGUIValue(h.Value);
        localTint(h, isempty(v) || strcmpi(v, epsych.SubjectRoster.BEHAVIORGUI_NONE) ...
            || ~isempty(which(v)));
    end

% -------------------------------------------------------------------
    function onSavingChanged(h)
        % Same tint for the saving function, including its signature: a
        % SaveFcn with the wrong shape fails at the end of a run, when the
        % data it was supposed to write is the only copy.
        v = strtrim(h.Value);
        if isempty(v) || isempty(which(v))
            localTint(h, false);
        else
            localTint(h, nargin(v) == 1 && nargout(v) == 0);
        end
    end

% -------------------------------------------------------------------
    function onBrowseProtocol()
        % PDir is the repo-wide last-protocol-directory pref, shared with
        % RunExpt's own protocol pickers, so a lab that keeps its protocols in
        % one place browses there from either window.
        start = ddProtocol.Value;
        if isempty(start) || ~isfile(start)
            start = getpref('ep_RunExpt_Setup','PDir',cd);
            if ~isfolder(start), start = cd; end
        end
        [fn, pn] = uigetfile( ...
            {'*.eprot;*.prot','Protocol Files (*.eprot, *.prot)'; '*.*','All Files (*.*)'}, ...
            'Select Default Protocol', start);
        if isequal(fn, 0), return, end
        setpref('ep_RunExpt_Setup','PDir', pn);
        localSetValue(ddProtocol, fullfile(pn, fn));
    end

% -------------------------------------------------------------------
    function onBrowseDataPath()
        % Projects are usually created in batches under one data root, so the
        % last folder picked here is a better start than cd. Falls back to the
        % session's default data path (RunExpt/DataPath) the first time.
        start = ddDataPath.Value;
        if isempty(start) || ~isfolder(start)
            start = getpref('ep_RunExpt_Setup','DDir', ...
                char(getpref('RunExpt','DataPath',cd)));
            if ~isfolder(start), start = cd; end
        end
        pth = uigetdir(start, 'Select Default Data Path');
        if isequal(pth, 0), return, end
        setpref('ep_RunExpt_Setup','DDir', pth);
        localSetValue(ddDataPath, pth);
    end

% -------------------------------------------------------------------
    function onBrowseDir(h, ttl)
        start = h.Value;
        if isempty(start) || ~isfolder(start)
            start = ddDataPath.Value;
            if ~isfolder(start), start = cd; end
        end
        pth = uigetdir(start, ttl);
        if isequal(pth, 0), return, end
        localSetValue(h, pth);
    end

% -------------------------------------------------------------------
    function onBrowseFile(h, ttl, filter)
        start = cd;
        if ~isempty(h.Value)
            d = fileparts(h.Value);
            if ~isempty(d) && isfolder(d), start = d; end
        end
        [fn, pn] = uigetfile(filter, ttl, start);
        if isequal(fn, 0), return, end
        h.Value = fullfile(pn, fn);
    end

end

% -----------------------------------------------------------------------
function localLabel(g, row, text)
h = uilabel(g, 'Text', text, 'HorizontalAlignment','right');
h.Layout.Row = row;
h.Layout.Column = 1;
end

% -----------------------------------------------------------------------
function localTint(h, ok)
% The light-red "this will not resolve" background the Customize dialog uses.
INVALID_COLOR = [1.00 0.85 0.85];
VALID_COLOR   = [1.00 1.00 1.00];
if ok
    h.BackgroundColor = VALID_COLOR;
else
    h.BackgroundColor = INVALID_COLOR;
end
end

% -----------------------------------------------------------------------
function localSetValue(h, value)
% Assign to an editable dropdown. The value has to be in Items first: an
% editable dropdown accepts typed text, but not a programmatic value it has
% never heard of.
value = char(value);
if ~any(strcmp(h.Items, value))
    h.Items = [{value}, h.Items];
end
h.Value = value;
end

% -----------------------------------------------------------------------
function localReset(h, value, changedFcn)
% Restore a field's built-in default and re-run its validation.
localSetValue(h, value);
changedFcn(h);
end

% -----------------------------------------------------------------------
function v = localOr(v, fallback)
% First non-empty of the two.
if isempty(strtrim(char(v))), v = fallback; end
v = char(v);
end

% -----------------------------------------------------------------------
% Recently-used values. A lab creating a run of projects types each path,
% function, and protocol number once; the next project opens on them. Stored
% per field under the roster preference group, so they follow the user rather
% than the roster file -- two rigs sharing one roster still browse their own
% drives.
% -----------------------------------------------------------------------
function v = localSeed(current, group, key, dflt)
% What a field opens on: its stored value, else the most recent one used here,
% else this machine's own setting.
v = strtrim(char(string(current)));
if ~isempty(v), return, end

recent = localRecent(group, key);
if ~isempty(recent)
    v = recent{1};
    return
end

v = strtrim(char(string(dflt)));
end

% -----------------------------------------------------------------------
function p = localRecentPeriod(group, dflt)
% The timer period is a number, so it is remembered as one rather than in the
% recents list, which holds text.
p = getpref(group, 'RecentTimerPeriod', dflt);
if ~isscalar(p) || ~isnumeric(p) || isnan(p) || p < 0.001 || p > 1
    p = 0.01;
end
end

% -----------------------------------------------------------------------
function items = localRecent(group, key)
% The stored most-recently-used list for one field, normalized to a row cellstr.
items = getpref(group, ['Recent' key], {});
if isstring(items)
    items = cellstr(items(:));
elseif ischar(items)
    items = {items};
elseif ~iscell(items)
    items = {};
end
items = cellfun(@(v) char(string(v)), items(:)', 'UniformOutput', false);
items = items(~cellfun(@isempty, items));
end

% -----------------------------------------------------------------------
function items = localItems(group, key, current, dflt)
% A dropdown's item list: recents first, then the current value and built-in
% default, de-duplicated (case-insensitive) with order preserved. Never empty
% and never containing an empty string -- a blank item renders as a line the
% operator cannot tell from a rendering glitch.
items = [localRecent(group, key), {char(current)}, {char(dflt)}];
items = items(~cellfun(@(v) isempty(strtrim(v)), items));

keep = true(1, numel(items));
for ii = 2:numel(items)
    if any(strcmpi(items(1:ii-1), items{ii}))
        keep(ii) = false;
    end
end
items = items(keep);

if isempty(items), items = {''}; end
end

% -----------------------------------------------------------------------
function localRemember(group, key, value)
% Record an accepted value at the front of its most-recently-used list.
MAX_RECENT = 12;

value = strtrim(char(string(value)));
if isempty(value), return, end

recent = localRecent(group, key);
recent = [{value}, recent(~strcmpi(recent, value))];
if numel(recent) > MAX_RECENT
    recent = recent(1:MAX_RECENT);
end

setpref(group, ['Recent' key], recent);
end

% -----------------------------------------------------------------------
function data = localLinkData(links)
% Link records -> the table's cell array. Always a cell, never [], so an empty
% project still shows two editable columns rather than a bare grey panel.
data = cell(numel(links), 2);
for i = 1:numel(links)
    data{i,1} = links(i).Label;
    data{i,2} = links(i).URL;
end
end

% -----------------------------------------------------------------------
% The Behavior GUI dropdown stores a function name but shows a sentence for the two
% states that are not one: '' (inherit) and BEHAVIORGUI_NONE (launch nothing). An
% empty dropdown item would render as a blank line the operator cannot tell from
% a rendering glitch, so the mapping lives in these three functions and nowhere
% else.
% -----------------------------------------------------------------------
function items = localBehaviorGUIItems(roster, group, current)
% Both sentinels, every behavior GUI already used in this roster, the recently-used
% ones, the built-in default, and whatever this project holds -- de-duplicated,
% order preserved.
items = {localBehaviorGUIDisplay(''), localBehaviorGUIDisplay(epsych.SubjectRoster.BEHAVIORGUI_NONE)};

used = {};
if ~isempty(roster) && isvalid(roster) && ~isempty(roster.Projects)
    used = {roster.Projects.BehaviorGUI};
    used = used(~cellfun(@isempty, used));
end

items = [items, used, localRecent(group, 'BehaviorGUI'), {'ep_GenericGUI'}, ...
    {localBehaviorGUIDisplay(current)}];
items = items(~cellfun(@isempty, items));

keep = true(1, numel(items));
for ii = 2:numel(items)
    if any(strcmpi(items(1:ii-1), items{ii}))
        keep(ii) = false;
    end
end
items = items(keep);
end

% -----------------------------------------------------------------------
function txt = localBehaviorGUIDisplay(value)
% Stored value -> what the dropdown shows.
value = char(string(value));
if isempty(value)
    txt = '(session default)';
elseif strcmpi(value, epsych.SubjectRoster.BEHAVIORGUI_NONE)
    txt = '(none)';
else
    txt = value;
end
end

% -----------------------------------------------------------------------
function value = localBehaviorGUIValue(txt)
% What the dropdown shows -> the stored value.
txt = strtrim(char(string(txt)));
switch lower(txt)
    case {'', '(session default)'}
        value = '';
    case {'(none)', 'none'}
        value = epsych.SubjectRoster.BEHAVIORGUI_NONE;
    otherwise
        value = txt;
end
end
