function P = projectDialog_(self, seed)
% P = projectDialog_(self, seed)
% Modal dialog for a project's name, notes, and defaults.
%
% Shaped after epsych.DefaultSubject.open: modal uifigure, uiwait, [] on
% cancel, Esc cancels and Ctrl+Enter accepts.
%
% Parameters:
%   seed - struct with Name, Notes, DefaultProtocol, DefaultDataPath, BoxGUI.
%
% Returns:
%   P - struct with the same fields, or [] when cancelled.
%
% The Box GUI dropdown offers what other projects in this roster already use,
% rather than the session's RecentBoxFig preference: the roster is the shared
% thing, so a rig that has never run a paradigm still proposes its GUI, and this
% window works with no session open.
%
% See also: epsych.SubjectRoster.addProject, epsych.DefaultSubject.open
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

dlg = uifigure('Name', title, 'Position', [0 0 480 366], ...
    'Resize','off', 'WindowStyle','modal', ...
    'WindowKeyPressFcn', @(~,evt) onKey(evt), ...
    'CloseRequestFcn', @(~,~) onCancel());
movegui(dlg, 'center');

g = uigridlayout(dlg, [6 3]);
g.RowHeight = {28, 90, 28, 28, 28, 32};
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

localLabel(g, 3, 'Default Protocol:');
efProtocol = uieditfield(g, 'text', 'Value', seed.DefaultProtocol, ...
    'Tooltip', ['Applied to a member with no protocol of its own.' newline ...
                'Leave empty to browse for one each time.']);
efProtocol.Layout.Row = 3; efProtocol.Layout.Column = 2;
btnProtocol = uibutton(g, 'Text','Browse...', 'ButtonPushedFcn', @(~,~) onBrowseProtocol());
btnProtocol.Layout.Row = 3; btnProtocol.Layout.Column = 3;

localLabel(g, 4, 'Default Data Path:');
efDataPath = uieditfield(g, 'text', 'Value', seed.DefaultDataPath, ...
    'Tooltip', 'Where this project''s data is saved. Leave empty to use the session default.');
efDataPath.Layout.Row = 4; efDataPath.Layout.Column = 2;
btnDataPath = uibutton(g, 'Text','Browse...', 'ButtonPushedFcn', @(~,~) onBrowseDataPath());
btnDataPath.Layout.Row = 4; btnDataPath.Layout.Column = 3;

localLabel(g, 5, 'Box GUI:');
ddBoxGUI = uidropdown(g, 'Editable','on', ...
    'Items', localBoxGuiItems(self.Roster, seed.BoxGUI), ...
    'Value', localBoxGuiDisplay(seed.BoxGUI), ...
    'Tooltip', ['Behavior GUI launched when a session with this project''s subjects starts.' newline ...
                'Signature: BoxGUI(RUNTIME) -- typically a gui.BoxGUI subclass.' newline ...
                'Pick one another project uses, or type a class or function name.' newline ...
                'Session default: whatever Customize last left in FUNCS.BoxFig (ep_GenericGUI).']);
ddBoxGUI.Layout.Row = 5; ddBoxGUI.Layout.Column = [2 3];
ddBoxGUI.ValueChangedFcn = @(h,~) onBoxGuiChanged(h);
onBoxGuiChanged(ddBoxGUI);

gButtons = uigridlayout(g, [1 3]);
gButtons.Layout.Row = 6; gButtons.Layout.Column = [1 3];
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

        result = struct( ...
            'Name', name, ...
            'Notes', char(strjoin(string(taNotes.Value), newline)), ...
            'DefaultProtocol', strtrim(efProtocol.Value), ...
            'DefaultDataPath', strtrim(efDataPath.Value), ...
            'BoxGUI', localBoxGuiValue(ddBoxGUI.Value));

        accepted = true;
        uiresume(dlg);
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
