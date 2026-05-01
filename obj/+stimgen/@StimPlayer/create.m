function create(obj)
% create(obj) - Build the StimPlayer uifigure and all UI components.

f = uifigure('Name', 'StimPlayer', 'Position', [100 100 900 620]);
f.DeleteFcn = @(~,~) delete(obj);
obj.hFig = f;

% --- Top-level grid: 3 rows x 1 col ---
g = uigridlayout(f);
g.ColumnWidth = {'1x'};
g.RowHeight   = {110, '1x', 44};
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
bg.RowHeight   = {26, 26, '1x', 26, 26, 26};
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
ctrlG.ColumnWidth   = {100, 100, 120, '1x', 160};
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

h = uibutton(ctrlG, 'Text', 'Play Stim');
h.Layout.Column   = 3;
h.Layout.Row      = 1;
h.FontSize        = 14;
h.ButtonPushedFcn = @obj.play_preview;
obj.handles.PlayStimBtn = h;

% Spacer (column 4 = '1x')

h = uilabel(ctrlG, 'Text', '0 / 0', 'FontSize', 16, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'right');
h.Layout.Column = 5;
h.Layout.Row    = 1;
obj.handles.Counter = h;

% ---- Menu ----
mFile = uimenu(f, 'Text', '&File');
uimenu(mFile, 'Text', '&Load Bank',  'Accelerator', 'L', ...
    'MenuSelectedFcn', @(~,~) obj.load_bank);
uimenu(mFile, 'Text', '&Save Bank',  'Accelerator', 'S', ...
    'MenuSelectedFcn', @(~,~) obj.save_bank);
uimenu(mFile, 'Text', '&Calibration', 'Accelerator', 'C', ...
    'MenuSelectedFcn', @(~,~) set_calibration_(obj));

movegui(f, 'onscreen');

end % create


% =========================================================================
% Inline helpers called only from create
% =========================================================================

function on_reps_changed_(obj, src, ~)
% Update Reps on the currently selected StimPlay when the field changes.
idx = selected_bank_idx_(obj);
if isempty(idx), return; end
obj.StimPlayObjs(idx).Reps = src.Value;
obj.refresh_listbox_;
end

function on_isi_changed_(obj, src, event)
% Validate and store ISI on StimPlayer; parse "[min max]" or scalar.
v = str2num(src.Value); %#ok<ST2NM>
v = sort(v(:)');
if numel(v) == 1
    v = [v v];
elseif numel(v) ~= 2 || any(v <= 0)
    src.Value = event.PreviousValue;
    return
end
obj.ISI = v;
src.Value = mat2str(v);
end

function on_order_changed_(obj, src, ~)
obj.SelectionType = src.Value;
end

function set_calibration_(obj)
% Prompt user for a calibration file and apply to all bank items.
[fn, pn] = uigetfile('*.sgc', 'Select Calibration File');
if isequal(fn, 0), return; end
cal = load(fullfile(pn, fn), '-mat');
fn = fieldnames(cal);
calObj = cal.(fn{1});
for i = 1:numel(obj.StimPlayObjs)
    obj.StimPlayObjs(i).StimObj.Calibration = calObj;
end
vprintf(1, 'Calibration applied to %d bank items.', numel(obj.StimPlayObjs));
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
