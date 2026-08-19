function P = projectDialog_(self, seed, options)
% P = projectDialog_(self, seed)
% P = projectDialog_(self, seed, Title = 'Copy Project')
% Modal dialog for a project's identity, its session-defaults template, links,
% and archived flag.
%
% Shaped after epsych.DefaultSubject.open: modal uifigure, uiwait, [] on
% cancel, Esc cancels and Ctrl+Enter accepts.
%
% Parameters:
%   seed - struct with Name, Notes, Investigator, IACUCProtocol,
%          DefaultProtocol, and the SESSION_FIELDS (DefaultDataPath, SavingFcn,
%          TimerPeriod, the four Timer*Fcn callbacks, VideoRootDir,
%          IntanRootDir, IntanSettingsFile, BehaviorGUI), plus Links and
%          Archived.
%
% Options:
%   Title - window title. The dialog otherwise infers it from the seed, which
%           cannot tell an edit from a copy: both arrive with a name filled in.
%
% Returns:
%   P - struct with the same fields, or [] when cancelled.
%
% The Session Defaults tab holds what used to be in RunExpt's Customize dialog.
% Those settings describe a paradigm, not a rig: which function saves the data,
% which callbacks the timer runs and how fast, where recordings go, which
% behavior GUI runs. They are a TEMPLATE: stamped onto a subject's membership
% when it joins the project (epsych.SubjectRoster.assign), and edits here do
% not reach existing members -- Re-apply Project Template is the deliberate
% push. The field grid itself is built by sessionDefaultsGrid_, shared with
% the membership dialog, which also owns the seeding and refusal rules (no
% session default may be left blank; Default Protocol and Intan Settings File
% are the deliberate exceptions).
%
% Links are validated here, not only on commit, so an address the roster would
% refuse is caught while the operator can still see and fix what they typed --
% and the normalized form (https:// added, a path turned into a file URL) is
% written back into the table, so what is saved is what is shown.
%
% See also: epsych.SubjectRoster.addProject, gui.SubjectManager.sessionDefaultsGrid_,
%   gui.SubjectManager.membershipDialog_, epsych.SubjectRoster.makeLink
arguments
    self
    seed (1,1) struct
    options.Title (1,:) char = ''
end

P = [];
accepted = false;
result = struct();   % filled by onOK; shared with the nested callbacks

PREFS = self.PREF_GROUP;   % local functions are not methods, so it is passed in

if ~isempty(options.Title)
    title = options.Title;
elseif ~isempty(seed.Name)
    title = 'Edit Project';
else
    title = 'New Project';
end

vInvestigator = localSeed(seed.Investigator,  PREFS, 'Investigator', '');
vIacuc        = localSeed(seed.IACUCProtocol, PREFS, 'IACUCProtocol', '');

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
efName = uieditfield(g, 'text', 'Value', seed.Name, 'Tag','ProjectDlg_Name');
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

% ---- TAB: Session Defaults (template) ------------------------------------
% Stamped onto each subject's membership when it joins; edits here do not
% reach existing members (Project > Re-apply Project Template does that).
tabSession = uitab(tg, 'Title','Session Defaults (template)');
S = self.sessionDefaultsGrid_(tabSession, seed, 'ProjectDlg_');

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

        [vals, okv, vmsg] = S.collect();
        if ~okv
            uialert(dlg, vmsg, title, 'Icon','warning');
            return
        end

        [links, ok] = collectLinks();
        if ~ok, return, end

        result = struct( ...
            'Name', name, ...
            'Notes', char(strjoin(string(taNotes.Value), newline)), ...
            'Investigator', strtrim(ddInvestigator.Value), ...
            'IACUCProtocol', strtrim(ddIacuc.Value), ...
            'DefaultProtocol', vals.DefaultProtocol, ...
            'DefaultDataPath', vals.DefaultDataPath, ...
            'SavingFcn', vals.SavingFcn, ...
            'TimerStartFcn', vals.TimerStartFcn, ...
            'TimerRunTimeFcn', vals.TimerRunTimeFcn, ...
            'TimerStopFcn', vals.TimerStopFcn, ...
            'TimerErrorFcn', vals.TimerErrorFcn, ...
            'TimerPeriod', vals.TimerPeriod, ...
            'VideoRootDir', vals.VideoRootDir, ...
            'IntanRootDir', vals.IntanRootDir, ...
            'IntanSettingsFile', vals.IntanSettingsFile, ...
            'BehaviorGUI', vals.BehaviorGUI, ...
            'Archived', cbArchived.Value);

        % Assigned, never passed to struct() above: a struct-array value makes
        % struct() build one result per link instead of one result holding them.
        result.Links = links;

        % Remembered only once the values are accepted, so a cancelled or
        % refused dialog does not seed the next project with a typo.
        S.remember(vals);
        localRemember(PREFS, 'Investigator',  result.Investigator);
        localRemember(PREFS, 'IACUCProtocol', result.IACUCProtocol);

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

end

% -----------------------------------------------------------------------
function localLabel(g, row, text)
h = uilabel(g, 'Text', text, 'HorizontalAlignment','right');
h.Layout.Row = row;
h.Layout.Column = 1;
end

% -----------------------------------------------------------------------
% Small copies of sessionDefaultsGrid_'s MRU helpers, for the two identity
% fields (Investigator, IACUC) that live on the Project tab rather than in the
% shared grid.
% -----------------------------------------------------------------------
function v = localSeed(current, group, key, dflt)
% What a field opens on: its stored value, else the most recent one used here,
% else the given default.
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
% default, de-duplicated (case-insensitive) with order preserved.
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
