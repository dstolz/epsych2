function OpenCustomizeDialog(self)
% OpenCustomizeDialog — Open the unified Customize Settings dialog.
% Presents the settings that describe THIS MACHINE — where it browses for
% configs, where it writes its log, which roster it shares, and the data root
% new projects start from — in a single modal window. Changes are validated and
% applied on OK. The individual Define* methods remain available for
% programmatic use.
%
% What a paradigm decides rather than a rig — saving function, timer period,
% behavior GUI, and the video and Intan recording roots — lives on the project
% instead (gui.SubjectManager > Edit Project > Session Defaults), and is applied
% to the session when that project's subjects are added. The two notes in this
% dialog say so where the fields used to be, so an operator who looks for one
% is told where it went rather than concluding it was removed.
if self.STATE >= PRGMSTATE.RUNNING, return, end

% Gather current values ------------------------------------------------
F         = self.FUNCS;
addSubj   = char(fieldOr_(F, 'AddSubjectFcn', 'epsych.DefaultSubject.open'));
% The rig's stored value, not the session's: a project may have overridden the
% live session, and showing that here would invite OK to write one study's path
% back into the machine preference.
dataPath  = char(getpref('RunExpt','DataPath', char(self.DefaultDataPath)));
cfgRoot   = char(getpref('ep_RunExpt_Setup','ConfigBrowserRootDir',''));
if isempty(cfgRoot)
    cfgRoot = char(getpref('ep_RunExpt_Setup','CDir',cd));
end
if ~exist(cfgRoot,'dir'), cfgRoot = cd; end
% Shown empty when unset, so the field reads as "the EPsych default" rather
% than proposing the repository path as something the operator chose.
logDir    = '';
if ispref('eplog','LogDir')   % three-arg getpref would create the preference
    logDir = char(getpref('eplog','LogDir'));
end
logViewer = char(getpref('ep_RunExpt_Logging','ExternalViewer',''));
% What "empty" actually resolves to, shown as placeholder text so the operator
% can read the default instead of inferring it. Named from the same functions
% that pick it at run time, and deliberately the built-in rather than
% eplog.defaultLogDir -- clearing the field must preview the fallback, not echo
% the override being cleared.
dfltLogDir    = eplog.builtinLogDir();
dfltLogViewer = epsych.RunExpt.defaultLogViewer();

% The roster is the one path here with no default at all: empty means no roster
% has been chosen yet, and Subjects & Projects will ask before it saves
% anything. Nothing to preview, so the placeholder says that instead.
rosterFile = epsych.SubjectRoster.configuredFile();

% Assemble the recents-backed item list for the function dropdown ------
itemsAddSubj = buildItems_('RecentAddSubjectFcn', addSubj,   'epsych.DefaultSubject.open');

% Build dialog ---------------------------------------------------------
% Close any stale instance (e.g. left from a previous blocked attempt)
stale = findall(groot,'Type','figure','Tag','RunExptCustomize');
if ~isempty(stale), delete(stale); end

ontop = self.AlwaysOnTop(false);
% Sized for the tallest tab (Paths, five rows plus the note). The grid there is
% scrollable as a backstop, but a dialog that opens already scrolled hides
% fields the operator does not know to look for.
dlg = uifigure('Name','Customize EPsych','Tag','RunExptCustomize', ...
    'Resize','off', ...
    'Position',[0 0 560 320]);
dlg.CloseRequestFcn = @(~,~) onClose_();   % set after dlg is assigned
movegui(dlg,'center');
drawnow;          % flush queue so the window renders
figure(dlg);      % bring to front

% Outer grid: tab group + button row
g = uigridlayout(dlg,[2 1]);
g.RowHeight    = {'1x', 46};
g.Padding      = [10 10 10 10];
g.RowSpacing   = 8;

tg = uitabgroup(g);
tg.Layout.Row = 1; tg.Layout.Column = 1;

% ---- TAB: Functions --------------------------------------------------
tabFcn = uitab(tg,'Title','Functions');
gFcn = uigridlayout(tabFcn,[2 3]);
gFcn.RowHeight    = {28, 'fit'};   % row 2 wraps, so it sizes to its text
gFcn.ColumnWidth  = {160, '1x', 80};
gFcn.Padding      = [10 12 10 12];
gFcn.RowSpacing   = 8;
gFcn.ColumnSpacing = 8;

addLabel_(gFcn, 1, 'Add Subject Function:');
ef_addsubj = uidropdown(gFcn,'Editable','on','Items',itemsAddSubj,'Value',addSubj, ...
    'Tooltip', ['Function that collects subject information when adding a new subject.' newline ...
                'Signature: S = AddSubjectFcn(S, boxids)' newline ...
                'Pick a previously-used function or type a new one.' newline ...
                'Default: epsych.DefaultSubject.open']);
ef_addsubj.Layout.Row = 1; ef_addsubj.Layout.Column = 2;
ef_addsubj.ValueChangedFcn = @(h,~) validateFcnField_(h,'addsubj');
addResetBtn_(gFcn, 1, ef_addsubj, 'epsych.DefaultSubject.open', 'addsubj');

% The saving function, behavior GUI, and timer period used to be fields here. They
% belong to a paradigm rather than to a rig, so they are now project properties;
% this line is left in their place so an operator looking for one is told where
% it went instead of concluding the feature was removed.
lblMoved = uilabel(gFcn, 'Text', ...
    ['Saving function, behavior GUI, and timer period: set per project in ' ...
     'Subjects > Subjects & Projects (Project > Edit Project... > Session Defaults).'], ...
    'FontColor',[0.35 0.38 0.42], 'WordWrap','on', ...
    'Tooltip', ['A project applies these to the session when its subjects are added.' newline ...
                'Saving function — SaveFcn(RUNTIME), default ep_SaveDataFcn.' newline ...
                'Behavior GUI — feval(BehaviorGUI, RUNTIME) at run start, default ep_GenericGUI.' newline ...
                'Timer period — PsychTimer period in seconds, default 0.01.']);
lblMoved.Layout.Row = 2; lblMoved.Layout.Column = [1 3];

% Initial validation pass
validateFcnField_(ef_addsubj, 'addsubj');

% ---- TAB: Paths ------------------------------------------------------
tabPaths = uitab(tg,'Title','Paths');
gPaths = uigridlayout(tabPaths,[6 3]);
gPaths.RowHeight    = {28, 28, 28, 28, 28, 'fit'};
gPaths.Scrollable   = 'on';
gPaths.ColumnWidth  = {160, '1x', 80};
gPaths.Padding      = [10 12 10 12];
gPaths.RowSpacing   = 8;
gPaths.ColumnSpacing = 8;

addLabel_(gPaths, 1, 'Data Save Path:');
ef_datapath = uieditfield(gPaths,'text','Value',dataPath, ...
    'Tooltip', ['Default directory where experiment data files are written.' newline ...
                'Saved as the RunExpt DataPath preference, and the value a new' newline ...
                'project starts from. A project that names its own data path' newline ...
                'overrides this for the sessions its subjects run in.']);
ef_datapath.Layout.Row = 1; ef_datapath.Layout.Column = 2;
btn_dp = uibutton(gPaths,'Text','Browse...', ...
    'ButtonPushedFcn', @(~,~) browseDir_(ef_datapath, ef_datapath.Value, 'Select Data Save Path'));
btn_dp.Layout.Row = 1; btn_dp.Layout.Column = 3;

addLabel_(gPaths, 2, 'Config Browser Root:');
ef_cfgroot = uieditfield(gPaths,'text','Value',cfgRoot, ...
    'Tooltip', ['Root folder scanned recursively for *.ecfg configuration files' newline ...
                'shown in the Config Browser dialog.']);
ef_cfgroot.Layout.Row = 2; ef_cfgroot.Layout.Column = 2;
btn_cr = uibutton(gPaths,'Text','Browse...', ...
    'ButtonPushedFcn', @(~,~) browseDir_(ef_cfgroot, ef_cfgroot.Value, 'Select Config Browser Root'));
btn_cr.Layout.Row = 2; btn_cr.Layout.Column = 3;

addLabel_(gPaths, 3, 'Error Log Path:');
ef_logdir = uieditfield(gPaths,'text','Value',logDir, ...
    'Tag','Customize_LogDir', ...
    'Placeholder', dfltLogDir, ...
    'Tooltip', ['Directory for the daily EPsych error log.' newline ...
                'Must be an absolute path; a relative one would follow the working directory.' newline ...
                sprintf('Leave empty for the default, %s.', dfltLogDir)]);
ef_logdir.Layout.Row = 3; ef_logdir.Layout.Column = 2;
btn_ld = uibutton(gPaths,'Text','Browse...', ...
    'ButtonPushedFcn', @(~,~) browseDir_(ef_logdir, ef_logdir.Value, 'Select Error Log Path'));
btn_ld.Layout.Row = 3; btn_ld.Layout.Column = 3;

addLabel_(gPaths, 4, 'Error Log Viewer:');
ef_logviewer = uieditfield(gPaths,'text','Value',logViewer, ...
    'Tag','Customize_LogViewer', ...
    'Placeholder', dfltLogViewer, ...
    'Tooltip', ['Application used by Help > Open Current Error Log (External Viewer).' newline ...
                'Useful when MATLAB owns the .txt association and the plain menu item' newline ...
                'would open the log in the MATLAB editor.' newline ...
                sprintf('Leave empty for the platform default (%s).', dfltLogViewer)]);
ef_logviewer.Layout.Row = 4; ef_logviewer.Layout.Column = 2;
if ispc
    viewerFilter = {'*.exe','Applications (*.exe)'; '*.*','All Files (*.*)'};
else
    viewerFilter = {'*','All Files'};
end
btn_lv = uibutton(gPaths,'Text','Browse...', ...
    'ButtonPushedFcn', @(~,~) browseFile_(ef_logviewer, ef_logviewer.Value, ...
        'Select Error Log Viewer', viewerFilter));
btn_lv.Layout.Row = 4; btn_lv.Layout.Column = 3;

addLabel_(gPaths, 5, 'Subject Roster File:');
ef_roster = uieditfield(gPaths,'text','Value',rosterFile, ...
    'Tag','Customize_RosterFile', ...
    'Placeholder', '(none chosen yet)', ...
    'Tooltip', ['Subject and project roster used by Subjects > Subjects & Projects.' newline ...
                'Put this on a shared drive and point every rig at it to share one roster.' newline ...
                'The file is created when the first subject is added.' newline ...
                'There is no default: left empty, Subjects & Projects asks for one' newline ...
                'before it saves anything.']);
ef_roster.Layout.Row = 5; ef_roster.Layout.Column = 2;
btn_rf = uibutton(gPaths,'Text','Browse...', ...
    'ButtonPushedFcn', @(~,~) browseFile_(ef_roster, ef_roster.Value, ...
        'Select Subject Roster', ...
        {['*' epsych.SubjectRoster.FILE_EXTENSION], ...
         ['Subject Roster (*' epsych.SubjectRoster.FILE_EXTENSION ')']; ...
         '*.*','All Files (*.*)'}));
btn_rf.Layout.Row = 5; btn_rf.Layout.Column = 3;

% The recording roots used to be rows 3-5 here. Same reason as the Functions
% tab: where a study's video and ephys go is the study's business, and a rig
% that runs two paradigms had to re-enter them by hand between sessions.
lblMovedPaths = uilabel(gPaths, 'Text', ...
    ['Video and Intan recording paths: set per project in ' ...
     'Subjects > Subjects & Projects (Project > Edit Project... > Session Defaults).'], ...
    'FontColor',[0.35 0.38 0.42], 'WordWrap','on', ...
    'Tooltip', ['A project applies these to the session when its subjects are added.' newline ...
                'Both fall back to the Data Save Path when no project names one.' newline ...
                'The Intan paths must contain no spaces (RHX cannot express them).']);
lblMovedPaths.Layout.Row = 6; lblMovedPaths.Layout.Column = [1 3];

% ---- Button row ------------------------------------------------------
gBtns = uigridlayout(g,[1 3]);
gBtns.Layout.Row = 2; gBtns.Layout.Column = 1;
gBtns.ColumnWidth  = {'1x',90,90};
gBtns.RowHeight    = {'1x'};
gBtns.Padding      = [0 0 0 0];
gBtns.ColumnSpacing = 8;

spc = uilabel(gBtns,'Text','');
spc.Layout.Row = 1; spc.Layout.Column = 1;

btn_ok = uibutton(gBtns,'Text','OK','ButtonPushedFcn',@(~,~) onOK_());
btn_ok.Layout.Row = 1; btn_ok.Layout.Column = 2;

btn_cancel = uibutton(gBtns,'Text','Cancel','ButtonPushedFcn',@(~,~) onClose_());
btn_cancel.Layout.Row = 1; btn_cancel.Layout.Column = 3;

% -----------------------------------------------------------------------
    function addLabel_(parent, row, txt)
        % Add a right-aligned label into column 1 of the given row.
        lbl = uilabel(parent,'Text',txt,'HorizontalAlignment','right');
        lbl.Layout.Row = row; lbl.Layout.Column = 1;
    end

    function items = buildItems_(prefKey, currentVal, dflt)
        % Assemble a function dropdown's item list: persisted recents first,
        % then the current value and built-in default, de-duplicated
        % (case-insensitive) while preserving order. Guarantees a non-empty
        % list so the dropdown is useful before any history accumulates.
        items = self.GetRecentFuncs(prefKey);
        items = [items, {char(currentVal)}, {char(dflt)}];
        items = items(~cellfun(@isempty, items));
        keep = true(1, numel(items));
        for ii = 2:numel(items)
            if any(strcmpi(items(1:ii-1), items{ii}))
                keep(ii) = false;
            end
        end
        items = items(keep);
        if isempty(items), items = {char(dflt)}; end
    end

    function addResetBtn_(parent, row, ef, dflt, kind)
        % Add a Reset button that restores ef to dflt and re-validates.
        btn = uibutton(parent,'Text','Reset', ...
            'ButtonPushedFcn',@(~,~) resetField_(ef, dflt, kind));
        btn.Layout.Row = row; btn.Layout.Column = 3;
    end

    function resetField_(ef, dflt, kind)
        % Restore the default value and immediately re-validate.
        ef.Value = dflt;
        validateFcnField_(ef, kind);
    end

    function validateFcnField_(ef, kind)
        % Highlight ef with a light-red background when the named function
        % cannot be resolved; restore white when valid or empty.
        INVALID_COLOR = [1.00 0.85 0.85];
        VALID_COLOR   = [1.00 1.00 1.00];
        v = strtrim(ef.Value);
        if isempty(v)
            ef.BackgroundColor = VALID_COLOR;
            return
        end
        switch kind
            case 'addsubj'
                if strcmp(v,'epsych.DefaultSubject.open')
                    ok = ~isempty(which('epsych.DefaultSubject'));
                else
                    ok = ~isempty(which(v));
                end
        end
        if ok
            ef.BackgroundColor = VALID_COLOR;
        else
            ef.BackgroundColor = INVALID_COLOR;
        end
    end

    function browseDir_(ef, startDir, ttl)
        % Open a folder picker; update ef.Value if the user confirms.
        if isempty(startDir) || ~exist(startDir,'dir'), startDir = cd; end
        pth = uigetdir(startDir, ttl);
        if ~isequal(pth, 0)
            ef.Value = pth;
        end
    end

    function browseFile_(ef, startFile, ttl, filter)
        % Open a file picker; update ef.Value with the full path if confirmed.
        startDir = cd;
        if ~isempty(startFile)
            d = fileparts(startFile);
            if ~isempty(d) && exist(d,'dir'), startDir = d; end
        end
        [fn, pn] = uigetfile(filter, ttl, startDir);
        if ~isequal(fn, 0)
            ef.Value = fullfile(pn, fn);
        end
    end

    function onClose_()
        % Restore always-on-top state and destroy the dialog.
        self.AlwaysOnTop(ontop);
        delete(dlg);
    end

    function onOK_()
        % Validate all fields then apply changes and close the dialog.
        errs = {};

        asf = strtrim(ef_addsubj.Value);

        % Add Subject Function
        if ~isempty(asf)
            if strcmp(asf,'epsych.DefaultSubject.open')
                b = which('epsych.DefaultSubject');
            else
                b = which(asf);
            end
            if isempty(b)
                errs{end+1} = sprintf('Add Subject Function ''%s'' was not found on the path.', asf);
            end
        end

        % Error log path: a relative path would follow the working directory,
        % scattering log folders and pointing the Help menu at whichever one is
        % current. Refused here rather than in eplog so the operator sees it
        % against the field they typed it into.
        ld = strtrim(ef_logdir.Value);
        if ~isempty(ld) && ~eplog.isAbsolutePath(ld)
            errs{end+1} = sprintf('Error Log Path must be an absolute path; ''%s'' is relative.', ld);
        end

        if ~isempty(errs)
            uialert(dlg, strjoin(errs, newline), 'Validation Error');
            return
        end

        % FUNCS.SavingFcn, FUNCS.BehaviorGUI, and FUNCS.TimerPeriod are deliberately
        % not touched here: a project may have applied them when its subjects
        % were added, and re-asserting a stale dialog value on every OK would
        % undo that. They are edited on the project instead.

        % Apply: Add Subject Function
        self.FUNCS.AddSubjectFcn = asf;
        setpref('ep_RunExpt_FUNCS','AddSubjectFcn',asf);
        self.RememberRecentFunc('RecentAddSubjectFcn',asf);
        vprintf(0,'Add Subject Function: %s\n',asf);

        % Apply: Data Save Path. The live session follows only when it is still
        % on the rig's value; a project that overrode it keeps its own until its
        % subjects are committed again, which is the whole point of the override.
        dp = strtrim(ef_datapath.Value);
        if ~isempty(dp)
            if strcmp(char(self.DefaultDataPath), dataPath)
                self.DefaultDataPath = string(dp);
            else
                vprintf(1,['This session keeps the project data path "%s"; ' ...
                    'the rig default is now "%s".'], char(self.DefaultDataPath), dp);
            end
            setpref('RunExpt','DataPath',string(dp));
        end

        % Apply: Config Browser Root
        cr = strtrim(ef_cfgroot.Value);
        if ~isempty(cr)
            setpref('ep_RunExpt_Setup','ConfigBrowserRootDir',cr);
            vprintf(1,'Config browser root: %s\n',cr);
        end

        % Apply: Error Log Path (empty clears the override). setLogDir also
        % re-points the running logger, so the next message lands in the new
        % directory rather than at the next MATLAB session. It creates the
        % directory, which can fail on a share; the dialog stays open in that
        % case so the operator can correct the path. Everything applied above
        % has already been persisted and re-applying it on the next OK is
        % harmless.
        try
            eplog.setLogDir(ld);
        catch ME
            vprintf(0,1,ME);
            uialert(dlg, ME.message, 'Error Log Path', 'Icon', 'error');
            return
        end

        % Apply: Error Log Viewer (persist empty too, so the platform default
        % can be restored)
        lv = strtrim(ef_logviewer.Value);
        setpref('ep_RunExpt_Logging','ExternalViewer',lv);
        if ~isempty(lv)
            vprintf(1,'Error log viewer: %s\n',lv);
        end

        % Apply: Subject Roster File (empty leaves the rig with no roster at
        % all; Subjects & Projects will ask for one). The file itself is not
        % created here -- it appears when the first subject is added. Named by
        % hand rather than through the chooser, so no legacy file is adopted:
        % typing a path is a deliberate act that should do exactly what it says.
        try
            epsych.SubjectRoster.setConfiguredFile(strtrim(ef_roster.Value));
        catch ME
            vprintf(0,1,ME);
            uialert(dlg, ME.message, 'Subject Roster File', 'Icon', 'error');
            return
        end

        self.CheckReady;
        onClose_();
    end

end

% -----------------------------------------------------------------------
function val = fieldOr_(s, fname, dflt)
% Return s.(fname) when the field exists and is non-empty, otherwise dflt.
if isfield(s,fname) && ~isempty(s.(fname))
    val = s.(fname);
else
    val = dflt;
end
end
