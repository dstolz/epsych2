function gui(obj)
% gui(obj)
% Build or re-use the StimCalibration control panel.
%
% Creates numeric fields for all engine parameters, a "Measure Reference"
% button, a "Run Calibration" button, and a File menu for .esgc I/O.
% Registers a PostSet listener on STATE to drive the calibration state
% machine.

if isempty(obj.handles.parent)
    h   = uifigure;
    pos = getpref('StimCalibration', 'pos', [400 250 300 420]);
    h.Position = pos;
    obj.handles.parent = h;
end

parent = obj.handles.parent;
movegui(parent, 'onscreen');

% Build grid layout.
sg               = uigridlayout(parent);
sg.ColumnWidth   = {'1x','1x'};
sg.RowHeight     = [repmat({30},1,7) {'1x'}];
sg.Scrollable    = 'on';
obj.handles.SideGrid = sg;

R = 1;

% --- Ref. Sound Level ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Ref. Sound Level:'; h.HorizontalAlignment = 'right';

h = uieditfield(sg, 'numeric');
h.Tag = 'ReferenceLevel';
h.Layout.Column = 2; h.Layout.Row = R;
h.ValueDisplayFormat = '%.1f dB SPL';
h.Value  = obj.Engine.ReferenceLevel;
h.Limits = [1 160];
h.ValueChangedFcn = @obj.set_prop;
obj.handles.ReferenceLevel = h;
R = R + 1;

% --- Ref. Frequency ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Ref. Frequency:'; h.HorizontalAlignment = 'right';

h = uieditfield(sg, 'numeric');
h.Tag = 'ReferenceFrequency';
h.Layout.Column = 2; h.Layout.Row = R;
h.ValueDisplayFormat = '%.1f Hz';
h.Value  = obj.Engine.ReferenceFrequency;
h.Limits = [100 100000];
h.ValueChangedFcn = @obj.set_prop;
obj.handles.ReferenceFrequency = h;
R = R + 1;

% --- Mic Sensitivity ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Mic. Sensitivity:'; h.HorizontalAlignment = 'right';

h = uieditfield(sg, 'numeric');
h.Tag = 'MicSensitivity';
h.Layout.Column = 2; h.Layout.Row = R;
h.ValueDisplayFormat = '%.4f V/Pa';
h.Limits = [0 10];
h.LowerLimitInclusive = 'off';
h.Value = obj.Engine.MicSensitivity;
h.ValueChangedFcn = @obj.set_prop;
obj.handles.MicSensitivity = h;
R = R + 1;

% --- Measure Reference button ---
h = uibutton(sg);
h.Layout.Column = [1 2]; h.Layout.Row = R;
h.Text = 'Measure Reference';
h.ButtonPushedFcn = @obj.measure_ref;
obj.handles.RefMeasure = h;
R = R + 1;

% --- Normative Sound Level ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Normative Sound Level:'; h.HorizontalAlignment = 'right';

h = uieditfield(sg, 'numeric');
h.Tag = 'NormativeValue';
h.Layout.Column = 2; h.Layout.Row = R;
h.ValueDisplayFormat = '%d dB SPL';
h.Value  = obj.Engine.NormativeValue;
h.Limits = [60 120];
h.ValueChangedFcn = @obj.set_prop;
obj.handles.NormativeValue = h;    % correct handle assignment
R = R + 1;

% --- Excitation Voltage ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Excitation Voltage:'; h.HorizontalAlignment = 'right';

h = uieditfield(sg, 'numeric');
h.Tag = 'ExcitationSignalVoltage';
h.Layout.Column = 2; h.Layout.Row = R;
h.ValueDisplayFormat = '%.2f V';
h.Value  = obj.Engine.ExcitationVoltage;
h.Limits = [0 10];
h.LowerLimitInclusive = 'off';
h.ValueChangedFcn = @obj.set_prop;
obj.handles.ExcitationSignalVoltage = h;   % bug fix: was handles.NormativeValue
R = R + 1;

% --- Run Calibration button ---
h = uibutton(sg);
h.Layout.Column = [1 2]; h.Layout.Row = R;
h.Text       = {'Run'; 'Calibration'};
h.FontSize   = 18;
h.FontWeight = 'bold';
h.ButtonPushedFcn = @obj.run_calibration;
obj.handles.RunCalibration = h;

% --- File menu (.esgc) ---
hf = uimenu(parent, 'Text', '&File', 'Accelerator', 'F');

h = uimenu(hf, 'Tag', 'menu_Load', 'Text', '&Load (.esgc)', ...
    'Accelerator', 'L', ...
    'MenuSelectedFcn', @(~,~) obj.load_calibration());
obj.handles.MenuLoadCalibration = h;

h = uimenu(hf, 'Tag', 'menu_Save', 'Text', '&Save (.esgc)', ...
    'Accelerator', 'S', ...
    'Enable', 'off', ...
    'MenuSelectedFcn', @(~,~) obj.save_calibration());
obj.handles.MenuSaveCalibration = h;

% --- Activate state machine ---
obj.STATE = "IDLE";
addlistener(obj, 'STATE', 'PostSet', @obj.calibration_state);

