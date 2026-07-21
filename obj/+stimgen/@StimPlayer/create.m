function create(obj)
% create(obj) - Build the StimPlayer uifigure and all UI components.

f = uifigure('Name', 'StimPlayer', 'Position', [100 100 900 760]);
f.DeleteFcn = @(~,~) delete(obj);
f.WindowKeyPressFcn = @(~,evt) on_keypress_(obj, evt);
obj.hFig = f;

% --- Top-level grid: 3 rows x 1 col ---
g = uigridlayout(f);
g.ColumnWidth = {'1x'};
g.RowHeight   = {220, '1x', 44};
g.Padding     = [6 6 6 6];
g.RowSpacing  = 4;

% ---- Row 1: Signal plot ----
ax = uiaxes(g);
ax.Layout.Row    = 1;
ax.Layout.Column = 1;
grid(ax, 'on');
box(ax, 'on');
xlabel(ax, 'time (s)');
ylabel(ax, 'amplitude');
obj.handles.SignalAx   = ax;
obj.handles.SignalLine = line(ax, nan, nan, 'Color', [0.2 0.4 0.8]);

% ---- Row 2: Bank panel + Tab group ----
g2 = uigridlayout(g);
g2.Layout.Row    = 2;
g2.Layout.Column = 1;
g2.ColumnWidth   = {240, '1x'};
g2.RowHeight     = {'1x'};
g2.Padding       = [0 0 0 0];
g2.ColumnSpacing = 6;

% --- Left: bank panel ---
bankPnl = uipanel(g2, 'Title', 'Stimulus Bank', 'FontWeight', 'bold');
bankPnl.Layout.Row    = 1;
bankPnl.Layout.Column = 1;

bg = uigridlayout(bankPnl);
bg.ColumnWidth = {'1x', '1x'};
bg.RowHeight   = {26, 26, '1x', 26, 26, 26, 26, 26, 30};
bg.Padding     = [6 6 6 6];
bg.RowSpacing  = 4;

R = 1;

% Type dropdown
h = uidropdown(bg, 'Tag', 'StimTypeDD');
h.Layout.Row    = R;
h.Layout.Column = [1 2];
stTypes = stimgen.StimType.list;
h.Items     = stTypes;
h.ItemsData = stTypes;
obj.handles.TypeDropdown = h;

R = R + 1;

% Add / Remove buttons
h = uibutton(bg, 'Text', 'Add Stim');
h.Layout.Row          = R;
h.Layout.Column       = 1;
h.FontWeight          = 'bold';
h.ButtonPushedFcn     = @obj.add_stim;
obj.handles.AddBtn    = h;

h = uibutton(bg, 'Text', 'Remove');
h.Layout.Row          = R;
h.Layout.Column       = 2;
h.ButtonPushedFcn     = @obj.remove_stim;
obj.handles.RemoveBtn = h;

R = R + 1;

% Listbox (bank)
h = uilistbox(bg, 'Tag', 'BankList');
h.Layout.Row             = R;
h.Layout.Column          = [1 2];
h.Items                  = {};
h.ItemsData              = {};
h.ValueChangedFcn        = @obj.on_bank_selection_changed;
obj.handles.BankList     = h;

R = R + 1;

% Reps field
lbl = uilabel(bg, 'Text', 'Reps:', 'HorizontalAlignment', 'right');
lbl.Layout.Row    = R;
lbl.Layout.Column = 1;

h = uieditfield(bg, 'numeric', 'Tag', 'RepsField');
h.Layout.Row              = R;
h.Layout.Column           = 2;
h.Limits                  = [1 1e6];
h.RoundFractionalValues   = 'on';
h.ValueDisplayFormat      = '%d';
h.Value                   = 20;
h.ValueChangedFcn     = @(s,e) on_reps_changed_(obj,s,e);
obj.handles.RepsField     = h;

R = R + 1;

% ISI field
lbl = uilabel(bg, 'Text', 'ISI (s):', 'HorizontalAlignment', 'right');
lbl.Layout.Row    = R;
lbl.Layout.Column = 1;

h = uieditfield(bg, 'Tag', 'ISIField');
h.Layout.Row          = R;
h.Layout.Column       = 2;
h.Value               = mat2str(obj.ISI);
h.ValueChangedFcn     = @(s,e) on_isi_changed_(obj,s,e);
obj.handles.ISIField  = h;

R = R + 1;

% Order dropdown
h = uidropdown(bg, 'Tag', 'OrderDD');
h.Layout.Row      = R;
h.Layout.Column   = [1 2];
h.Items           = {'Shuffle', 'Serial'};
h.ItemsData       = {"Shuffle", "Serial"};
h.Value           = "Shuffle";
h.ValueChangedFcn = @(s,e) on_order_changed_(obj,s,e);
obj.handles.OrderDD = h;

R = R + 1;

% Combination stepping buttons
h = uibutton(bg, 'Text', '<');
h.Layout.Row          = R;
h.Layout.Column       = 1;
h.ButtonPushedFcn     = @(~,~) obj.step_combination(-1);
obj.handles.ComboPrevBtn = h;

h = uibutton(bg, 'Text', '>');
h.Layout.Row          = R;
h.Layout.Column       = 2;
h.ButtonPushedFcn     = @(~,~) obj.step_combination(1);
obj.handles.ComboNextBtn = h;

R = R + 1;

% Combination status label
h = uilabel(bg, 'Text', 'Combo: - / -', 'HorizontalAlignment', 'center');
h.Layout.Row    = R;
h.Layout.Column = [1 2];
obj.handles.ComboStatusLbl = h;

R = R + 1;

% Preview buttons
h = uibutton(bg, 'Text', 'Play');
h.Layout.Row          = R;
h.Layout.Column       = 1;
h.ButtonPushedFcn     = @obj.play_preview;
obj.handles.PlayBtn   = h;

h = uibutton(bg, 'Text', 'Play All');
h.Layout.Row          = R;
h.Layout.Column       = 2;
h.ButtonPushedFcn     = @obj.play_all;
obj.handles.PlayAllBtn = h;

% --- Right: scrollable param panel (rebuilt on listbox selection) ---
pnl = uipanel(g2, 'BorderType', 'none');
pnl.Layout.Row    = 1;
pnl.Layout.Column = 2;
obj.handles.ParamPanel = pnl;

% Placeholder label shown before any bank selection
uilabel(pnl, 'Text', 'Select an item from the bank to edit its parameters.', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'center', ...
    'Position', [10 10 380 40]);

% ---- Row 3: Playback controls bar ----
ctrlG = uigridlayout(g);
ctrlG.Layout.Row    = 3;
ctrlG.Layout.Column = 1;
ctrlG.ColumnWidth   = {100, 100, 280, 240, 160};
ctrlG.RowHeight     = {'1x'};
ctrlG.Padding       = [0 0 0 0];
ctrlG.ColumnSpacing = 6;

h = uibutton(ctrlG, 'Text', 'Run');
h.Layout.Column   = 1;
h.Layout.Row      = 1;
h.FontSize        = 14;
h.FontWeight      = 'bold';
h.ButtonPushedFcn = @obj.playback_control;
obj.handles.RunBtn = h;

h = uibutton(ctrlG, 'Text', 'Pause');
h.Layout.Column   = 2;
h.Layout.Row      = 1;
h.FontSize        = 14;
h.FontWeight      = 'bold';
h.Enable          = 'off';
h.ButtonPushedFcn = @obj.playback_control;
obj.handles.PauseBtn = h;

h = uilabel(ctrlG, 'Text', 'Protocol: none | HW: speaker preview only', ...
    'HorizontalAlignment', 'left', 'FontColor', [0.35 0.35 0.35]);
h.Layout.Column = 3;
h.Layout.Row    = 1;
obj.handles.ProtocolStatusLabel = h;

h = uilabel(ctrlG, 'Text', 'Ready.', 'HorizontalAlignment', 'left', ...
    'FontColor', [0.35 0.35 0.35]);
h.Layout.Column = 4;
h.Layout.Row    = 1;
obj.handles.StatusLabel = h;

h = uilabel(ctrlG, 'Text', '0 / 0', 'FontSize', 16, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'right');
h.Layout.Column = 5;
h.Layout.Row    = 1;
obj.handles.Counter = h;

% ---- Menu ----
mFile = uimenu(f, 'Text', '&File');
mLoadProtocol = uimenu(mFile, 'Text', 'Load &Protocol',  'Accelerator', 'P', ...
    'MenuSelectedFcn', @(~,~) obj.load_protocol_());
mLoadBank = uimenu(mFile, 'Text', '&Load Bank',  'Accelerator', 'L', ...
    'Separator', 'on', ...
    'MenuSelectedFcn', @(~,~) obj.load_bank());
mSaveBank = uimenu(mFile, 'Text', '&Save Bank',  'Accelerator', 'S', ...
    'MenuSelectedFcn', @(~,~) obj.save_bank());
mCalibration = uimenu(mFile, 'Text', '&Calibration', 'Accelerator', 'C', ...
    'MenuSelectedFcn', @(~,~) set_calibration_(obj));
mOpenCalibrationGui = uimenu(mFile, 'Text', 'Open Calibration &GUI', ...
    'MenuSelectedFcn', @(~,~) obj.open_calibration_gui());
mExportSignal = uimenu(mFile, 'Text', '&Export Signal to Workspace', 'Separator', 'on', ...
    'MenuSelectedFcn', @(~,~) export_signal_to_workspace_(obj));
mExportAll = uimenu(mFile, 'Text', 'Export &All Signals to Workspace', ...
    'MenuSelectedFcn', @(~,~) export_all_signals_to_workspace_(obj));
mExportObjs = uimenu(mFile, 'Text', 'Export Bank as &StimType Objects', ...
    'MenuSelectedFcn', @(~,~) export_bank_as_stimtype_(obj));

movegui(f, 'onscreen');

obj.refresh_combo_controls_;
obj.update_protocol_status_;
obj.handles.LoadProtocolMenu  = mLoadProtocol;
obj.handles.LoadBankMenu      = mLoadBank;
obj.handles.SaveBankMenu      = mSaveBank;
obj.handles.CalibrationMenu   = mCalibration;
obj.handles.CalibrationGuiMenu = mOpenCalibrationGui;
obj.handles.ExportSignalMenu  = mExportSignal;
obj.handles.ExportAllMenu     = mExportAll;
obj.handles.ExportObjsMenu    = mExportObjs;

end % create


% =========================================================================
% Inline helpers called only from create
% =========================================================================

function on_reps_changed_(obj, src, ~)
% Update Reps on the currently selected StimPlay when the field changes.
idx = selected_bank_idx_(obj);
if isempty(idx), return; end
try
    obj.StimPlayObjs(idx).Reps = src.Value;
    obj.refresh_listbox_;
catch ME
    src.Value = obj.StimPlayObjs(idx).Reps;
    obj.report_gui_error_(ME, "Invalid Repetitions", ...
        "Unable to update the repetition count for the selected stimulus.");
end
end

function on_isi_changed_(obj, src, event)
% Validate and store ISI on StimPlayer; parse "[min max]" or scalar.
try
    v = str2num(src.Value); %#ok<ST2NM>
    v = sort(v(:)');
    if isempty(v)
        error('StimPlayer:InvalidISI', 'Enter a scalar or two-element numeric range for ISI.');
    end
    if numel(v) == 1
        v = [v v];
    elseif numel(v) ~= 2 || any(v <= 0)
        error('StimPlayer:InvalidISI', 'ISI must be a positive scalar or positive [min max] pair.');
    end
    obj.ISI = v;
    src.Value = mat2str(v);
catch ME
    src.Value = event.PreviousValue;
    obj.report_gui_error_(ME, "Invalid ISI", ...
        "Stimulus ISI must be a positive scalar or a two-value range.");
end
end

function on_order_changed_(obj, src, ~)
try
    obj.SelectionType = src.Value;
catch ME
    obj.report_gui_error_(ME, "Invalid Order", ...
        "Unable to apply the selected playback order.");
end
end

function on_keypress_(obj, evt)
% Map left/right arrow keys to combo stepping for the selected bank item.
try
    switch lower(string(evt.Key))
        case "leftarrow"
            obj.step_combination(-1);
        case "rightarrow"
            obj.step_combination(1);
    end
catch ME
    obj.report_gui_error_(ME, "Key Binding Error", ...
        "StimPlayer could not handle the requested keyboard shortcut.");
end
end

function set_calibration_(obj)
% Prompt user for a calibration file and apply to all bank items.
[fn, pn] = uigetfile( ...
    {'*.esgc;*.sgc','Calibration Files (*.esgc, *.sgc)'; ...
     '*.esgc','EPsych Stim Calibration (*.esgc)'; ...
     '*.sgc','Legacy Calibration (*.sgc)'}, ...
    'Select Calibration File');
if isequal(fn, 0), return; end

ffn = fullfile(pn, fn);
try
    [~, ~, ext] = fileparts(ffn);

    if strcmpi(ext, '.esgc')
        calObj = stimgen.StimCalibration();
        calObj.load_calibration(ffn);
    else
        cal = load(ffn, '-mat');
        fields = fieldnames(cal);
        if isempty(fields)
            error('StimPlayer:InvalidCalibrationFile', ...
                'The selected calibration file did not contain any variables.');
        end

        raw = cal.(fields{1});
        if isa(raw, 'stimgen.StimCalibration')
            calObj = raw;
        elseif isstruct(raw)
            calObj = stimgen.StimCalibration.loadobj(raw);
        else
            error('StimPlayer:InvalidCalibrationFile', ...
                'The selected calibration file did not contain a usable calibration object.');
        end
    end

    for i = 1:numel(obj.StimPlayObjs)
        obj.StimPlayObjs(i).StimObj.Calibration = calObj;
    end
    stimgen.util.vprintf(1, 'Calibration applied to %d bank items.', numel(obj.StimPlayObjs));
catch ME
    obj.report_gui_error_(ME, "Calibration Error", ...
        "StimPlayer could not load or apply the selected calibration file.");
end
end

function idx = selected_bank_idx_(obj)
% Return the currently selected listbox index, or [] if none.
h = obj.handles.BankList;
if isempty(h.ItemsData) || isempty(h.Value)
    idx = [];
else
    idx = h.Value;
end
end

function export_signal_to_workspace_(obj)
% Export the currently selected stim signal to the base workspace as `y`.
idx = selected_bank_idx_(obj);
if isempty(idx)
    obj.show_gui_message_("Select a stimulus bank item before exporting its signal.", ...
        "Nothing To Export", "warning");
    return
end
try
    sp = obj.StimPlayObjs(idx);
    stimObj = sp.CurrentStimObj;
    if isempty(stimObj.Signal)
        stimObj.update_signal;
    end
    if isempty(stimObj.Signal)
        obj.show_gui_message_("The selected stimulus does not currently have a signal to export.", ...
            "Empty Signal", "warning");
        return
    end
    assignin('base', 'y', stimObj.Signal);
    stimgen.util.vprintf(1, 'StimPlayer: signal exported to workspace variable ''y'' (%d samples, Fs = %g Hz).\n', ...
        numel(stimObj.Signal), stimObj.Fs);
catch ME
    obj.report_gui_error_(ME, "Export Error", ...
        "StimPlayer could not export the selected signal to the workspace.");
end
end


function export_all_signals_to_workspace_(obj)
% Export signals for every combination of every bank item to the workspace.
% Creates a struct `signals` with one field per bank entry (named by bank
% label, sanitized for use as a struct field).  Each field is an N-by-1
% struct array over combinations. For each element c:
%   .Fs         - sample rate (Hz)
%   .signal     - signal vector for combination c
%   .parameters - struct of user-property values for combination c

if isempty(obj.StimPlayObjs)
    obj.show_gui_message_("The stimulus bank is empty.", "Nothing To Export", "warning");
    return
end

try
    signals = struct(); %#ok<NASGU>

    for i = 1:numel(obj.StimPlayObjs)
        sp      = obj.StimPlayObjs(i);
        stimObj = sp.CurrentStimObj;

        % Sanitize bank label → valid struct field name
        rawName   = char(sp.Name);
        fieldName = matlab.lang.makeValidName(rawName);
        if isempty(fieldName) || ~isletter(fieldName(1))
            fieldName = sprintf('stim%d', i);
        end
        if isfield(signals, fieldName)
            fieldName = sprintf('%s_%d', fieldName, i);
        end

        info   = stimObj.get_variant_info();
        nCombo = info.NumCombinations;

        % Snapshot the currently active combination index to restore later
        savedIdx = info.ActiveIndex;

        fsVal  = stimObj.Fs;
        entry  = repmat(struct('Fs', fsVal, 'signal', [], 'parameters', struct()), nCombo, 1);

        for c = 1:nCombo
            stimObj.set_variant_index(c);
            if isempty(stimObj.Signal)
                stimObj.update_signal;
            end
            entry(c).Fs = fsVal;
            entry(c).signal = stimObj.Signal;

            % Collect current values of all user-defined properties
            props = string(stimObj.UserProperties);
            for p = 1:numel(props)
                pname = char(props(p));
                fld   = matlab.lang.makeValidName(pname);
                if isprop(stimObj, pname)
                    entry(c).parameters.(fld) = stimObj.(pname);
                end
            end
        end

        % Restore the original combination
        stimObj.set_variant_index(savedIdx);

        signals.(fieldName) = entry; %#ok<AGROW>
    end

    assignin('base', 'signals', signals);
    stimgen.util.vprintf(1, 'StimPlayer: exported all signals to workspace variable ''signals'' (%d bank item(s)).\n', ...
        numel(obj.StimPlayObjs));
    obj.set_status_(sprintf('Exported %d bank item(s) to ''signals''.', numel(obj.StimPlayObjs)));
catch ME
    obj.report_gui_error_(ME, "Export All Error", ...
        "StimPlayer could not export all signals to the workspace.");
end
end


function export_bank_as_stimtype_(obj)
% Export every bank entry as copied StimType objects to the workspace.
% Creates a struct `stimBank` with one field per bank entry (bank label
% sanitized for use as a struct field).  Each field contains a struct with:
%   .name     - bank label string
%   .type     - StimType subclass name (e.g. "ClickTrain")
%   .objects  - (nCombinations x 1) array of independent copied StimType objects,
%               one per variant combination, each with Signal pre-generated

if isempty(obj.StimPlayObjs)
    obj.show_gui_message_("The stimulus bank is empty.", "Nothing To Export", "warning");
    return
end

try
    stimBank = struct();

    for i = 1:numel(obj.StimPlayObjs)
        sp      = obj.StimPlayObjs(i);
        stimObj = sp.CurrentStimObj;

        % Sanitize bank label -> valid struct field name
        rawName   = char(sp.Name);
        fieldName = matlab.lang.makeValidName(rawName);
        if isempty(fieldName) || ~isletter(fieldName(1))
            fieldName = sprintf('stim%d', i);
        end
        if isfield(stimBank, fieldName)
            fieldName = sprintf('%s_%d', fieldName, i);
        end

        info     = stimObj.get_variant_info();
        nCombo   = info.NumCombinations;
        savedIdx = info.ActiveIndex;

        % Collect one deep copy per combination
        objs = cell(nCombo, 1);
        for c = 1:nCombo
            stimObj.set_variant_index(c);
            if isempty(stimObj.Signal)
                stimObj.update_signal;
            end
            objs{c} = copy(stimObj);
        end

        % Restore original combination
        stimObj.set_variant_index(savedIdx);

        % Convert cell array to heterogeneous array when all same class,
        % otherwise keep as cell
        try
            classNames = cellfun(@class, objs, 'uni', false);
            if numel(unique(classNames)) == 1
                objArr = vertcat(objs{:});
            else
                objArr = objs;
            end
        catch
            objArr = objs;
        end

        typeParts = split(string(class(stimObj)), ".");
        entry.name    = string(sp.Name);
        entry.type    = typeParts(end);
        entry.objects = objArr;

        stimBank.(fieldName) = entry;
    end

    assignin('base', 'stimBank', stimBank);
    stimgen.util.vprintf(1, 'StimPlayer: exported bank as StimType objects to workspace variable ''stimBank'' (%d item(s)).\n', ...
        numel(obj.StimPlayObjs));
    obj.set_status_(sprintf('Exported %d bank item(s) as StimType objects to ''stimBank''.', numel(obj.StimPlayObjs)));
catch ME
    obj.report_gui_error_(ME, "Export Bank Error", ...
        "StimPlayer could not export the bank as StimType objects.");
end
end
