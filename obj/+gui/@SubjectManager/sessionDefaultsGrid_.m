function S = sessionDefaultsGrid_(self, parent, seed, tagPrefix, options)
% S = self.sessionDefaultsGrid_(parent, seed, tagPrefix)
% S = self.sessionDefaultsGrid_(parent, seed, tagPrefix, IncludeProtocol = false)
% Build the session-settings field grid shared by the project (template) and
% membership dialogs.
%
% One builder for both dialogs because the field set is one thing: the
% membership carries SESSION_FIELDS and the project's template stamps them, so
% two hand-maintained grids would be the pair that drifts. The tag prefix is
% what tells the dialogs apart ('ProjectDlg_' vs 'MembershipDlg_'), so the
% smoke tests' ^ProjectDlg_ probe keeps meaning "the template".
%
% Parameters:
%   parent    - uitab or container the grid is built into.
%   seed      - record supplying the opening values: a project or a membership
%               (identical SESSION_FIELDS names; DefaultProtocol only read when
%               IncludeProtocol).
%   tagPrefix - prepended to each field's Tag.
%
% Options:
%   IncludeProtocol - also build the Default Protocol row (project template
%                     only; a membership resolves its protocol through the
%                     protocol-memory workflow, not here). Default true.
%
% Returns:
%   S - struct with the field handles plus three closures the dialog's OK path
%       uses:
%         [vals, ok, msg] = S.collect()  values trimmed and mapped; ok false
%                                        with a user-facing msg on refusal
%                                        (blank session default, spaced Intan
%                                        path)
%         S.remember(vals)               push accepted values onto the
%                                        per-field MRU lists
%
% Every field arrives already filled -- from the value most recently used
% here, else from the machine's own setting, else the built-in -- because a
% blank one would silently inherit whatever the last session left behind.
%
% See also: gui.SubjectManager.projectDialog_, gui.SubjectManager.membershipDialog_,
%   epsych.SubjectRoster.updateMembership
arguments
    self
    parent
    seed (1,1) struct
    tagPrefix (1,:) char
    options.IncludeProtocol (1,1) logical = true
end

PREFS = self.PREF_GROUP;

% ---- what each field opens on -------------------------------------------
vDataPath  = localSeed(seed.DefaultDataPath,  PREFS, 'DataPath', ...
    char(getpref('RunExpt','DataPath', cd)));
vSaving    = localSeed(seed.SavingFcn,        PREFS, 'SavingFcn', 'ep_SaveDataFcn');
vBehaviorGUI = localSeed(seed.BehaviorGUI,       PREFS, 'BehaviorGUI', 'ep_GenericGUI');
vVideo     = localSeed(seed.VideoRootDir,     PREFS, 'VideoRootDir', ...
    localOr(char(getpref('ep_RunExpt_Video','RecordingRootDir','')), vDataPath));
vIntan     = localSeed(seed.IntanRootDir,     PREFS, 'IntanRootDir', ...
    localOr(char(getpref('ep_RunExpt_Intan','RecordingRootDir','')), vDataPath));
vIntanSet  = localSeed(seed.IntanSettingsFile, PREFS, 'IntanSettingsFile', ...
    char(getpref('ep_RunExpt_Intan','SettingsFile','')));

% The timer callbacks seed from the MRU else the built-in literal -- there is
% no machine preference layer for them, by design.
TIMER_FIELDS = { ...  % record field, label, built-in, nargin, nargout
    'TimerStartFcn',   'Timer Start Fcn:',    'ep_TimerFcn_Start',   2, 1; ...
    'TimerRunTimeFcn', 'Timer RunTime Fcn:',  'ep_TimerFcn_RunTime', 1, 1; ...
    'TimerStopFcn',    'Timer Stop Fcn:',     'ep_TimerFcn_Stop',    1, 1; ...
    'TimerErrorFcn',   'Timer Error Fcn:',    'ep_TimerFcn_Error',   1, 1};
vTimer = cell(1, 4);
for k = 1:4
    vTimer{k} = localSeed(seed.(TIMER_FIELDS{k,1}), PREFS, TIMER_FIELDS{k,1}, ...
        TIMER_FIELDS{k,3});
end

% NaN is the record's "inherit" state; the field itself cannot hold it.
vPeriod = seed.TimerPeriod;
if ~isscalar(vPeriod) || isnan(vPeriod)
    vPeriod = localRecentPeriod(PREFS, 0.01);
end

nRows = 11 + options.IncludeProtocol;
gs = uigridlayout(parent, [nRows 3]);
gs.RowHeight = repmat({28}, 1, nRows);
gs.Scrollable = 'on';
gs.ColumnWidth = {130, '1x', 80};
gs.Padding = [10 12 10 12];
gs.RowSpacing = 8;
gs.ColumnSpacing = 8;

row = 0;
ddProtocol = [];
if options.IncludeProtocol
    vProtocol = localSeed(seed.DefaultProtocol, PREFS, 'Protocol', '');
    row = row + 1;
    localLabel(gs, row, 'Default Protocol:');
    % Every session default carries a Tag: this tab is what the self-test and
    % the smoke test look at, and finding a field by its label would break on
    % rewording.
    ddProtocol = uidropdown(gs, 'Editable','on', ...
        'Tag',[tagPrefix 'DefaultProtocol'], ...
        'Items', localItems(PREFS, 'Protocol', vProtocol, ''), ...
        'Value', vProtocol, ...
        'Tooltip', ['Applied to a member with no protocol of its own.' newline ...
                    'The one field that may be left empty: a study often exists' newline ...
                    'before its protocol does, and then each subject is given one.']);
    ddProtocol.Layout.Row = row; ddProtocol.Layout.Column = 2;
    btnProtocol = uibutton(gs, 'Text','Browse...', 'ButtonPushedFcn', @(~,~) onBrowseProtocol());
    btnProtocol.Layout.Row = row; btnProtocol.Layout.Column = 3;
end

row = row + 1;
localLabel(gs, row, 'Data Save Path:');
ddDataPath = uidropdown(gs, 'Editable','on', ...
    'Tag',[tagPrefix 'DefaultDataPath'], ...
    'Items', localItems(PREFS, 'DataPath', vDataPath, ''), ...
    'Value', vDataPath, ...
    'Tooltip', ['Where this data is written: <path>\<subject>\.' newline ...
                'Applied to the session when the subject is added.']);
ddDataPath.Layout.Row = row; ddDataPath.Layout.Column = 2;
btnDataPath = uibutton(gs, 'Text','Browse...', 'ButtonPushedFcn', @(~,~) onBrowseDataPath());
btnDataPath.Layout.Row = row; btnDataPath.Layout.Column = 3;

row = row + 1;
localLabel(gs, row, 'Saving Function:');
ddSaving = uidropdown(gs, 'Editable','on', ...
    'Tag',[tagPrefix 'SavingFcn'], ...
    'Items', localItems(PREFS, 'SavingFcn', vSaving, 'ep_SaveDataFcn'), ...
    'Value', vSaving, ...
    'Tooltip', ['Function called after the run to save the session''s data.' newline ...
                'Signature: SaveFcn(RUNTIME) -- 1 input, 0 outputs.' newline ...
                'Default: ep_SaveDataFcn']);
ddSaving.Layout.Row = row; ddSaving.Layout.Column = 2;
ddSaving.ValueChangedFcn = @(h,~) onSavingChanged(h);
onSavingChanged(ddSaving);
btnSaving = uibutton(gs, 'Text','Reset', ...
    'ButtonPushedFcn', @(~,~) localReset(ddSaving, 'ep_SaveDataFcn', @onSavingChanged));
btnSaving.Layout.Row = row; btnSaving.Layout.Column = 3;

row = row + 1;
localLabel(gs, row, 'Behavior GUI:');
ddBehaviorGUI = uidropdown(gs, 'Editable','on', ...
    'Tag',[tagPrefix 'BehaviorGUI'], ...
    'Items', localBehaviorGUIItems(self.Roster, PREFS, vBehaviorGUI), ...
    'Value', localBehaviorGUIDisplay(vBehaviorGUI), ...
    'Tooltip', ['Behavior GUI launched when a session with this subject starts.' newline ...
                'Signature: BehaviorGUI(RUNTIME) -- typically a gui.BehaviorGUI subclass.' newline ...
                'Pick one another project uses, or type a class or function name.' newline ...
                '"(none)" runs no GUI; "(built-in default)" is ep_GenericGUI.']);
ddBehaviorGUI.Layout.Row = row; ddBehaviorGUI.Layout.Column = 2;
ddBehaviorGUI.ValueChangedFcn = @(h,~) onBehaviorGUIChanged(h);
onBehaviorGUIChanged(ddBehaviorGUI);
btnBehaviorGUI = uibutton(gs, 'Text','Reset', ...
    'ButtonPushedFcn', @(~,~) localReset(ddBehaviorGUI, 'ep_GenericGUI', @onBehaviorGUIChanged));
btnBehaviorGUI.Layout.Row = row; btnBehaviorGUI.Layout.Column = 3;

row = row + 1;
localLabel(gs, row, 'Timer Period (s):');
efPeriod = uieditfield(gs, 'numeric', 'Value', vPeriod, ...
    'Tag',[tagPrefix 'TimerPeriod'], ...
    'Limits', [0.001 1], ...
    'LowerLimitInclusive','on', 'UpperLimitInclusive','on', ...
    'Tooltip', ['PsychTimer callback period in seconds.' newline ...
                'Smaller values increase timing resolution at the cost of CPU.' newline ...
                'Valid range: 0.001 - 1 s.  Default: 0.01']);
efPeriod.Layout.Row = row; efPeriod.Layout.Column = 2;
btnPeriod = uibutton(gs, 'Text','Reset', 'ButtonPushedFcn', @(~,~) set(efPeriod,'Value',0.01));
btnPeriod.Layout.Row = row; btnPeriod.Layout.Column = 3;

% The four PsychTimer lifecycle callbacks: the trial loop itself. A lab
% running a custom loop names its functions here, which is the only remaining
% way to configure them -- there is no dialog on the session and no machine
% preference.
ddTimer = cell(1, 4);
for k = 1:4
    row = row + 1;
    localLabel(gs, row, TIMER_FIELDS{k,2});
    ddTimer{k} = uidropdown(gs, 'Editable','on', ...
        'Tag',[tagPrefix TIMER_FIELDS{k,1}], ...
        'Items', localItems(PREFS, TIMER_FIELDS{k,1}, vTimer{k}, TIMER_FIELDS{k,3}), ...
        'Value', vTimer{k}, ...
        'Tooltip', sprintf(['PsychTimer %s callback.\nSignature: %d input(s), ' ...
            '%d output.\nDefault: %s'], ...
            erase(TIMER_FIELDS{k,1}, ["Timer" "Fcn"]), ...
            TIMER_FIELDS{k,4}, TIMER_FIELDS{k,5}, TIMER_FIELDS{k,3}));
    ddTimer{k}.Layout.Row = row; ddTimer{k}.Layout.Column = 2;
    ddTimer{k}.ValueChangedFcn = @(h,~) onTimerFcnChanged(h, TIMER_FIELDS{k,4}, TIMER_FIELDS{k,5});
    onTimerFcnChanged(ddTimer{k}, TIMER_FIELDS{k,4}, TIMER_FIELDS{k,5});
    btnTimer = uibutton(gs, 'Text','Reset', ...
        'ButtonPushedFcn', @(h,~) localResetTimer(ddTimer{k}, TIMER_FIELDS(k,:)));
    btnTimer.Layout.Row = row; btnTimer.Layout.Column = 3;
end

row = row + 1;
localLabel(gs, row, 'Video Recording Path:');
ddVideo = uidropdown(gs, 'Editable','on', ...
    'Tag',[tagPrefix 'VideoRootDir'], ...
    'Items', localItems(PREFS, 'VideoRootDir', vVideo, ''), ...
    'Value', vVideo, ...
    'Tooltip', ['Root for webcam recordings made via the "Record video" toolbar toggle.' newline ...
                'Files save to <root>\<subject>\<subject>_<yyMMddTHHmmss>.ts.']);
ddVideo.Layout.Row = row; ddVideo.Layout.Column = 2;
btnVideo = uibutton(gs, 'Text','Browse...', ...
    'ButtonPushedFcn', @(~,~) onBrowseDir(ddVideo, 'Select Video Recording Root'));
btnVideo.Layout.Row = row; btnVideo.Layout.Column = 3;

row = row + 1;
localLabel(gs, row, 'Intan Recording Path:');
ddIntan = uidropdown(gs, 'Editable','on', ...
    'Tag',[tagPrefix 'IntanRootDir'], ...
    'Items', localItems(PREFS, 'IntanRootDir', vIntan, ''), ...
    'Value', vIntan, ...
    'Tooltip', ['Root for Intan RHX recordings, under <root>\<subject>\.' newline ...
                'Must contain no spaces (RHX commands cannot express them).']);
ddIntan.Layout.Row = row; ddIntan.Layout.Column = 2;
btnIntan = uibutton(gs, 'Text','Browse...', ...
    'ButtonPushedFcn', @(~,~) onBrowseDir(ddIntan, 'Select Intan Recording Root'));
btnIntan.Layout.Row = row; btnIntan.Layout.Column = 3;

% A plain field, not a dropdown like its neighbours: this is the one session
% default with no value to propose, since the .eprot usually carries its own
% and wins over whatever is set here.
row = row + 1;
localLabel(gs, row, 'Intan Settings File:');
efIntanSet = uieditfield(gs, 'text', 'Value', vIntanSet, ...
    'Tag',[tagPrefix 'IntanSettingsFile'], ...
    'Placeholder', '(none; the protocol''s own setting is used)', ...
    'Tooltip', ['RHX .xml loaded when the Intan interface connects.' newline ...
                'A protocol that names its own settings file wins over this.' newline ...
                'Must contain no spaces (RHX commands cannot express them).']);
efIntanSet.Layout.Row = row; efIntanSet.Layout.Column = 2;
btnIntanSet = uibutton(gs, 'Text','Browse...', ...
    'ButtonPushedFcn', @(~,~) onBrowseFile(efIntanSet, 'Select Intan Settings File', ...
        {'*.xml','RHX Settings (*.xml)'; '*.*','All Files (*.*)'}));
btnIntanSet.Layout.Row = row; btnIntanSet.Layout.Column = 3;

S = struct();
S.Grid        = gs;
S.Protocol    = ddProtocol;
S.DataPath    = ddDataPath;
S.Saving      = ddSaving;
S.BehaviorGUI = ddBehaviorGUI;
S.Period      = efPeriod;
S.TimerStart  = ddTimer{1};
S.TimerRunTime = ddTimer{2};
S.TimerStop   = ddTimer{3};
S.TimerError  = ddTimer{4};
S.Video       = ddVideo;
S.Intan       = ddIntan;
S.IntanSet    = efIntanSet;
S.collect     = @collect;
S.remember    = @remember;

% -------------------------------------------------------------------
    function [vals, ok, msg] = collect()
        % Trimmed, mapped values plus the shared refusals. The caller renders
        % msg in its own uialert so both dialogs refuse identically.
        ok = false;
        msg = '';

        vals = struct( ...
            'DefaultDataPath', strtrim(ddDataPath.Value), ...
            'SavingFcn', strtrim(ddSaving.Value), ...
            'BehaviorGUI', localBehaviorGUIValue(ddBehaviorGUI.Value), ...
            'TimerPeriod', efPeriod.Value, ...
            'TimerStartFcn', strtrim(ddTimer{1}.Value), ...
            'TimerRunTimeFcn', strtrim(ddTimer{2}.Value), ...
            'TimerStopFcn', strtrim(ddTimer{3}.Value), ...
            'TimerErrorFcn', strtrim(ddTimer{4}.Value), ...
            'VideoRootDir', strtrim(ddVideo.Value), ...
            'IntanRootDir', strtrim(ddIntan.Value), ...
            'IntanSettingsFile', strtrim(efIntanSet.Value));
        if options.IncludeProtocol
            vals.DefaultProtocol = strtrim(ddProtocol.Value);
        end

        % A blank session default would silently inherit whatever the previous
        % session left on the rig, so it is refused rather than stored.
        blanks = {};
        if isempty(vals.DefaultDataPath), blanks{end+1} = 'Data Save Path'; end
        if isempty(vals.SavingFcn),   blanks{end+1} = 'Saving Function'; end
        if isempty(vals.TimerStartFcn),   blanks{end+1} = 'Timer Start Fcn'; end
        if isempty(vals.TimerRunTimeFcn), blanks{end+1} = 'Timer RunTime Fcn'; end
        if isempty(vals.TimerStopFcn),    blanks{end+1} = 'Timer Stop Fcn'; end
        if isempty(vals.TimerErrorFcn),   blanks{end+1} = 'Timer Error Fcn'; end
        if isempty(vals.VideoRootDir),    blanks{end+1} = 'Video Recording Path'; end
        if isempty(vals.IntanRootDir),    blanks{end+1} = 'Intan Recording Path'; end
        if ~isempty(blanks)
            msg = sprintf(['%s must have a value. Every session default ' ...
                'is filled in for you; clearing one would leave the session to ' ...
                'follow whatever the previous study left behind.'], ...
                strjoin(blanks, ', '));
            return
        end

        % RHX set/execute commands cannot express spaces, so a spaced path
        % would fail silently at run time rather than here.
        if any(isspace(vals.IntanRootDir))
            msg = 'The Intan Recording Path must not contain spaces (RHX command limitation).';
            return
        end
        if ~isempty(vals.IntanSettingsFile) && any(isspace(vals.IntanSettingsFile))
            msg = 'The Intan Settings File path must not contain spaces (RHX command limitation).';
            return
        end

        ok = true;
    end

% -------------------------------------------------------------------
    function remember(vals)
        % Record accepted values, so the next dialog opens on them. Called
        % only after the values are accepted, so a cancelled or refused dialog
        % does not seed the next one with a typo.
        if options.IncludeProtocol
            localRemember(PREFS, 'Protocol', vals.DefaultProtocol);
        end
        localRemember(PREFS, 'DataPath',      vals.DefaultDataPath);
        localRemember(PREFS, 'SavingFcn',     vals.SavingFcn);
        localRemember(PREFS, 'BehaviorGUI',   vals.BehaviorGUI);
        localRemember(PREFS, 'TimerStartFcn',   vals.TimerStartFcn);
        localRemember(PREFS, 'TimerRunTimeFcn', vals.TimerRunTimeFcn);
        localRemember(PREFS, 'TimerStopFcn',    vals.TimerStopFcn);
        localRemember(PREFS, 'TimerErrorFcn',   vals.TimerErrorFcn);
        localRemember(PREFS, 'VideoRootDir',  vals.VideoRootDir);
        localRemember(PREFS, 'IntanRootDir',  vals.IntanRootDir);
        localRemember(PREFS, 'IntanSettingsFile', vals.IntanSettingsFile);
        setpref(PREFS, 'RecentTimerPeriod', vals.TimerPeriod);
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
            localTint(h, localArity(v, 1, 0));
        end
    end

% -------------------------------------------------------------------
    function onTimerFcnChanged(h, nIn, nOut)
        % The timer callbacks get the tint too, arity included: a loop
        % function with the wrong shape fails on the first tick of a run.
        v = strtrim(h.Value);
        if isempty(v) || isempty(which(v))
            localTint(h, false);
        else
            localTint(h, localArity(v, nIn, nOut));
        end
    end

% -------------------------------------------------------------------
    function localResetTimer(h, spec)
        localSetValue(h, spec{3});
        onTimerFcnChanged(h, spec{4}, spec{5});
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
            {'*.eprot','Protocol Files (*.eprot)'; '*.*','All Files (*.*)'}, ...
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
function tf = localArity(fcn, nIn, nOut)
% Whether a function matches the expected signature. nargin/nargout are
% negative for varargin/varargout, which can satisfy anything, and throw for
% names that resolve to something uncallable -- treated as "cannot tell", so
% the tint stays honest rather than red on a technicality.
try
    ni = nargin(fcn);
    no = nargout(fcn);
catch
    tf = true;
    return
end
tf = (ni == nIn || ni < 0) && (no == nOut || no < 0);
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
% The Behavior GUI dropdown stores a function name but shows a sentence for the two
% states that are not one: '' (inherit) and BEHAVIORGUI_NONE (launch nothing). An
% empty dropdown item would render as a blank line the operator cannot tell from
% a rendering glitch, so the mapping lives in these three functions and nowhere
% else.
% -----------------------------------------------------------------------
function items = localBehaviorGUIItems(roster, group, current)
% Both sentinels, every behavior GUI already used in this roster, the recently-used
% ones, the built-in default, and whatever this record holds -- de-duplicated,
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
    txt = '(built-in default)';
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
    case {'', '(built-in default)', '(session default)'}
        value = '';
    case {'(none)', 'none'}
        value = epsych.SubjectRoster.BEHAVIORGUI_NONE;
    otherwise
        value = txt;
end
end
