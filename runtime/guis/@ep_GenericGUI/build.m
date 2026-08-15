function build(obj, fig)
% build(obj, fig)
% Build the generic runtime GUI from the current RUNTIME parameter set.
% Called by the gui.BehaviorGUI constructor after the figure exists.
%
% Parameters:
%	obj	- ep_GenericGUI instance whose UI handles are populated by this method.
%	fig	- Main uifigure created by the base class.

R = obj.RUNTIME;

% ---- Collect and classify parameters ------------------------------------
allParams = R.all_parameters(Access='All', includeTriggers=true);
[trigParams, ctrlParams, monitorParams] = gui.BehaviorGUI.classifyParameters(allParams);

nTrig    = numel(trigParams);
nCtrl    = numel(ctrlParams);
nMonitor = numel(monitorParams);

% ---- Outer grid: 2 rows x 3 columns ------------------------------------
%   Row 1: control buttons (spans all columns)
%   Row 2: writable params | monitor table | event log
outerGrid = uigridlayout(fig, [2, 3]);
outerGrid.RowHeight    = {70, '1x'};
outerGrid.ColumnWidth  = {'1x', '1x', '1x'};
outerGrid.Padding      = [4 4 4 4];
outerGrid.RowSpacing   = 4;
outerGrid.ColumnSpacing = 4;

% =========================================================================
% ROW 1 — CONTROL BUTTONS
% =========================================================================
panelButtons = uipanel(outerGrid, 'Title', 'Controls');
panelButtons.Layout.Row    = 1;
panelButtons.Layout.Column = [1 3];

nBtnCols = max(nTrig, 1);
btnGrid  = uigridlayout(panelButtons, [1, nBtnCols]);
btnGrid.RowHeight    = {'1x'};
btnGrid.ColumnWidth  = repmat({'1x'}, 1, nBtnCols);
btnGrid.Padding      = [2 2 2 2];
btnGrid.ColumnSpacing = 2;

for k = 1:nTrig
    obj.addButton(btnGrid, trigParams(k));
end

if nTrig == 0
    uilabel(btnGrid, ...
        'Text',                'No trigger parameters found.', ...
        'HorizontalAlignment', 'center', ...
        'FontColor',           [0.5 0.5 0.5]);
end

% =========================================================================
% ROW 2 LEFT — WRITABLE PARAMETER CONTROLS
% =========================================================================
panelCtrl = uipanel(outerGrid, 'Title', 'Parameter Controls');
panelCtrl.Layout.Row    = 2;
panelCtrl.Layout.Column = [1 2];

nCtrlRows = max(nCtrl, 1);
ctrlGrid  = uigridlayout(panelCtrl, [nCtrlRows, 1]);
ctrlGrid.RowHeight    = repmat({25}, 1, nCtrlRows);
ctrlGrid.ColumnWidth  = {'1x'};
ctrlGrid.RowSpacing   = 1;
ctrlGrid.Padding      = [2 2 2 2];
ctrlGrid.Scrollable   = 'on';

obj.ParamControls = cell(nCtrl, 1);
for k = 1:nCtrl
    p = ctrlParams(k);

    if strcmp(p.Type, 'Boolean')
        ctype = 'checkbox';
    elseif numel(p.Values) > 1
        ctype = 'dropdown';
    else
        ctype = 'editfield';
    end

    obj.ParamControls{k} = obj.addControl(ctrlGrid, p, Type=ctype);
end

if nCtrl == 0
    uilabel(ctrlGrid, ...
        'Text',                'No writable parameters found.', ...
        'HorizontalAlignment', 'center', ...
        'FontColor',           [0.5 0.5 0.5]);
end

% =========================================================================
% ROW 2 RIGHT — PARAMETER MONITOR + EVENT LOG
% =========================================================================
rightGrid = uigridlayout(outerGrid, [2, 1]);
rightGrid.Layout.Row    = 2;
rightGrid.Layout.Column = 3;
rightGrid.RowHeight     = {'1x', 180};
rightGrid.ColumnWidth   = {'1x'};
rightGrid.Padding       = [0 0 0 0];
rightGrid.RowSpacing    = 4;

% --- Parameter Monitor ---
panelMonitor = uipanel(rightGrid, 'Title', 'Parameter Monitor');
panelMonitor.Layout.Row    = 1;
panelMonitor.Layout.Column = 1;

if nMonitor > 0
    obj.ParameterMonitor = obj.addMonitor(panelMonitor, monitorParams, pollPeriod=1);
else
    monitorGrid = uigridlayout(panelMonitor, [1, 1]);
    monitorGrid.Padding = [0 0 0 0];
    uilabel(monitorGrid, ...
        'Text',                'No read-only parameters found.', ...
        'HorizontalAlignment', 'center', ...
        'FontColor',           [0.5 0.5 0.5]);
end

% --- Event Log ---
panelLog = uipanel(rightGrid, 'Title', 'Event Log');
panelLog.Layout.Row    = 2;
panelLog.Layout.Column = 1;

logGrid = uigridlayout(panelLog, [1, 1]);
logGrid.Padding = [2 2 2 2];

obj.h_logArea = uitextarea(logGrid, ...
    'Editable',  'off',         ...
    'FontName',  'Courier New', ...
    'FontSize',  10,            ...
    'Value',     {'--- Event Log ---'});
obj.h_logArea.Layout.Row    = 1;
obj.h_logArea.Layout.Column = 1;

obj.log_event('GUI initialized');
