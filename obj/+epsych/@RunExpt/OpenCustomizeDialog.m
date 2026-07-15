function OpenCustomizeDialog(self)
% OpenCustomizeDialog — Open the unified Customize Settings dialog.
% Presents all customizable callback function names, file paths, and timer
% settings in a single modal window. Changes are validated and applied on OK.
% The individual Define* methods remain available for programmatic use.
if self.STATE >= PRGMSTATE.RUNNING, return, end

% Gather current values ------------------------------------------------
F         = self.FUNCS;
savingFcn = char(fieldOr_(F, 'SavingFcn',    'ep_SaveDataFcn'));
boxFig    = char(fieldOr_(F, 'BoxFig',        'ep_GenericGUI'));
addSubj   = char(fieldOr_(F, 'AddSubjectFcn', 'epsych.DefaultSubject.open'));
timerPer  = fieldOr_(F, 'TimerPeriod', 0.01);
dataPath  = char(self.dfltDataPath);
cfgRoot   = char(getpref('ep_RunExpt_Setup','ConfigBrowserRootDir',''));
if isempty(cfgRoot)
    cfgRoot = char(getpref('ep_RunExpt_Setup','CDir',cd));
end
if ~exist(cfgRoot,'dir'), cfgRoot = cd; end

% Assemble recents-backed item lists for the function dropdowns --------
itemsSaving  = buildItems_('RecentSavingFcn',     savingFcn, 'ep_SaveDataFcn');
itemsBoxFig  = buildItems_('RecentBoxFig',        boxFig,    'ep_GenericGUI');
itemsAddSubj = buildItems_('RecentAddSubjectFcn', addSubj,   'epsych.DefaultSubject.open');

% Build dialog ---------------------------------------------------------
% Close any stale instance (e.g. left from a previous blocked attempt)
stale = findall(groot,'Type','figure','Tag','RunExptCustomize');
if ~isempty(stale), delete(stale); end

ontop = self.AlwaysOnTop(false);
dlg = uifigure('Name','Customize EPsych','Tag','RunExptCustomize', ...
    'Resize','off', ...
    'Position',[0 0 500 250]);
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
gFcn = uigridlayout(tabFcn,[3 3]);
gFcn.RowHeight    = {28, 28, 28};
gFcn.ColumnWidth  = {160, '1x', 80};
gFcn.Padding      = [10 12 10 12];
gFcn.RowSpacing   = 8;
gFcn.ColumnSpacing = 8;

addLabel_(gFcn, 1, 'Saving Function:');
ef_saving = uidropdown(gFcn,'Editable','on','Items',itemsSaving,'Value',savingFcn, ...
    'Tooltip', ['Function called after experiment to save experiment data.' newline ...
                'Signature: SaveFcn(RUNTIME)  — 1 input, 0 outputs.' newline ...
                'Pick a previously-used function or type a new one.' newline ...
                'Default: ep_SaveDataFcn']);
ef_saving.Layout.Row = 1; ef_saving.Layout.Column = 2;
ef_saving.ValueChangedFcn = @(h,~) validateFcnField_(h,'saving');
addResetBtn_(gFcn, 1, ef_saving, 'ep_SaveDataFcn', 'saving');

addLabel_(gFcn, 2, 'Box GUI Function:');
ef_boxfig = uidropdown(gFcn,'Editable','on','Items',itemsBoxFig,'Value',boxFig, ...
    'Tooltip', ['Function that opens the behavioral GUI when the experiment starts.' newline ...
                'Signature: BoxFig(RUNTIME)' newline ...
                'Pick a previously-used GUI or type a new one.' newline ...
                'Leave empty to disable.' newline ...
                'Default: ep_GenericGUI']);
ef_boxfig.Layout.Row = 2; ef_boxfig.Layout.Column = 2;
ef_boxfig.ValueChangedFcn = @(h,~) validateFcnField_(h,'boxfig');
addResetBtn_(gFcn, 2, ef_boxfig, 'ep_GenericGUI', 'boxfig');

addLabel_(gFcn, 3, 'Add Subject Function:');
ef_addsubj = uidropdown(gFcn,'Editable','on','Items',itemsAddSubj,'Value',addSubj, ...
    'Tooltip', ['Function that collects subject information when adding a new subject.' newline ...
                'Signature: S = AddSubjectFcn(S, boxids)' newline ...
                'Pick a previously-used function or type a new one.' newline ...
                'Default: epsych.DefaultSubject.open']);
ef_addsubj.Layout.Row = 3; ef_addsubj.Layout.Column = 2;
ef_addsubj.ValueChangedFcn = @(h,~) validateFcnField_(h,'addsubj');
addResetBtn_(gFcn, 3, ef_addsubj, 'epsych.DefaultSubject.open', 'addsubj');

% Initial validation pass
validateFcnField_(ef_saving,  'saving');
validateFcnField_(ef_boxfig,  'boxfig');
validateFcnField_(ef_addsubj, 'addsubj');

% ---- TAB: Paths ------------------------------------------------------
tabPaths = uitab(tg,'Title','Paths');
gPaths = uigridlayout(tabPaths,[2 3]);
gPaths.RowHeight    = {28, 28};
gPaths.ColumnWidth  = {160, '1x', 80};
gPaths.Padding      = [10 12 10 12];
gPaths.RowSpacing   = 8;
gPaths.ColumnSpacing = 8;

addLabel_(gPaths, 1, 'Data Save Path:');
ef_datapath = uieditfield(gPaths,'text','Value',dataPath, ...
    'Tooltip', ['Default directory where experiment data files are written.' newline ...
                'Saved as the RunExpt DataPath preference.']);
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

% ---- TAB: Options ----------------------------------------------------
tabOpts = uitab(tg,'Title','Options');
gOpts = uigridlayout(tabOpts,[1 3]);
gOpts.RowHeight    = {28};
gOpts.ColumnWidth  = {160, '1x', 80};
gOpts.Padding      = [10 12 10 12];
gOpts.ColumnSpacing = 8;

addLabel_(gOpts, 1, 'Timer Period (s):');
ef_timer = uieditfield(gOpts,'numeric','Value',timerPer, ...
    'Limits',[0.001 1], ...
    'LowerLimitInclusive','on', ...
    'UpperLimitInclusive','on', ...
    'Tooltip', ['PsychTimer callback period in seconds.' newline ...
                'Smaller values increase timing resolution at the cost of higher CPU use.' newline ...
                'Valid range: 0.001 – 1 s.  Default: 0.01']);
ef_timer.Layout.Row = 1; ef_timer.Layout.Column = 2;
ph = uilabel(gOpts,'Text','');   % column-3 placeholder
ph.Layout.Row = 1; ph.Layout.Column = 3;

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
            case 'saving'
                b = which(v);
                if isempty(b)
                    ok = false;
                else
                    ok = nargin(v) == 1 && nargout(v) == 0;
                end
            case 'boxfig'
                ok = ~isempty(which(v));
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

    function onClose_()
        % Restore always-on-top state and destroy the dialog.
        self.AlwaysOnTop(ontop);
        delete(dlg);
    end

    function onOK_()
        % Validate all fields then apply changes and close the dialog.
        errs = {};

        sf  = strtrim(ef_saving.Value);
        bf  = strtrim(ef_boxfig.Value);
        asf = strtrim(ef_addsubj.Value);

        % Saving Function
        if ~isempty(sf)
            b = which(sf);
            if isempty(b)
                errs{end+1} = sprintf('Saving Function ''%s'' was not found on the path.', sf);
            elseif nargin(sf) ~= 1 || nargout(sf) ~= 0
                errs{end+1} = 'Saving Function must accept 1 input and return 0 outputs.';
            end
        end

        % Box GUI Function
        if ~isempty(bf) && isempty(which(bf))
            errs{end+1} = sprintf('Box GUI Function ''%s'' was not found on the path.', bf);
        end

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

        if ~isempty(errs)
            uialert(dlg, strjoin(errs, newline), 'Validation Error');
            return
        end

        % Apply: Saving Function
        if ~isempty(sf)
            self.FUNCS.SavingFcn = sf;
            setpref('ep_RunExpt_FUNCS','SavingFcn',sf);
            self.RememberRecentFunc('RecentSavingFcn',sf);
            vprintf(0,'Saving Function: %s\n',sf);
        end

        % Apply: Box GUI Function
        self.FUNCS.BoxFig = bf;
        if ~isempty(bf)
            setpref('ep_RunExpt_FUNCS','BoxFig',bf);
            self.RememberRecentFunc('RecentBoxFig',bf);
            vprintf(0,'Box GUI Function: %s\n',bf);
        end

        % Apply: Add Subject Function
        self.FUNCS.AddSubjectFcn = asf;
        setpref('ep_RunExpt_FUNCS','AddSubjectFcn',asf);
        self.RememberRecentFunc('RecentAddSubjectFcn',asf);
        vprintf(0,'Add Subject Function: %s\n',asf);

        % Apply: Timer Period
        val = ef_timer.Value;
        self.FUNCS.TimerPeriod = val;
        setpref('ep_RunExpt_TIMER','Period',val);
        vprintf(0,'Timer period: %.4g s\n',val);

        % Apply: Data Save Path
        dp = strtrim(ef_datapath.Value);
        if ~isempty(dp)
            self.dfltDataPath = string(dp);
            setpref('RunExpt','DataPath',string(dp));
        end

        % Apply: Config Browser Root
        cr = strtrim(ef_cfgroot.Value);
        if ~isempty(cr)
            setpref('ep_RunExpt_Setup','ConfigBrowserRootDir',cr);
            vprintf(1,'Config browser root: %s\n',cr);
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
