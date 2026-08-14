function P = projectDialog_(self, seed)
% P = projectDialog_(self, seed)
% Modal dialog for a project's name, notes, defaults, links, and archived flag.
%
% Shaped after epsych.DefaultSubject.open: modal uifigure, uiwait, [] on
% cancel, Esc cancels and Ctrl+Enter accepts.
%
% Parameters:
%   seed - struct with Name, Notes, Investigator, IACUCProtocol,
%          DefaultProtocol, DefaultDataPath, BoxGUI, Links, Archived.
%
% Returns:
%   P - struct with the same fields, or [] when cancelled.
%
% The Box GUI dropdown offers what other projects in this roster already use,
% rather than the session's RecentBoxFig preference: the roster is the shared
% thing, so a rig that has never run a paradigm still proposes its GUI, and this
% window works with no session open.
%
% Links are validated here, not only on commit, so an address the roster would
% refuse is caught while the operator can still see and fix what they typed --
% and the normalized form (https:// added, a path turned into a file URL) is
% written back into the table, so what is saved is what is shown.
%
% See also: epsych.SubjectRoster.addProject, epsych.SubjectRoster.makeLink,
%   epsych.DefaultSubject.open
arguments
    self
    seed (1,1) struct
end

P = [];
accepted = false;
result = struct();   % filled by onOK; shared with the nested callbacks

isEdit = ~isempty(seed.Name);
if isEdit
    title = 'Edit Project';
else
    title = 'New Project';
end

dlg = uifigure('Name', title, 'Position', [0 0 580 548], ...
    'Resize','off', 'WindowStyle','modal', ...
    'WindowKeyPressFcn', @(~,evt) onKey(evt), ...
    'CloseRequestFcn', @(~,~) onCancel());
movegui(dlg, 'center');

g = uigridlayout(dlg, [10 3]);
g.RowHeight = {28, 72, 28, 28, 28, 28, 28, 132, 24, 32};
g.ColumnWidth = {130, '1x', 80};
g.Padding = [12 12 12 12];
g.RowSpacing = 8;
g.ColumnSpacing = 8;

localLabel(g, 1, 'Project Name:');
efName = uieditfield(g, 'text', 'Value', seed.Name);
efName.Layout.Row = 1; efName.Layout.Column = [2 3];

localLabel(g, 2, 'Notes:');
taNotes = uitextarea(g, 'Value', seed.Notes);
taNotes.Layout.Row = 2; taNotes.Layout.Column = [2 3];

localLabel(g, 3, 'Investigator:');
efInvestigator = uieditfield(g, 'text', 'Value', seed.Investigator, ...
    'Tooltip', 'Who is responsible for this study. Recorded, not enforced.');
efInvestigator.Layout.Row = 3; efInvestigator.Layout.Column = [2 3];

localLabel(g, 4, 'IACUC Protocol:');
efIacuc = uieditfield(g, 'text', 'Value', seed.IACUCProtocol, ...
    'Tooltip', ['Animal-use protocol number this study runs under.' newline ...
                'Kept with the project so an export can answer for it.']);
efIacuc.Layout.Row = 4; efIacuc.Layout.Column = [2 3];

localLabel(g, 5, 'Default Protocol:');
efProtocol = uieditfield(g, 'text', 'Value', seed.DefaultProtocol, ...
    'Tooltip', ['Applied to a member with no protocol of its own.' newline ...
                'Leave empty to browse for one each time.']);
efProtocol.Layout.Row = 5; efProtocol.Layout.Column = 2;
btnProtocol = uibutton(g, 'Text','Browse...', 'ButtonPushedFcn', @(~,~) onBrowseProtocol());
btnProtocol.Layout.Row = 5; btnProtocol.Layout.Column = 3;

localLabel(g, 6, 'Default Data Path:');
efDataPath = uieditfield(g, 'text', 'Value', seed.DefaultDataPath, ...
    'Tooltip', 'Where this project''s data is saved. Leave empty to use the session default.');
efDataPath.Layout.Row = 6; efDataPath.Layout.Column = 2;
btnDataPath = uibutton(g, 'Text','Browse...', 'ButtonPushedFcn', @(~,~) onBrowseDataPath());
btnDataPath.Layout.Row = 6; btnDataPath.Layout.Column = 3;

localLabel(g, 7, 'Box GUI:');
ddBoxGUI = uidropdown(g, 'Editable','on', ...
    'Items', localBoxGuiItems(self.Roster, seed.BoxGUI), ...
    'Value', localBoxGuiDisplay(seed.BoxGUI), ...
    'Tooltip', ['Behavior GUI launched when a session with this project''s subjects starts.' newline ...
                'Signature: BoxGUI(RUNTIME) -- typically a gui.BoxGUI subclass.' newline ...
                'Pick one another project uses, or type a class or function name.' newline ...
                'Session default: whatever Customize last left in FUNCS.BoxFig (ep_GenericGUI).']);
ddBoxGUI.Layout.Row = 7; ddBoxGUI.Layout.Column = [2 3];
ddBoxGUI.ValueChangedFcn = @(h,~) onBoxGuiChanged(h);
onBoxGuiChanged(ddBoxGUI);

% ---- Links: an editable two-column table plus its own button strip --------
% A table rather than a growing stack of edit fields: the count is unbounded,
% both columns are free text, and reordering by retyping is good enough for a
% handful of addresses.
localLabel(g, 8, 'Links:');
gLinks = uigridlayout(g, [1 2]);
gLinks.Layout.Row = 8; gLinks.Layout.Column = [2 3];
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
cbArchived.Layout.Row = 9; cbArchived.Layout.Column = [2 3];

gButtons = uigridlayout(g, [1 3]);
gButtons.Layout.Row = 10; gButtons.Layout.Column = [1 3];
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

        [links, ok] = collectLinks();
        if ~ok, return, end

        result = struct( ...
            'Name', name, ...
            'Notes', char(strjoin(string(taNotes.Value), newline)), ...
            'Investigator', strtrim(efInvestigator.Value), ...
            'IACUCProtocol', strtrim(efIacuc.Value), ...
            'DefaultProtocol', strtrim(efProtocol.Value), ...
            'DefaultDataPath', strtrim(efDataPath.Value), ...
            'BoxGUI', localBoxGuiValue(ddBoxGUI.Value), ...
            'Archived', cbArchived.Value);

        % Assigned, never passed to struct() above: a struct-array value makes
        % struct() build one result per link instead of one result holding them.
        result.Links = links;

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
    function onBoxGuiChanged(h)
        % Flag a name that will not resolve at run start, without refusing it:
        % a lab may add its GUI to the path later, and the same tint is what the
        % Customize dialog's function fields use.
        INVALID_COLOR = [1.00 0.85 0.85];
        VALID_COLOR   = [1.00 1.00 1.00];
        v = localBoxGuiValue(h.Value);
        if isempty(v) || strcmpi(v, epsych.SubjectRoster.BOXGUI_NONE) || ~isempty(which(v))
            h.BackgroundColor = VALID_COLOR;
        else
            h.BackgroundColor = INVALID_COLOR;
        end
    end

% -------------------------------------------------------------------
    function onBrowseProtocol()
        % PDir is the repo-wide last-protocol-directory pref, shared with
        % RunExpt's own protocol pickers, so a lab that keeps its protocols in
        % one place browses there from either window.
        start = efProtocol.Value;
        if isempty(start) || ~isfile(start)
            start = getpref('ep_RunExpt_Setup','PDir',cd);
            if ~isfolder(start), start = cd; end
        end
        [fn, pn] = uigetfile( ...
            {'*.eprot;*.prot','Protocol Files (*.eprot, *.prot)'; '*.*','All Files (*.*)'}, ...
            'Select Default Protocol', start);
        if isequal(fn, 0), return, end
        setpref('ep_RunExpt_Setup','PDir', pn);
        efProtocol.Value = fullfile(pn, fn);
    end

% -------------------------------------------------------------------
    function onBrowseDataPath()
        % Projects are usually created in batches under one data root, so the
        % last folder picked here is a better start than cd. Falls back to the
        % session's default data path (RunExpt/DataPath) the first time.
        start = efDataPath.Value;
        if isempty(start) || ~isfolder(start)
            start = getpref('ep_RunExpt_Setup','DDir', ...
                char(getpref('RunExpt','DataPath',cd)));
            if ~isfolder(start), start = cd; end
        end
        pth = uigetdir(start, 'Select Default Data Path');
        if isequal(pth, 0), return, end
        setpref('ep_RunExpt_Setup','DDir', pth);
        efDataPath.Value = pth;
    end

end

% -----------------------------------------------------------------------
function localLabel(g, row, text)
h = uilabel(g, 'Text', text, 'HorizontalAlignment','right');
h.Layout.Row = row;
h.Layout.Column = 1;
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
% The Box GUI dropdown stores a function name but shows a sentence for the two
% states that are not one: '' (inherit) and BOXGUI_NONE (launch nothing). An
% empty dropdown item would render as a blank line the operator cannot tell from
% a rendering glitch, so the mapping lives in these three functions and nowhere
% else.
% -----------------------------------------------------------------------
function items = localBoxGuiItems(roster, current)
% Both sentinels, every box GUI already used in this roster, the built-in
% default, and whatever this project holds -- de-duplicated, order preserved.
items = {localBoxGuiDisplay(''), localBoxGuiDisplay(epsych.SubjectRoster.BOXGUI_NONE)};

used = {};
if ~isempty(roster) && isvalid(roster) && ~isempty(roster.Projects)
    used = {roster.Projects.BoxGUI};
    used = used(~cellfun(@isempty, used));
end

items = [items, used, {'ep_GenericGUI'}, {char(current)}];
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
function txt = localBoxGuiDisplay(value)
% Stored value -> what the dropdown shows.
value = char(string(value));
if isempty(value)
    txt = '(session default)';
elseif strcmpi(value, epsych.SubjectRoster.BOXGUI_NONE)
    txt = '(none)';
else
    txt = value;
end
end

% -----------------------------------------------------------------------
function value = localBoxGuiValue(txt)
% What the dropdown shows -> the stored value.
txt = strtrim(char(string(txt)));
switch lower(txt)
    case {'', '(session default)'}
        value = '';
    case {'(none)', 'none'}
        value = epsych.SubjectRoster.BOXGUI_NONE;
    otherwise
        value = txt;
end
end
