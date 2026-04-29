function create_gui(obj)
% create_gui(obj)
% Auto-discover parameters from RUNTIME and build the generic GUI layout.
%
% Classifies parameters into three groups:
%   Triggers/toggles  (isTrigger=true or name prefixed '~' or '!')
%     -> control buttons in the top panel.
%   Writable visible  (Access = 'Any', 'Write', or 'Read / Write')
%     -> labeled controls in a scrollable left panel.
%   Read-only visible (Access = 'Read')
%     -> rows in a polling Parameter Monitor table (right panel).
%
% An event log (uitextarea) sits below the monitor panel.
%
% Parameters:
%   obj - ep_GenericGUI instance
%
% Returns:
%   None. All handles are stored in obj properties.

R = obj.RUNTIME;

% ---- Collect and classify parameters ------------------------------------
allParams = R.all_parameters( ...
    Access           = 'All', ...
    includeTriggers  = true,  ...
    includeInvisible = true);

if isempty(allParams)
    allParams = hw.Parameter.empty(1,0);
end

isTrigArr  = logical([allParams.isTrigger]);
isVisArr   = logical([allParams.Visible]);
accessArr  = {allParams.Access};
nameArr    = {allParams.Name};

% Trigger-style: explicitly tagged as trigger, or name starts with ~ or !
isTrigStyle = isTrigArr | cellfun(@(n) ~isempty(n) && ...
    (n(1)=='~' || n(1)=='!'), nameArr);

isWrite = ismember(accessArr, {'Any', 'Write', 'Read / Write'});
isRead  = strcmp(accessArr, 'Read');

trigParams    = allParams(isTrigStyle & isVisArr);
ctrlParams    = allParams(~isTrigStyle & isVisArr & isWrite);
monitorParams = allParams(~isTrigStyle & isVisArr & isRead);

nTrig    = numel(trigParams);
nCtrl    = numel(ctrlParams);
nMonitor = numel(monitorParams);

% ---- Create main figure -------------------------------------------------
fig = uifigure( ...
    'Tag',             'ep_GenericGUI',  ...
    'Name',            'Behavior Box',   ...
    'CloseRequestFcn', @(src,evt) obj.closeGUI(src,evt), ...
    'UserData',        obj);
fig.Position = ep_GenericGUI.getSavedFigurePosition([100 100 1100 680]);
movegui(fig, 'onscreen');
obj.h_figure = fig;

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

bcmActive = min(lines(max(nTrig, 1)) + 0.3, 1);
bcmNormal = repmat(fig.Color, size(bcmActive, 1), 1);

obj.hButtons = struct();
for k = 1:nTrig
    p = trigParams(k);

    % Choose button style: toggles use ~ prefix, all others are momentary
    if ~isempty(p.Name) && p.Name(1) == '~'
        btnType = 'toggle';
    else
        btnType = 'momentary';
    end

    h = gui.Parameter_Control(btnGrid, p, Type=btnType, autoCommit=true);

    % Strip special prefix characters from the display label
    label = regexprep(p.Name, '^[~!]+', '');
    if ~isempty(p.Unit)
        label = sprintf('%s (%s)', label, p.Unit);
    end
    h.Text          = strtrim(label);
    h.colorNormal   = bcmNormal(k, :);
    h.colorOnUpdate = bcmActive(k, :);

    fname = matlab.lang.makeValidName(p.Name);
    obj.hButtons.(fname) = h;
end

% Style all buttons uniformly
bh = [findobj(fig, 'Type', 'uibutton'); findobj(fig, 'Type', 'uistatebutton')];
if ~isempty(bh)
    set(bh, FontWeight='bold', FontSize=13);
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

    h = gui.Parameter_Control(ctrlGrid, p, Type=ctype);

    label = p.Name;
    if ~isempty(p.Unit)
        label = sprintf('%s (%s)', p.Name, p.Unit);
    end
    h.Text = label;

    obj.ParamControls{k} = h;
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
    obj.ParameterMonitor = gui.Parameter_Monitor( ...
        panelMonitor, monitorParams, pollPeriod=1);
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
